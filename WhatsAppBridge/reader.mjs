import makeWASocket, { initAuthCreds, BufferJSON, DisconnectReason, proto } from '@whiskeysockets/baileys';
import pino from 'pino';
import QRCode from 'qrcode';
import { createInterface } from 'node:readline';
import { seal, open, textMessage, boundedMessages } from './data.mjs';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
const emit = value => process.stdout.write(JSON.stringify(value)+'\n');
let socket, directory, secret, state, stopping=false, retry=0, timer, connectionGeneration=0;
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
function ingest(messages) {
  for(const m of messages) {
    const value=textMessage(m);
    if(value) state.messages[value.id]=value;
  }
  state.messages=boundedMessages(state.messages);
  emitChats();
  save('messages.enc',state.messages); emit({type:'messages',messages:Object.values(state.messages),coverage:'Linked-device text received so far; history may be partial.'});
}
async function connect() {
  const generation=++connectionGeneration;
  const current=makeWASocket({auth:{creds:state.creds,keys:{get:async(type,ids)=>Object.fromEntries(ids.filter(id=>state.keys[type]?.[id]!=null).map(id=>[id,type==='app-state-sync-key'?proto.Message.AppStateSyncKeyData.fromObject(state.keys[type][id]):state.keys[type][id]])),set:async(data)=>{for(const [type,values] of Object.entries(data)){state.keys[type]??={};for(const [id,value]of Object.entries(values)){if(value==null)delete state.keys[type][id];else state.keys[type][id]=value;}}save('auth.enc',{creds:state.creds,keys:state.keys});}}},logger:pino({level:'silent'}),markOnlineOnConnect:false,syncFullHistory:false,browser:['Mission Control','Desktop','0.1.0']});
  socket=current;
  const on=(event,handler)=>current.ev.on(event,(...args)=>{if(generation===connectionGeneration&&!stopping)return handler(...args);});
  on('creds.update',()=>save('auth.enc',{creds:state.creds,keys:state.keys}));
  on('messages.upsert',({messages})=>ingest(messages));
  on('messaging-history.set',({messages,chats,contacts})=>{updateChats(chats);updateChats(contacts);ingest(messages);});
  on('chats.upsert',updateChats);on('chats.update',updateChats);on('contacts.upsert',updateChats);on('contacts.update',updateChats);
  on('messages.update',updates=>{for(const {key,update} of updates){const id=key.remoteJid+':'+key.id;if(update.message===null)delete state.messages[id];else if(update.message){const old=state.messages[id];if(old)ingest([{key,message:update.message,messageTimestamp:old.time/1000,pushName:old.sender}]);}}ingest([]);});
  on('messages.delete',({keys,jid,all})=>{if(all&&jid)for(const [id,m]of Object.entries(state.messages))if(m.chat===jid)delete state.messages[id];for(const key of keys??[])delete state.messages[key.remoteJid+':'+key.id];save('messages.enc',state.messages);emit({type:'messages',messages:Object.values(state.messages)});});
  on('connection.update',async update=>{
    if(update.qr)emit({type:'qr',png:await QRCode.toDataURL(update.qr,{width:280,margin:2}),status:'Scan in WhatsApp → Settings → Linked devices → Link a device.'});
    if(update.connection==='open'){
      retry=0;const identity=createHash('sha256').update(current.user.id.split(':')[0]).digest('hex');
      const previous=read('identity.enc',null);
      if(previous&&previous!==identity){state.messages={};state.chats={};save('messages.enc',state.messages);save('chats.enc',state.chats);ingest([]);}
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
    if(update.connection==='close'&&!stopping){const code=update.lastDisconnect?.error?.output?.statusCode;if(code===DisconnectReason.loggedOut){emit({type:'status',status:'Session revoked. Disconnect, then link again.',connected:false});}else if(retry++<3){emit({type:'status',status:'Reconnecting…',connected:false});timer=setTimeout(()=>connect().catch(fail),2000*retry);}else emit({type:'status',status:'Connection stopped after three retries. Reconnect manually.',connected:false});}
  });
}
const fail=()=>emit({type:'status',status:'WhatsApp connection failed. Reconnect or relink the device.',connected:false});
process.on('uncaughtException',fail);process.on('unhandledRejection',fail);
createInterface({input:process.stdin}).on('line',async line=>{try{const command=JSON.parse(line);if(command.action==='start'&&!socket){directory=command.directory;secret=Buffer.from(command.key,'base64');if(secret.length!==32)throw Error();mkdirSync(directory,{recursive:true,mode:0o700});const auth=read('auth.enc',{creds:initAuthCreds(),keys:{}});state={...auth,messages:read('messages.enc',{}),chats:read('chats.enc',{})};ingest([]);await connect();}else if(command.action==='stop'){stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);}}catch{fail();}});
process.stdin.on('end',()=>{stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);});
