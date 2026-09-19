import {createBrain} from './brain-v4.mjs';

const canvas=document.querySelector('#film'),ctx=canvas.getContext('2d',{alpha:false});
const FONT='"Microsoft YaHei", "Segoe UI", sans-serif';
const C={bg:'#f3f5f7',paper:'#ffffff',ink:'#233244',muted:'#74818f',line:'#e3e8ee',teal:'#187e83',tealSoft:'#eaf4f3',orange:'#b76a32',orangeSoft:'#fbf1e8',viewer:'#141e2b',viewerHead:'#1c2837',darkMuted:'#91a2b5',green:'#698b63'};
const clamp=x=>Math.max(0,Math.min(1,x));
const smooth=(a,b,t)=>{const v=clamp((t-a)/(b-a));return v*v*(3-2*v)};
const ease=x=>1-(1-clamp(x))**3;
const mix=(a,b,t)=>a+(b-a)*t;
const stage=t=>t<2.35?'ready':t<9.1?'analysis':'complete';
const brain=await createBrain();
const scans=await new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=reject;image.src='../brain-medical-system-master-keyframe-v1.png'});
await document.fonts.load('500 23px "Microsoft YaHei"','颞叶');
await document.fonts.ready;
const reportSnapshot=brain.captureReport(13.65);

function round(x,y,w,h,r=6){ctx.beginPath();ctx.roundRect(x,y,w,h,r)}
function box(x,y,w,h,fill=C.paper,stroke=null,r=6){round(x,y,w,h,r);if(fill){ctx.fillStyle=fill;ctx.fill()}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1;ctx.stroke()}}
function text(value,x,y,size=16,color=C.ink,weight=400,align='left'){
 const legibleSize=size<16?size+1:size;
 ctx.font=`${weight} ${legibleSize}px ${FONT}`;ctx.textAlign=align;ctx.textBaseline='middle';ctx.fillStyle=color;ctx.fillText(value,x,y);
}
function line(points,color=C.line,width=1){ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.strokeStyle=color;ctx.lineWidth=width;ctx.lineCap='round';ctx.lineJoin='round';ctx.stroke()}
function circle(x,y,r,color,stroke=null){ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);if(color){ctx.fillStyle=color;ctx.fill()}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1.5;ctx.stroke()}}
function icon(name,x,y,size=20,color=C.muted){
 ctx.save();ctx.translate(x,y);ctx.scale(size/24,size/24);ctx.strokeStyle=color;ctx.fillStyle=color;ctx.lineWidth=1.7;ctx.lineCap='round';ctx.lineJoin='round';
 const p=points=>line(points,color,1.7);
 if(name==='grid'){for(const [a,b] of [[3,3],[14,3],[3,14],[14,14]]){round(a,b,7,7,1.3);ctx.stroke()}}
 if(name==='patient'){ctx.beginPath();ctx.arc(12,7,3.6,0,7);ctx.stroke();ctx.beginPath();ctx.moveTo(4,22);ctx.lineTo(4,19);ctx.bezierCurveTo(4,11,20,11,20,19);ctx.lineTo(20,22);ctx.stroke()}
 if(name==='report'){round(5,2,14,20,2);ctx.stroke();p([[9,8],[15,8]]);p([[9,12],[15,12]]);p([[9,16],[13,16]])}
 if(name==='wave')p([[1,13],[5,13],[8,5],[12,20],[16,8],[19,13],[23,13]]);
 if(name==='settings'){ctx.beginPath();ctx.arc(12,12,7,0,7);ctx.stroke();ctx.beginPath();ctx.arc(12,12,2.5,0,7);ctx.stroke();for(let i=0;i<8;i++){const a=i*Math.PI/4;p([[12+Math.cos(a)*7,12+Math.sin(a)*7],[12+Math.cos(a)*10,12+Math.sin(a)*10]])}}
 if(name==='check')p([[5,12],[10,17],[20,6]]);
 if(name==='plus'){p([[4,12],[20,12]]);p([[12,4],[12,20]])}
 if(name==='close'){p([[5,5],[19,19]]);p([[19,5],[5,19]])}
 if(name==='download'){p([[12,3],[12,16],[7,11]]);p([[12,16],[17,11]]);p([[4,16],[4,21],[20,21],[20,16]])}
 if(name==='clock'){ctx.beginPath();ctx.arc(12,12,9,0,7);ctx.stroke();p([[12,6],[12,12],[16,14]])}
 if(name==='rotate'){ctx.beginPath();ctx.arc(12,12,8,.15,Math.PI*1.8);ctx.stroke();p([[18,3],[18,8],[13,7]])}
 if(name==='chevron')p([[9,5],[16,12],[9,19]]);
 if(name==='layers'){p([[2,8],[12,3],[22,8],[12,13],[2,8]]);p([[3,13],[12,18],[21,13]]);p([[3,18],[12,23],[21,18]])}
 ctx.restore();
}
function tag(value,x,y,w,color=C.teal,fill=C.tealSoft){box(x,y-13,w,26,fill,null,4);text(value,x+w/2,y,12,color,500,'center')}
function button(value,x,y,w,enabled=true,style='primary',symbol=null){
 const fill=!enabled?'#e9edf1':style==='primary'?C.teal:C.paper;
 box(x,y,w,44,fill,style==='secondary'?C.line:null,5);
 const color=!enabled?'#9aa6b2':style==='primary'?'#fff':C.ink;
 if(symbol)icon(symbol,x+16,y+12,19,color);
 text(value,x+w/2+(symbol?8:0),y+22,15,color,500,'center');
}

