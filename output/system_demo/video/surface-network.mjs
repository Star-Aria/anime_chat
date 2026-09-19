const smooth=(a,b,x)=>{const q=Math.min(1,Math.max(0,(x-a)/(b-a)));return q*q*(3-2*q)};

// Endpoints are actual cortex surface anchors. Continuous annotations are clipped
// to the rendered cortex silhouette, so deep sulci cannot fragment their arrows.
export function createSurfaceNetwork(network,nodes){
 const canvas=document.createElement('canvas');canvas.width=1000;canvas.height=900;
 const context=canvas.getContext('2d');
 const byId=new Map(nodes.map(node=>[node.id,node]));
 const edges=network.edges.map((spec,index)=>({...spec,delay:spec.delay??2.95+index*.18}));
 function draw(t,camera,group,surfaceImage){
  context.clearRect(0,0,canvas.width,canvas.height);
  const reveal=smooth(9.1,9.8,t);
  const project=node=>{
   const world=node.position.clone().applyMatrix4(group.matrixWorld);
   const view=world.clone().applyMatrix4(camera.matrixWorldInverse),p=world.project(camera);
   const radius=(node.role==='source'?.071:.052)*900/(2*Math.tan(camera.fov*Math.PI/360)*-view.z);
   return {x:(p.x*.5+.5)*1000,y:(-.5*p.y+.5)*900,radius};
  };
  for(let index=0;index<edges.length;index++){
   const edge=edges[index],build=smooth(edge.delay,edge.delay+1.65,t);if(build<=0)continue;
   const color=reveal>.05?network.palette[edge.type]:network.palette.secondary;
   const primary=edge.type==='primary';
   const from=project(byId.get(edge.from)),to=project(byId.get(edge.to));
   const distance=Math.hypot(to.x-from.x,to.y-from.y),dx=(to.x-from.x)/distance,dy=(to.y-from.y)/distance;
   const a={x:from.x+dx*(from.radius+3),y:from.y+dy*(from.radius+3)};
   const end={x:to.x-dx*(to.radius+6),y:to.y-dy*(to.radius+6)};
   const b={x:a.x+(end.x-a.x)*build,y:a.y+(end.y-a.y)*build};
   context.save();context.globalAlpha=(primary?.97:.9)*Math.min(1,build*4);
   context.strokeStyle=color;context.lineWidth=primary?4:2.7;context.lineCap='round';
   context.beginPath();context.moveTo(a.x,a.y);context.lineTo(b.x,b.y);context.stroke();
   // Head, shaft and flow particles share this silhouette-constrained layer.
   const at=Math.min(.97,build*.97),tip={x:a.x+(end.x-a.x)*at,y:a.y+(end.y-a.y)*at};
   const length=(primary?29:22)*Math.min(1,build*4),halfWidth=(primary?10.5:8)*Math.min(1,build*4);
   context.fillStyle=color;context.beginPath();context.moveTo(tip.x,tip.y);
   context.lineTo(tip.x-dx*length-dy*halfWidth,tip.y-dy*length+dx*halfWidth);
   context.lineTo(tip.x-dx*length+dy*halfWidth,tip.y-dy*length-dx*halfWidth);context.closePath();context.fill();
   for(let bead=0;bead<2;bead++){
    const phase=(t*.23+index*.173+bead*.5)%1;if(phase>=build)continue;
    const x=a.x+(end.x-a.x)*phase,y=a.y+(end.y-a.y)*phase,radius=primary?14:11;
    const glow=context.createRadialGradient(x,y,0,x,y,radius);
    glow.addColorStop(0,'#ffffff');glow.addColorStop(.14,'#ffffffee');glow.addColorStop(.36,color+'88');glow.addColorStop(1,color+'00');
    context.fillStyle=glow;context.fillRect(x-radius,y-radius,radius*2,radius*2);
   }
   context.restore();
  }
  context.save();context.globalCompositeOperation='destination-in';context.drawImage(surfaceImage,0,0);context.restore();
  return canvas;
 }
 function verifyMask(surfaceImage){
  const maskCanvas=document.createElement('canvas');maskCanvas.width=1000;maskCanvas.height=900;
  const c=maskCanvas.getContext('2d');c.drawImage(surfaceImage,0,0);
  const mask=c.getImageData(0,0,1000,900).data,graph=context.getImageData(0,0,1000,900).data;
  let outsidePixels=0;for(let i=3;i<graph.length;i+=4)if(mask[i]===0&&graph[i]>0)outsidePixels++;
  return{outsidePixels};
 }
 return{draw,verifyMask,method:'actual cortex anchors; continuous arrows clipped to the rendered cortex silhouette',edgeCount:edges.length};
}
