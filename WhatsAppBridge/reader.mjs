import makeWASocket, { initAuthCreds, BufferJSON, DisconnectReason, proto } from '@whiskeysockets/baileys';
import pino from 'pino';
import QRCode from 'qrcode';
import { createInterface } from 'node:readline';
import { seal, open } from './data.mjs';
import { ReceivedTextCache, deliverIfCurrent } from './reconciliation.mjs';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
const emit = value => process.stdout.write(JSON.stringify(value)+'\n');
let socket, directory, secret, state, stopping=false, retry=0, timer, connectionGeneration=0, cache;
function read(name,fallback) {
  const path=join(directory,name); if(!existsSync(path)) return fallback;
  return JSON.parse(open(readFileSync(path),secret),BufferJSON.reviver);
}
function save(name,value) {
  const path=join(directory,name); writeFileSync(path+'.tmp',seal(JSON.stringify(value,BufferJSON.replacer),secret),{mode:0o600}); renameSync(path+'.tmp',path);
}
function emitChats() {
  const ids=new Set([...Object.keys(state.chats),...Object.values(state.messages).map(m=>m.chat)]);
  emit({chats:[...ids].filter(id=>id!=='status@broadcast').map(id=>({id,name:state.chats[id]||Object.values(state.messages).find(m=>m.chat===id&&!m.sentByMe&&m.sender!==id&&!id.endsWith('@g.us'))?.sender||(id.endsWith('@g.us')?'Group · '+id.split('@')[0].slice(-6):id.split('@')[0]),group:id.endsWith('@g.us')}))});
}
function updateChats(chats) {
  for(const chat of chats??[]) if(chat.id && (chat.name||chat.subject||chat.notify)) state.chats[chat.id]=chat.name||chat.subject||chat.notify;
  save('chats.enc',state.chats);emitChats();
}
function publishMessages() {
  // Journal first: on interruption its revisions also apply to the preceding
  // messages.enc snapshot, so deleted/edited content cannot reappear on load.
  save('revisions.enc',cache.journal());
  state.messages=cache.messages;
  save('messages.enc',state.messages);
  emitChats();
  emit({type:'messages',messages:Object.values(state.messages),coverage:'Linked-device text received so far; history may be partial. Up to 2,000 messages / 12 MB; edit/delete replay protection is bounded.'});
}
function ingest(messages) { cache.ingest(messages);publishMessages(); }
async function connect() {
  const generation=++connectionGeneration;
  clearTimeout(timer);
  socket?.end(undefined);
  const isCurrent=()=>generation===connectionGeneration&&!stopping;
  // Baileys mutates the credential object internally. Do not let an old socket
  // retain the object owned by its replacement.
  const creds=JSON.parse(JSON.stringify(state.creds,BufferJSON.replacer),BufferJSON.reviver);
  state.creds=creds;
  const current=makeWASocket({auth:{creds,keys:{get:async(type,ids)=>isCurrent()?Object.fromEntries(ids.filter(id=>state.keys[type]?.[id]!=null).map(id=>[id,type==='app-state-sync-key'?proto.Message.AppStateSyncKeyData.fromObject(state.keys[type][id]):state.keys[type][id]])):{},set:async(data)=>{if(!isCurrent())return;for(const [type,values] of Object.entries(data)){state.keys[type]??={};for(const [id,value]of Object.entries(values)){if(value==null)delete state.keys[type][id];else state.keys[type][id]=value;}}save('auth.enc',{creds:state.creds,keys:state.keys});}}},logger:pino({level:'silent'}),markOnlineOnConnect:false,syncFullHistory:false,browser:['Mission Control','Desktop','0.1.0']});
  socket=current;
  const on=(event,handler)=>current.ev.on(event,(...args)=>{if(generation===connectionGeneration&&!stopping)return handler(...args);});
  on('creds.update',()=>save('auth.enc',{creds:state.creds,keys:state.keys}));
  on('messages.upsert',({messages})=>ingest(messages));
  on('messaging-history.set',({messages,chats,contacts})=>{updateChats(chats);updateChats(contacts);ingest(messages);});
  on('chats.upsert',updateChats);on('chats.update',updateChats);on('contacts.upsert',updateChats);on('contacts.update',updateChats);
  on('messages.update',updates=>{cache.update(updates);publishMessages();});
  on('messages.delete',event=>{cache.delete(event);publishMessages();});
  on('chats.delete',ids=>{for(const jid of ids??[]){delete state.chats[jid];cache.delete({all:true,jid});}save('chats.enc',state.chats);ingest([]);});
  on('connection.update',async update=>{
    if(update.qr)await deliverIfCurrent(()=>generation===connectionGeneration&&!stopping,()=>QRCode.toDataURL(update.qr,{width:280,margin:2}),png=>emit({type:'qr',png,status:'Scan in WhatsApp → Settings → Linked devices → Link a device.'}));
    if(generation!==connectionGeneration||stopping)return;
    if(update.connection==='open'){
      retry=0;const identity=createHash('sha256').update(current.user.id.split(':')[0]).digest('hex');
      const previous=read('identity.enc',null);
      if(previous&&previous!==identity){cache=new ReceivedTextCache();state.messages={};state.chats={};save('chats.enc',state.chats);publishMessages();}
      save('identity.enc',identity);emit({type:'status',status:'Connected · read-only',connected:true,identity});
      // Resolve only a small number of already-received group names; never fetch messages/media.
      const groups=[...new Set(Object.values(state.messages).map(m=>m.chat))].filter(id=>id.endsWith('@g.us')&&!state.chats[id]).slice(0,12);
      for(const id of groups){
        if(generation!==connectionGeneration||stopping)break;
        let timeout;
        try {
          const metadata=await Promise.race([current.groupMetadata(id),new Promise((_,reject)=>{timeout=setTimeout(()=>reject(Error()),5000);})]);
          if(generation===connectionGeneration&&!stopping&&metadata.subject)updateChats([{id,name:metadata.subject}]);
        }catch{/* Retain honest fallback label; never log group metadata. */}
        finally{clearTimeout(timeout);}
      }
    }
    if(update.connection==='close'&&!stopping){const code=update.lastDisconnect?.error?.output?.statusCode;if(code===DisconnectReason.loggedOut){emit({type:'status',status:'Session revoked. Disconnect, then link again.',connected:false});}else if(retry++<3){emit({type:'status',status:'Reconnecting…',connected:false});clearTimeout(timer);timer=setTimeout(()=>{if(isCurrent())connect().catch(fail);},2000*retry);}else emit({type:'status',status:'Connection stopped after three retries. Reconnect manually.',connected:false});}
  });
}
const fail=()=>emit({type:'status',status:'WhatsApp connection failed. Reconnect or relink the device.',connected:false});
process.on('uncaughtException',fail);process.on('unhandledRejection',fail);
createInterface({input:process.stdin}).on('line',async line=>{try{const command=JSON.parse(line);if(command.action==='start'&&!socket){directory=command.directory;secret=Buffer.from(command.key,'base64');if(secret.length!==32)throw Error();mkdirSync(directory,{recursive:true,mode:0o700});const auth=read('auth.enc',{creds:initAuthCreds(),keys:{}});state={...auth,messages:read('messages.enc',{}),chats:read('chats.enc',{})};cache=new ReceivedTextCache(state.messages,read('revisions.enc',{}));ingest([]);await connect();}else if(command.action==='stop'){stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);}}catch{fail();}});
process.stdin.on('end',()=>{stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);});
