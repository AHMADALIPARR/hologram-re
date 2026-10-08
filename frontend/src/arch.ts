// Architecture detection from tensor names + stack model for visualization.
// Works from the header manifest alone — no weights, no config needed.

import { type Manifest, type TensorEntry, tensorElements } from "./safetensors";

export type Family = "llama" | "bert" | "gpt2" | "unknown";

export interface TensorRef {
  name: string;
  shape: number[];
  params: number;
}

export interface Block {
  kind: string; // 'attention' | 'mlp' | 'norm' | 'embedding' | 'head' | 'other'
  label: string;
  tensors: TensorRef[];
}

export interface Layer {
  index: number;
  params: number;
  blocks: Block[];
}

export interface StackModel {
  family: Family;
  familyLabel: string;
  numLayers: number;
  embedding: Block | null;
  layers: Layer[];
  tail: Block[];
  ungrouped: Block | null;
  totalParams: number;
}

function ref(t: TensorEntry): TensorRef {
  return { name: t.name, shape: t.shape, params: tensorElements(t) };
}

function blockOf(kind: string, label: string, tensors: TensorEntry[]): Block {
  return { kind, label, tensors: tensors.map(ref) };
}

const LAYER_RE = {
  llama: /^model\.layers\.(\d+)\.(.+)$/,
  bert: /^bert\.encoder\.layer\.(\d+)\.(.+)$/,
  gpt2: /^transformer\.h\.(\d+)\.(.+)$/,
};

export function detectFamily(m: Manifest): Family {
  const names = m.tensors.map((t) => t.name);
  if (names.some((n) => LAYER_RE.llama.test(n))) return "llama";
  if (names.some((n) => LAYER_RE.bert.test(n))) return "bert";
  if (names.some((n) => LAYER_RE.gpt2.test(n))) return "gpt2";
  return "unknown";
}

function blockParams(b: Block): number {
  return b.tensors.reduce((a, t) => a + t.params, 0);
}

function layerParams(l: Layer): number {
  return l.blocks.reduce((a, b) => a + blockParams(b), 0);
}

function groupLayers(
  tensors: TensorEntry[],
  re: RegExp,
  classify: (rest: string) => string,
  blockLabel: (kind: string) => string
): Layer[] {
  const byLayer = new Map<number, Map<string, TensorEntry[]>>();
  for (const t of tensors) {
    const m = re.exec(t.name);
    if (!m) continue;
    const idx = Number(m[1]);
    const kind = classify(m[2]);
    if (!byLayer.has(idx)) byLayer.set(idx, new Map());
    const kinds = byLayer.get(idx)!;
    if (!kinds.has(kind)) kinds.set(kind, []);
    kinds.get(kind)!.push(t);
  }
  return [...byLayer.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([index, kinds]) => {
      const blocks: Block[] = [...kinds.entries()]
        .sort((a, b) => (a[0] < b[0] ? -1 : 1))
        .map(([kind, ts]) => blockOf(kind, blockLabel(kind), ts));
      const layer: Layer = { index, params: 0, blocks };
      layer.params = layerParams(layer);
      return layer;
    });
}

function llamaClassify(rest: string): string {
  if (rest.startsWith("self_attn.")) return "attention";
  if (rest.startsWith("mlp.")) return "mlp";
  if (rest.includes("layernorm") || rest.includes("norm")) return "norm";
  return "other";
}

function bertClassify(rest: string): string {
  if (rest.startsWith("attention.")) return "attention";
  if (rest.startsWith("intermediate.")) return "mlp";
  if (rest.startsWith("output.")) return "output";
  return "other";
}

function gpt2Classify(rest: string): string {
  if (rest.startsWith("attn.")) return "attention";
  if (rest.startsWith("mlp.")) return "mlp";
  if (rest.startsWith("ln_")) return "norm";
  return "other";
}

const KIND_LABEL: Record<string, string> = {
  attention: "Attention",
  mlp: "MLP",
  norm: "Norm",
  output: "Output",
  other: "Other",
};