function header(t){
 box(0,0,1920,64,C.paper,null,0);line([[0,64],[1920,64]]);
 // A restrained neural mark replaces the large glowing raster logo.
 const logo=[[31,24],[44,19],[50,32],[39,43],[25,37]];
 line([...logo,logo[0]],C.teal,1.7);line([[31,24],[39,43],[50,32],[25,37]],C.teal,1.2);
 logo.forEach(([x,y])=>circle(x,y,3,C.teal));
 text('脑因智医',69,32,22,C.ink,600);line([[196,21],[196,43]]);
 text('多模态因果脑网络智能诊疗平台',218,32,14,C.muted);
 tag('概念演示',1580,32,80);text('医生工作站',1690,32,14,C.muted);circle(1868,32,16,'#eef2f5');icon('patient',1858,21,20,C.muted);
 box(0,65,72,1015,C.paper,null,0);line([[72,65],[72,1080]]);
 ['grid','patient','wave','report'].forEach((name,i)=>{
  const y=107+i*64;if(i===1){box(12,y-17,48,44,C.tealSoft,null,5);box(0,y-17,3,44,C.teal,null,0)}
  icon(name,25,y-6,22,i===1?C.teal:C.muted);
 });
 icon('settings',25,1019,22);
 text('工作台',96,94,13,C.muted);text('/',151,94,13,'#b7c0c9');text('患者分析',169,94,13,C.muted);
 text('脑网络分析',96,137,27,C.ink,600);
 text('P0001',285,138,14,C.muted);tag('示例患者',344,137,76,'#68798a','#e9eef3');
 const stepLabels=['数据接入','因果网络分析','结果与报告'];
 stepLabels.forEach((label,i)=>{
  const x=1265+i*215,active=i===0||i===1&&t>2.35||i===2&&t>=9.1;
  circle(x,133,10,active?C.teal:'#dce2e8');
  if(i===0||i===1&&t>=9.1)icon('check',x-7,126,14,'#fff');else text(String(i+1),x,133,11,'#fff',500,'center');
  text(label,x+20,133,14,active?C.ink:C.muted,i===2&&t>=9.1?500:400);
  if(i<2)line([[x+150,133],[x+194,133]],C.line);
 });
}

function wave(t,x,y,w,h,color=C.teal){
 ctx.save();ctx.beginPath();ctx.rect(x,y,w,h);ctx.clip();
 for(let channel=0;channel<3;channel++){
  line([[x,y+10+channel*19],[x+w,y+10+channel*19]],'#e9eef1');
  const points=[];
  for(let dx=0;dx<w;dx++){
   const phase=dx*.20-t*3+channel*2.3;
   const signal=Math.sin(phase)*2.3+Math.sin(phase*2.37+.8)*1.6;
   const burst=Math.exp(-Math.pow(((dx+t*25+channel*14)%85-42)/5.5,2))*Math.sin(phase*3.3)*6;
   points.push([x+dx,y+12+channel*19+signal+burst]);
  }
  line(points,color,1.15);
 }
 ctx.restore();
}

