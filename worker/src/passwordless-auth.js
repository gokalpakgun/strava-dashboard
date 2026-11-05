import { appleReady, verifyAppleIdentity, exchangeAppleCode, sealAppleRefresh } from './apple-auth.js';
import { readLimitedText } from './http.js';
import { createSession, publicUser, sha256Hex, rateLimit } from './account.js';

const json = (body, status = 200) => Response.json(body, {status, headers:{'Cache-Control':'no-store'}});
const validEmail = value => typeof value === 'string' && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
const token = () => [...crypto.getRandomValues(new Uint8Array(32))].map(v=>v.toString(16).padStart(2,'0')).join('');
async function codeHash(env, flow, code) {
 const key = await crypto.subtle.importKey('raw',new TextEncoder().encode(env.AUTH_PEPPER_V2 || env.AUTH_PEPPER),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(flow+':'+code)))].map(v=>v.toString(16).padStart(2,'0')).join('');
}
function equal(a,b) { if(typeof a!=='string'||typeof b!=='string'||a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0; }
function makeCode() { const limit=Math.floor(2**32/1_000_000)*1_000_000;let value;do{value=crypto.getRandomValues(new Uint32Array(1))[0];}while(value>=limit);return String(value%1_000_000).padStart(6,'0'); }

export async function handlePasswordlessAuth(request, env) {
 const path=new URL(request.url).pathname;
 if(path==='/api/account/access/options'&&request.method==='GET')return json({emailCode:Boolean(env.AUTH_FLOW&&env.RESEND_API_KEY),apple:appleReady(env)});
 if(['/api/account/access/apple/start','/api/account/access/apple/verify'].includes(path)&&request.method==='POST') {
  if(!appleReady(env))return json({error:'auth.apple.unavailable'},503);
  const limited=await rateLimit(request,env,'apple-access',20);if(limited)return limited;
  let body;try{body=JSON.parse(await readLimitedText(request,24000));}catch{return json({error:'auth.apple.failed'},400);}
  const flowID=path.endsWith('/start')?token():body?.flowID;if(!/^[a-f0-9]{64}$/.test(flowID||''))return json({error:'auth.apple.failed'},400);
  const stub=env.AUTH_FLOW.get(env.AUTH_FLOW.idFromName('apple:'+flowID));
  return stub.fetch('https://auth.internal/'+(path.endsWith('/start')?'apple/start':'apple/verify'),{method:'POST',body:JSON.stringify({flowID,identityToken:body.identityToken,authorizationCode:body.authorizationCode})});
 }
 if(!['/api/account/access/start','/api/account/access/verify'].includes(path)||request.method!=='POST')return json({error:'Method not allowed'},405);
 if(!env.AUTH_FLOW||!env.RESEND_API_KEY||(env.AUTH_PEPPER_V2||env.AUTH_PEPPER||'').length<32)return json({error:'auth.code.unavailable'},503);
 let body;try{body=JSON.parse(await readLimitedText(request,4096));}catch{return json({error:'auth.code.invalid'},400);}
 const email=typeof body?.email==='string'?body.email.trim().toLowerCase():'';
 if(!validEmail(email))return json({error:'auth.code.emailInvalid'},400);
 const limited=await rateLimit(request,env,'access',20);if(limited)return limited;
 const stub=env.AUTH_FLOW.get(env.AUTH_FLOW.idFromName(await sha256Hex(email)));
 return stub.fetch('https://auth.internal/'+(path.endsWith('/start')?'start':'verify'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...body,email,language:(request.headers.get('Accept-Language')||'').toLowerCase().startsWith('tr')?'tr':'en'})});
}

