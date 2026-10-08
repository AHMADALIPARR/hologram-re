import { useMemo, useState } from "react";
import {
  type Manifest,
  type TensorEntry,
  formatBytes,
  formatCount,
  parseSafetensorsHeader,
  tensorBytes,
  tensorElements,
} from "./safetensors";
import { type Block, type StackModel, buildStack } from "./arch";
import "./index.css";

type View = "overview" | "stack" | "tensors";

export default function App() {
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [view, setView] = useState<View>("overview");
  const [dragOver, setDragOver] = useState(false);

  const stack: StackModel | null = useMemo(
    () => (manifest ? buildStack(manifest) : null),
    [manifest]
  );

  async function handleFile(f: File | undefined) {
    if (!f) return;
    setBusy(true);
    setError(null);
    try {
      const m = await parseSafetensorsHeader(f);
      setManifest(m);
      setView("overview");
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed to parse file");
      setManifest(null);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">◈</span> safetensors inspector
        </div>
        {manifest && (
          <nav className="tabs">
            {(["overview", "stack", "tensors"] as View[]).map((v) => (
              <button
                key={v}
                className={view === v ? "tab active" : "tab"}
                onClick={() => setView(v)}
              >
                {v}
              </button>
            ))}
          </nav>
        )}
      </header>

      {!manifest && (
        <div
          className={dragOver ? "dropzone over" : "dropzone"}
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            handleFile(e.dataTransfer.files[0]);
          }}
          onClick={() => document.getElementById("filepick")?.click()}
        >
          <input
            id="filepick"
            type="file"
            accept=".safetensors"
            hidden
            onChange={(e) => handleFile(e.target.files?.[0])}
          />
          <div className="dz-icon">⇪</div>
          <div className="dz-title">
            {busy ? "Reading header…" : "Drop a .safetensors file here"}
          </div>
          <div className="dz-sub">
            Header-only parse — tensor weights are never loaded. Works on
            multi-GB files.
          </div>
        </div>
      )}

      {error && <div className="error">{error}</div>}

      {manifest && stack && (
        <main>
          {view === "overview" && (
            <Overview manifest={manifest} stack={stack} onReset={() => setManifest(null)} />
          )}
          {view === "stack" && <StackView stack={stack} />}
          {view === "tensors" && <TensorTable manifest={manifest} />}
        </main>
      )}

      <footer className="foot">
        header-only · no weights leave your machine
      </footer>
    </div>
  );
}

function Overview({
  manifest,
  stack,
  onReset,
}: {
  manifest: Manifest;
  stack: StackModel;
  onReset: () => void;
}) {
  const totalBytes = manifest.tensors.reduce((a, t) => a + tensorBytes(t), 0);
  const byDtype = useMemo(() => {
    const m = new Map<string, { n: number; params: number; bytes: number }>();
    for (const t of manifest.tensors) {
      const e = m.get(t.dtype) ?? { n: 0, params: 0, bytes: 0 };
      e.n++;
      e.params += tensorElements(t);
      e.bytes += tensorBytes(t);
      m.set(t.dtype, e);
    }
    return [...m.entries()].sort((a, b) => b[1].bytes - a[1].bytes);
  }, [manifest]);

  return (
    <div className="overview">
      <div className="fileline">
        <span className="filename">{manifest.fileName}</span>
        <span className="family-badge">{stack.familyLabel}</span>
        <button className="ghost" onClick={onReset}>
          load another
        </button>
      </div>
      <div className="cards">
        <Stat label="tensors" value={String(manifest.tensors.length)} />
        <Stat label="parameters" value={formatCount(stack.totalParams)} />
        <Stat label="weight data" value={formatBytes(totalBytes)} />
        <Stat label="layers" value={String(stack.numLayers)} />
      </div>
      <h3>dtypes</h3>
      <div className="dtypes">
        {byDtype.map(([dt, s]) => (
          <div key={dt} className="dtype-row">
            <span className="dtype-name">{dt}</span>
            <div className="bar">
              <div
                className="bar-fill"
                style={{ width: `${(100 * s.bytes) / (totalBytes || 1)}%` }}
              />
            </div>
            <span className="dtype-meta">
              {s.n} tensors · {formatCount(s.params)} params · {formatBytes(s.bytes)}
            </span>
          </div>
        ))}
      </div>
      {Object.keys(manifest.metadata).length > 0 && (
        <>
          <h3>metadata</h3>
          <dl className="meta">
            {Object.entries(manifest.metadata).map(([k, v]) => (
              <div key={k} className="meta-row">
                <dt>{k}</dt>
                <dd>{v}</dd>
              </div>
            ))}
          </dl>
        </>
      )}
      <p className="hint">
        Header read: {formatBytes(manifest.headerBytes)} of{" "}
        {formatBytes(manifest.fileSize)}.
      </p>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="card">
      <div className="card-value">{value}</div>
      <div className="card-label">{label}</div>
    </div>
  );
}

function StackView({ stack }: { stack: StackModel }) {
  const maxLayer = Math.max(1, ...stack.layers.map((l) => l.params));
  return (
    <div className="stack">
      <div className="stack-col">
        {stack.embedding && (
          <StackBlock block={stack.embedding} accent="embed" />
        )}
        {stack.layers.map((l) => (
          <LayerCard key={l.index} layer={l} maxParams={maxLayer} />
        ))}
        {stack.tail.map((b, i) => (
          <StackBlock key={i} block={b} accent="tail" />
        ))}
        {stack.ungrouped && (
          <StackBlock block={stack.ungrouped} accent="other" />
        )}
        {stack.layers.length === 0 && !stack.embedding && (
          <p className="hint">
            No layered structure detected — see the tensors tab for the flat
            inventory.
          </p>
        )}
      </div>
    </div>
  );
}