function leftPanel(t){
 const state=stage(t);box(96,180,260,812,C.paper,C.line,6);
 text('患者信息',116,210,17,C.ink,600);line([[116,233],[336,233]]);
 text('示例患者',116,263,20,C.ink,600);tag('示例',290,262,44,'#718294','#f0f3f6');
 [['患者编号','P0001'],['性别 / 年龄','男 / 56岁']].forEach(([label,value],i)=>{text(label,116,300+i*32,13,C.muted);text(value,336,300+i*32,14,C.ink,400,'right')});
 line([[116,359],[336,359]]);text('多模态数据',116,389,17,C.ink,600);text('3 / 3',336,389,12,C.muted,400,'right');
 const rows=[{name:'fMRI',desc:'功能磁共振',sy:451},{name:'DTI',desc:'弥散张量成像',sy:598}];
 rows.forEach((row,i)=>{
  const y=422+i*121;
  box(116,y,68,68,'#151c24',null,4);ctx.save();round(116,y,68,68,4);ctx.clip();ctx.drawImage(scans,176,row.sy+3,92,86,116,y,68,68);ctx.restore();
  text(row.name,198,y+12,16,C.ink,600);text(row.desc,198,y+35,12,C.muted);
  icon('check',198,y+49,14,C.teal);text(state==='complete'?'分析完成':'数据已导入',218,y+57,12,C.teal);
  line([[116,y+95],[336,y+95]]);
 });
 text('EEG',116,682,16,C.ink,600);text('脑电信号',336,682,12,C.muted,400,'right');
 wave(t,116,702,220,64);
 icon('check',116,779,14,C.teal);text(state==='complete'?'分析完成':'数据已导入',136,786,12,C.teal);
 line([[116,817],[336,817]]);
 const progress=state==='ready'?0:state==='complete'?1:clamp((t-2.35)/6.75);
 text(state==='ready'?'数据已就绪':state==='complete'?'分析已完成':t<4.4?'多模态数据融合':t<7?'正在构建因果网络':'正在生成分析结果',116,846,13,C.muted);
 if(state==='analysis'){box(116,869,170,4,'#e5ebef',null,2);box(116,869,170*progress,4,C.teal,null,2);text(`${Math.round(8+92*progress)}%`,336,871,12,C.teal,500,'right')}
 else text(state==='ready'?'可开始脑网络分析':'结果与报告可查看',116,873,12,C.muted);
 button(state==='ready'?'开始分析':state==='analysis'?'分析中…':'分析完成',116,904,220,state!=='analysis','primary',state==='complete'?'check':null);
 text('fMRI · DTI · EEG',226,971,11,C.muted,400,'center');
}

function legend(t){
 if(t<9.1)return;
 const items=[{x:402,type:'secondary',label:'脑区 / 网络连接',node:true},{x:640,type:'propagation',label:'次级传播通路（示意）'},{x:946,type:'primary',label:'关键因果通路',node:true},{x:1184,type:'primary',label:'异常起始脑区',source:true}];
 line([[397,924],[1388,924]],'#2e3a49');
 items.forEach(item=>{
  const color=brain.network.palette[item.type],y=951;
  if(item.node||item.source)circle(item.x+4,y,4,color);
  if(item.source)circle(item.x+4,y,8,null,color);
  else{line([[item.x+15,y],[item.x+42,y]],color,1.8);ctx.beginPath();ctx.moveTo(item.x+43,y);ctx.lineTo(item.x+36,y-3.5);ctx.lineTo(item.x+36,y+3.5);ctx.closePath();ctx.fillStyle=color;ctx.fill()}
  text(item.label,item.x+(item.source?22:52),y,12,'#b4c0cf');
 });
}

function brainPanel(t){
 box(376,180,1032,812,C.viewer,null,6);
 ctx.save();round(376,180,1032,812,6);ctx.clip();box(376,180,1032,52,C.viewerHead,null,0);ctx.restore();
 text('因果脑网络',400,207,18,'#ecf0f5',500);
 box(1120,190,112,32,'#334253',null,4);text('三维表面',1176,206,13,'#ecf0f5',500,'center');text('切片',1265,206,13,C.darkMuted,400,'center');icon('rotate',1338,196,20,C.darkMuted);
 const state=stage(t);circle(402,262,3,state==='complete'?'#72b4a4':C.darkMuted);
 text(state==='ready'?'待分析':state==='analysis'?'网络构建中':'分析完成',415,262,12,C.darkMuted);
 text('fMRI / DTI / EEG',1384,262,12,C.darkMuted,400,'right');
 ctx.save();round(377,275,1030,642,0);ctx.clip();ctx.drawImage(brain.render(t),0,0,1000,900,406,174,972,820);ctx.restore();
 // Small orientation widget, with no decorative holographic rings.
 line([[1344,874],[1319,859]],'#8b9db1',1.5);line([[1344,874],[1371,868]],'#8b9db1',1.5);line([[1344,874],[1344,844]],'#8b9db1',1.5);
 text('L',1310,854,10,C.darkMuted);text('P',1376,868,10,C.darkMuted);text('S',1344,835,10,C.darkMuted,400,'center');
 if(t<9.1)text('脑网络连接将在分析过程中逐步呈现',400,951,12,C.darkMuted);else legend(t);
 text('节点位置为概念映射',1383,976,10,'#728296',400,'right');
}

