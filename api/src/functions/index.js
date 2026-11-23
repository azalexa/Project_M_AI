'use strict';
const {app}=require('@azure/functions');
const {randomUUID}=require('node:crypto');
const {requireUser}=require('../lib/auth');
const {posts,responses,messages,getPost}=require('../lib/storage');
const {HttpError,validatePost,validateReply,validateId,postView,replyView}=require('../lib/validate');
function result(status,body){return {status,jsonBody:body,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}}}
function route(handler){return async (request,context)=>{
 try{return await handler(request,context)}catch(e){
  if(e instanceof HttpError)return result(e.status,{error:e.message});
  context.error(e);return result(500,{error:'Wystąpił błąd serwera. Spróbuj ponownie później.'});
 }
}}
async function requestData(req){const len=Number(req.headers.get('content-length')||'0');if(len>16000)throw new HttpError(413,'Zbyt duże zgłoszenie.');try{return await req.json()}catch{throw new HttpError(400,'Nieprawidłowe dane JSON.')}}
app.http('postsList',{methods:['GET'],authLevel:'anonymous',route:'posts',handler:route(async()=>{
 const data=[];let seen=0;
 for await(const entity of posts().listEntities({queryOptions:{filter:"PartitionKey eq 'POST'"}})){
  data.push(postView(entity));if(++seen>=500)break;
 }
 data.sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt));
 return result(200,{posts:data.slice(0,120)});
})});
app.http('postsCreate',{methods:['POST'],authLevel:'anonymous',route:'posts',handler:route(async req=>{
 const user=await requireUser(req);const post=validatePost(await requestData(req));const row={partitionKey:'POST',rowKey:randomUUID(),...post,authorId:user.id,authorName:user.name,status:'open',createdAt:new Date().toISOString()};
 await posts().createEntity(row);return result(201,{post:postView(row)});
})});
app.http('postsStatus',{methods:['PATCH'],authLevel:'anonymous',route:'posts/{id}',handler:route(async req=>{
 const user=await requireUser(req);const id=validateId(req.params.id);const post=await getPost(id);if(!post)throw new HttpError(404,'Ogłoszenie nie istnieje.');if(post.authorId!==user.id)throw new HttpError(403,'Tylko autor może zamknąć ogłoszenie.');
 const body=await requestData(req);if(body?.status!=='closed')throw new HttpError(400,'Dozwolona jest tylko zmiana na zakończone.');
 await posts().updateEntity({partitionKey:'POST',rowKey:id,status:'closed'},'Merge');return result(200,{ok:true});
})});
app.http('responsesList',{methods:['GET'],authLevel:'anonymous',route:'posts/{id}/responses',handler:route(async req=>{
 const user=await requireUser(req);const id=validateId(req.params.id);const post=await getPost(id);if(!post)throw new HttpError(404,'Ogłoszenie nie istnieje.');
 const owner=post.authorId===user.id;const out=[];
 const filter=owner?`PartitionKey eq '${id}'`:`PartitionKey eq '${id}' and RowKey eq '${user.id.replaceAll("'","''")}'`;
 const iter=responses().listEntities({queryOptions:{filter}});
 for await(const entity of iter){if(owner||entity.rowKey===user.id)out.push(replyView(entity));if(out.length>=100)break}
 out.sort((a,b)=>new Date(a.createdAt)-new Date(b.createdAt));return result(200,{responses:out});
})});
app.http('responsesCreate',{methods:['POST'],authLevel:'anonymous',route:'posts/{id}/responses',handler:route(async req=>{
 const user=await requireUser(req);const id=validateId(req.params.id);const post=await getPost(id);
 if(!post)throw new HttpError(404,'Ogłoszenie nie istnieje.');if(post.status==='closed')throw new HttpError(409,'Ogłoszenie jest zakończone.');if(post.authorId===user.id)throw new HttpError(403,'Nie można odpowiadać na własne ogłoszenie.');
 const message=validateReply(await requestData(req));
 // Jedna odpowiedz na ogloszenie od danego uzytkownika (unikalny RowKey).
 try{await responses().createEntity({partitionKey:id,rowKey:user.id,authorName:user.name,message,createdAt:new Date().toISOString()})}
 catch(e){if(e.statusCode===409)throw new HttpError(409,'Na to ogłoszenie już wysłano odpowiedź.');throw e}
 return result(201,{ok:true});
})});

async function thread(req){
 const user=await requireUser(req);const id=validateId(req.params.id);
 const responder=String(req.params.respondentId||'');
 if(!/^[A-Za-z0-9_-]{8,150}$/.test(responder))throw new HttpError(400,'Nieprawidłowy identyfikator rozmowy.');
 const post=await getPost(id);if(!post)throw new HttpError(404,'Ogłoszenie nie istnieje.');
 if(user.id!==post.authorId&&user.id!==responder)throw new HttpError(403,'Nie masz dostępu do tej rozmowy.');
 let response;
 try{response=await responses().getEntity(id,responder)}catch(e){if(e.statusCode===404)throw new HttpError(404,'Rozmowa nie istnieje.');throw e}
 return {user,id,responder,response};
}
app.http('messagesList',{methods:['GET'],authLevel:'anonymous',route:'posts/{id}/responses/{respondentId}/messages',handler:route(async req=>{
 const t=await thread(req);const partitionKey=`${t.id}_${t.responder}`;
 const out=[{id:'initial',authorId:t.responder,authorName:t.response.authorName,message:t.response.message,createdAt:t.response.createdAt}];
 for await(const m of messages().listEntities({queryOptions:{filter:`PartitionKey eq '${partitionKey}'`}})){
  out.push({id:m.rowKey,authorId:m.authorId,authorName:m.authorName,message:m.message,createdAt:m.createdAt});if(out.length>=200)break;
 }
 out.sort((a,b)=>new Date(a.createdAt)-new Date(b.createdAt));return result(200,{messages:out});
})});
app.http('messagesCreate',{methods:['POST'],authLevel:'anonymous',route:'posts/{id}/responses/{respondentId}/messages',handler:route(async req=>{
 const t=await thread(req);const message=validateReply(await requestData(req));
 const entity={partitionKey:`${t.id}_${t.responder}`,rowKey:randomUUID(),authorId:t.user.id,authorName:t.user.name,message,createdAt:new Date().toISOString()};
 await messages().createEntity(entity);return result(201,{ok:true});
})});
