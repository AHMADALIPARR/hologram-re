// Header-only safetensors parsing. Only the first (8 + header_len) bytes
// are ever read — the tensor data itself is never loaded.

export interface TensorEntry {
  name: string;
  dtype: string;
  shape: number[];
  offsets: [number, number];
}

export interface Manifest {
  fileName: string;
  fileSize: number;
  headerBytes: number;
  tensors: TensorEntry[];
  metadata: Record<string, string>;
}

export const DTYPE_BYTES: Record<string, number> = {
  BOOL: 1, U8: 1, I8: 1,
  F16: 2, BF16: 2, I16: 2, U16: 2,
  F32: 4, I32: 4, U32: 4,
  F64: 8, I64: 8, U64: 8,
};

export function tensorElements(t: TensorEntry): number {
  return t.shape.reduce((a, b) => a * b, 1);
}

export function tensorBytes(t: TensorEntry): number {
  const per = DTYPE_BYTES[t.dtype] ?? 0;
  return tensorElements(t) * per;
}

export function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = n / 1024;
  let u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return `${v.toFixed(2)} ${units[u]}`;
}

export function formatCount(n: number): string {
  if (n < 1000) return `${n}`;
  const units = ["K", "M", "B", "T"];
  let v = n / 1000;
  let u = 0;
  while (v >= 1000 && u < units.length - 1) {
    v /= 1000;
    u++;
  }
  return `${v.toFixed(2)}${units[u]}`;
}

export async function parseSafetensorsHeader(file: File): Promise<Manifest> {
  // Read the 8-byte little-endian header length first, then slice exactly
  // the header — never the tensor payload.
  const lenBuf = await file.slice(0, 8).arrayBuffer();
  const headerLen = Number(new DataView(lenBuf).getBigUint64(0, true));
  if (!Number.isSafeInteger(headerLen) || headerLen > file.size) {
    throw new Error("not a safetensors file: bad header length");
  }
  const headBuf = await file.slice(0, 8 + headerLen).arrayBuffer();
  const json = new TextDecoder().decode(new Uint8Array(headBuf, 8, headerLen));
  let header: Record<string, unknown>;
  try {
    header = JSON.parse(json);
  } catch {
    throw new Error("not a safetensors file: header is not JSON");
  }

  const metadata: Record<string, string> = {};
  const tensors: TensorEntry[] = [];
  for (const [name, v] of Object.entries(header)) {
    if (name === "__metadata__") {
      if (v && typeof v === "object") {
        for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
          metadata[k] = String(val);
        }
      }
      continue;
    }
    const t = v as { dtype?: unknown; shape?: unknown; data_offsets?: unknown };
    if (
      typeof t.dtype !== "string" ||
      !Array.isArray(t.shape) ||
      !Array.isArray(t.data_offsets)
    ) {
      throw new Error(`malformed tensor entry: ${name}`);
    }
    tensors.push({
      name,
      dtype: t.dtype,
      shape: (t.shape as unknown[]).map(Number),
      offsets: [Number(t.data_offsets[0]), Number(t.data_offsets[1])],
    });
  }
  tensors.sort((a, b) => (a.name < b.name ? -1 : 1));
  return {
    fileName: file.name,
    fileSize: file.size,
    headerBytes: 8 + headerLen,
    tensors,
    metadata,
  };
}
