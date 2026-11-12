import assert from 'node:assert/strict';
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const cli = fileURLToPath(new URL('../bin/render.mjs', import.meta.url));
function run(source, width = 120) {
  return spawnSync(process.execPath, [cli], {
    input: JSON.stringify({source, width}), encoding: 'utf8', timeout: 10000,
  });
}
function render(source, width) {
  const process = run(source, width);
  assert.equal(process.status, 0, process.stderr);
  const result = JSON.parse(process.stdout);
  assert.equal(result.kind, 'sequence');
  for (const [row, start, end] of result.highlights) {
    assert(row >= 0 && row < result.lines.length);
    const bytes = Buffer.from(result.lines[row]);
    assert(start >= 0 && end > start && end <= bytes.length);
    for (const part of [bytes.subarray(0, start), bytes.subarray(start, end)]) {
      assert(!part.toString().includes('\ufffd'), 'highlight splits UTF-8');
    }
  }
  return {result, text: result.lines.join('\n')};
}

const sample = fs.readFileSync(new URL('../examples/batch-transfer.mmd', import.meta.url), 'utf8');
for (const width of [80, 100, 120]) {
  const {result, text} = render(sample, width);
  for (const line of sample.split('\n')) {
    const label = line.match(/^\s*(?:participant \S+ as |\S+[-]+>>\S+: )(.*)$/)?.[1];
    if (label) assert(text.includes(label), `missing label: ${label}`);
  }
  assert(result.highlights.some(h => h[3] === 'fragment'));
  assert(text.includes('rect'));
  assert(!text.includes('rgb('), 'background color must not become a message label');
  const top = result.lines.findIndex(line => line.includes('rect'));
  const bottom = result.lines.findIndex((line, row) => row > top && line.startsWith('╰'));
  assert(result.lines[top].startsWith('╭') && result.lines[top].endsWith('╮'));
  assert(bottom > top && result.lines[bottom].endsWith('╯'), 'rect frame must close');
  assert(result.lines.slice(top + 1, bottom).some(line => line.includes('REPEATABLE_READ')));
  for (const line of result.lines.slice(top + 1, bottom)) {
    assert(line.startsWith('│') && line.endsWith('│'), 'rect walls must enclose its content');
  }
  assert(result.lines.slice(bottom + 1).some(line => line.includes('保存首次估值')));
}

// Nested rectangles must not consume the surrounding alt/loop or box end.
const {text} = render(`sequenceDiagram
box rgb(220, 220, 220) Services
  participant A
  participant B
end
loop Retry
  alt Ready
    rect rgba(0, 0, 255, .1)
      A->>B: Outer message
      rect rgb(200, 150, 255)
        B-->>A: Inner response
      end
      A->>A: Self call
    end
  else Waiting
    B-->>A: Wait
  end
end
A->>B: After blocks`);
for (const label of ['Services', 'Retry', 'Ready', 'Outer message', 'Inner response', 'Self call', 'Waiting', 'Wait', 'After blocks']) {
  assert(text.includes(label), label);
}
assert.equal((text.match(/rect/g) ?? []).length, 2);

for (const [source, error] of [
  ['sequenceDiagram\nrect rgb(1,2,3)\nA->>B: Unclosed', /Unclosed rect block.*line 2/],
  ['sequenceDiagram\nrect rgb(1,2,3)\nelse Invalid\nend', /Unexpected "else"/],
  ['sequenceDiagram\nrect rgb(1,2,3)\nA->>B: Done\nend\nend', /Unexpected "end"/],
  ['sequenceDiagram\nrect nonsense\nA->>B: Invalid\nend', /Unsupported syntax.*line 2/],
]) {
  const process = run(source);
  assert.notEqual(process.status, 0);
  assert.match(process.stderr, error);
}
console.log('PASS: sequence rect/rgb/rgba, full CJK sample, nested blocks, UTF-8 highlights, syntax errors');
