const encoder=new TextEncoder();
export const APPLE_CLIENT_ID='com.apitempo.tempohealth';
export const appleReady=env=>Boolean(env.APPLE_KEY_ID&&env.APPLE_TEAM_ID&&env.APPLE_PRIVATE_KEY&&env.AUTH_FLOW);
const b64=bytes=>btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
const bytes=value=>Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(value.length/4)*4,'=')),c=>c.charCodeAt(0));
let keyCache;
export async function verifyAppleIdentity(jwt,nonce,now=Math.floor(Date.now()/1000)){
 if(typeof jwt!=='string'||jwt.length>16000)throw Error('invalid');
 const parts=jwt.split('.');if(parts.length!==3)throw Error('invalid');
 const header=JSON.parse(new TextDecoder().decode(bytes(parts[0]))),claims=JSON.parse(new TextDecoder().decode(bytes(parts[1])));
 if(header.alg!=='RS256'||typeof header.kid!=='string'||header.kid.length>128)throw Error('invalid');
 if(!keyCache||keyCache.expires<Date.now()||!keyCache.keys.some(k=>k.kid===header.kid)){
  const response=await fetch('https://appleid.apple.com/auth/keys',{signal:AbortSignal.timeout(8000)});if(!response.ok)throw Error('apple unavailable');
  const body=await response.json();if(!Array.isArray(body.keys)||body.keys.length>20)throw Error('invalid');keyCache={keys:body.keys,expires:Date.now()+3600_000};
 }
 const jwk=keyCache.keys.find(k=>k.kid===header.kid&&k.kty==='RSA'&&k.alg==='RS256');if(!jwk)throw Error('invalid');
 const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
 if(!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,bytes(parts[2]),encoder.encode(parts[0]+'.'+parts[1])))throw Error('invalid');
 if(claims.iss!=='https://appleid.apple.com'||claims.aud!==APPLE_CLIENT_ID||!Number.isFinite(claims.exp)||claims.exp<=now||!Number.isFinite(claims.iat)||claims.iat>now+60||claims.iat<now-600||claims.nonce!==nonce||typeof claims.sub!=='string'||claims.sub.length>256||!claims.sub||![true,'true'].includes(claims.email_verified)||typeof claims.email!=='string')throw Error('invalid');
 return claims;
}
async function clientSecret(env){
 if(!appleReady(env))throw Error('apple unavailable');
 const pem=env.APPLE_PRIVATE_KEY.replace(/\\n/g,'\n').replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
 const now=Math.floor(Date.now()/1000),part=value=>b64(encoder.encode(JSON.stringify(value)));
 const payload=part({alg:'ES256',kid:env.APPLE_KEY_ID})+'.'+part({iss:env.APPLE_TEAM_ID,iat:now,exp:now+300,aud:'https://appleid.apple.com',sub:APPLE_CLIENT_ID});
 return payload+'.'+b64(new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,encoder.encode(payload))));
}
export async function exchangeAppleCode(env,code){
 if(typeof code!=='string'||code.length<10||code.length>4096)throw Error('invalid');
 const response=await fetch('https://appleid.apple.com/auth/token',{method:'POST',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:APPLE_CLIENT_ID,client_secret:await clientSecret(env),grant_type:'authorization_code',code}).toString()});
 if(!response.ok)throw Error('apple unavailable');const result=await response.json();if(!result.refresh_token||!result.id_token)throw Error('invalid');return result;
}
export async function sealAppleRefresh(env,token){
 const version=env.AUTH_PEPPER_V2?2:1,secret=version===2?env.AUTH_PEPPER_V2:env.AUTH_PEPPER;
 const key=await crypto.subtle.importKey('raw',await crypto.subtle.digest('SHA-256',encoder.encode('tempo.apple.refresh:'+secret)),{name:'AES-GCM'},false,['encrypt']);
 const iv=crypto.getRandomValues(new Uint8Array(12));return {version,iv:b64(iv),ciphertext:b64(new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv},key,encoder.encode(token))))};
}
export async function revokeAppleAccount(env,user){
 if(!user.appleRefreshToken)return true;
 try{
  const entry=user.appleRefreshToken,secret=entry.version===2?env.AUTH_PEPPER_V2:env.AUTH_PEPPER;if(!secret)return false;
  const key=await crypto.subtle.importKey('raw',await crypto.subtle.digest('SHA-256',encoder.encode('tempo.apple.refresh:'+secret)),{name:'AES-GCM'},false,['decrypt']);
  const token=new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes(entry.iv)},key,bytes(entry.ciphertext)));
  const response=await fetch('https://appleid.apple.com/auth/revoke',{method:'POST',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:APPLE_CLIENT_ID,client_secret:await clientSecret(env),token,token_type_hint:'refresh_token'}).toString()});return response.ok;
 }catch{return false;}
}