export function buildStack(m: Manifest): StackModel {
  const family = detectFamily(m);
  const names = new Set(m.tensors.map((t) => t.name));
  const take = (pred: (n: string) => boolean) =>
    m.tensors.filter((t) => pred(t.name));
  const notTaken = new Set<string>();

  let embedding: Block | null = null;
  let layers: Layer[] = [];
  const tail: Block[] = [];

  if (family === "llama") {
    const re = LAYER_RE.llama;
    const layerNames = new Set(
      m.tensors.filter((t) => re.test(t.name)).map((t) => t.name)
    );
    layerNames.forEach((n) => notTaken.add(n));
    const emb = take((n) => n === "model.embed_tokens.weight");
    emb.forEach((t) => notTaken.add(t.name));
    if (emb.length) embedding = blockOf("embedding", "Token embedding", emb);
    layers = groupLayers(
      m.tensors.filter((t) => layerNames.has(t.name)),
      re,
      llamaClassify,
      (k) => KIND_LABEL[k] ?? k
    );
    const rest = (pred: (n: string) => boolean, kind: string, label: string) => {
      const ts = take((n) => !notTaken.has(n) && pred(n));
      ts.forEach((t) => notTaken.add(t.name));
      if (ts.length) tail.push(blockOf(kind, label, ts));
    };
    rest((n) => n === "model.norm.weight", "norm", "Final RMS norm");
    rest((n) => n === "lm_head.weight", "head", "LM head");
  } else if (family === "bert") {
    const re = LAYER_RE.bert;
    const layerNames = new Set(
      m.tensors.filter((t) => re.test(t.name)).map((t) => t.name)
    );
    layerNames.forEach((n) => notTaken.add(n));
    const emb = take((n) => n.startsWith("bert.embeddings."));
    emb.forEach((t) => notTaken.add(t.name));
    if (emb.length) embedding = blockOf("embedding", "Embeddings", emb);
    layers = groupLayers(
      m.tensors.filter((t) => layerNames.has(t.name)),
      re,
      bertClassify,
      (k) => KIND_LABEL[k] ?? k
    );
    const rest = (pred: (n: string) => boolean, kind: string, label: string) => {
      const ts = take((n) => !notTaken.has(n) && pred(n));
      ts.forEach((t) => notTaken.add(t.name));
      if (ts.length) tail.push(blockOf(kind, label, ts));
    };
    rest((n) => n.startsWith("bert.pooler."), "other", "Pooler");
    rest((n) => n.startsWith("cls."), "head", "CLS head");
  } else if (family === "gpt2") {
    const re = LAYER_RE.gpt2;
    const layerNames = new Set(
      m.tensors.filter((t) => re.test(t.name)).map((t) => t.name)
    );
    layerNames.forEach((n) => notTaken.add(n));
    const emb = take(
      (n) => n === "transformer.wte.weight" || n === "transformer.wpe.weight"
    );
    emb.forEach((t) => notTaken.add(t.name));
    if (emb.length) embedding = blockOf("embedding", "Token + position embedding", emb);
    layers = groupLayers(
      m.tensors.filter((t) => layerNames.has(t.name)),
      re,
      gpt2Classify,
      (k) => KIND_LABEL[k] ?? k
    );
    const rest = (pred: (n: string) => boolean, kind: string, label: string) => {
      const ts = take((n) => !notTaken.has(n) && pred(n));
      ts.forEach((t) => notTaken.add(t.name));
      if (ts.length) tail.push(blockOf(kind, label, ts));
    };
    rest((n) => n === "transformer.ln_f.weight" || n === "transformer.ln_f.bias", "norm", "Final layer norm");
    rest((n) => n === "lm_head.weight", "head", "LM head");
  }

  let ungrouped: Block | null = null;
  const leftover = m.tensors.filter((t) => !notTaken.has(t.name));
  if (leftover.length) {
    ungrouped = blockOf("other", "Ungrouped tensors", leftover);
  }

  const totalParams = m.tensors.reduce((a, t) => a + tensorElements(t), 0);
  const familyLabel =
    family === "llama"
      ? "Llama-family decoder"
      : family === "bert"
        ? "BERT encoder"
        : family === "gpt2"
          ? "GPT-2 decoder"
          : "Unknown architecture";
  void names;
  return {
    family,
    familyLabel,
    numLayers: layers.length,
    embedding,
    layers,
    tail,
    ungrouped,
    totalParams,
  };
}
