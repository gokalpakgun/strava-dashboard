import test from 'node:test';
import assert from 'node:assert/strict';
import { NotificationInbox } from '../src/notification-inbox.js';
import { createNotification, handlePushRequest, deletePushAccount, queueSocialNotification } from '../src/push.js';
import { randomUUID, webcrypto } from 'node:crypto';
globalThis.crypto ||= webcrypto;
class Storage {
  values=new Map(); alarmTime=null;
  async get(k){return structuredClone(this.values.get(k));}
  async put(k,v){this.values.set(k,structuredClone(v));}
  async deleteAll(){this.values.clear();}
  async getAlarm(){return this.alarmTime;}
  async setAlarm(t){this.alarmTime=t;}
  async deleteAlarm(){this.alarmTime=null;}
}
function object(){const storage=new Storage();let queue=Promise.resolve();const state={storage,blockConcurrencyWhile(fn){const r=queue.then(fn);queue=r.catch(()=>{});return r;}};return {storage,inbox:new NotificationInbox(state)};}
function binding(){const instances=new Map();return {instances,idFromName:n=>n,get(id){if(!instances.has(id))instances.set(id,object());return {fetch:(url,init)=>instances.get(id).inbox.fetch(new Request(url,init))};}};}
const notice=(extra={})=>({id:randomUUID(),type:'friend_request',createdAt:new Date().toISOString(),read:false,destination:'social',...extra});
const call=(inbox,path,body)=>inbox.fetch(new Request('https://inbox.internal'+path,{method:body===undefined?'GET':'POST',...(body===undefined?{}:{body:JSON.stringify(body)})})).then(r=>r.json());
const fakeKV={get:async()=>null,list:async()=>({keys:[],list_complete:true}),delete:async()=>{},put:async()=>{throw Error('New inbox records must not use eventually-consistent KV');}};
const api=(path,body)=>new Request('https://apitempo.com'+path,{method:body===undefined?'GET':'POST',...(body===undefined?{}:{body:JSON.stringify(body)})});

test('durable inbox immediately returns a newly saved notification',async()=>{const {inbox}=object(),n=notice();assert.equal((await call(inbox,'/create',n)).created,true);const rows=(await call(inbox,'/list')).notifications;assert.equal(rows.length,1);assert.equal(rows[0].id,n.id);assert.equal(rows[0].read,false);assert.ok(Date.parse(rows[0].createdAt)>=Date.parse(n.createdAt));});
test('concurrent duplicate deliveries create exactly one durable notification',async()=>{const {inbox}=object(),n=notice();const r=await Promise.all(Array.from({length:10},()=>call(inbox,'/create',n)));assert.equal(r.filter(x=>x.created).length,1);assert.equal((await call(inbox,'/list')).notifications.length,1);});
test('durable read state is immediately visible to the next client',async()=>{const {inbox}=object(),n=notice();await call(inbox,'/create',n);await call(inbox,'/read',{id:n.id});assert.equal((await call(inbox,'/list')).notifications[0].read,true);});
test('durable inbox retains at most fifty recent records',async()=>{const {inbox}=object();for(let i=0;i<60;i++)await call(inbox,'/create',notice());assert.equal((await call(inbox,'/list')).notifications.length,50);});
test('legacy import preserves read state and does not overwrite a newer durable state',async()=>{const {inbox}=object(),n=notice({read:true});await call(inbox,'/import',[n]);await call(inbox,'/import',[{...n,read:false}]);assert.equal((await call(inbox,'/list')).notifications[0].read,true);});
test('expired imports are excluded and cannot extend retention',async()=>{const {inbox,storage}=object();await call(inbox,'/import',[notice({createdAt:new Date(Date.now()-36*86400000).toISOString()})]);assert.deepEqual((await call(inbox,'/list')).notifications,[]);assert.equal(storage.alarmTime,null);});
test('retention alarm deletes expired data even without an app visit',async()=>{const {inbox,storage}=object();storage.values.set('notices',[notice({createdAt:new Date(Date.now()-36*86400000).toISOString()})]);await inbox.alarm();assert.equal(storage.values.size,0);assert.equal(storage.alarmTime,null);});
test('account deletion clears durable data and its scheduled alarm',async()=>{const {inbox,storage}=object();await call(inbox,'/create',notice());assert.ok(storage.alarmTime>Date.now());await call(inbox,'/delete',{});assert.equal(storage.values.size,0);assert.equal(storage.alarmTime,null);});
test('invalid durable notice types are rejected',async()=>{const {inbox}=object();const r=await inbox.fetch(new Request('https://inbox.internal/create',{method:'POST',body:JSON.stringify(notice({type:'medical_data'}))}));assert.equal(r.status,400);});
test('Worker inbox uses the authenticated account durable object despite stale KV',async()=>{
 const env={TOKEN_STORE:fakeKV,NOTIFICATION_INBOX:binding()};await createNotification(env,'alice','friend_request','a');const a={user:{id:'alice'}},b={user:{id:'bob'}};
 let mine=await (await handlePushRequest(api('/api/account/notifications'),env,a)).json();assert.equal(mine.inboxStorage,'durable');assert.equal(mine.notifications.length,1);
 assert.equal((await (await handlePushRequest(api('/api/account/notifications'),env,b)).json()).notifications.length,0);
 await handlePushRequest(api('/api/account/notifications/read',{id:mine.notifications[0].id}),env,b);
 assert.equal((await (await handlePushRequest(api('/api/account/notifications'),env,a)).json()).notifications[0].read,false);
 await handlePushRequest(api('/api/account/notifications/read',{id:mine.notifications[0].id}),env,a);
 assert.equal((await (await handlePushRequest(api('/api/account/notifications'),env,a)).json()).notifications[0].read,true);
 await deletePushAccount(env,'alice');assert.equal((await (await handlePushRequest(api('/api/account/notifications'),env,a)).json()).notifications.length,0);
});
test('background APNs scheduling never precedes durable inbox persistence',async()=>{const env={TOKEN_STORE:fakeKV,NOTIFICATION_INBOX:binding()};const jobs=[];await queueSocialNotification(env,{waitUntil:p=>jobs.push(p)},'alice','friend_request','event');const inbox=await env.NOTIFICATION_INBOX.get('alice').fetch('https://inbox.internal/list').then(r=>r.json());assert.equal(inbox.notifications.length,1);await Promise.all(jobs);});
