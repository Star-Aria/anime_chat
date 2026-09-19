import * as THREE from './assets/three.module.js';
import {network} from './brain-network.mjs';
import {createSurfaceNetwork} from './surface-network.mjs';
import {selectSurfaceAnchor} from './surface-anchors.mjs';

const smooth=(a,b,x)=>{const q=Math.min(1,Math.max(0,(x-a)/(b-a)));return q*q*(3-2*q)};
export async function createBrain(){
 const meshData=await fetch('./assets/brain-mesh.json').then(r=>r.json());
 const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:true,powerPreference:'high-performance'});
 renderer.setSize(1000,900);renderer.setClearColor(0x000000,0);
 renderer.outputColorSpace=THREE.SRGBColorSpace;
 const composite=document.createElement('canvas');composite.width=1000;composite.height=900;
 const context=composite.getContext('2d');
 const surfaceImage=document.createElement('canvas');surfaceImage.width=1000;surfaceImage.height=900;
 const surfaceContext=surfaceImage.getContext('2d');
 const scene=new THREE.Scene();
 const camera=new THREE.PerspectiveCamera(30,1000/900,0.1,100);
 camera.position.set(0,.02,6.0);camera.lookAt(0,0,0);
 const group=new THREE.Group();scene.add(group);
 const materials=[],cortexMeshes=[];
 for(const part of meshData.hemispheres){
  const geometry=new THREE.BufferGeometry();
  geometry.setAttribute('position',new THREE.Float32BufferAttribute(part.positions,3));
  geometry.setAttribute('sulc',new THREE.Float32BufferAttribute(part.sulc,1));
  geometry.setIndex(part.indices);geometry.computeVertexNormals();
  const material=new THREE.ShaderMaterial({
   uniforms:{uTime:{value:0},uScan:{value:0}},
   vertexShader:`attribute float sulc; varying vec3 vNormal; varying vec3 vView; varying vec3 vLocal; varying float vSulc;
    void main(){vec4 p=modelViewMatrix*vec4(position,1.);vNormal=normalize(normalMatrix*normal);vView=-p.xyz;vLocal=position;vSulc=sulc;gl_Position=projectionMatrix*p;}`,
   fragmentShader:`precision highp float; uniform float uTime;uniform float uScan;varying vec3 vNormal;varying vec3 vView;varying vec3 vLocal;varying float vSulc;
    void main(){
     vec3 n=normalize(vNormal);vec3 v=normalize(vView);
     vec3 key=normalize(vec3(-.65,.85,1.2));vec3 fill=normalize(vec3(.8,.1,.7));
     float diffuse=max(dot(n,key),0.);float side=max(dot(n,fill),0.);
     float fold=clamp(.62-.15*vSulc,.26,.96);
     vec3 base=mix(vec3(.055,.09,.16),vec3(.18,.29,.43),fold);
     vec3 color=base*(.40+diffuse*.80+side*.25);
     float rim=pow(1.-max(dot(n,v),0.),2.4);
     float spec=pow(max(dot(reflect(-key,n),v),0.),36.);
     color+=vec3(.28,.48,.64)*rim*.68+vec3(.52,.69,.81)*spec*.19;
     float scanY=1.35-mod(uTime*.56,2.7);
     float band=exp(-pow((vLocal.y-scanY)*22.,2.));
     color+=uScan*band*vec3(.06,.47,.49)*(.25+.35*rim);
     gl_FragColor=vec4(color,1.);
    }`,side:THREE.FrontSide});
  const cortex=new THREE.Mesh(geometry,material);group.add(cortex);cortexMeshes.push(cortex);materials.push(material);
 }
 const glowCanvas=document.createElement('canvas');glowCanvas.width=128;glowCanvas.height=128;
 const gc=glowCanvas.getContext('2d');const gg=gc.createRadialGradient(64,64,0,64,64,64);
 gg.addColorStop(0,'rgba(255,255,255,1)');gg.addColorStop(.12,'rgba(255,255,255,.9)');gg.addColorStop(.30,'rgba(255,255,255,.28)');gg.addColorStop(1,'rgba(255,255,255,0)');gc.fillStyle=gg;gc.fillRect(0,0,128,128);
 const glowTexture=new THREE.CanvasTexture(glowCanvas);
 const colors={cyan:0x5cddd9,amber:0xffbc74,green:0xa2eb8a};
 group.updateMatrixWorld(true);
 const anchors=[];
 const nodes=network.nodes.map(spec=>{
  const anchor=selectSurfaceAnchor(spec,cortexMeshes),position=anchor.center.clone();
  anchors.push({id:spec.id,hemisphere:anchor.side,vertex:anchor.vertex,surface:anchor.point.toArray(),normal:anchor.normal.toArray(),center:position.toArray(),normalOffset:.024});
  const nodeGroup=new THREE.Group();nodeGroup.position.copy(position);
  cortexMeshes[anchor.side].add(nodeGroup);
  const material=new THREE.ShaderMaterial({
   uniforms:{uColor:{value:new THREE.Color(colors.cyan)},uOpacity:{value:1}},
   vertexShader:`varying vec3 vNormal;varying vec3 vView;void main(){vec4 p=modelViewMatrix*vec4(position,1.);vNormal=normalize(normalMatrix*normal);vView=-p.xyz;gl_Position=projectionMatrix*p;}`,
   fragmentShader:`uniform vec3 uColor;uniform float uOpacity;varying vec3 vNormal;varying vec3 vView;void main(){vec3 n=normalize(vNormal);vec3 v=normalize(vView);float light=max(0.,dot(n,normalize(vec3(-.5,.8,1.))));float rim=pow(1.-max(0.,dot(n,v)),2.);float spec=pow(max(dot(reflect(-normalize(vec3(-.5,.8,1.)),n),v),0.),18.);gl_FragColor=vec4(uColor*(.62+.3*light)+vec3(.42)*rim+vec3(.55)*spec,uOpacity);}`,
   transparent:true,depthTest:true,depthWrite:false
  });
  const ball=new THREE.Mesh(new THREE.SphereGeometry(spec.role==='source'?.071:.052,32,24),material);ball.renderOrder=30;nodeGroup.add(ball);
  const sprite=new THREE.Sprite(new THREE.SpriteMaterial({map:glowTexture,color:colors.cyan,transparent:true,opacity:.15,depthTest:true,depthWrite:false,blending:THREE.AdditiveBlending}));sprite.scale.set(.2,.2,1);sprite.renderOrder=29;nodeGroup.add(sprite);
  let ring=null;
  if(spec.role==='source'){
   ring=new THREE.Mesh(new THREE.TorusGeometry(.088,.0035,8,64),new THREE.MeshBasicMaterial({color:colors.amber,transparent:true,opacity:.85,depthTest:true,depthWrite:false}));
   ring.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),anchor.normal);ring.renderOrder=31;nodeGroup.add(ring);
  }
  return{...spec,position,nodeGroup,ball,sprite,ring,anchor};
 });
 const surfaceNetwork=createSurfaceNetwork(network,nodes);
 function render(t){
  const reveal=smooth(9.1,9.8,t);
  group.rotation.set(.06+Math.sin(t*.21)*.045,-.20+Math.sin(t*.32-.4)*.30,Math.sin(t*.19)*.025);
  group.position.y=.045*Math.sin(t*.28);
  for(const material of materials){material.uniforms.uTime.value=t;material.uniforms.uScan.value=smooth(2.5,3,t)*(1-smooth(9.5,10,t));}
  nodes.forEach((node,i)=>{
   const alpha=smooth(2.5+i*.13,3.3+i*.13,t);
   node.nodeGroup.visible=alpha>0;node.nodeGroup.scale.setScalar(.65+.35*alpha);
   node.ball.material.uniforms.uOpacity.value=alpha;
   const color=node.role&&reveal>.1?colors.amber:colors.cyan;
   node.ball.material.uniforms.uColor.value.set(color);node.sprite.material.color.set(color);
   node.sprite.material.opacity=alpha*.16;node.sprite.scale.setScalar(.20);
   if(node.ring)node.ring.visible=reveal>.1;
  });
  const nodeVisibility=nodes.map(node=>node.nodeGroup.visible);
  nodes.forEach(node=>node.nodeGroup.visible=false);
  renderer.render(scene,camera);
  surfaceContext.clearRect(0,0,1000,900);surfaceContext.drawImage(renderer.domElement,0,0);
  nodes.forEach((node,i)=>node.nodeGroup.visible=nodeVisibility[i]);
  renderer.render(scene,camera);
  context.clearRect(0,0,1000,900);context.drawImage(renderer.domElement,0,0);
  context.drawImage(surfaceNetwork.draw(t,camera,group,surfaceImage),0,0);
  // Labels are projected from the same node positions as the 3D arrows.
  nodes.forEach((node,i)=>{
   const alpha=smooth(3.1+i*.13,3.6+i*.13,t);if(alpha<=0)return;
   const point=node.position.clone().applyMatrix4(group.matrixWorld).project(camera);
   const x=(point.x*.5+.5)*1000,y=(-point.y*.5+.5)*900;
   const [dx,dy]=node.offset,color=node.role&&reveal>.1?'#ffce98':'#c4f6f0';
   context.save();context.globalAlpha=alpha;
   context.strokeStyle=color;context.lineWidth=1;context.globalAlpha=alpha*.55;
   context.beginPath();context.moveTo(x+dx*.35,y+dy*.35);context.lineTo(x+dx*.85,y+dy*.7);context.stroke();
   context.globalAlpha=alpha;context.font='500 23px "Microsoft YaHei", "Segoe UI", sans-serif';context.textAlign=node.align;context.textBaseline='middle';
   context.lineJoin='round';context.lineWidth=3;context.strokeStyle='rgba(8,26,42,.82)';context.strokeText(node.label,x+dx,y+dy);
   context.fillStyle=color;context.fillText(node.label,x+dx,y+dy);
   context.restore();
  });
  return composite;
 }
 function captureReport(t=13.65){
  const source=render(t),snapshot=document.createElement('canvas');snapshot.width=1000;snapshot.height=690;
  const c=snapshot.getContext('2d');c.fillStyle='#141e2b';c.fillRect(0,0,1000,690);
  c.drawImage(source,0,100,1000,690,0,0,1000,690);
  return snapshot;
 }
 function verifyAnchors(){
  const checks=nodes.map(node=>{
   const mesh=cortexMeshes[node.anchor.side];
   const vertex=new THREE.Vector3().fromBufferAttribute(mesh.geometry.attributes.position,node.anchor.vertex);
   const expected=vertex.addScaledVector(node.anchor.normal,.024).applyMatrix4(mesh.matrixWorld);
   const actual=node.nodeGroup.getWorldPosition(new THREE.Vector3());
   const screen=actual.clone().project(camera);
   return{id:node.id,vertex:node.anchor.vertex,drift:expected.distanceTo(actual),pixel:[(screen.x*.5+.5)*1000,(-screen.y*.5+.5)*900],parentIsCortex:node.nodeGroup.parent===mesh,ringIs3D:node.ring?node.ring.parent===node.nodeGroup:null};
  });
  return{maxAnchorDrift:Math.max(...checks.map(check=>check.drift)),checks};
 }
 return{render,renderer,captureReport,network,verifyAnchors,verifySurface:()=>surfaceNetwork.verifyMask(surfaceImage),surfaceEvidence:{method:surfaceNetwork.method,anchorMethod:'fixed visible cortical vertex + normal offset, parented to cortex mesh; depth-tested 3D source ring',anchors,edgeCount:surfaceNetwork.edgeCount}};
}
