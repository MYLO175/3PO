import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
export function seal(text,key) {
  const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',key,iv);
  const data=Buffer.concat([cipher.update(text),cipher.final()]);
  return Buffer.concat([iv,cipher.getAuthTag(),data]);
}
export function open(bytes,key) {
  const decipher=createDecipheriv('aes-256-gcm',key,bytes.subarray(0,12));
  decipher.setAuthTag(bytes.subarray(12,28));
  return Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]).toString();
}
export function textMessage(m) {
  const chat=m.key?.remoteJid, id=m.key?.id;
  if(!id||!chat||chat==='status@broadcast') return;
  let content=m.message;
  for(let depth=0;depth<4;depth++) {
    const wrapped=content?.ephemeralMessage?.message || content?.viewOnceMessage?.message || content?.documentWithCaptionMessage?.message;
    if(!wrapped) break; content=wrapped;
  }
  const body=content?.conversation ?? content?.extendedTextMessage?.text;
  const time=Number(m.messageTimestamp)*1000;
  if(typeof body!=='string'||!body||!Number.isFinite(time)) return;
  return {id:chat+':'+id,chat,sender:m.pushName||m.key.participant||chat,text:body.slice(0,12000),sentByMe:!!m.key.fromMe,time};
}
export function boundedMessages(messages) {
  return Object.fromEntries(Object.entries(messages).sort((a,b)=>b[1].time-a[1].time).slice(0,2000));
}
