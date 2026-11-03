import { accountContext } from './account.js';
import { readLimitedText } from './http.js';
import { queueSocialNotification } from './push.js';
import { createPledge, acceptPledge, nextPledgeWeek, advancePledge, withdrawPledgeConsent,
  applyTrustedReceipt, applyTrustedSync, pledgeProjection, passiveMemberStatus, nudgeDecision,
  makeGhostTrace, createGhostMatch, finishGhostMatch } from './passive-social-core.js';

const DAY=86400000, ROOT='/api/account/passive-social';
const uid=id=>typeof id==='string'&&/^[a-f0-9]{40}$/.test(id);
const gid=id=>typeof id==='string'&&/^[a-f0-9-]{36}$/.test(id);
const json=(body,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
export async function passiveCall(binding,id,body) {
  const r=await binding.get(binding.idFromName(id)).fetch('https://passive.internal/',{method:'POST',body:JSON.stringify(body)});
  const value=await r.json(); if(!r.ok) throw Object.assign(new Error(value.error||'circle.failed'),{status:r.status}); return value;
}
const recipient=(env,id,body)=>passiveCall(env.PASSIVE_RECIPIENT,id,body);
const cohort=(env,id,body)=>passiveCall(env.PASSIVE_COHORT,id,body);
async function connected(env,a,b) {
  if(a===b)return true;
  const [x,y]=await Promise.all([env.TOKEN_STORE.get('social-state:'+a,'json'),env.TOKEN_STORE.get('social-state:'+b,'json')]);
  return x?.friends?.includes(b)&&y?.friends?.includes(a)&&!x?.blocked?.includes(b)&&!y?.blocked?.includes(a);
}
async function relations(env,ids){for(let i=0;i<ids.length;i++)for(let j=i+1;j<ids.length;j++)if(!await connected(env,ids[i],ids[j]))return false;return true;}

export async function handlePassiveSocial(request,env,url,ctx) {
  if(url.pathname!==ROOT&&!url.pathname.startsWith(ROOT+'/'))return null;
  const auth=await accountContext(request,env);if(auth.response)return auth.response;
  if(!env.PASSIVE_COHORT||!env.PASSIVE_RECIPIENT)return json({error:'circle.serverPending'},503);
  const actor=auth.user.id;
  try {
    await recipient(env,actor,{action:'rate'});
    let body={};if(request.method==='POST'){try{body=JSON.parse(await readLimitedText(request,220000));}catch{return json({error:'circle.invalid'},400);}if(!body||Array.isArray(body))return json({error:'circle.invalid'},400);}
    if(url.pathname===ROOT&&request.method==='GET') {
      const mine=await recipient(env,actor,{action:'list'});
      const rows=await Promise.all(mine.groups.map(async id=>{try{
        const view=await cohort(env,id,{action:'view',actor});
        if(!await relations(env,view.members.map(p=>p.id))){await cohort(env,id,{action:'deleteMember',actor});await recipient(env,actor,{action:'remove',id});return null;}
        view.members=await Promise.all(view.members.map(async p=>{const u=await env.TOKEN_STORE.get('account-user:'+p.id,'json');return {...p,name:u?.displayName||u?.username||'Tempo'};}));return view;
      }catch(e){if([403,410].includes(e.status)){await recipient(env,actor,{action:'remove',id});return null;}throw e;}}));
      return json({groups:rows.filter(Boolean),assurance:'device-reported-v1'});
    }
    if(url.pathname===ROOT+'/groups'&&request.method==='POST') {
      const ids=[actor,...(Array.isArray(body.friendIds)?body.friendIds:[])];
      if(!gid(body.id)||ids.length<3||ids.length>6||new Set(ids).size!==ids.length||!ids.every(uid)||!await relations(env,ids))return json({error:'circle.membersRequired'},400);
      // Bütün indeksleri önce ayır; tekrar aynı ID ile çağrılırsa rezervasyon tekrarlanmaz.
      const reserved=[];
      try{for(const id of ids){const r=await recipient(env,id,{action:'join',id:body.id});if(r.added)reserved.push(id);}
        await cohort(env,body.id,{action:'create',id:body.id,actor,members:ids,goal:body.goal,target:body.target,stake:body.stake});
        for(const id of ids.filter(id=>id!==actor))await queueSocialNotification(env,ctx,id,'circle_invite',body.id);
      }catch(e){for(const id of reserved)await recipient(env,id,{action:'remove',id:body.id});throw e;}
      return json({ok:true},201);
    }
    if(url.pathname===ROOT+'/sync'&&request.method==='POST') {
      if(!Array.isArray(body.sessions)||body.sessions.length>24)return json({error:'circle.invalid'},400);
      const mine=await recipient(env,actor,{action:'timezone',timeZone:body.timeZone});
      for(const id of mine.groups){let view;try{view=await cohort(env,id,{action:'view',actor});}catch(e){if([403,410].includes(e.status)){await recipient(env,actor,{action:'remove',id});continue;}throw e;}if(await relations(env,view.members.map(p=>p.id)))await cohort(env,id,{action:'sync',actor,sessions:body.sessions,queryComplete:body.queryComplete===true,venueComplete:body.venueComplete===true});else await cohort(env,id,{action:'revoke',actor});}
      return json({ok:true});
    }
    const match=url.pathname.match(/^\/api\/account\/passive-social\/groups\/([a-f0-9-]{36})$/);
    if(match&&request.method==='POST') {
      const id=match[1],view=await cohort(env,id,{action:'view',actor});
        if(!await relations(env,view.members.map(p=>p.id))){await cohort(env,id,{action:'deleteMember',actor});await recipient(env,actor,{action:'remove',id});return json({error:'circle.relationshipChanged'},409);}
      if(body.action==='nudge') {
        if(!uid(body.recipient))return json({error:'circle.invalid'},400);
        const target=view.members.find(p=>p.id===body.recipient);
        if(!target||!view.myAccepted||!target.accepted||!target.nudges)return json({error:'circle.notAllowed'},403);
        // Alıcı DO kotası gruplar arasında tek ve atomiktir; durum istemciden alınmaz.
        return json(await recipient(env,body.recipient,{action:'nudge',groupId:id,sender:actor,recipient:body.recipient,members:view.members.map(p=>p.id),status:target.activity}));
      }
      if(!['accept','withdraw','preferences','renew','leave'].includes(body.action))return json({error:'circle.invalid'},400);
      if(body.action==='leave'){await cohort(env,id,{action:'deleteMember',actor});await recipient(env,actor,{action:'remove',id});return json({ok:true});}
      if(body.action==='preferences')await recipient(env,actor,{action:'preferences',groupId:id,nudges:body.nudges===true,timeZone:body.timeZone});
      return json(await cohort(env,id,{action:body.action,actor,consent:body.consent,ghosts:body.ghosts===true,nudges:body.nudges===true}));
    }
    if(url.pathname===ROOT&&request.method==='DELETE'){await deletePassiveSocial(env,actor);return json({ok:true});}
    return json({error:'circle.invalid'},405);
  }catch(e){return json({error:e.message?.startsWith('circle.')?e.message:'circle.failed'},e.status||400);}
}
export async function deletePassiveSocial(env,actor) {
  if(!env.PASSIVE_RECIPIENT||!env.PASSIVE_COHORT)return;
  const mine=await recipient(env,actor,{action:'list'});
  for(const id of mine.groups){try{await cohort(env,id,{action:'deleteMember',actor});}catch(e){if(![403,410].includes(e.status))throw e;}}
  await recipient(env,actor,{action:'delete'});
}

// İnternetten doğrudan erişilemez. Atomik çember defteri ve kalıcı bildirim outbox'ı.
export class PassiveCohort {
  constructor(state,env){this.state=state;this.env=env;}
  async fetch(request){let b;try{b=await request.json();}catch{return json({error:'circle.invalid'},400);}
    try{return await this.state.blockConcurrencyWhile(async()=>{
      let g=await this.state.storage.get('group');const now=Date.now();
      if(b.action==='create'){
        if(g){if(g.creator!==b.actor||JSON.stringify(g.pledge.members)!==JSON.stringify([...b.members].sort()))return json({error:'circle.invalid'},409);return json({ok:true});}
        if(!Array.isArray(b.members)||!b.members.includes(b.actor)||!b.members.every(uid))return json({error:'circle.invalid'},400);
        const id=b.id;
        const pledge=createPledge({id,members:b.members,startsAt:nextPledgeWeek(now),goal:b.goal,target:b.target,stake:b.stake,balances:Object.fromEntries(b.members.map(id=>[id,100]))},now);
        g={id,creator:b.actor,pledge,preferences:{},activity:{},traces:{},matches:{},results:{},outbox:[],sequence:1};
      }else{
        if(!g||!g.pledge.members.includes(b.actor))return json({error:'circle.notAllowed'},403);
        if(g.deleted)return json({error:'circle.closed'},410);
        g.pledge=advancePledge(g.pledge,now);
        if(b.action==='accept'){if(b.consent!==true)return json({error:'circle.consentRequired'},400);g.pledge=acceptPledge(g.pledge,b.actor,{version:1,activity:true,creditLoss:true},now);g.activity[b.actor]??={joinedAt:now,lastSyncAt:null,lastSessionAt:null};}
        else if(['withdraw','revoke','deleteMember'].includes(b.action)){
          g.pledge=withdrawPledgeConsent(g.pledge,b.actor,now);delete g.activity[b.actor];delete g.traces[b.actor];g.matches={};g.results={};g.preferences[b.actor]={ghosts:false,nudges:false};
          if(b.action==='deleteMember'){g.deleted=true;g.traces={};g.activity={};g.outbox=[];g.pledge.receipts=[];}
        }else if(b.action==='preferences'){
          if(!g.pledge.consent[b.actor]?.activity)return json({error:'circle.notAllowed'},403);
          g.preferences[b.actor]={ghosts:b.ghosts,nudges:b.nudges};
          if(!b.ghosts){delete g.traces[b.actor];g.matches=Object.fromEntries(Object.entries(g.matches).filter(([,m])=>m.challenger!==b.actor&&m.ghost.owner!==b.actor));g.results={};}
        }else if(b.action==='renew'){
          if(!['settled','void'].includes(g.pledge.status))return json({error:'circle.notReady'},409);
          g.sequence++;g.pledge=createPledge({id:g.pledge.id+'_'+g.sequence,members:g.pledge.members,startsAt:nextPledgeWeek(now),goal:g.pledge.goal,target:g.pledge.target,stake:g.pledge.stake,balances:g.pledge.balances},now);g.activity={};g.traces={};g.matches={};g.results={};
        }else if(b.action==='sync'){
          if(g.pledge.consent[b.actor]?.activity&&!['settled','void'].includes(g.pledge.status)){
            const a=g.activity[b.actor]||{joinedAt:now};
            for(const input of (b.sessions||[]).slice(0,24)){
              const r=validatedReport(input,b.actor,now);if(!r)continue;
              if((g.pledge.goal==='sensorSessions'&&r.source==='healthkit')||(g.pledge.goal==='venueVisits'&&r.source==='corelocation')){
                a.lastSessionAt=Math.max(a.lastSessionAt||0,r.end);
                try{g.pledge=applyTrustedReceipt(g.pledge,r,now);}catch{/* Haftası dışında kalan geçmiş kayıt yalnız aktifliğe destek olur. */}
              }
              if(g.preferences[b.actor]?.ghosts&&r.source==='healthkit'&&input.trace){
                try{
                  const trace=makeGhostTrace({...input.trace,id:r.id,owner:b.actor,startedAt:r.start,durationSeconds:Math.floor((r.end-r.start)/1000),consentVersion:1},now);
                  const match=g.matches[b.actor];
                  if(match?.status==='pending'&&g.preferences[match.ghost.owner]?.ghosts){try{const done=finishGhostMatch(match,trace,now);g.matches[b.actor]=done;for(const event of done.events){g.results[event.recipient]={id:done.id,recordedAt:now,...done.result};enqueue(g,event);}}catch{}}
                  if(!g.traces[b.actor]||g.traces[b.actor].startedAt<trace.startedAt)g.traces[b.actor]=trace;
                }catch{}
              }
            }
            // Beta sözleşmesinde yalnız cihazın tamamlanmış sorgu bildirimi kullanılır.
            // Bu App Attest veya HealthKit verisi için sunucu doğrulaması değildir.
            const sourceAvailable=g.pledge.receipts.some(r=>r.owner===b.actor);
            const coverageReported=(b.queryComplete===true&&g.pledge.goal==='sensorSessions')||(b.venueComplete===true&&g.pledge.goal==='venueVisits');
            // Tamamen boş okuma, read izni veya o haftanın eksiksizliği için kanıt olamaz.
            if(sourceAvailable&&coverageReported){a.lastSyncAt=now;if(now>=g.pledge.startsAt)try{g.pledge=applyTrustedSync(g.pledge,b.actor,Math.min(now,g.pledge.endsAt),now);}catch{}}
            g.activity[b.actor]=a;
            for(const id of g.pledge.members)if(id!==b.actor&&g.pledge.consent[id]?.activity&&g.preferences[id]?.ghosts&&g.preferences[b.actor]?.ghosts&&g.traces[b.actor]&&(!g.matches[id]||g.matches[id].expiresAt<now)){
              try{g.matches[id]=createGhostMatch({id:crypto.randomUUID(),groupId:g.pledge.id,members:g.pledge.members,ghost:g.traces[b.actor],challenger:id,ghostConsent:true,challengerConsent:true},now);}catch{}
            }
          }
        }else if(b.action!=='view')return json({error:'circle.invalid'},400);
      }
      if(!g.deleted&&g.pledge.settlement)for(const id of g.pledge.members)enqueue(g,{id:g.pledge.settlement.id+':'+id,recipient:id,type:'pledge_settled'});
      // Aggregate + outbox tek yazma kapısı içinde; dış ağ işlemi bundan sonra yapılır.
      prune(g,now);
      await this.state.storage.put('group',g);await this.schedule(g,now);
      const p=pledgeProjection(g.pledge,b.actor);
      const live=!['settled','void'].includes(g.pledge.status);
      return json({...p,id:g.id,myAccepted:live&&!!g.pledge.consent[b.actor]?.activity,myGhosts:!!g.preferences[b.actor]?.ghosts,myNudges:!!g.preferences[b.actor]?.nudges,
        members:p.members.map(m=>({...m,nudges:!!g.preferences[m.id]?.nudges,activity:passiveMemberStatus({optedIn:live&&m.accepted,paused:false,...g.activity[m.id]},now)})),
        ghost:g.matches[b.actor]?{status:g.matches[b.actor].status,expiresAt:g.matches[b.actor].expiresAt}:null,result:g.results[b.actor]||null});
    });}catch(e){return json({error:e.message?.startsWith('circle.')?e.message:'circle.failed'},400);}}
  async schedule(g,now){const next=[g.pledge.startsAt,g.pledge.endsAt,g.pledge.finalizeAt,g.pledge.finalizeAt+30*DAY,g.pledge.finalizeAt+90*DAY,...Object.values(g.traces).map(x=>x.expiresAt),...Object.values(g.matches).map(x=>x.expiresAt),...(g.outbox.some(x=>!x.sent)?[now+60000]:[])].filter(t=>t>now).sort((a,b)=>a-b)[0];if(next)await this.state.storage.setAlarm(next);else await this.state.storage.deleteAlarm();}
  async drain(g){let changed=false;for(const e of g.outbox.filter(x=>!x.sent).slice(0,12)){const result=await queueSocialNotification(this.env,this.state,e.recipient,e.type,e.id);if(result?.queued){e.sent=true;changed=true;}}if(changed)await this.state.storage.put('group',g);}
  async alarm(){await this.state.blockConcurrencyWhile(async()=>{const g=await this.state.storage.get('group');if(!g)return;if(Date.now()>=g.pledge.finalizeAt+90*DAY){await this.state.storage.deleteAll();await this.state.storage.deleteAlarm();return;}prune(g,Date.now());if(!g.deleted){g.pledge=advancePledge(g.pledge,Date.now());if(g.pledge.settlement)for(const id of g.pledge.members)enqueue(g,{id:g.pledge.settlement.id+':'+id,recipient:id,type:'pledge_settled'});await this.state.storage.put('group',g);await this.drain(g);}else await this.state.storage.put('group',g);await this.schedule(g,Date.now());});}
}
function prune(g,now){g.traces=Object.fromEntries(Object.entries(g.traces).filter(([,t])=>t.expiresAt>now));g.matches=Object.fromEntries(Object.entries(g.matches).filter(([,m])=>m.expiresAt>now));g.results=Object.fromEntries(Object.entries(g.results).filter(([,r])=>r.recordedAt>now-30*DAY));if(now>=g.pledge.finalizeAt+30*DAY){g.pledge.receipts=[];g.pledge.syncThrough={};g.activity={};}}
function enqueue(g,event){if(!g.outbox.some(x=>x.id===event.id))g.outbox.push({...event,sent:false});g.outbox=g.outbox.slice(-100);}
function validatedReport(input,owner,now){
  if(!input||!gid(input.id)||input.manual!==false||!['healthkit','corelocation'].includes(input.source)||!Number.isFinite(input.start)||!Number.isFinite(input.end)||input.end>now||input.start<now-7*DAY||(input.end-input.start)<900000||(input.end-input.start)>14400000)return null;
  if(input.source==='healthkit'&&!(Number.isFinite(input.heartCoverage)&&input.heartCoverage>=0.7&&input.heartCoverage<=1))return null;
  return {id:input.id,fingerprint:input.id,owner,source:input.source,assurance:input.source==='healthkit'?'sensor-source':'venue-presence',policyVersion:1,wasManuallyEntered:false,start:input.start,end:input.end,verifiedAt:now};
}

export class PassiveRecipient {
  constructor(state,env){this.state=state;this.env=env;}
  async fetch(request){let b;try{b=await request.json();}catch{return json({error:'circle.invalid'},400);}
    return this.state.blockConcurrencyWhile(async()=>{
      let s=await this.state.storage.get('recipient')||{groups:[],nudgeGroups:{},timeZone:'UTC',lastNudge:null,outbox:[]};s.nudgeGroups??={};
      if(b.action==='delete'){await this.state.storage.deleteAll();await this.state.storage.deleteAlarm();return json({ok:true});}
      let added=false;
      if(b.action==='rate'){if(!s.windowAt||Date.now()-s.windowAt>=60000){s.windowAt=Date.now();s.requests=0;}if((s.requests||0)>=40)return json({error:'circle.rateLimited'},429);s.requests=(s.requests||0)+1;}
      else if(b.action==='join'){if(!gid(b.id))return json({error:'circle.invalid'},400);if(!s.groups.includes(b.id)){if(s.groups.length>=8)return json({error:'circle.groupLimit'},409);s.groups.push(b.id);added=true;}}
      else if(b.action==='remove')s.groups=s.groups.filter(x=>x!==b.id);
      else if(b.action==='preferences'){if(!s.groups.includes(b.groupId))return json({error:'circle.notAllowed'},403);s.nudgeGroups[b.groupId]=b.nudges===true;try{new Intl.DateTimeFormat('en',{timeZone:b.timeZone}).format();s.timeZone=b.timeZone;}catch{}}
      else if(b.action==='timezone'){if(typeof b.timeZone==='string')try{new Intl.DateTimeFormat('en',{timeZone:b.timeZone}).format();s.timeZone=b.timeZone;}catch{}}
      else if(b.action==='nudge'){
        if(!s.groups.includes(b.groupId))return json({error:'circle.notAllowed'},403);
        const decision=nudgeDecision({...b,friends:true,blocked:false,optedIn:s.nudgeGroups[b.groupId]===true,lastRecipientNudgeAt:s.lastNudge,timeZone:s.timeZone},Date.now());
        if(!decision.allowed)return json({error:'circle.nudgeUnavailable'},429);
        s.lastNudge=Date.now();s.outbox.push({id:decision.eventId,recipient:decision.recipient,sender:b.sender,groupId:b.groupId,createdAt:Date.now(),type:'passive_nudge'});
      }else if(b.action!=='list')return json({error:'circle.invalid'},400);
      await this.state.storage.put('recipient',s);
      await this.state.storage.setAlarm(Date.now()+60000);
      return json({groups:s.groups,ok:true,added});
    });}
  async alarm(){await this.state.blockConcurrencyWhile(async()=>{const s=await this.state.storage.get('recipient');if(!s)return;const remaining=[];for(const e of s.outbox){
    if(!s.nudgeGroups[e.groupId]||Date.now()-e.createdAt>DAY||!await connected(this.env,e.sender,e.recipient))continue;
    let view;try{view=await cohort(this.env,e.groupId,{action:'view',actor:e.recipient});}catch{continue;}
    const me=view.members.find(x=>x.id===e.recipient);if(!view.myAccepted||!me?.nudges||me.activity!=='atRisk')continue;
    const r=await queueSocialNotification(this.env,this.state,e.recipient,e.type,e.id);if(!r?.queued)remaining.push(e);
  }s.outbox=remaining;await this.state.storage.put('recipient',s);if(remaining.length)await this.state.storage.setAlarm(Date.now()+3600000);else await this.state.storage.deleteAlarm();});}
}
