// Class-diagram adapter. Grammar follows Mermaid's public classDiagram syntax.
import { decodeHTMLStrict } from 'entities';
import type {FlowchartDirection} from '../merman/flowchart/types';

export interface ClassNode { id:string; name:string; annotation?:string; attributes:string[]; methods:string[]; namespace?:string }
export interface ClassRelation { from:string; to:string; fromMarker:string; toMarker:string; dashed:boolean; label:string; fromCardinality?:string; toCardinality?:string }
export interface ClassNamespace { id:string; label:string; parentId?:string; nodeIds:string[] }
export interface ClassDiagram { direction:FlowchartDirection; nodes:ClassNode[]; relations:ClassRelation[]; namespaces:ClassNamespace[] }

function tokens(source:string) {
  const out:Array<{text:string;line:number}>=[];
  let value='',quote='',escape=false,line=1,start=1;
  const flush=()=>{if(value.trim())out.push({text:value.trim(),line:start});value='';start=line;};
  for(let i=0;i<source.length;i++) {
    const c=source[i]!;
    if(quote) {
      value+=c;
      if(escape)escape=false; else if(c==='\\')escape=true; else if(c===quote)quote='';
    } else if(c==='"'||c==='`') {quote=c;value+=c;}
    else if(c==='%'&&source[i+1]==='%') {
      while(i<source.length&&source[i]!=='\n')i++;
      flush();line++;start=line;
    } else if(c==='{'||c==='}') {flush();out.push({text:c,line});}
    else if(c==='\n'||c===';') {flush();if(c==='\n'){line++;start=line;}}
    else {if(!value.trim())start=line;value+=c;}
  }
  if(quote)throw new Error(`classDiagram line ${line}: unclosed quoted label`);
  flush();return out;
}

