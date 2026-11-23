'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const Module=require('node:module');

test('API: ogloszenia, odpowiedzi, prywatne rozmowy i uprawnienia', async()=>{
 const handlers=new Map();
 function table(){
  const entries=new Map();const k=(pk,rk)=>pk+'|'+rk;
  return {
   async createEntity(e){if(entries.has(k(e.partitionKey,e.rowKey))){const err=Error('conflict');err.statusCode=409;throw err}entries.set(k(e.partitionKey,e.rowKey),{...e})},
   async getEntity(pk,rk){const row=entries.get(k(pk,rk));if(!row){const err=Error('not found');err.statusCode=404;throw err}return {...row}},
   async updateEntity(e){const key=k(e.partitionKey,e.rowKey);entries.set(key,{...entries.get(key),...e})},
   async *listEntities(args){const filter=args?.queryOptions?.filter||'';const pk=/PartitionKey eq '([^']+)'/.exec(filter)?.[1];const rk=/RowKey eq '([^']+)'/.exec(filter)?.[1];for(const r of entries.values()){if((!pk||r.partitionKey===pk)&&(!rk||r.rowKey===rk))yield {...r}}}
  }
 }
 const ps=table(),rs=table(),ms=table();
 const fakeStorage={posts:()=>ps,responses:()=>rs,messages:()=>ms,getPost:async id=>{try{return await ps.getEntity('POST',id)}catch(e){if(e.statusCode===404)return null;throw e}}};
 const original=Module._load;
 Module._load=function(request,parent,isMain){
  if(request==='@azure/functions')return {app:{http:(name,config)=>handlers.set(name,config.handler)}};
  if(parent?.filename?.replace(/\\/g,'/').endsWith('/src/functions/index.js')){
   if(request==='../lib/auth')return {requireUser:async req=>req.user};
   if(request==='../lib/storage')return fakeStorage;
  }
  return original.call(this,request,parent,isMain);
 };
 try{require('../src/functions/index.js')}finally{Module._load=original}
 const owner={id:'owner-550e8400',name:'Anna'};
 const helper={id:'helper-550e8400',name:'Marek'};
 const stranger={id:'stranger-550e8400',name:'Ola'};
 const ctx={error:e=>{throw e}};
 async function run(name,user,params,body){return handlers.get(name)({user,params:params||{},headers:new Headers(),json:async()=>body},ctx)}
 let res=await run('postsCreate',owner,{}, {kind:'need',title:'Pomocy z cieknacym kranem',category:'Hydraulika',city:'Szczecin',description:'Kran leje wodę i nie da się go zamknąć, pomocy.',budget:'Do ustalenia',urgency:'Pilne'});
 assert.equal(res.status,201);const id=res.jsonBody.post.id;
 res=await run('postsList',null);assert.equal(res.status,200);assert.equal(res.jsonBody.posts.length,1);
 res=await run('responsesCreate',owner,{id},{message:'Moge to naprawic jutro'});assert.equal(res.status,403);
 res=await run('responsesCreate',helper,{id},{message:'Mogę przyjechać i wymienić uszczelkę.'});assert.equal(res.status,201);
 res=await run('responsesCreate',helper,{id},{message:'Druga odpowiedz nie powinna przejsc'});assert.equal(res.status,409);
 res=await run('responsesList',stranger,{id});assert.equal(res.status,200);assert.equal(res.jsonBody.responses.length,0);
 res=await run('responsesList',owner,{id});assert.equal(res.status,200);assert.equal(res.jsonBody.responses.length,1);
 res=await run('messagesList',stranger,{id,respondentId:helper.id});assert.equal(res.status,403);
 res=await run('messagesCreate',owner,{id,respondentId:helper.id},{message:'Dziękuję, proszę napisać po godzinie 18.'});assert.equal(res.status,201);
 res=await run('messagesList',helper,{id,respondentId:helper.id});assert.equal(res.status,200);assert.equal(res.jsonBody.messages.length,2);
 res=await run('postsStatus',stranger,{id},{status:'closed'});assert.equal(res.status,403);
 res=await run('postsStatus',owner,{id},{status:'closed'});assert.equal(res.status,200);
});

