'use strict';
const CATEGORIES = Object.freeze(['Motoryzacja','Hydraulika','Elektryka','AGD','Dom i ogród','Komputery','Inne']);
const KINDS = Object.freeze(['need','offer']);
const URGENCIES = Object.freeze(['Do ustalenia','Pilne','W tym tygodniu','Elastycznie']);
class HttpError extends Error {constructor(status,message){super(message);this.status=status}}
const clean = v => typeof v==='string'?v.trim():'';
function validatePost(data){
 if(!data||typeof data!=='object'||Array.isArray(data))throw new HttpError(400,'Nieprawidłowe dane ogłoszenia.');
 const out={kind:clean(data.kind),title:clean(data.title),category:clean(data.category),city:clean(data.city),description:clean(data.description),budget:clean(data.budget),urgency:clean(data.urgency)||'Do ustalenia'};
 if(!KINDS.includes(out.kind))throw new HttpError(400,'Nieprawidłowy typ ogłoszenia.');
 if(out.title.length<8||out.title.length>110)throw new HttpError(400,'Tytuł musi mieć od 8 do 110 znaków.');
 if(!CATEGORIES.includes(out.category))throw new HttpError(400,'Nieprawidłowa kategoria.');
 if(out.city.length<2||out.city.length>80)throw new HttpError(400,'Miasto musi mieć od 2 do 80 znaków.');
 if(out.description.length<20||out.description.length>2500)throw new HttpError(400,'Opis musi mieć od 20 do 2500 znaków.');
 if(out.budget.length>70)throw new HttpError(400,'Zbyt długi budżet lub stawka.');
 if(!URGENCIES.includes(out.urgency))throw new HttpError(400,'Nieprawidłowy termin.');
 return out;
}
function validateReply(data){const value=clean(data?.message);if(value.length<10||value.length>1200)throw new HttpError(400,'Wiadomość musi mieć od 10 do 1200 znaków.');return value}
function validateId(id){if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id||''))throw new HttpError(400,'Nieprawidłowy identyfikator ogłoszenia.');return id}
function postView(p){return {id:p.rowKey,kind:p.kind,title:p.title,category:p.category,city:p.city,description:p.description,budget:p.budget,urgency:p.urgency,authorId:p.authorId,authorName:p.authorName,createdAt:p.createdAt,status:p.status||'open'}}
function replyView(r){return {id:r.rowKey,postId:r.partitionKey,authorName:r.authorName,message:r.message,createdAt:r.createdAt}}
module.exports={CATEGORIES,HttpError,validatePost,validateReply,validateId,postView,replyView};