function unquote(text:string) {
  text=text.trim();
  if((text.startsWith('"')&&text.endsWith('"'))||(text.startsWith('`')&&text.endsWith('`')))text=text.slice(1,-1);
  return decodeHTMLStrict(text.replace(/\\"/g,'"'));
}
function generic(text:string) {
  // ~...~ is Mermaid's generic notation; retain nested generic types.
  return text.replace(/~/g,(value,at)=> {
    if(at===0 || /\s/.test(text[at-1]!))return value;
    return /[\p{L}\p{N}_]/u.test(text[at+1]??'')?'<':'>';
  });
}
function reference(text:string) {
  const m=text.trim().match(/^(`[^`]+`|[\p{L}\p{N}_$.-]+)(~.*~)?(.*)$/u);
  if(!m)throw new Error(`Invalid class reference: ${text}`);
  return {id:unquote(m[1]!),name:generic(unquote(m[1]!)+(m[2]??'')),rest:m[3]!.trim()};
}
function colon(text:string) {
  let quote='',escape=false;
  for(let i=0;i<text.length;i++) {
    const c=text[i]!;
    if(quote){if(escape)escape=false;else if(c==='\\')escape=true;else if(c===quote)quote='';}
    else if(c==='"'||c==='`')quote=c;
    else if(c===':')return [text.slice(0,i).trim(),text.slice(i+1).trim()];
  }
  return [text.trim(),''];
}

export function parseClassDiagram(source:string):ClassDiagram {
  const ts=tokens(source);
  if(ts.shift()?.text!=='classDiagram')throw new Error('Expected classDiagram header');
  const result:ClassDiagram={direction:'TD',nodes:[],relations:[],namespaces:[]};
  const nodes=new Map<string,ClassNode>();
  const stack:Array<{type:'class'|'namespace';id:string}>=[];
  const namespace=()=>[...stack].reverse().find(c=>c.type==='namespace')?.id;
  const ensure=(id:string,name=id)=>{
    let n=nodes.get(id);
    if(!n){n={id,name,attributes:[],methods:[]};nodes.set(id,n);result.nodes.push(n);}
    return n;
  };
  const member=(node:ClassNode,text:string)=>{
    const annotation=text.match(/^<<(.+?)>>$/);
    if(annotation){node.annotation=annotation[1];return;}
    const value=generic(unquote(text));
    (value.includes('(')?node.methods:node.attributes).push(value);
  };
  for(let i=0;i<ts.length;i++) {
    const {text,line}=ts[i]!;
    try {
      if(text==='}') {if(!stack.pop())throw new Error('Unexpected closing brace');continue;}
      const active=stack.at(-1);
      if(active?.type==='class') {if(text==='{')throw new Error('Unexpected nested member block');member(nodes.get(active.id)!,text);continue;}
      const dir=text.match(/^direction\s+(TD|TB|BT|LR|RL)$/);
      if(dir){result.direction=dir[1] as FlowchartDirection;continue;}
      if(/^(?:accTitle|accDescr|title)\s*:/.test(text)||/^(?:classDef|cssClass|style|click|link|callback)\s/.test(text))continue;
      if(text.startsWith('namespace ')) {
        const ref=reference(text.slice(10));
        if(ts[i+1]?.text!=='{')throw new Error('Namespace requires a brace block');
        const parent=namespace(),id=parent?`${parent}.${ref.id}`:`namespace:${ref.id}`;
        let label=ref.name;
        if(ref.rest){const m=ref.rest.match(/^\[\s*(.*?)\s*\]$/);if(!m)throw new Error('Invalid namespace label');label=unquote(m[1]!);}
        if(result.namespaces.some(n=>n.id===id))throw new Error('Namespace already declared');
        result.namespaces.push({id,label,parentId:parent,nodeIds:[]});stack.push({type:'namespace',id});i++;continue;
      }
      if(text.startsWith('class ')) {
        const ref=reference(text.slice(6));const n=ensure(ref.id,ref.name);n.name=ref.name;
        const rest=ref.rest.replace(/:::[\w-]+$/,'').trim();
        if(rest){const m=rest.match(/^\[\s*(.*?)\s*\]$/);if(!m)throw new Error('Invalid class label');n.name=unquote(m[1]!);}
        if(namespace())n.namespace=namespace();
        if(ts[i+1]?.text==='{'){stack.push({type:'class',id:n.id});i++;}
        continue;
      }
      const annotation=text.match(/^<<(.+?)>>\s+(.+)$/);
      if(annotation){const ref=reference(annotation[2]!);if(ref.rest)throw new Error('Invalid annotation target');ensure(ref.id).annotation=annotation[1];continue;}
      const [body,label]=colon(text);
      const relation=body!.match(/^(.*?)\s*((?:<\||<|\*|o)?(?:--|\.\.)(?:\|>|>|\*|o)?)\s*(.*?)$/);
      if(relation) {
        let left=relation[1]!.trim(),right=relation[3]!.trim();
        const lm=left.match(/\s+"([^"]*)"$/),rm=right.match(/^"([^"]*)"\s+/);
        if(lm)left=left.slice(0,lm.index).trim();if(rm)right=right.slice(rm[0].length).trim();
        const from=reference(left),to=reference(right);
        if(from.rest||to.rest)throw new Error('Invalid relationship endpoint');
        const f=ensure(from.id),t=ensure(to.id);
        if(namespace()){f.namespace??=namespace();t.namespace??=namespace();}
        const op=relation[2]!,core=op.includes('..')?'..':'--',at=op.indexOf(core);
        result.relations.push({from:f.id,to:t.id,fromMarker:op.slice(0,at),toMarker:op.slice(at+2),dashed:core==='..',label:unquote(label!),fromCardinality:lm?.[1],toCardinality:rm?.[1]});
        continue;
      }
      if(label){const ref=reference(body!);if(ref.rest)throw new Error('Invalid member target');member(ensure(ref.id),label);continue;}
      throw new Error(`Unsupported classDiagram statement: ${text}`);
    } catch(error) {throw new Error(`classDiagram line ${line}: ${error instanceof Error?error.message:error}`);}
  }
  if(stack.length)throw new Error(`classDiagram: unclosed ${stack.at(-1)!.type} block`);
  if(!nodes.size)throw new Error('classDiagram contains no classes');
  for(const n of result.nodes)if(n.namespace)result.namespaces.find(s=>s.id===n.namespace)?.nodeIds.push(n.id);
  return result;
}
