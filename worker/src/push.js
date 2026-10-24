import { readLimitedText } from "./http.js";

const TTL = 60 * 60 * 24 * 35;
const TOPIC = "com.apitempo.tempohealth";
const encoder = new TextEncoder();
let cachedJWT;
let pendingJWT;
const json = (body, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const digest = async value => [...new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)))].map(x => x.toString(16).padStart(2, "0")).join("");
const indexKey = (userId, id) => `push-user:${userId}:${id}`;
const ready = env => Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY);

export async function handlePushRequest(request, env, context) {
  if (context.response) return context.response;
  const path = new URL(request.url).pathname;
  const userId = context.user.id;
  if (path === "/api/account/notifications" && request.method === "GET") {
    const entries = await listValues(env, `notification:${userId}:`, 50);
    return json({ notifications: entries.sort((a, b) => b.createdAt.localeCompare(a.createdAt)), pushAvailable: ready(env) });
  }
  let body;
  try { body = JSON.parse(await readLimitedText(request, 4096)); }
  catch { return json({ error: "Geçersiz bildirim isteği." }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Geçersiz bildirim isteği." }, 400);
  if (path === "/api/account/notifications/read" && request.method === "POST") {
    if (!/^[a-f0-9-]{20,64}$/i.test(body.id || "")) return json({ error: "Geçersiz bildirim." }, 400);
    const key = `notification:${userId}:${body.id}`;
    const record = await env.TOKEN_STORE.get(key, "json");
    if (record && !record.read) await env.TOKEN_STORE.put(key, JSON.stringify({ ...record, read: true }), { expirationTtl: Math.max(60, Math.ceil((Date.parse(record.createdAt) + TTL * 1000 - Date.now()) / 1000)) });
    return json({ ok: true });
  }
  if (path !== "/api/account/push/devices" || !["POST", "DELETE"].includes(request.method)) return json({ error: "Method not allowed." }, 405);
  if (!/^(?:[a-f0-9]{2}){1,256}$/i.test(body.token || "") || !["production", "development"].includes(body.environment)) return json({ error: "Geçersiz cihaz kaydı." }, 400);
  if (["friends", "challenges"].some(key => body[key] !== undefined && typeof body[key] !== "boolean")) return json({ error: "Geçersiz bildirim tercihi." }, 400);
  const token = body.token.toLowerCase();
  const id = await digest(TOPIC + body.environment + token);
  const key = "push-device:" + id;
  const previous = await env.TOKEN_STORE.get(key, "json");
  if (request.method === "DELETE") {
    if (previous?.userId === userId && previous.sessionHash === context.sessionHash) await removeDevice(env, id, previous);
    return json({ ok: true });
  }
  // Recheck the authoritative record when sending: stale indexes must not leak alerts.
  if (previous && previous.userId !== userId) await env.TOKEN_STORE.delete(indexKey(previous.userId, id));
  const record = {
    id, userId, sessionHash: context.sessionHash, sessionVersion: context.user.sessionVersion || 1,
    token, environment: body.environment, language: body.language === "tr" ? "tr" : "en",
    friends: body.friends !== false, challenges: body.challenges !== false, updatedAt: new Date().toISOString(),
  };
  if (previous && ["userId", "sessionHash", "token", "environment", "language", "friends", "challenges"].every(key => previous[key] === record[key])
      && Date.now() - Date.parse(previous.updatedAt) < 86400000) return json({ ok: true, pushAvailable: ready(env) });
  const devices = await listValues(env, `push-user:${userId}:`, 30);
  const oldest = devices.filter(x => x.id !== id).sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || "")).slice(9);
  await Promise.all(oldest.map(async item => {
    const current = await env.TOKEN_STORE.get("push-device:" + item.id, "json");
    if (current?.userId === userId) await removeDevice(env, item.id, current);
  }));
  await Promise.all([
    env.TOKEN_STORE.put(key, JSON.stringify(record), { expirationTtl: TTL }),
    env.TOKEN_STORE.put(indexKey(userId, id), JSON.stringify({ id, updatedAt: record.updatedAt }), { expirationTtl: TTL }),
  ]);
  return json({ ok: true, pushAvailable: ready(env) });
}

export async function deletePushAccount(env, userId) {
  const devices = await listValues(env, `push-user:${userId}:`, 100);
  await Promise.all(devices.map(async item => {
    const record = await env.TOKEN_STORE.get("push-device:" + item.id, "json");
    if (record?.userId === userId) await removeDevice(env, item.id, record);
    else await env.TOKEN_STORE.delete(indexKey(userId, item.id));
  }));
  const notifications = await listValues(env, `notification:${userId}:`, 1000);
  await Promise.all(notifications.map(item => env.TOKEN_STORE.delete(`notification:${userId}:${item.id}`)));
}

export async function removeSessionDevices(env, userId, sessionHash) {
  const devices = await listValues(env, `push-user:${userId}:`, 100);
  await Promise.all(devices.map(async item => {
    const record = await env.TOKEN_STORE.get("push-device:" + item.id, "json");
    if (record?.userId === userId && record.sessionHash === sessionHash) await removeDevice(env, item.id, record);
  }));
}

