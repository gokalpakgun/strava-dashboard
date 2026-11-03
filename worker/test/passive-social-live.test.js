import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID, webcrypto } from 'node:crypto';
import { PassiveCohort, PassiveRecipient, handlePassiveSocial, deletePassiveSocial } from '../src/passive-social-live.js';
import { NotificationInbox } from '../src/notification-inbox.js';
globalThis.crypto ||= webcrypto;
class KV {values=new Map();async get(k,t){const v=this.values.get(k);return v===undefined?null:t==='json'?JSON.parse(v):v;}async put(k,v){this.values.set(k,String(v));}async delete(k){this.values.delete(k);}async list({prefix}){return {keys:[...this.values.keys()].filter(k=>k.startsWith(prefix)).map(name=>({name})),list_complete:true};}}
class Storage {values=new Map();alarm=null;async get(k){return structuredClone(this.values.get(k));}async put(k,v){this.values.set(k,structuredClone(v));}async deleteAll(){this.values.clear();}async getAlarm(){return this.alarm;}async setAlarm(t){this.alarm=t;}async deleteAlarm(){this.alarm=null;}}
function binding(Class,env){const instances=new Map();return {instances,idFromName:id=>id,get(id){if(!instances.has(id)){const storage=new Storage();let q=Promise.resolve();const state={id:{toString:()=>id},storage,blockConcurrencyWhile(fn){const r=q.then(fn);q=r.catch(()=>{});return r;}};instances.set(id,{object:new Class(state,env),storage});}return {fetch:(url,init)=>instances.get(id).object.fetch(new Request(url,init))};}};}
async function fixture(){const env={TOKEN_STORE:new KV()};env.NOTIFICATION_INBOX=binding(NotificationInbox,env);env.PASSIVE_COHORT=binding(PassiveCohort,env);env.PASSIVE_RECIPIENT=binding(PassiveRecipient,env);
const users=['a','b','c','d'].map((s,i)=>({id:s.repeat(40),token:String(i+1).repeat(64),displayName:'Test '+s,sessionVersion:1}));
for(const u of users){await env.TOKEN_STORE.put('account-user:'+u.id,JSON.stringify(u));await env.TOKEN_STORE.put('account-session:'+createHash('sha256').update(u.token).digest('hex'),JSON.stringify({userId:u.id,version:1}));await env.TOKEN_STORE.put('social-state:'+u.id,JSON.stringify({friends:users.filter(x=>x!==u).map(x=>x.id),blocked:[]}));}
return {env,users};}
async function call(env,user,path='',body,method=body===undefined?'GET':'POST'){const request=new Request('https://apitempo.com/api/account/passive-social'+path,{method,headers:{'Content-Type':'application/json',...(user?{Authorization:'Bearer '+user.token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});const r=await handlePassiveSocial(request,env,new URL(request.url));return {status:r.status,value:await r.json()};}
async function create(env,users,extra={}){const id=randomUUID(),r=await call(env,users[0],'/groups',{id,friendIds:users.slice(1,3).map(x=>x.id),goal:'sensorSessions',target:1,stake:20,...extra});assert.equal(r.status,201,JSON.stringify(r));return id;}
async function accept(env,users,id){for(const user of users.slice(0,3)){const r=await call(env,user,'/groups/'+id,{action:'accept',consent:true});assert.equal(r.status,200,JSON.stringify(r));}}
async function clock(time,fn){const previous=Date.now;Date.now=()=>time;try{return await fn();}finally{Date.now=previous;}}
const T=Date.UTC(2026,10,3,12),DAY=86400000;
test('real API rejects anonymous use, wrong friendship and unaccepted terms',async()=>clock(T,async()=>{
 const {env,users}=await fixture();assert.equal((await call(env,null)).status,401);
 assert.equal((await call(env,users[0],'/groups',{id:randomUUID(),friendIds:[users[1].id]})).status,400);
 const id=await create(env,users);assert.equal((await call(env,users[1],'/groups/'+id,{action:'accept'})).status,400);
 assert.equal((await call(env,users[3],'/groups/'+id,{action:'accept',consent:true})).status,403);
 const other=JSON.parse(await env.TOKEN_STORE.get('social-state:'+users[1].id));other.blocked=[users[0].id];await env.TOKEN_STORE.put('social-state:'+users[1].id,JSON.stringify(other));
 assert.equal((await call(env,users[0],'/groups',{id:randomUUID(),friendIds:users.slice(1,3).map(u=>u.id)})).status,400);
}));
test('creation reaches all three inboxes and concurrent acceptance reserves one stake',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);
 for(const u of users.slice(0,3)){const r=await call(env,u);assert.equal(r.value.groups[0].id,id);assert.equal(r.value.groups[0].members.length,3);}
 const responses=await Promise.all(Array.from({length:4},()=>call(env,users[0],'/groups/'+id,{action:'accept',consent:true})));
 assert.ok(responses.every(r=>r.status===200));
 const g=(await call(env,users[0])).value.groups[0];assert.equal(g.balance,80);assert.equal(g.locked,20);
 const inbox=env.NOTIFICATION_INBOX.instances.get(users[1].id);assert.equal((await inbox.storage.get('notices')).filter(n=>n.type==='circle_invite').length,1);
}));
test('device sync excludes manual/foreign-source reports and payout alarm is idempotent',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users,{target:2});await accept(env,users,id);
 let raw=await env.PASSIVE_COHORT.instances.get(id).storage.get('group'),start=raw.pledge.startsAt;
 await clock(start+DAY,async()=>{
   const r={id:randomUUID(),source:'healthkit',manual:false,start:start+3600000,end:start+5400000,heartCoverage:1};
   await call(env,users[0],'/sync',{sessions:[{...r,id:randomUUID(),manual:true},{...r,id:randomUUID(),source:'strava'},r,r],queryComplete:true});
   const view=(await call(env,users[0])).value.groups[0];assert.equal(view.members.find(m=>m.id===users[0].id).days,1);
   assert.equal(JSON.stringify(view).includes('heartCoverage'),false);assert.equal(JSON.stringify(view).includes('fingerprint'),false);
   for(const u of users.slice(1,3))await call(env,u,'/sync',{sessions:[{...r,id:randomUUID()}],queryComplete:true});
 });
 await clock(start+2*DAY,async()=>{await call(env,users[0],'/sync',{sessions:[{id:randomUUID(),source:'healthkit',manual:false,start:start+DAY+3600000,end:start+DAY+5400000,heartCoverage:1}],queryComplete:true});});
 await clock(raw.pledge.endsAt+DAY,async()=>{for(const u of users.slice(0,3))await call(env,u,'/sync',{sessions:[],queryComplete:true});});
 await clock(raw.pledge.finalizeAt+1,async()=>{const object=env.PASSIVE_COHORT.instances.get(id).object;await Promise.all([object.alarm(),object.alarm()]);const g=(await call(env,users[0])).value.groups[0];assert.equal(g.status,'settled');assert.equal(g.balance,140);});
}));
test('missing sync refunds the week and gym presence cannot fill a sensor target',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);await accept(env,users,id);const raw=await env.PASSIVE_COHORT.instances.get(id).storage.get('group');
 await clock(raw.pledge.startsAt+DAY,async()=>{await call(env,users[0],'/sync',{sessions:[{id:randomUUID(),source:'corelocation',manual:false,start:raw.pledge.startsAt+100000,end:raw.pledge.startsAt+1900000,heartCoverage:0}],venueComplete:true});const g=(await call(env,users[0])).value.groups[0];assert.equal(g.members[0].days,0);});
 await clock(raw.pledge.finalizeAt+1,async()=>{const g=(await call(env,users[0])).value.groups[0];assert.equal(g.status,'void');assert.equal(g.balance,100);assert.ok(g.members.every(m=>m.activity==='hidden'));});
}));
test('per-group recipient consent, quiet hours and simultaneous nudge attempts enforce one recipient quota',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);await accept(env,users,id);
 await call(env,users[1],'/groups/'+id,{action:'preferences',ghosts:false,nudges:true,timeZone:'UTC'});
 const instance=env.PASSIVE_COHORT.instances.get(id),g=await instance.storage.get('group');
 g.activity[users[1].id]={joinedAt:T-6*DAY,lastSessionAt:T-5*DAY,lastSyncAt:T};await instance.storage.put('group',g);
 const results=await Promise.all([users[0],users[2]].map(u=>call(env,u,'/groups/'+id,{action:'nudge',recipient:users[1].id})));
 assert.equal(results.filter(r=>r.status===200).length,1);assert.equal(results.filter(r=>r.status===429).length,1);
 await env.PASSIVE_RECIPIENT.instances.get(users[1].id).object.alarm();
 const notices=await env.NOTIFICATION_INBOX.instances.get(users[1].id).storage.get('notices');assert.equal(notices.filter(n=>n.type==='passive_nudge').length,1);
}));
test('automatic ghost pairing uses only opted-in curves and produces one result per participant',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);await accept(env,users,id);
 for(const user of users.slice(0,2))await call(env,user,'/groups/'+id,{action:'preferences',ghosts:true,nudges:false,timeZone:'UTC'});
 const trace={sport:'running',metric:'relativeEffort',points:Array.from({length:30},()=>({value:50,observedSeconds:60}))};
 const a={id:randomUUID(),source:'healthkit',manual:false,start:T-3600000,end:T-1800000,heartCoverage:1,trace};
 await call(env,users[0],'/sync',{sessions:[a],queryComplete:true});
 let view=(await call(env,users[1])).value.groups[0];assert.equal(view.ghost.status,'pending');
 await clock(T+3600000,async()=>{const b={...a,id:randomUUID(),start:T+1000,end:T+1801000};await call(env,users[1],'/sync',{sessions:[b],queryComplete:true});await call(env,users[1],'/sync',{sessions:[b],queryComplete:true});view=(await call(env,users[1])).value.groups[0];assert.equal(view.result.status,'comparable');const g=await env.PASSIVE_COHORT.instances.get(id).storage.get('group');assert.equal(g.outbox.filter(n=>n.type==='ghost_result').length,2);});
}));
test('withdrawal removes sharing and account deletion closes membership without touching classic friends',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);await accept(env,users,id);
 let r=await call(env,users[0],'/groups/'+id,{action:'withdraw'});assert.equal(r.status,200);assert.equal(r.value.balance,100);assert.equal(r.value.myAccepted,false);
 await deletePassiveSocial(env,users[0].id);assert.deepEqual((await call(env,users[0])).value.groups,[]);
 assert.deepEqual((await call(env,users[1])).value.groups,[]);
 const classic=await env.TOKEN_STORE.get('social-state:'+users[0].id,'json');assert.equal(classic.friends.length,3);
}));
test('account cleanup is idempotent even when another member already closed the group',async()=>clock(T,async()=>{
 const {env,users}=await fixture(),id=await create(env,users);await accept(env,users,id);
 await deletePassiveSocial(env,users[0].id);await deletePassiveSocial(env,users[1].id);await deletePassiveSocial(env,users[1].id);
 assert.deepEqual((await call(env,users[1])).value.groups,[]);
}));
