'use strict';
const {TableClient}=require('@azure/data-tables');
const {DefaultAzureCredential}=require('@azure/identity');
let postsClient;let repliesClient;let messagesClient;
function table(name){
 const endpoint=process.env.TABLE_STORAGE_URL;
 if(!/^https:\/\/[a-z0-9-]+\.table\.core\.windows\.net\/?$/i.test(endpoint||''))throw Error('TABLE_STORAGE_URL nie jest skonfigurowany');
 return new TableClient(endpoint.replace(/\/$/,''),name,new DefaultAzureCredential());
}
function posts(){return postsClient||(postsClient=table('MechMasterPosts'))}
function responses(){return repliesClient||(repliesClient=table('MechMasterResponses'))}
function messages(){return messagesClient||(messagesClient=table('MechMasterMessages'))}
async function getPost(id){try{return await posts().getEntity('POST',id)}catch(e){if(e.statusCode===404)return null;throw e}}
module.exports={posts,responses,messages,getPost};