/// Her e-posta tek bir Durable Object üzerinden sıralanır; eşzamanlı kod kullanımı ikinci oturum oluşturamaz.
export class AuthFlow {
 constructor(state,env){this.storage=state.storage;this.env=env;this.queue=Promise.resolve();}
 fetch(request){const work=this.queue.then(()=>this.handle(request));this.queue=work.catch(()=>{});return work;}
 async handle(request){
  const path=new URL(request.url).pathname;
  if(request.method!=='POST')return json({error:'Method not allowed'},405);
  if(path==='/erase'){await this.storage.deleteAll();await this.storage.put('blockedUntil',Date.now()+30_000);return json({ok:true});}
  const body=await request.json(),now=Date.now();
  if((await this.storage.get('blockedUntil')||0)>now)return json({error:'auth.code.wait'},429);
  if(path==='/apple/start'){
   const nonce=token();await this.storage.put('appleChallenge',{nonce:await sha256Hex(nonce),expiresAt:now+300_000});await this.storage.setAlarm(now+300_000);
   return json({flowID:body.flowID,nonce});
  }
  if(path==='/apple/verify'){
   const challenge=await this.storage.get('appleChallenge');if(!challenge||challenge.expiresAt<=now)return json({error:'auth.apple.failed'},401);
   try{
    const claims=await verifyAppleIdentity(body.identityToken,challenge.nonce);
    await this.storage.delete('appleChallenge');
    const exchanged=await exchangeAppleCode(this.env,body.authorizationCode),verified=await verifyAppleIdentity(exchanged.id_token,challenge.nonce);
    if(verified.sub!==claims.sub)return json({error:'auth.apple.failed'},401);
    const subjectKey='account-apple:'+await sha256Hex(claims.sub),owner=await this.env.TOKEN_STORE.get(subjectKey);
    const existing=owner?await this.env.TOKEN_STORE.get('account-user:'+owner,'json'):null;
    const email=(existing?.email||claims.email).trim().toLowerCase();
    if(!validEmail(email))return json({error:'auth.apple.failed'},401);
    return this.env.AUTH_FLOW.get(this.env.AUTH_FLOW.idFromName(await sha256Hex(email))).fetch('https://auth.internal/apple/identity',{method:'POST',body:JSON.stringify({email,subject:claims.sub,refresh:await sealAppleRefresh(this.env,exchanged.refresh_token)})});
   }catch{return json({error:'auth.apple.failed'},401);}
  }
  if(!validEmail(body.email))return json({error:'auth.code.emailInvalid'},400);
  if(path==='/start'){
   const rate=await this.storage.get('rate')||{start:now,count:0,last:0};
   if(now-rate.start>=3600_000){rate.start=now;rate.count=0;}
   if(now-rate.last<60_000||rate.count>=5)return json({error:'auth.code.wait'},429);
   rate.last=now;rate.count++;await this.storage.put('rate',rate);
   const flowID=token(),code=makeCode(),expiresAt=now+5*60_000;
   await this.storage.put('challenge',{flowID,hash:await codeHash(this.env,flowID,code),expiresAt,attempts:0});
   await this.storage.setAlarm(expiresAt);
   const tr=body.language==='tr';let response;
   try{response=await fetch('https://api.resend.com/emails',{method:'POST',signal:AbortSignal.timeout(10_000),headers:{Authorization:'Bearer '+this.env.RESEND_API_KEY,'Content-Type':'application/json','Idempotency-Key':'tempo-access-'+flowID},body:JSON.stringify({from:this.env.EMAIL_FROM||'Tempo <noreply@apitempo.com>',to:[body.email],subject:tr?'Tempo giriş kodun':'Your Tempo sign-in code',text:(tr?'Tempo giriş kodun: ':'Your Tempo sign-in code: ')+code+(tr?'\nKod 5 dakika geçerlidir. Kimseyle paylaşma. Bu isteği sen yapmadıysan yok sayabilirsin.':'\nValid for 5 minutes. Do not share it. If you did not request this, ignore this email.')})});}catch{}
   if(!response?.ok){await this.storage.delete('challenge');return json({error:'auth.code.deliveryFailed'},503);}
   return json({flowID,expiresAt,message:'auth.code.sent'});
  }
  if(path==='/verify'||path==='/apple/identity'){
   if(path==='/verify'){
   const entry=await this.storage.get('challenge');
   if(!entry||entry.expiresAt<=now||entry.attempts>=5||entry.flowID!==body.flowID)return json({error:'auth.code.invalid'},401);
   entry.attempts++;await this.storage.put('challenge',entry);
   if(!/^\d{6}$/.test(body.code||'')||!equal(entry.hash,await codeHash(this.env,entry.flowID,body.code)))return json({error:'auth.code.invalid'},401);
   // Kod hesap/oturum yazımı başlamadan tüketilir; kayıp yanıt için yeni kod istenir.
   await this.storage.delete('challenge');
   }
   const emailKey='account-email:'+await sha256Hex(body.email);
   const owner=await this.storage.get('owner')||await this.env.TOKEN_STORE.get(emailKey);
   let user=owner?await this.env.TOKEN_STORE.get('account-user:'+owner,'json'):null;
   if(!user){
    const id=token().slice(0,40),username='athlete_'+id.slice(0,16),createdAt=new Date(now).toISOString();
    user={id,email:body.email,username,displayName:'',avatarBase64:null,sports:[],onboardingComplete:false,createdAt,updatedAt:createdAt,sessionVersion:1,emailVerified:true};
    await this.env.TOKEN_STORE.put('account-user:'+id,JSON.stringify(user));
    await Promise.all([this.env.TOKEN_STORE.put(emailKey,id),this.env.TOKEN_STORE.put('account-username:'+username,id)]);
   }
   if(path==='/apple/identity'){
    if(user.appleSubject&&user.appleSubject!==body.subject)return json({error:'auth.apple.failed'},409);
    user.appleSubject=body.subject;user.appleRefreshToken=body.refresh;user.emailVerified=true;
    await this.env.TOKEN_STORE.put('account-user:'+user.id,JSON.stringify(user));
    await this.env.TOKEN_STORE.put('account-apple:'+await sha256Hex(body.subject),user.id);
   }
   await this.storage.put('owner',user.id);
   const session=await createSession(this.env,user.id,user.sessionVersion||1);
   return json({token:session.token,user:publicUser(user)});
  }
  return json({error:'Not found'},404);
 }
 async alarm(){for(const key of ['challenge','appleChallenge']){const entry=await this.storage.get(key);if(entry&&entry.expiresAt<=Date.now())await this.storage.delete(key);}}
}
