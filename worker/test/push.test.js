import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, webcrypto } from 'node:crypto';
import worker from '../src/index.js';
import { handlePushRequest, createNotification, providerToken, deletePushAccount, removeSessionDevices } from '../src/push.js';
import { handleSocialRequest } from '../src/social.js';
globalThis.crypto ||= webcrypto;
const pair=generateKeyPairSync('ec',{namedCurve:'P-256'});
const pem=pair.privateKey.export({type:'pkcs8',format:'pem'});
class KV {
  values=new Map();
  async get(key,type){const v=this.values.get(key);return v===undefined?null:type==='json'?JSON.parse(v):v;}
  async put(k,v){this.values.set(k,String(v));}
  async delete(k){this.values.delete(k);}
  async list({prefix,limit=1000}){return {keys:[...this.values.keys()].filter(k=>k.startsWith(prefix)).slice(0,limit).map(name=>({name})),list_complete:true};}
}
async function fixture(){
  const env={TOKEN_STORE:new KV(),APNS_KEY_ID:'TESTKEY123',APNS_TEAM_ID:'TESTTEAM12',APNS_PRIVATE_KEY:pem};
  const users=['a','b'].map((c,i)=>({id:c.repeat(40),username:'athlete_'+c,sessionVersion:1,token:String(i+1).repeat(64)}));
  const contexts=[];
  for(const user of users){const sessionHash=createHash('sha256').update(user.token).digest('hex');await env.TOKEN_STORE.put('account-user:'+user.id,JSON.stringify(user));await env.TOKEN_STORE.put('account-username:'+user.username,user.id);await env.TOKEN_STORE.put('account-session:'+sessionHash,JSON.stringify({userId:user.id,version:1}));contexts.push({user,sessionHash});}
  return {env,contexts};
}
function req(path,method='POST',body){return new Request('https://apitempo.com'+path,{method,headers:{'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});}
const device=(token='e'.repeat(64),overrides={})=>({token,environment:'production',language:'en',...overrides});
const register=(env,context,body=device(),method='POST')=>handlePushRequest(req('/api/account/push/devices',method,body),env,context);
const keys=(env,prefix)=>[...env.TOKEN_STORE.values.keys()].filter(k=>k.startsWith(prefix));
async function mockFetch(fn,run){const original=globalThis.fetch;globalThis.fetch=fn;try{return await run();}finally{globalThis.fetch=original;}}

test('notification and device endpoints require an authenticated Tempo account',async()=>{
  const {env}=await fixture();
  for(const [p,m,b]of [['/api/account/push/devices','POST',device()],['/api/account/notifications','GET'],['/api/account/notifications/read','POST',{id:'a'.repeat(32)}]])assert.equal((await worker.fetch(req(p,m,b),env)).status,401);
});
test('device input is bounded and constrained to a known APNs environment',async()=>{
  const {env,contexts:[a]}=await fixture();
  for(const body of [device('bad'),device('a'.repeat(514)),device('z'.repeat(64)),device(undefined,{environment:'http://attacker'})])assert.equal((await register(env,a,body)).status,400);
  assert.equal(keys(env,'push-device:').length,0);
});
test('registration never returns raw device tokens and caps devices at ten',async()=>{
  const {env,contexts:[a]}=await fixture();
  for(let i=0;i<11;i++){const result=await register(env,a,device(i.toString(16).padStart(64,'a')));assert.equal(result.status,200);assert.equal((await result.text()).includes('token'),false);}
  assert.equal(keys(env,'push-device:').length,10);
});
test('a token reassigned to another account cannot receive the former account alerts',async()=>{
  const {env,contexts:[a,b]}=await fixture();await register(env,a);await register(env,b);
  let calls=0;
  await mockFetch(async()=>{calls++;return new Response(null,{status:200});},async()=>{await createNotification(env,a.user.id,'friend_request','1');assert.equal(calls,0);await createNotification(env,b.user.id,'friend_request','2');assert.equal(calls,1);});
  assert.equal(keys(env,'push-user:'+a.user.id).length,0);
});
test('APNs uses ES256, the fixed Tempo topic, generic English alerts, and event deduplication',async()=>{
  const {env,contexts:[a]}=await fixture();await register(env,a);let calls=0;
  await mockFetch(async(url,options)=>{
    calls++;assert.equal(url,'https://api.push.apple.com/3/device/'+'e'.repeat(64));assert.equal(options.headers['apns-topic'],'com.apitempo.tempohealth');assert.equal(options.headers['apns-push-type'],'alert');
    const body=JSON.parse(options.body);assert.equal(body.aps.alert.body,'You have a new friend request.');assert.equal(body.tempo.destination,'social');assert.equal(JSON.stringify(body).includes(a.user.id),false);
    const jwt=options.headers.authorization.slice(7).split('.');assert.equal(JSON.parse(Buffer.from(jwt[0],'base64url')).alg,'ES256');
    const pub=await crypto.subtle.importKey('spki',pair.publicKey.export({type:'spki',format:'der'}),{name:'ECDSA',namedCurve:'P-256'},false,['verify']);assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},pub,Buffer.from(jwt[2],'base64url'),new TextEncoder().encode(jwt[0]+'.'+jwt[1])),true);
    return new Response(null,{status:200});
  },async()=>{await createNotification(env,a.user.id,'friend_request','once');await createNotification(env,a.user.id,'friend_request','once');});assert.equal(calls,1);
});
test('Turkish preferences localize alerts and opt-out suppresses only remote alerts',async()=>{
  const {env,contexts:[a]}=await fixture();await register(env,a,device(undefined,{language:'tr',friends:false,challenges:true}));let calls=0;
  await mockFetch(async(url,opts)=>{calls++;assert.match(JSON.parse(opts.body).aps.alert.body,/yarış davetin/);return new Response(null,{status:200});},async()=>{await createNotification(env,a.user.id,'friend_request','one');await createNotification(env,a.user.id,'challenge_invite','two');});
  assert.equal(calls,1);assert.equal(keys(env,'notification:').length,2);
});
test('invalid or unregistered APNs tokens are removed; a provider outage preserves the inbox',async()=>{
  for(const status of [400,410,503]){
    const {env,contexts:[a]}=await fixture();await register(env,a);
    await mockFetch(async()=>Response.json({reason:'BadDeviceToken'},{status}),()=>createNotification(env,a.user.id,'friend_request','x'));
    assert.equal(keys(env,'push-device:').length,status===503?1:0);assert.equal(keys(env,'notification:').length,1);
  }
});
test('expired or password-revoked sessions cannot receive remote alerts',async()=>{
  for(const expired of [true,false]){const {env,contexts:[a]}=await fixture();await register(env,a);if(expired)await env.TOKEN_STORE.delete('account-session:'+a.sessionHash);else await env.TOKEN_STORE.put('account-user:'+a.user.id,JSON.stringify({...a.user,sessionVersion:2}));
    await mockFetch(()=>{throw Error('Must not send');},()=>createNotification(env,a.user.id,'friend_request','x'));assert.equal(keys(env,'push-device:').length,0);}
});
test('foreign reads and device removal cannot mutate another account',async()=>{
  const {env,contexts:[a,b]}=await fixture();await register(env,a);await register(env,b,device('f'.repeat(64)));await createNotification({...env,APNS_KEY_ID:''},a.user.id,'friend_request','x');
  const id=JSON.parse(await env.TOKEN_STORE.get(keys(env,'notification:')[0])).id;
  await handlePushRequest(req('/api/account/notifications/read','POST',{id}),env,b);assert.equal(JSON.parse(await env.TOKEN_STORE.get(keys(env,'notification:')[0])).read,false);
  await register(env,b,device(),'DELETE');assert.equal(keys(env,'push-device:').length,2);
  await handlePushRequest(req('/api/account/notifications/read','POST',{id}),env,a);assert.equal(JSON.parse(await env.TOKEN_STORE.get(keys(env,'notification:')[0])).read,true);
});
test('logout removes only its session devices; account deletion also removes the inbox',async()=>{
  const {env,contexts:[a,b]}=await fixture();await register(env,a);await register(env,b,device('f'.repeat(64)));await createNotification({...env,APNS_KEY_ID:''},a.user.id,'friend_request','x');
  await removeSessionDevices(env,a.user.id,a.sessionHash);assert.equal(keys(env,'push-device:').length,1);await deletePushAccount(env,a.user.id);assert.equal(keys(env,'notification:'+a.user.id).length,0);assert.equal(keys(env,'push-device:').length,1);
});
test('a saved friend request succeeds even when push transport fails and a duplicate sends no alert',async()=>{
  const {env,contexts:[a,b]}=await fixture();await register(env,b);let calls=0;
  const request=()=>new Request('https://apitempo.com/api/account/social/friends',{method:'POST',headers:{Authorization:'Bearer '+a.user.token,'Content-Type':'application/json'},body:JSON.stringify({username:b.user.username})});
  await mockFetch(async()=>{calls++;throw Error('Provider unavailable');},async()=>{let r=request();assert.equal((await handleSocialRequest(r,env,new URL(r.url))).status,201);await env.TOKEN_STORE.delete('social-request-cooldown:'+a.user.id);r=request();assert.equal((await handleSocialRequest(r,env,new URL(r.url))).status,409);});assert.equal(calls,1);assert.equal(keys(env,'notification:').length,1);
});
test('provider JWT is reused within its allowed lifetime',async()=>{const {env}=await fixture();assert.equal(await providerToken(env),await providerToken(env));});
