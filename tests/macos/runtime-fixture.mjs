import {createServer} from "node:http";
export const canary = "KELPIE_NATIVE_Aa b+!_DO_NOT_EXPORT";
export async function startFixture() {
 const events=[]; const sockets=new Set();
 const server=createServer(async(req,res)=>{
  const url=new URL(req.url,"http://fixture.invalid");
  if(req.method==="POST"&&url.pathname==="/events"){
   let text="";for await(const bytes of req){text+=bytes;if(text.length>16384){res.writeHead(413).end();return;}}
   let value;try{value=JSON.parse(text);}catch{res.writeHead(400).end();return;}
   if(events.length<10000)events.push(value);
   res.writeHead(202).end();return;
  }
  const mode=url.pathname;
  const privacyMode=["/focus-password","/focus-autocomplete","/focus-url","/focus-delay","/input-autocomplete","/known-url"].includes(mode)?mode:"";
  const pacedMode=["/paced","/paced-blur","/paced-replace","/paced-sensitive"].includes(mode)?mode:"";
  const title=mode==="/secret"||privacyMode||pacedMode==="/paced-sensitive"?canary+" | "+encodeURIComponent(canary)+" | "+new URLSearchParams({v:canary}).toString().slice(2):mode==="/paced"?"Paced A😀e fixture":"Hosted Mac fixture";
  const motion=mode==="/motion",bands=mode==="/bands",next=mode==="/next";
  const body=motion?'<button id="first" aria-label="First"></button><button id="second" aria-label="Second"></button>':
   bands?"":next?'<h1>Next native document</h1>':`
   <label>Draft message<textarea id="entry">Draft seed</textarea></label>
   <label>Account password<input id="password" type="password"></label>
   <label id="privacy-label">Focus privacy<input id="focus-privacy" type="text"></label>
   <button id="submit">Submit</button><a id="next" href="/next">Next document</a>
   <div id="clip"><button id="partial">Partially visible</button></div>
   <button id="duplicate-a">Duplicate</button><button id="duplicate-b">Duplicate</button>
   <button id="disabled" disabled>Disabled</button><button hidden>Hidden</button>
   <div id="cover-box"><button id="covered">Covered</button><div id="cover">Cover</div></div>
   <button id="replace"><span>Replace child</span></button>
   <label>Readonly on focus<input id="readonly" value="seed"></label>
   <button id="moving">Moving</button><button id="start">Start motion</button>
   <section id="catalogue"><h3>Green tea</h3><h3>Black tea</h3></section>
   <button id="scroll-target">Scrolled target</button>`;
  const script=`(()=>{const privacyMode=${JSON.stringify(privacyMode)},pacedMode=${JSON.stringify(pacedMode)};const documentId=crypto.randomUUID();let sequence=0;
  const send=(value,synchronous=false)=>{const body=JSON.stringify({
   documentId,sequence:++sequence,path:location.pathname,time:performance.now(),...value,scrollX,scrollY,viewport:{width:innerWidth,height:innerHeight,clientWidth:document.documentElement.clientWidth,clientHeight:document.documentElement.clientHeight,pixelRatio:devicePixelRatio},
   visual:{pageX:visualViewport.pageLeft,pageY:visualViewport.pageTop,width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale}});
   if(synchronous){const request=new XMLHttpRequest();request.open('POST','/events',false);request.setRequestHeader('content-type','application/json');request.send(body);return;}
   return fetch('/events',{method:'POST',headers:{'content-type':'application/json'},body}).catch(()=>{});};
  for(const type of ['pointermove','pointerdown','pointerup','click','input'])document.addEventListener(type,event=>{
   const target=event.target.closest('button,a,input,textarea');const r=target?.getBoundingClientRect();
   const clip=target?.id==='partial'?document.querySelector('#clip').getBoundingClientRect():null;
   send({type,target:target?.id??null,trusted:event.isTrusted,x:event.clientX??null,y:event.clientY??null,
    hit:typeof event.clientX==='number'?document.elementFromPoint(event.clientX,event.clientY)?.closest('button,a')?.id:null,
    rect:r?{left:Math.max(0,r.left,clip?.left??0),top:Math.max(0,r.top),right:Math.min(innerWidth,r.right,clip?.right??innerWidth),bottom:Math.min(innerHeight,r.bottom)}:null});
  },true);
  for(const id of ['entry','focus-privacy']){
   const field=document.getElementById(id);
   field?.addEventListener('focus',()=>{if(pacedMode)send({type:'paced-focus',target:id},true)});
   field?.addEventListener('input',event=>{
    if(!pacedMode)return;
    const value=event.target,rect=value.getBoundingClientRect();
    send({type:'paced-input',target:id,length:value.value.length,rect:{left:rect.left,top:rect.top,width:rect.width,height:rect.height}},true);
    if(id==='entry'&&pacedMode==='/paced-blur')value.blur();
    if(id==='entry'&&pacedMode==='/paced-replace')value.replaceWith(value.cloneNode(true));
    if(id==='focus-privacy'&&pacedMode==='/paced-sensitive')value.autocomplete='current-password';
   });
  }
  document.querySelector('#submit')?.addEventListener('pointerdown',()=>{if(privacyMode==='/known-url'){send({type:'known-mid-transition'},true);history.replaceState(null,'','/known-url-changed')}});
  document.querySelector('#submit')?.addEventListener('click',()=>{if(privacyMode==='/known-url')send({type:'known-final-click'},true)});
  document.querySelector('#replace')?.addEventListener('pointerdown',event=>{event.currentTarget.replaceChildren(document.createElement('span'))});
  document.querySelector('#readonly')?.addEventListener('focus',event=>{event.target.readOnly=true});
  document.querySelector('#focus-privacy')?.addEventListener('focus',event=>{
   if(!privacyMode||privacyMode==='/input-autocomplete')return;
   if(privacyMode==='/focus-password')event.target.type='password';else event.target.autocomplete='current-password';
   send({type:'focus-privacy'},privacyMode==='/focus-delay');
   if(privacyMode==='/focus-url')history.replaceState(null,'','/focus-url-changed');
   if(privacyMode==='/focus-delay'){const end=performance.now()+5500;while(performance.now()<end){}}
  });
  document.querySelector('#focus-privacy')?.addEventListener('input',event=>{
   if(privacyMode==='/input-autocomplete')event.target.autocomplete='current-password';
  });
  document.querySelector('#password')?.addEventListener('input',event=>{document.title=event.target.value});
  document.querySelector('#start')?.addEventListener('click',()=>document.querySelector('#moving').animate(
   [{transform:'translateX(0px)'},{transform:'translateX(100px)'}],{duration:200,iterations:Infinity,direction:'alternate'}));
  addEventListener('scroll',()=>send({type:'scroll'}));
  send({type:'document'});
  })();`;
  const style=motion?`body{margin:0;background:white;overflow:hidden}button{position:absolute;border:0;background:white;color:white}
   #first{left:40px;top:230px;width:30px;height:30px}#second{left:540px;top:60px;width:30px;height:30px}`:
   bands?`body{margin:0;height:9000px;background:repeating-linear-gradient(to bottom,#f00 0 1000px,#0f0 1000px 2000px,#00f 2000px 3000px,#f0f 3000px 4000px)}`:
   next?"body{background:#ffe881;color:black}":`
   body{margin:12px;font:14px sans-serif;background:white;min-height:2000px}
   label{display:inline-block;margin:4px}textarea,input{width:150px;height:35px}button,a{padding:12px;margin:5px}
   #privacy-label{position:absolute;left:560px;top:60px}
   #submit{position:absolute;left:140px;top:100px;width:180px;height:60px}
   #next{position:absolute;left:330px;top:110px}#clip{position:absolute;left:520px;top:110px;width:110px;overflow:hidden}
   #partial{width:180px;margin-left:-80px}#duplicate-a{position:absolute;left:20px;top:190px}
   #duplicate-b{position:absolute;left:150px;top:190px}#disabled{position:absolute;left:280px;top:190px}
   #cover-box{position:absolute;left:400px;top:190px}#cover{position:absolute;inset:0;background:#ddd}
   #replace{position:absolute;left:20px;top:260px}label:has(#readonly){position:absolute;left:180px;top:270px}
   #moving{position:absolute;left:20px;top:330px}#start{position:absolute;left:180px;top:330px}
   #catalogue{position:absolute;top:410px}#scroll-target{position:absolute;top:1500px;left:100px}
   `;
  const html="<!doctype html><meta charset=utf-8><title>"+title.replaceAll("&","&amp;").replaceAll("<","&lt;")+"</title><style>"+style+"</style>"+body+"<script>"+script+"</script>";
  res.writeHead(200,{"content-type":"text/html","cache-control":"no-store"}).end(html);
 });
 server.on("connection",socket=>{sockets.add(socket);socket.once("close",()=>sockets.delete(socket));});
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 return {url:"http://127.0.0.1:"+server.address().port,events,
  close:()=>new Promise(resolve=>{for(const socket of sockets)socket.destroy();server.close(resolve);})};
}
