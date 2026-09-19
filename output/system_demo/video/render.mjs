import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import http from 'node:http';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
const require=createRequire(import.meta.url);
const {chromium}=require('C:/Users/LLer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.dirname(here);
const version='v4';
const qaDir=path.join(here,'qa-v4');
const args=new Set(process.argv.slice(2));
const mime={'.html':'text/html','.mjs':'text/javascript','.js':'text/javascript','.json':'application/json','.png':'image/png'};
const server=http.createServer((req,res)=>{
 const requestPath=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
 if(requestPath==='/favicon.ico'){res.writeHead(204);res.end();return}
 const p=path.resolve(root,'.'+requestPath);
 if(!p.startsWith(root+path.sep)||!fs.existsSync(p)||!fs.statSync(p).isFile()){res.writeHead(404);res.end();return}
 res.setHeader('Content-Type',mime[path.extname(p)]||'application/octet-stream');fs.createReadStream(p).pipe(res);
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--enable-webgl','--ignore-gpu-blocklist','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-features=CalculateNativeWinOcclusion']});
 const page=await browser.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
 const errors=[];page.on('pageerror',e=>{errors.push(e.message);console.error('PAGE ERROR',e.message)});
 page.on('console',m=>{if(m.type()==='error')console.error('BROWSER',m.text())});
 await page.goto(`http://127.0.0.1:${server.address().port}/video/index-v4.html`);
 await page.waitForFunction(()=>window.videoReady===true,{timeout:60000});
 console.log('Scene ready');
 await fsp.mkdir(qaDir,{recursive:true});
 const samples=[0,3.8,6.5,10.9,16.2];
 for(const t of samples){await page.evaluate(t=>window.drawFrame(t),t);await page.screenshot({path:path.join(qaDir,`frame-${t.toFixed(1)}.png`)});}
 await fsp.writeFile(path.join(qaDir,'brain-network-consistency.json'),JSON.stringify(await page.evaluate(()=>window.brainNetworkEvidence),null,2));
 const surfaceChecks=[];
 for(const time of [3.8,6.5,9.2,10.9,13.65,14.3,16.2,17.8])surfaceChecks.push(await page.evaluate(t=>window.verifyBrainSurface(t),time));
 await fsp.writeFile(path.join(qaDir,'surface-checks.json'),JSON.stringify(surfaceChecks,null,2));
 if(surfaceChecks.some(check=>check.outsidePixels!==0))throw new Error('Arrow pixels outside cortex silhouette');
 if(surfaceChecks.some(check=>check.maxAnchorDrift>1e-10))throw new Error('Cortex anchor drift');
 console.log('Saved five QA frames');
 if(errors.length)throw Error(errors.join('; '));
 if(!args.has('--preview')){
  const exeDir=path.join(here,'vendor','python','imageio_ffmpeg','binaries');
  const exe=fs.readdirSync(exeDir).find(x=>x.endsWith('.exe'));
  const fps=60,duration=args.has('--short')?4:18;
  const output=path.join(root,args.has('--short')?`brain-medical-system-motion-preview-${version}.mp4`:`brain-medical-system-demo-${version}.mp4`);
  const ff=spawn(path.join(exeDir,exe),['-hide_banner','-loglevel','warning','-y','-f','image2pipe','-vcodec','mjpeg','-framerate',String(fps),'-i','pipe:0','-an','-c:v','libx264','-preset','medium','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',output],{stdio:['pipe','ignore','pipe'],windowsHide:true});
  let stderr='';ff.stderr.on('data',c=>{stderr+=c.toString()});
  const done=new Promise((resolve,reject)=>{ff.on('error',reject);ff.on('close',code=>code===0?resolve():reject(Error(`ffmpeg ${code}: ${stderr}`)))});
  const start=Date.now();
  for(let i=0;i<fps*duration;i++){
   const t=(args.has('--short')?5:0)+i/fps;
   const jpg=await page.evaluate(t=>window.frameAsJpeg(t),t);
   if(!ff.stdin.write(Buffer.from(jpg,'base64')))await once(ff.stdin,'drain');
   if(i%60===0)console.log(`Rendered ${i}/${fps*duration} frames (${((Date.now()-start)/1000).toFixed(1)}s)`);
  }
  ff.stdin.end();await done;
  const rigAudit=await page.evaluate(()=>window.rigAudit);
  await fsp.writeFile(path.join(qaDir,'full-frame-rig-audit.json'),JSON.stringify(rigAudit,null,2));
  if(rigAudit.frames!==fps*duration||rigAudit.maxDrift>1e-10||!rigAudit.allNodesParented||!rigAudit.sourceRing3D)throw new Error('Full-frame rig validation failed');
  await fsp.writeFile(path.join(qaDir,args.has('--short')?'preview-render.json':'render-summary.json'),JSON.stringify({output,width:1920,height:1080,fps,duration,frames:fps*duration,renderSeconds:(Date.now()-start)/1000,bytes:fs.statSync(output).size,browserErrors:errors},null,2));
  console.log('COMPLETE',output,fs.statSync(output).size);
 }
}finally{if(browser)await browser.close();server.close();}