function chart(t,x,y,w,h,reveal=1,dark=false){
 const muted=dark?'#91a2b5':C.muted,grid=dark?'#314052':'#e9edf2';
 const values=[[.25,.25,.26,.28,.32],[.38,.48,.64,.76,.88]],colors=['#468f99','#b97847'];
 for(let i=0;i<3;i++){const yy=y+h-i*h/2;line([[x,yy],[x+w,yy]],grid);text((i*.5).toFixed(1),x-12,yy,11,muted,400,'right')}
 for(let i=0;i<5;i++)text('T'+(i+1),x+i*w/4,y+h+22,11,muted,400,'center');
 if(reveal<=0){text('等待分析完成',x+w/2,y+h/2,13,muted,400,'center');return}
 for(let s=0;s<2;s++){
  ctx.save();ctx.beginPath();ctx.rect(x-7,y-7,(w+14)*reveal,h+14);ctx.clip();
  const points=values[s].map((value,i)=>[x+i*w/4,y+h-value*h]);line(points,colors[s],2);
  points.forEach(([px,py])=>{circle(px,py,3.5,C.paper);circle(px,py,2.7,colors[s])});ctx.restore();
 }
}

function rightPanel(t){
 const complete=t>=9.1;box(1428,180,468,812,C.paper,C.line,6);
 text('辅助分析结果',1452,210,18,C.ink,600);tag(complete?'已生成':'待分析',1808,208,64,complete?C.teal:C.muted,complete?C.tealSoft:'#f1f3f6');line([[1452,233],[1872,233]]);
 const fields=[{label:'异常脑区',value:'颞叶',y:267,at:8.9},{label:'关键因果通路',value:'颞叶 → 丘脑 → 额叶',y:391,at:9.18}];
 fields.forEach(field=>{
  text(field.label,1452,field.y,13,C.muted);
  const alpha=ease((t-field.at)/.65);text('待生成',1452,field.y+40,22,'#bcc5ce');
  if(alpha>0){ctx.save();ctx.globalAlpha=alpha;box(1449,field.y+18,422,48,C.paper,null,0);text(field.value,1452,field.y+42,field.label==='异常脑区'?28:23,field.label==='异常脑区'?C.orange:C.ink,500);ctx.restore()}
 });
 if(complete)tag('高风险',1798,310,74,'#a65542','#f8eeeb');
 line([[1452,350],[1872,350]]);line([[1452,472],[1872,472]]);
 text('模型置信度',1452,508,13,C.muted);
 const confidence=87*smooth(9.8,11.25,t);
 text(t>9.8?Math.round(confidence)+'%':'—',1452,550,33,C.ink,500);
 text('示意结果',1872,550,12,C.muted,400,'right');
 box(1452,585,420,5,'#edf1f4',null,2);if(confidence>0)box(1452,585,420*confidence/100,5,C.teal,null,2);
 line([[1452,621],[1872,621]]);text('关键指标趋势',1452,652,17,C.ink,500);text('示意',1872,652,12,C.muted,400,'right');
 chart(t,1490,690,350,147,smooth(9.6,12,t));
 text('结果需经医生审核',1452,888,12,C.muted);
 button('生成辅助报告',1452,922,420,t>9.8,'primary','report');
}

function cursor(t){
 let x,y,alpha=0,click;
 if(t>.55&&t<3.05){const u=ease((t-.75)/1.25);x=mix(470,220,u);y=mix(974,925,u);alpha=smooth(.55,.8,t)*(1-smooth(2.65,3.05,t));click=2.18}
 if(t>12.2&&t<14.6){const u=ease((t-12.3)/1.12);x=mix(1340,1660,u);y=mix(1025,945,u);alpha=smooth(12.2,12.45,t)*(1-smooth(13.95,14.5,t));click=13.65}
 if(alpha<=0)return;
 ctx.save();ctx.globalAlpha=alpha;
 if(t>click&&t<click+.45){const u=(t-click)/.45;ctx.globalAlpha=alpha*(1-u);circle(x+4,y+5,8+22*u,null,'#58a9aa');ctx.globalAlpha=alpha}
 ctx.translate(x,y);ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(0,23);ctx.lineTo(6,17);ctx.lineTo(11,28);ctx.lineTo(16,26);ctx.lineTo(11,15);ctx.lineTo(21,15);ctx.closePath();ctx.fillStyle='#fff';ctx.fill();ctx.strokeStyle='#243649';ctx.lineWidth=1.3;ctx.stroke();ctx.restore();
}

