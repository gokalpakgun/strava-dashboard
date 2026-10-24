// Each account has one serialized, strongly consistent inbox. This class is
// reachable only through its Worker binding, never a public HTTP route.
const TTL_MS = 35 * 86400 * 1000;
const TYPES = new Set(["friend_request", "friend_accepted", "challenge_invite"]);
const valid = n => n && /^[a-f0-9-]{36}$/i.test(n.id || "") && TYPES.has(n.type) && Number.isFinite(Date.parse(n.createdAt));
export class NotificationInbox {
  constructor(state) { this.state = state; }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    let body;
    if (request.method === "POST") {
      try { body = await request.json(); } catch { return Response.json({error:"Invalid inbox request"},{status:400}); }
    }
    return this.state.blockConcurrencyWhile(async () => {
      if (path === "/delete" && request.method === "POST") {
        await this.state.storage.deleteAll(); await this.state.storage.deleteAlarm();
        return Response.json({ok:true});
      }
      let records = (await this.state.storage.get("notices")) || [];
      const beforePruning = records.length;
      records = records.filter(n => valid(n) && Date.parse(n.createdAt) > Date.now() - TTL_MS);
      let changed = beforePruning !== records.length, created = false;
      if (path === "/create" && request.method === "POST") {
        if (!valid(body)) return Response.json({error:"Invalid inbox record"},{status:400});
        if (!records.some(n => n.id === body.id)) {
          records.push({id:body.id,type:body.type,createdAt:new Date().toISOString(),read:false,destination:"social"});
          changed = created = true;
        }
      } else if (path === "/read" && request.method === "POST") {
        const record = records.find(n => n.id === body?.id);
        if (record && !record.read) { record.read = true; changed = true; }
      } else if (path === "/import" && request.method === "POST") {
        if (!Array.isArray(body)) return Response.json({error:"Invalid inbox import"},{status:400});
        for (const n of body.slice(0,50).filter(valid)) if (Date.parse(n.createdAt) > Date.now()-TTL_MS && !records.some(x=>x.id===n.id)) {
          records.push({id:n.id,type:n.type,createdAt:n.createdAt,read:n.read===true,destination:"social"}); changed=true;
        }
      } else if (!(path === "/list" && request.method === "GET")) return Response.json({error:"Not found"},{status:404});
      records.sort((a,b)=>b.createdAt.localeCompare(a.createdAt)); records=records.slice(0,50);
      if (changed) await this.state.storage.put("notices",records);
      await this.scheduleExpiry(records);
      return Response.json({created, notifications:records});
    });
  }
  async scheduleExpiry(records) {
    if (!records.length) { await this.state.storage.deleteAll(); await this.state.storage.deleteAlarm(); return; }
    const next = Math.max(Date.now()+1000, Math.min(...records.map(n=>Date.parse(n.createdAt)))+TTL_MS);
    if (await this.state.storage.getAlarm() !== next) await this.state.storage.setAlarm(next);
  }
  async alarm() {
    const records = ((await this.state.storage.get("notices")) || []).filter(n=>valid(n)&&Date.parse(n.createdAt)>Date.now()-TTL_MS);
    if (records.length) await this.state.storage.put("notices", records);
    await this.scheduleExpiry(records);
  }
}
