import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';

const source=readFileSync(new URL('../MissionControl/Mail/MailReader.js',import.meta.url),'utf8');
function reader() {
  const context=createContext({ObjC:{import:()=>{},unwrap:value=>value}});
  runInContext(source,context);return context;
}
function fixture({names=['Inbox','Sent','Archive'],enabled=true,before=false,after=before,identity='fixture@example.invalid',changedIdentity=identity,throwBody=false}={}) {
  let bodyReads=0,stateReads=0,identityReads=0;
  const mailboxes=names.map(name=>()=>({messages:{byId:id=>()=>id===42?{
    messageId:()=>++identityReads===1?identity:changedIdentity,
    readStatus:(...args)=>{assert.equal(args.length,0,'read state must never be written');return ++stateReads===1?before:after},
    content:()=>{bodyReads++;if(throwBody)throw Error('Fixture content unavailable');return name+' disposable body'}
  }:undefined}}));
  mailboxes.name=()=>names;
  const account={enabled:()=>enabled,mailboxes};
  const mail={accounts:{byId:id=>()=>id==='fixture-account'?account:undefined}};
  return {mail,reads:()=>({bodyReads,stateReads,identityReads})};
}
const request={accountID:'fixture-account',messageID:42,expectedInternetMessageID:'fixture@example.invalid'};

test('actual JXA helper previews exact Inbox/Sent/Archive sources with unchanged unread state and no writes',()=>{
  for(const name of ['Inbox','Sent','Archive'])for(const state of [false,true,0,1]){
    const f=fixture({before:state}),context=reader();
    const result=context.runBody(f.mail,{...request,mailboxName:name});
    assert.equal(result.errors.length,0);assert.equal(result.body,name+' disposable body');
    assert.equal(result.unreadBefore,state===false||state===0);assert.equal(result.unreadAfter,result.unreadBefore);
    assert.deepEqual(f.reads(),{bodyReads:1,stateReads:2,identityReads:2});
  }
});
test('changed exact message identity is rejected before content access',()=>{
  const f=fixture({identity:'replacement@example.invalid'});
  const result=reader().runBody(f.mail,request);
  assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);
});
test('ambiguous mailbox, disabled account, different account and vanished ID cannot fall through to another source',()=>{
  const cases=[
    [fixture({names:['Archive','Archive']}),{...request,mailboxName:'Archive'}],
    [fixture({enabled:false}),request],
    [fixture(),{...request,accountID:'different-account'}],
    [fixture(),{...request,messageID:43}],
    [fixture(),{...request,mailboxName:'Missing'}]
  ];
  for(const [f,input] of cases){const result=reader().runBody(f.mail,input);assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);}
});
test('missing read status fails closed before reading; changed or unavailable after-state discards the body',()=>{
  for(const before of [null,'false',undefined,2]){
    const f=fixture({before:before===undefined?null:before});
    const result=reader().runBody(f.mail,request);
    assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);
  }
  for(const after of [true,null,'false']){
    const f=fixture({before:false,after});const result=reader().runBody(f.mail,request);
    assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,1);
  }
});
test('identity changes during content retrieval or unavailable content never become a verified preview',()=>{
  for(const f of [fixture({changedIdentity:'changed@example.invalid'}),fixture({throwBody:true})]){
    const result=reader().runBody(f.mail,request);assert.equal(result.body,'');assert.equal(result.errors.length,1);
  }
});
