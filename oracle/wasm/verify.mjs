// Verification harness for dequant.wat.
// Assembles the WAT with wabt, instantiates it in Node, and checks every
// exported function against hand-computed IEEE 754 values.
// Run: node --experimental-wasm-modules verify.mjs (node >= 22 runs as-is)
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import wabt from 'wabt';

const dir = dirname(fileURLToPath(import.meta.url));
const wat = readFileSync(join(dir, 'dequant.wat'), 'utf8');
const wasm = (await wabt()).parseWat('dequant.wat', wat).toBinary({}).buffer;
const { instance } = await WebAssembly.instantiate(wasm, {});
const { memory, f16_to_f32, dequant_q8_0_block, dequant_q4_0_block } = instance.exports;
const mem8 = new Uint8Array(memory.buffer);
const view = new DataView(memory.buffer);

let failures = 0;
function check(name, actual, expected) {
  const ok = Object.is(actual, expected) ||
    (Number.isNaN(expected) && Number.isNaN(actual)) ||
    (typeof expected === 'number' && Math.abs(actual - expected) < 1e-12);
  if (!ok) { failures++; console.error(`FAIL ${name}: got ${actual}, want ${expected}`); }
  else console.log(`ok   ${name}`);
}

// ---- f16_to_f32 ----
check('f16 0x3C00 -> 1.0', f16_to_f32(0x3C00), 1.0);
check('f16 0xBC00 -> -1.0', f16_to_f32(0xBC00), -1.0);
check('f16 0x3800 -> 0.5', f16_to_f32(0x3800), 0.5);
check('f16 0x0000 -> +0.0', 1 / f16_to_f32(0x0000), Infinity);
check('f16 0x8000 -> -0.0', 1 / f16_to_f32(0x8000), -Infinity);
check('f16 0x0001 -> 2^-24', f16_to_f32(0x0001), 5.960464477539063e-8);
check('f16 0x03FF -> 1023*2^-24', f16_to_f32(0x03FF), 6.097555160522461e-5);
check('f16 0x8400 -> -2^-14', f16_to_f32(0x8400), -6.103515625e-5);
check('f16 0x7C00 -> +inf', f16_to_f32(0x7C00), Infinity);
check('f16 0xFC00 -> -inf', f16_to_f32(0xFC00), -Infinity);
check('f16 0x7E00 -> NaN', f16_to_f32(0x7E00), NaN);

// ---- dequant_q8_0_block ----
// block @0: scale LE 0x3C00 = 1.0 ; qs = [2, -4, 127, -128, 0...]
mem8.set([0x00, 0x3C, 2, 252, 127, 128], 0);
dequant_q8_0_block(0, 64);
const q8 = Array.from({ length: 6 }, (_, i) => view.getFloat32(64 + 4 * i, true));
check('q8 [2,-4,127,-128,0,0] @scale 1.0',
  JSON.stringify(q8), JSON.stringify([2, -4, 127, -128, 0, 0]));
// block @256: scale LE 0x3800 = 0.5 ; qs = [2, -4, ...]
mem8.fill(0, 256, 256 + 34);
mem8.set([0x00, 0x38, 2, 252], 256);
dequant_q8_0_block(256, 512);
check('q8 [2,-4] @scale 0.5',
  JSON.stringify([view.getFloat32(512, true), view.getFloat32(516, true)]),
  JSON.stringify([1, -2]));

// ---- dequant_q4_0_block ----
// block @1024: scale LE 0x3C00 = 1.0 ; qs[0]=0x09 -> [1,-8] ; qs[1]=0xF0 -> [-8,7] ; rest 0x88 -> [0,0]
mem8.fill(0, 1024, 1024 + 18);
mem8.set([0x00, 0x3C, 0x09, 0xF0], 1024);
for (let i = 4; i < 18; i++) mem8[1024 + i] = 0x88;
dequant_q4_0_block(1024, 1280);
const q4 = Array.from({ length: 6 }, (_, i) => view.getFloat32(1280 + 4 * i, true));
check('q4 [1,-8,-8,7,0,0] @scale 1.0',
  JSON.stringify(q4), JSON.stringify([1, -8, -8, 7, 0, 0]));
// scale 0x3800 = 0.5, qs[0]=0x19 -> lo=1 -> 0.5 ; hi=1-8=-7 -> -3.5
mem8.fill(0, 1536, 1536 + 18);
mem8.set([0x00, 0x38, 0x19], 1536);
for (let i = 3; i < 18; i++) mem8[1536 + i] = 0x88;
dequant_q4_0_block(1536, 1792);
check('q4 [0.5,-3.5] @scale 0.5',
  JSON.stringify([view.getFloat32(1792, true), view.getFloat32(1796, true)]),
  JSON.stringify([0.5, -3.5]));

if (failures) { console.error(`${failures} FAILURES`); process.exit(1); }
console.log('all wasm checks pass');
