import fs from 'node:fs';
import {detectMermaidDiagram} from './merman/detect';
import {parseMermaidFlowchartDiagram} from './merman/flowchart/parser';
import {drawFlowchartDiagramGrid} from './merman/flowchart/drawing';
import {parseMermaidSequenceDiagram} from './merman/sequence/parser';
import {drawSequenceDiagramGrid} from './merman/sequence/drawing';
import {parseMermaidStateDiagram} from './merman/state/parser';
import {drawStateDiagramGrid} from './merman/state/drawing';
import {parseMermaidGanttDiagram} from './merman/gantt/parser';
import {drawGanttDiagramGrid} from './merman/gantt/drawing';
import {parseMermaidGitGraphDiagram} from './merman/gitgraph/parser';
import {drawGitGraphDiagramGrid} from './merman/gitgraph/drawing';
import {parseMermaidTimelineDiagram} from './merman/timeline/parser';
import {drawTimelineDiagramGrid} from './merman/timeline/drawing';
import {parseClassDiagram} from './class/parser';
import {drawClassDiagramGrid} from './class/drawing';

try {
  const request = JSON.parse(fs.readFileSync(0,'utf8'));
  const source = request.source;
  if (typeof source !== 'string' || Buffer.byteLength(source) > 100000) throw new Error('Diagram must be a string smaller than 100 KB');
  const width = Math.max(20, Math.min(500, Number(request.width) || 120));
  const kind = /^\s*(?:%%[^\n]*\n\s*)*classDiagram\b/.test(source) ? 'class' : detectMermaidDiagram(source);
  const opts = {compact: true, layoutMaxWidth: width};
  let grid;
  switch (kind) {
    case 'class': grid = drawClassDiagramGrid(parseClassDiagram(source),opts); break;
    case 'flowchart': grid = drawFlowchartDiagramGrid(parseMermaidFlowchartDiagram(source),opts); break;
    case 'sequence': grid = drawSequenceDiagramGrid(parseMermaidSequenceDiagram(source),{compact:true}); break;
    case 'state': grid = drawStateDiagramGrid(parseMermaidStateDiagram(source),{layoutMaxWidth:width}); break;
    case 'gantt': grid = drawGanttDiagramGrid(parseMermaidGanttDiagram(source),{layoutMaxWidth:width}); break;
    case 'gitGraph': grid = drawGitGraphDiagramGrid(parseMermaidGitGraphDiagram(source)); break;
    case 'timeline': grid = drawTimelineDiagramGrid(parseMermaidTimelineDiagram(source)); break;
    default: throw new Error('Unsupported diagram type. Try flowchart, classDiagram, sequenceDiagram, stateDiagram-v2, gantt, gitGraph, or timeline.');
  }
  const lines: string[] = [''];
  const highlights: any[] = [];
  let row = 0, byte = 0;
  grid.forEachRun((run) => {
    const end = byte + Buffer.byteLength(run.text);
    if (run.style && end > byte) highlights.push([row,byte,end,run.style,run.cell.attributes || 0]);
    lines[row] += run.text;
    byte = end;
  }, () => { row++; lines.push(''); byte = 0; }, {trimTop:true,trimBottom:true,key:cell=>[cell.style,cell.attributes]});
  process.stdout.write(JSON.stringify({kind,width:grid.getTextSize().width,lines,highlights}));
} catch (e) {
  process.stderr.write(e instanceof Error ? e.message : String(e));
  process.exitCode=1;
}
