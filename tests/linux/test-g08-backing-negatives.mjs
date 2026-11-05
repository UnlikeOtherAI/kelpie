import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {resolve,join} from 'node:path';
const [rootArg,binaryArg,outArg]=process.argv.slice(2);
if (!outArg) throw Error('Expected completed G08 capture directory, candidate binary and new output directory');
const root=resolve(rootArg), binary=resolve(binaryArg), out=resolve(outArg);
await mkdir(out,{mode:0o700});
const report=JSON.parse(await readFile(join(root,'media/input.json'),'utf8'));
const c=report.cases.find(x=>x.curve==='c'), gif=c.artifacts.find(x=>x.mimeType==='image/gif').file;
const records=(await readFile(join(root,'c-backing.jsonl'),'utf8')).trimEnd().split('\n').map(x=>JSON.parse(x));
const expected=JSON.parse(await readFile(join(root,'c-expected.json'),'utf8'));
const run=(name,items,exp,needle)=>{
 const input=join(out,name+'.jsonl'), ep=join(out,name+'.json'), receipt=join(out,name+'-receipt.json');
 return Promise.all([writeFile(input,items.map(x=>JSON.stringify(x)).join('\n')+'\n',{flag:'wx',mode:0o600}),writeFile(ep,JSON.stringify(exp),{flag:'wx'})]).then(()=>{
  const result=spawnSync(process.execPath,['tests/linux/verify-g08-backing.mjs',input,gif,ep,join(root,'candidate-evidence.json'),binary,join(root,'media/input.json'),receipt],{encoding:'utf8',timeout:30000});
  if(result.status===0 || !String(result.stderr).includes(needle)) throw Error(name+' did not reject expected defect: '+result.stderr);
  return {name,rejected:true,reason:needle};
 });
};
const altered=structuredClone(records);const bytes=Buffer.from(altered[0].bgraBase64,'base64');bytes[0]=0;altered[0].bgraBase64=bytes.toString('base64');altered[0].bgraSHA256=createHash('sha256').update(bytes).digest('hex');
const timing=structuredClone(records);timing[1].elapsedMs+=8;
const missing=records.slice(1);const wrong={...expected,documentId:'wrong-document'};
const results=[];
results.push(await run('nonwhite',altered,expected,'Backing is not opaque white'));
results.push(await run('timing',timing,expected,'GIF PTS does not match source sample'));
results.push(await run('missing',missing,expected,'Dropped or unlinked GIF samples'));
results.push(await run('document',records,wrong,'wrong-document'));
await writeFile(join(out,'results.json'),JSON.stringify(results,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify(results));
