// Concept-demo graph: both the animated model and report use this single source.
// Node locations and edges are illustrative, not patient measurements.
export const network = {
 nodes: [
  {id:'frontal',label:'额叶',position:[-.94,.38,1.06],offset:[-24,-35],align:'right',role:'target'},
  {id:'parietal',label:'顶叶',position:[.07,.81,.91],offset:[23,-24],align:'left'},
  {id:'occipital',label:'枕叶',position:[.95,.37,.82],offset:[25,-24],align:'left'},
  {id:'temporal',label:'颞叶',position:[-.68,-.27,1.10],offset:[-20,44],align:'right',role:'source'},
  {id:'thalamus',label:'丘脑',position:[.10,.14,1.32],offset:[22,-30],align:'left',role:'relay'},
  {id:'hippocampus',label:'海马',position:[-.12,-.62,1.14],offset:[0,37],align:'center'},
  {id:'network',label:'关联脑区',position:[.86,-.39,.98],offset:[18,35],align:'left'},
  {id:'basal',label:'基底节',position:[.42,-.39,1.25],offset:[-1,38],align:'center'}
 ],
 edges: [
  {from:'frontal',to:'parietal',type:'secondary'},
  {from:'parietal',to:'occipital',type:'secondary'},
  {from:'temporal',to:'hippocampus',type:'secondary'},
  {from:'hippocampus',to:'basal',type:'secondary'},
  {from:'basal',to:'network',type:'secondary'},
  {from:'thalamus',to:'parietal',type:'propagation'},
  {from:'thalamus',to:'network',type:'propagation'},
  {from:'temporal',to:'thalamus',type:'primary',delay:5.11},
  {from:'thalamus',to:'frontal',type:'primary',delay:5.29}
 ],
 primaryPath:['temporal','thalamus','frontal'],
 palette:{secondary:'#5cddd9',propagation:'#a2eb8a',primary:'#ffbc74'},
 legend:[
  {type:'secondary',symbol:'node-arrow',label:'脑区节点 / 网络连接'},
  {type:'propagation',symbol:'arrow',label:'次级传播通路（示意）'},
  {type:'primary',symbol:'node-arrow',label:'关键通路节点 / 通路'},
  {type:'primary',symbol:'source',label:'异常起始脑区'}
 ]
};
