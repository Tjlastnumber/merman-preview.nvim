import stringWidth from 'string-width';
import {BorderChars} from '@opentui/core';
import {DiagramCanvas} from '../merman/core/canvas';
import {layoutFlowchartDiagram} from '../merman/flowchart/layout';
import {diagramArrowHeadBetween,drawDiagramFrame,drawOrthogonalPath,mergeDiagramLineGlyph} from '../merman/core/drawing';
import {flowchartRouteLabelLayout} from '../merman/flowchart/labels';
import type {FlowchartDiagram,FlowchartPoint,FlowchartEdge} from '../merman/flowchart/types';
import type {FlowchartDiagramRenderOptions} from '../merman/flowchart/options';
import type {ClassDiagram,ClassNode,ClassRelation} from './parser';

const split=(text:string)=>text.split(/<br\s*\/?>/i);
function compartments(node:ClassNode) {
  return {
    title:[...(node.annotation?[`<<${node.annotation}>>`]:[]),...split(node.name)],
    attributes:node.attributes.length?node.attributes.flatMap(split):[''],
    methods:node.methods.length?node.methods.flatMap(split):[''],
  };
}
function relationLabel(edge:ClassRelation) {
  return [edge.fromCardinality,edge.label,edge.toCardinality].filter(Boolean).join(' / ');
}
function marker(value:string,from:FlowchartPoint,to:FlowchartPoint) {
  if(value==='*')return '◆';
  if(value==='o')return '◇';
  if(value==='<|'||value==='|>') {
    if(to.x>from.x)return '▷';if(to.x<from.x)return '◁';
    return to.y>from.y?'▽':'△';
  }
  return diagramArrowHeadBetween(from,to);
}
const add=(p:FlowchartPoint,d:FlowchartPoint,scale=1)=>({x:p.x+d.x*scale,y:p.y+d.y*scale});