function report(t){
 const amount=ease((t-13.85)/1.05);if(amount<=0)return;
 const x=mix(1938,990,amount);
 ctx.save();ctx.globalAlpha=.12*amount;ctx.fillStyle='#132132';ctx.fillRect(73,65,1847,1015);ctx.restore();
 ctx.save();ctx.shadowColor='rgba(19,33,50,.12)';ctx.shadowBlur=24;ctx.shadowOffsetX=-5;box(x,112,906,902,C.paper,null,7);ctx.restore();
 text('辅助分析报告',x+28,152,24,C.ink,600);tag('已生成',x+215,151,64);icon('close',x+855,141,22,C.muted);line([[x,186],[x+906,186]]);
 text('示例患者',x+28,218,18,C.ink,600);text('P0001',x+138,218,14,C.muted);
 text('男 · 56岁',x+28,248,14,C.muted);text('数据来源  fMRI / DTI / EEG',x+876,248,13,C.muted,400,'right');
 line([[x+28,274],[x+878,274]]);text('脑网络分析摘要',x+28,302,17,C.ink,600);
 ctx.save();round(x+28,329,364,251,4);ctx.clip();ctx.drawImage(reportSnapshot,x+28,329,364,251);ctx.restore();
 const rows=[['异常脑区','颞叶',C.orange],['风险等级','高风险','#a65542'],['模型置信度','87%',C.ink]];
 rows.forEach(([label,value,color],i)=>{const y=363+i*84;text(label,x+424,y,14,C.muted);text(value,x+870,y,25,color,500,'right');if(i<2)line([[x+424,y+39],[x+874,y+39]])});
 box(x+28,608,850,58,'#f6f8fa',C.line,4);text('关键因果通路',x+46,637,14,C.muted);text('颞叶  →  丘脑  →  额叶',x+242,637,22,C.ink,500);
 text('关键指标趋势',x+28,704,17,C.ink,600);text('示意数据',x+878,704,12,C.muted,400,'right');
 chart(t,x+66,741,781,128,1);
 text('示意数据，仅供辅助决策；需医生审核。',x+28,917,12,C.muted);
 line([[x,942],[x+906,942]]);icon('clock',x+28,972,19,C.muted);text('待医生审核',x+57,982,14,C.muted);
 button('加入随访',x+508,960,158,true,'secondary','plus');button('导出 PDF',x+682,960,196,true,'primary','download');
}

const rigAudit={frames:0,maxDrift:0,allNodesParented:true,sourceRing3D:true,sourcePixels:[]};
window.drawFrame=function(t){
 ctx.setTransform(1,0,0,1,0,0);ctx.globalAlpha=1;ctx.fillStyle=C.bg;ctx.fillRect(0,0,1920,1080);
 header(t);leftPanel(t);brainPanel(t);rightPanel(t);cursor(t);
 text('概念系统演示 · 示意数据 · 不用于临床诊断',96,1043,12,C.muted);
 text('脑因智医 / 辅助诊疗工作站',1896,1043,12,C.muted,400,'right');report(t);return true;
};
window.frameAsJpeg=t=>{
 window.drawFrame(t);
 const check=brain.verifyAnchors(),source=check.checks.find(node=>node.id==='temporal');
 rigAudit.frames++;rigAudit.maxDrift=Math.max(rigAudit.maxDrift,check.maxAnchorDrift);
 rigAudit.allNodesParented&&=check.checks.every(node=>node.parentIsCortex);rigAudit.sourceRing3D&&=source.ringIs3D;
 if(rigAudit.frames%60===1)rigAudit.sourcePixels.push({time:t,pixel:source.pixel});
 return canvas.toDataURL('image/jpeg',.96).split(',')[1];
};
window.rigAudit=rigAudit;
window.verifyBrainSurface=t=>{window.drawFrame(t);return{time:t,...brain.verifySurface(),...brain.verifyAnchors()}};
window.brainNetworkEvidence={network:brain.network,surface:brain.surfaceEvidence,capturedAt:13.65,reportSource:'same renderer snapshot',ui:'vector text and controls, no generated interface backdrop',clinicalValues:{patient:'P0001',sex:'男',age:56,abnormalRegion:'颞叶',risk:'高风险',confidence:.87},duration:18};
window.videoReady=true;window.drawFrame(0);
if(new URLSearchParams(location.search).has('play')){const epoch=performance.now();const loop=()=>{window.drawFrame(((performance.now()-epoch)/1000)%18);requestAnimationFrame(loop)};requestAnimationFrame(loop)}
