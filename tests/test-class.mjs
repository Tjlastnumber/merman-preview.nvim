import assert from 'node:assert/strict';
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const cli=fileURLToPath(new URL('../bin/render.mjs',import.meta.url));
function render(source,width=120) {
 const r=spawnSync(process.execPath,[cli],{input:JSON.stringify({source,width}),encoding:'utf8',timeout:10000});
 assert.equal(r.status,0,r.stderr);const result=JSON.parse(r.stdout);
 assert(result.lines.length>0);
 for(const [row,start,end] of result.highlights) {
  assert(row>=0&&row<result.lines.length);assert(start>=0&&end<=Buffer.byteLength(result.lines[row]));
  for(const bytes of [Buffer.from(result.lines[row]).subarray(0,start),Buffer.from(result.lines[row]).subarray(start,end)]) {
   assert(!bytes.toString().includes('\ufffd'),'highlight split a UTF-8 character');
  }
 }
 return {result,text:result.lines.join('\n')};
}
const sample=fs.readFileSync(new URL('../examples/classes.mmd',import.meta.url),'utf8');
for(const width of [80,120]) {
 const {result,text}=render(sample,width);assert.equal(result.kind,'class');
 for(const member of ['SourceSnapshot','ProductionService','Repository<T>','+String 来源编号','-Repository<DailyProduction> repository','+save(T value) void','<<interface>>','1 / 生产 / *'])assert(text.includes(member),member);
 assert(text.includes('├')&&text.includes('┤')&&text.includes('◆')&&text.includes('▼'));
 assert(result.highlights.some(h=>h[3]==='classTitle'));
}
const cases=[
 ['Inheritance','Parent <|-- Child',/[△▽◁▷]/],
 ['Inheritance reversed','Child --|> Parent',/[△▽◁▷]/],
 ['Composition','Owner *-- Part',/◆/],
 ['Aggregation','Group o-- Member',/◇/],
 ['Association','A --> B',/[▲▼◀▶]/],
 ['Dependency','A ..> B',/[▲▼◀▶]/],
 ['Realization','A ..|> B',/[△▽◁▷]/],
 ['Solid link','A -- B',/│|─/],
 ['Dashed link','A .. B',/│|─/],
 ['Two-way','A <|--|> B',/[△▽◁▷]/],
 ['Self reference','Node --> Node : next',/[▲▼◀▶]/],
 ['Cycle','A-->B\nB-->C\nC-->A',/[▲▼◀▶]/],
];
for(const [name,body,marker]of cases){const{text}=render('classDiagram\n'+body);assert(marker.test(text),name);}
// Separate relation heads on a shared class must both survive.
{
 const{text}=render('classDiagram\nParent <|-- Child\nParent o-- Part');
 assert(/[△▽◁▷]/.test(text)&&text.includes('◇'));
}
{
 const{text}=render(`%% comment\nclassDiagram\nnamespace Domain["领域模型"] {\nclass Store~T~ {\n<<interface>>\n-List~List~int~~ values\n+get() T\n}\nnamespace Detail {\n class 订单 { +String 编号; +submit() bool }\n}\n}\nStore "1" --> "*" 订单 : 管理\nStore : +find() T\n`);
 for(const label of ['领域模型','Detail','Store<T>','List<List<int>>','订单','+String 编号','+submit() bool','+find() T','1 / 管理 / *'])assert(text.includes(label),label);
}
{
 const{text}=render('classDiagram\nclass Foo["有;括号{}和中文"]\nclass `Special Name!`\nFoo --> `Special Name!`');
 assert(text.includes('有;括号{}和中文')&&text.includes('Special Name!'));
}
for(const source of ['classDiagram\nclass Foo {','classDiagram\nA ??? B','classDiagram\nclass Foo["unclosed]']){
 const r=spawnSync(process.execPath,[cli],{input:JSON.stringify({source}),encoding:'utf8',timeout:10000});assert.notEqual(r.status,0);assert(r.stderr.includes('classDiagram'));
}
// Existing diagram types retain their dispatcher and render successfully.
for(const [kind,source]of[
 ['flowchart','flowchart LR\nA[你好]-->B[World]'],
 ['sequence','sequenceDiagram\nAlice->>Bob: Hello'],
 ['state','stateDiagram-v2\n[*]-->Idle'],
 ['gantt','gantt\ndateFormat YYYY-MM-DD\nTask :a, 2026-01-01, 2d'],
 ['gitGraph','gitGraph\ncommit'],
 ['timeline','timeline\n2026 : Start']
])assert.equal(render(source).result.kind,kind);
console.log('PASS: class members/generics/CJK; eight UML relations and two-way/self/cycles; namespaces/labels; errors; highlight byte ranges; all six previous types');
