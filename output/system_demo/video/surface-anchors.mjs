import * as THREE from './assets/three.module.js';

// Pick a nearby visible gyral vertex once; never re-project a marker per frame.
// Face-on visibility avoids the previous sulcal anchor showing through other folds.
export function selectSurfaceAnchor(spec,cortexMeshes){
 const ray=new THREE.Raycaster(),candidates=[];
 for(let side=0;side<cortexMeshes.length;side++){
  const mesh=cortexMeshes[side],positions=mesh.geometry.attributes.position,normals=mesh.geometry.attributes.normal;
  for(let vertex=0;vertex<positions.count;vertex++){
   const point=new THREE.Vector3().fromBufferAttribute(positions,vertex);
   const distance=Math.hypot(point.x-spec.position[0],point.y-spec.position[1]);
   if(distance>.22||point.z<.12)continue;
   const normal=new THREE.Vector3().fromBufferAttribute(normals,vertex).normalize();
   if(normal.z<.65)continue;
   candidates.push({side,vertex,point,normal,distance});
  }
 }
 candidates.sort((a,b)=>a.distance-b.distance);
 for(const candidate of candidates){
  const center=candidate.point.clone().addScaledVector(candidate.normal,.024);
  let visible=true;
  for(const t of [0,4,8,12,16,18]){
   const rotation=new THREE.Euler(.06+Math.sin(t*.21)*.045,-.20+Math.sin(t*.32-.4)*.30,Math.sin(t*.19)*.025);
   const inverse=new THREE.Matrix4().makeRotationFromEuler(rotation).invert();
   const camera=new THREE.Vector3(0,.02-.045*Math.sin(t*.28),6).applyMatrix4(inverse);
   const delta=center.clone().sub(camera),distance=delta.length();ray.set(camera,delta.normalize());
   const obstruction=ray.intersectObjects(cortexMeshes,false)[0];
   if(obstruction&&obstruction.distance<distance-.003){visible=false;break;}
  }
  if(visible)return{...candidate,center};
 }
 throw new Error(`No stable visible cortex anchor for ${spec.id}`);
}