export function queueSocialNotification(env, ctx, userId, type, eventId) {
  // Optional alert failures cannot fail an already saved social action.
  const work = createNotification(env, userId, type, eventId).catch(() => console.warn("Tempo notification delivery unavailable"));
  if (ctx?.waitUntil) ctx.waitUntil(work);
  return work;
}

export async function createNotification(env, userId, type, eventId) {
  if (!["friend_request", "friend_accepted", "challenge_invite"].includes(type)) return;
  const id = await notificationID(type, eventId);
  const key = `notification:${userId}:${id}`;
  if (await env.TOKEN_STORE.get(key)) return;
  const notification = { id, type, createdAt: new Date().toISOString(), read: false, destination: "social" };
  await env.TOKEN_STORE.put(key, JSON.stringify(notification), { expirationTtl: TTL });
  // An inbox event never contains health or location data.
  const inbox = await listValues(env, `notification:${userId}:`, 100);
  await Promise.all(inbox.sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(50).map(item => env.TOKEN_STORE.delete(`notification:${userId}:${item.id}`)));
  if (!ready(env)) return;
  const user = await env.TOKEN_STORE.get("account-user:" + userId, "json");
  if (!user) return;
  const devices = await listValues(env, `push-user:${userId}:`, 20);
  await Promise.all(devices.map(async item => {
    const record = await env.TOKEN_STORE.get("push-device:" + item.id, "json");
    if (!record || record.userId !== userId) return;
    let session = await env.TOKEN_STORE.get("account-session:" + record.sessionHash);
    try { session = JSON.parse(session); } catch { session = { userId: session, version: 1 }; }
    if (!session || session.userId !== userId || (session.version || 1) !== (user.sessionVersion || 1)) {
      await removeDevice(env, item.id, record); return;
    }
    if ((type === "challenge_invite" && !record.challenges) || (type !== "challenge_invite" && !record.friends)) return;
    const tr = record.language === "tr";
    const messages = {
      friend_request: tr ? "Yeni bir arkadaşlık isteğin var." : "You have a new friend request.",
      friend_accepted: tr ? "Arkadaşlık isteğin kabul edildi." : "Your friend request was accepted.",
      challenge_invite: tr ? "Birlikte hareket etmek için yeni bir yarış davetin var." : "You have a new challenge invitation.",
    };
    const host = record.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${record.token}`, {
      method: "POST", signal: AbortSignal.timeout(8000),
      headers: {
        authorization: "bearer " + await providerToken(env), "apns-topic": TOPIC,
        "apns-push-type": "alert", "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400), "apns-collapse-id": id,
      },
      body: JSON.stringify({ aps: { alert: { title: "Tempo", body: messages[type] }, sound: "default", "thread-id": "tempo.social" }, tempo: { id, type, destination: "social" } }),
    });
    if (response.status === 410) await removeDevice(env, item.id, record);
    else if (response.status === 400) {
      const error = await response.json().catch(() => ({}));
      if (["BadDeviceToken", "DeviceTokenNotForTopic"].includes(error.reason)) await removeDevice(env, item.id, record);
    }
    if (!response.ok) console.warn("APNs alert status", response.status);
  }));
}

export async function providerToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const signatureID = env.APNS_KEY_ID + ":" + env.APNS_TEAM_ID + ":" + await digest(env.APNS_PRIVATE_KEY);
  if (cachedJWT?.signatureID === signatureID && now - cachedJWT.issuedAt < 2400) return cachedJWT.value;
  if (pendingJWT?.signatureID === signatureID) return pendingJWT.promise;
  const signing = { signatureID, promise: (async () => {
  const b64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const part = value => b64(encoder.encode(JSON.stringify(value)));
  const raw = env.APNS_PRIVATE_KEY.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(raw), c => c.charCodeAt(0)), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const unsigned = part({ alg: "ES256", kid: env.APNS_KEY_ID }) + "." + part({ iss: env.APNS_TEAM_ID, iat: now });
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(unsigned));
  const value = unsigned + "." + b64(new Uint8Array(signature));
  cachedJWT = { signatureID, issuedAt: now, value };
  return value;
  })() };
  pendingJWT = signing;
  try { return await signing.promise; }
  finally { if (pendingJWT === signing) pendingJWT = undefined; }
}
async function notificationID(type, eventId) {
  const hash = await digest(type + ":" + eventId);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}
async function removeDevice(env, id, record) {
  await Promise.all([env.TOKEN_STORE.delete("push-device:" + id), env.TOKEN_STORE.delete(indexKey(record.userId, id))]);
}
async function listValues(env, prefix, limit) {
  const values = [];
  let cursor;
  do {
    const page = await env.TOKEN_STORE.list({ prefix, limit: Math.min(limit - values.length, 1000), ...(cursor ? { cursor } : {}) });
    values.push(...(await Promise.all(page.keys.map(item => env.TOKEN_STORE.get(item.name, "json")))).filter(Boolean));
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor && values.length < limit);
  return values;
}