export function drawClassDiagramGrid(model:ClassDiagram,options:FlowchartDiagramRenderOptions={}) {
  const diagram:FlowchartDiagram={
    direction:model.direction,
    nodes:model.nodes.map(n=>{
      const c=compartments(n);
      return {id:n.id,shape:'box',label:[...c.title,'',...c.attributes,'',...c.methods].join('<br/>')};
    }),
    edges:model.relations.map(r=>({from:r.from,to:r.to,label:relationLabel(r),style:r.dashed?'dashed':undefined,arrowhead:false,relation:r})),
    subgraphs:model.namespaces.map(n=>({...n})),
  };
  // merman supplies CJK-aware sizes, width folding, namespaces and orthogonal routes.
  const layout=layoutFlowchartDiagram(diagram,{...options,minRankGap:7});
  const grid=new DiagramCanvas<string>(layout.width,layout.height);
  const edgeCell=(x:number,y:number,char:string)=> {
    const old=grid.getCell(x,y)?.char??' ';
    grid.setCell(x,y,mergeDiagramLineGlyph(old,char,'rounded')??char,'edge');
  };
  for(const b of layout.subgraphBounds.values())drawDiagramFrame(b,BorderChars.rounded,(x,y,c)=>grid.setCell(x,y,c,'group'));
  // Different UML relation types must keep distinct endpoint markers, even if
  // merman shares the rest of their path. Allocate a separate cell per port.
  const used=new Map<string,Set<number>>();
  const port=(id:string,p:FlowchartPoint,toward:FlowchartPoint)=> {
    const b=layout.bounds.get(id)!;
    const d=p.x<b.left?{x:-1,y:0}:p.x>=b.left+b.width?{x:1,y:0}:p.y<b.top?{x:0,y:-1}:{x:0,y:1};
    const horizontal=d.x===0;
    const low=horizontal?b.left+1:b.top+1,high=horizontal?b.left+b.width-2:b.top+b.height-2;
    const original=horizontal?p.x:p.y;
    const preferred=Math.sign((horizontal?toward.x:toward.y)-original);
    const center=Math.max(low,Math.min(high,original+preferred*2));
    const key=`${id}:${d.x},${d.y}`;
    const taken=used.get(key)??new Set<number>();used.set(key,taken);
    let chosen=original;
    const candidates=Array.from({length:high-low+1},(_,i)=>low+i).sort((a,b)=>Math.abs(a-center)-Math.abs(b-center));
    chosen=candidates.find(v=>!taken.has(v)&&[...taken].every(t=>Math.abs(t-v)>=2))
      ??candidates.find(v=>!taken.has(v))??original;
    taken.add(chosen);
    return {p:horizontal?{x:chosen,y:p.y}:{x:p.x,y:chosen},d};
  };
  const routes=layout.routes.map(route=> {
    if(route.points.length<2)return {route,points:route.points};
    const first=route.points[0]!,last=route.points.at(-1)!;
    const from=port(route.edge.from,first,last),to=port(route.edge.to,last,first);
    let points=route.points.map(p=>({...p}));
    if(points.length===2) {
      if(from.d.x===0) {const y=Math.floor((first.y+last.y)/2);points=[from.p,{x:from.p.x,y},{x:to.p.x,y},to.p];}
      else {const x=Math.floor((first.x+last.x)/2);points=[from.p,{x,y:from.p.y},{x,y:to.p.y},to.p];}
    } else if(points.length===3) {
      points=[from.p,from.d.x===0?{x:from.p.x,y:to.p.y}:{x:to.p.x,y:from.p.y},to.p];
    } else {
      points[0]=from.p;points[points.length-1]=to.p;
      if(from.d.x===0)points[1]!.x=from.p.x;else points[1]!.y=from.p.y;
      if(to.d.x===0)points[points.length-2]!.x=to.p.x;else points[points.length-2]!.y=to.p.y;
    }
    // Preserve the first/last normal segments so UML heads do not collapse into a shared trunk.
    return {route,points,from,to};
  });
  for(const {route,points} of routes)drawOrthogonalPath(points,edgeCell,{cornerStyle:'rounded',lineStyle:route.edge.style==='dashed'?'dashed':'single'});
  for(const {route} of routes)if(route.edge.label) {
    const label=flowchartRouteLabelLayout(route,stringWidth);
    label.lines.forEach((line,i)=>grid.setText(label.point.x,label.point.y+i,line,'label'));
  }
  for(const node of model.nodes) {
    const b=layout.bounds.get(node.id);if(!b)continue;
    drawDiagramFrame(b,BorderChars.rounded,(x,y,c)=>grid.replaceCell(x,y,c,'nodeBorder'));
    for(let y=b.top+1;y<b.top+b.height-1;y++)for(let x=b.left+1;x<b.left+b.width-1;x++)grid.replaceCell(x,y,' ','node');
    const c=compartments(node);let row=b.top+1;
    for(const line of c.title)grid.setText(b.left+Math.max(1,Math.floor((b.width-stringWidth(line))/2)),row++,line,'classTitle');
    const divider=()=>{
      grid.replaceCell(b.left,row,'├','nodeBorder');
      for(let x=b.left+1;x<b.left+b.width-1;x++)grid.replaceCell(x,row,'─','nodeBorder');
      grid.replaceCell(b.left+b.width-1,row,'┤','nodeBorder');row++;
    };
    divider();for(const line of c.attributes)grid.setText(b.left+2,row++,line,'node');
    divider();for(const line of c.methods)grid.setText(b.left+2,row++,line,'node');
  }
  for(const b of layout.subgraphBounds.values()) {
    const row=b.labelSide==='top'?b.top:b.top+b.height-split(b.label).length;
    split(b.label).forEach((line,i)=>grid.setText(b.left+2,row+i,' '+line+' ','groupLabel'));
  }
  for(const {route,from,to} of routes) {
    if(!from||!to)continue;
    const r=(route.edge as FlowchartEdge&{relation:ClassRelation}).relation;
    for(const [endpoint,value] of [[from,r.fromMarker],[to,r.toMarker]] as const) {
      const border=add(endpoint.p,endpoint.d,-1);
      const junction=endpoint.d.x<0?'┤':endpoint.d.x>0?'├':endpoint.d.y<0?'┴':'┬';
      grid.replaceCell(border.x,border.y,junction,'nodeBorder');
      grid.replaceCell(endpoint.p.x,endpoint.p.y,value?marker(value,add(endpoint.p,endpoint.d),endpoint.p):endpoint.d.x===0?'│':'─','edge');
    }
  }
  return grid;
}
