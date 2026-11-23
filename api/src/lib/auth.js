'use strict';
const {createRemoteJWKSet,jwtVerify}=require('jose');
const {HttpError}=require('./validate');
let discoveryPromise;
function discovery(){
 if(!discoveryPromise){
  const tenant=process.env.EXTERNAL_TENANT_ID;
  const subdomain=process.env.EXTERNAL_TENANT_NAME;
  if(!/^[0-9a-f-]{36}$/i.test(tenant||'')||!/^[a-z0-9-]+$/.test(subdomain||''))throw Error('Brakuje konfiguracji Entra External ID');
  discoveryPromise=fetch(`https://${subdomain}.ciamlogin.com/${tenant}/v2.0/.well-known/openid-configuration`)
    .then(async r=>{if(!r.ok)throw Error('Nie udało się pobrać konfiguracji Entra');return r.json()})
    .then(d=>{if(!d.issuer||!d.jwks_uri||!new URL(d.jwks_uri).hostname.endsWith('.ciamlogin.com'))throw Error('Nieprawidłowe metadane Entra');return {issuer:d.issuer,jwks:createRemoteJWKSet(new URL(d.jwks_uri))}})
    .catch(e=>{discoveryPromise=null;throw e});
 }
 return discoveryPromise;
}
async function requireUser(req){
 const header=req.headers.get('authorization')||'';
 if(!/^Bearer\s+\S+$/i.test(header))throw new HttpError(401,'Zaloguj się, aby wykonać tę czynność.');
 const apiId=process.env.API_CLIENT_ID;const tenant=process.env.EXTERNAL_TENANT_ID;const requiredScope=process.env.API_SCOPE_NAME||'access_as_user';
 if(!/^[0-9a-f-]{36}$/i.test(apiId||''))throw Error('API_CLIENT_ID nie jest skonfigurowany');
 try{
  const metadata=await discovery();
  const {payload}=await jwtVerify(header.replace(/^Bearer\s+/i,''),metadata.jwks,{issuer:metadata.issuer,audience:apiId,algorithms:['RS256']});
  if(payload.tid!==tenant)throw new HttpError(403,'Nieprawidłowy katalog użytkownika.');
  if(!String(payload.scp||'').split(' ').includes(requiredScope))throw new HttpError(403,'Token nie ma uprawnień do MechMaster API.');
  const id=String(payload.oid||payload.sub||'');if(!id||id.length>150)throw new HttpError(401,'Brak identyfikatora użytkownika.');
  const authorName=String(payload.name||payload.given_name||'Użytkownik').trim().slice(0,65);
  return {id,name:authorName};
 }catch(error){if(error instanceof HttpError)throw error;throw new HttpError(401,'Sesja wygasła lub token jest nieprawidłowy. Zaloguj się ponownie.')}
}
module.exports={requireUser};
