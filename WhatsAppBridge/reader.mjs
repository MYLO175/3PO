import makeWASocket, { initAuthCreds, BufferJSON, DisconnectReason, proto } from '@whiskeysockets/baileys';
import pino from 'pino';
import QRCode from 'qrcode';
import { createInterface } from 'node:readline';
import { seal, open, textMessage, boundedMessages } from './data.mjs';
import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs';
import { join } from 'node:path';
const emit = value => process.stdout.write(JSON.stringify(value)+'\n');
let socket, directory, secret, state, stopping=false, retry=0, timer;
function read(name,fallback) {
  const path=join(directory,name); if(!existsSync(path)) return fallback;
  return JSON.parse(open(readFileSync(path),secret),BufferJSON.reviver);
}
function save(name,value) {
  const path=join(directory,name); writeFileSync(path+'.tmp',seal(JSON.stringify(value,BufferJSON.replacer),secret),{mode:0o600}); renameSync(path+'.tmp',path);
}
function ingest(messages) {
  for(const m of messages) {
    const value=textMessage(m);
    if(value) state.messages[value.id]=value;
  }
  state.messages=boundedMessages(state.messages);
  save('messages.enc',state.messages); emit({type:'messages',messages:Object.values(state.messages),coverage:'Linked-device text received so far; history may be partial.'});
}
async function connect() {
  socket=makeWASocket({auth:{creds:state.creds,keys:{get:async(type,ids)=>Object.fromEntries(ids.filter(id=>state.keys[type]?.[id]!=null).map(id=>[id,type==='app-state-sync-key'?proto.Message.AppStateSyncKeyData.fromObject(state.keys[type][id]):state.keys[type][id]])),set:async(data)=>{for(const [type,values] of Object.entries(data)){state.keys[type]??={};for(const [id,value]of Object.entries(values)){if(value==null)delete state.keys[type][id];else state.keys[type][id]=value;}}save('auth.enc',{creds:state.creds,keys:state.keys});}}},logger:pino({level:'silent'}),markOnlineOnConnect:false,syncFullHistory:false,browser:['Mission Control','Desktop','0.1.0']});
  socket.ev.on('creds.update',()=>save('auth.enc',{creds:state.creds,keys:state.keys}));
  socket.ev.on('messages.upsert',({messages})=>ingest(messages));
  socket.ev.on('messaging-history.set',({messages})=>ingest(messages));
  socket.ev.on('messages.delete',({keys})=>{for(const key of keys??[])delete state.messages[key.remoteJid+':'+key.id];save('messages.enc',state.messages);emit({type:'messages',messages:Object.values(state.messages)});});
  socket.ev.on('connection.update',async update=>{
    if(update.qr)emit({type:'qr',png:await QRCode.toDataURL(update.qr,{width:280,margin:2}),status:'Scan in WhatsApp → Settings → Linked devices → Link a device.'});
    if(update.connection==='open'){retry=0;emit({type:'status',status:'Connected · read-only',connected:true});}
    if(update.connection==='close'&&!stopping){const code=update.lastDisconnect?.error?.output?.statusCode;if(code===DisconnectReason.loggedOut){emit({type:'status',status:'Session revoked. Disconnect, then link again.',connected:false});}else if(retry++<3){emit({type:'status',status:'Reconnecting…',connected:false});timer=setTimeout(()=>connect().catch(fail),2000*retry);}else emit({type:'status',status:'Connection stopped after three retries. Reconnect manually.',connected:false});}
  });
}
const fail=()=>emit({type:'status',status:'WhatsApp connection failed. Reconnect or relink the device.',connected:false});
process.on('uncaughtException',fail);process.on('unhandledRejection',fail);
createInterface({input:process.stdin}).on('line',async line=>{try{const command=JSON.parse(line);if(command.action==='start'&&!socket){directory=command.directory;secret=Buffer.from(command.key,'base64');if(secret.length!==32)throw Error();mkdirSync(directory,{recursive:true,mode:0o700});const auth=read('auth.enc',{creds:initAuthCreds(),keys:{}});state={...auth,messages:read('messages.enc',{})};ingest([]);await connect();}else if(command.action==='stop'){stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);}}catch{fail();}});
process.stdin.on('end',()=>{stopping=true;clearTimeout(timer);socket?.end(undefined);process.exit(0);});