function blockParams(b: Block): number {
  return b.tensors.reduce((a, t) => a + t.params, 0);
}

function StackBlock({ block, accent }: { block: Block; accent: string }) {
  const [open, setOpen] = useState(false);
  return (
    <div className={`sblock ${accent}`}>
      <button className="sblock-head" onClick={() => setOpen(!open)}>
        <span className="sblock-label">{block.label}</span>
        <span className="sblock-meta">
          {block.tensors.length} tensors · {formatCount(blockParams(block))} params
        </span>
        <span className="caret">{open ? "▾" : "▸"}</span>
      </button>
      {open && <TensorList tensors={block.tensors} />}
    </div>
  );
}

function LayerCard({
  layer,
  maxParams,
}: {
  layer: { index: number; params: number; blocks: Block[] };
  maxParams: number;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="layer">
      <button className="layer-head" onClick={() => setOpen(!open)}>
        <span className="layer-idx">layer {layer.index}</span>
        <div className="layer-bar">
          <div
            className="layer-fill"
            style={{ width: `${(100 * layer.params) / maxParams}%` }}
          />
        </div>
        <span className="layer-meta">{formatCount(layer.params)}</span>
        <span className="caret">{open ? "▾" : "▸"}</span>
      </button>
      {open && (
        <div className="layer-blocks">
          {layer.blocks.map((b, i) => (
            <div key={i} className="lblock">
              <div className="lblock-label">
                {b.label} · {formatCount(blockParams(b))}
              </div>
              <TensorList tensors={b.tensors} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function TensorList({
  tensors,
}: {
  tensors: { name: string; shape: number[]; params: number }[];
}) {
  return (
    <ul className="tlist">
      {tensors.map((t) => (
        <li key={t.name}>
          <span className="tname">{t.name}</span>
          <span className="tshape">[{t.shape.join(", ")}]</span>
          <span className="tparams">{formatCount(t.params)}</span>
        </li>
      ))}
    </ul>
  );
}

type SortKey = "name" | "params" | "bytes";

function TensorTable({ manifest }: { manifest: Manifest }) {
  const [q, setQ] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("bytes");
  const [desc, setDesc] = useState(true);
  const [dtype, setDtype] = useState<string>("all");

  const dtypes = useMemo(
    () => ["all", ...new Set(manifest.tensors.map((t) => t.dtype))],
    [manifest]
  );

  const rows = useMemo(() => {
    const ql = q.toLowerCase();
    const r = manifest.tensors.filter(
      (t) =>
        (dtype === "all" || t.dtype === dtype) &&
        (ql === "" || t.name.toLowerCase().includes(ql))
    );
    const key =
      sortKey === "name"
        ? (t: TensorEntry) => t.name
        : sortKey === "params"
          ? (t: TensorEntry) => tensorElements(t)
          : (t: TensorEntry) => tensorBytes(t);
    return [...r].sort((a, b) => {
      const ka = key(a);
      const kb = key(b);
      const c = ka < kb ? -1 : ka > kb ? 1 : 0;
      return desc ? -c : c;
    });
  }, [manifest, q, sortKey, desc, dtype]);

  function sortBy(k: SortKey) {
    if (k === sortKey) setDesc(!desc);
    else {
      setSortKey(k);
      setDesc(true);
    }
  }

  return (
    <div className="ttable-wrap">
      <div className="tcontrols">
        <input
          className="search"
          placeholder="filter tensors…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <select value={dtype} onChange={(e) => setDtype(e.target.value)}>
          {dtypes.map((d) => (
            <option key={d} value={d}>
              {d}
            </option>
          ))}
        </select>
        <span className="count">
          {rows.length} / {manifest.tensors.length}
        </span>
      </div>
      <table className="ttable">
        <thead>
          <tr>
            <th>
              <SortBtn label="tensor" k="name" cur={sortKey} desc={desc} onClick={sortBy} />
            </th>
            <th>dtype</th>
            <th>shape</th>
            <th className="num">
              <SortBtn label="params" k="params" cur={sortKey} desc={desc} onClick={sortBy} />
            </th>
            <th className="num">
              <SortBtn label="size" k="bytes" cur={sortKey} desc={desc} onClick={sortBy} />
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.slice(0, 2000).map((t) => (
            <tr key={t.name}>
              <td className="mono">{t.name}</td>
              <td>
                <span className="dtype-chip">{t.dtype}</span>
              </td>
              <td className="mono dim">[{t.shape.join(", ")}]</td>
              <td className="num">{formatCount(tensorElements(t))}</td>
              <td className="num">{formatBytes(tensorBytes(t))}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length > 2000 && (
        <p className="hint">showing first 2000 of {rows.length} — refine the filter</p>
      )}
    </div>
  );
}

function SortBtn({
  label,
  k,
  cur,
  desc,
  onClick,
}: {
  label: string;
  k: SortKey;
  cur: SortKey;
  desc: boolean;
  onClick: (k: SortKey) => void;
}) {
  return (
    <button className="sortbtn" onClick={() => onClick(k)}>
      {label} {cur === k ? (desc ? "▾" : "▴") : ""}
    </button>
  );
}
