"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent as ReactPointerEvent } from "react";

// A mock of Lilypad's region picker, drawn over the page instead of a frozen screen. The sizes,
// colours and tool behaviour follow shell/capture/Editor.qml and Toolbar.qml.

const COMMAND = "curl -fsSL https://lilypad.to | sh";
const PALETTE = ["#89B4FA", "#FF6B6B", "#FFDC67", "#B0FF4F", "#F8F9F9", "#1D1D1D"];
const PEN = 4;
const MARKER = 20;
const BLOCK = 12;
const FONT = '600 22px "Segoe UI Variable", "Segoe UI", system-ui, sans-serif';

const TOOLS = [
  { id: "", icon: "select", name: "Select" },
  { id: "pen", icon: "pen", name: "Pen", key: "p" },
  { id: "arrow", icon: "arrow", name: "Arrow", key: "a" },
  { id: "line", icon: "line", name: "Line", key: "l" },
  { id: "rect", icon: "rect", name: "Rectangle", key: "r" },
  { id: "text", icon: "text", name: "Text", key: "t" },
  { id: "marker", icon: "marker", name: "Marker", key: "h" },
  { id: "pixelate", icon: "pixelate", name: "Pixelate", key: "b" },
];

type Point = { x: number; y: number };
type Rect = { x: number; y: number; w: number; h: number };
type Stroke = { type: "pen" | "marker"; color: string; points: Point[] };
type Span = { type: "arrow" | "line" | "rect" | "pixelate"; color: string; x0: number; y0: number; x1: number; y1: number };
type Label = { type: "text"; color: string; x: number; y: number; text: string };
type Op = Stroke | Span | Label;

const box = (el: Element | null, pad = 0): Rect => {
  const r = el ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
  return { x: r.left - pad, y: r.top - pad, w: r.width + pad * 2, h: r.height + pad * 2 };
};

const spanBox = (s: Span): Rect => ({
  x: Math.min(s.x0, s.x1), y: Math.min(s.y0, s.y1), w: Math.abs(s.x1 - s.x0), h: Math.abs(s.y1 - s.y0),
});

// Shift: square boxes, arrows and lines snapped to 45°.
function constrained(s: Span, p: Point): Point {
  const dx = p.x - s.x0, dy = p.y - s.y0;
  if (s.type === "arrow" || s.type === "line") {
    const angle = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
    const length = Math.hypot(dx, dy);
    return { x: s.x0 + Math.cos(angle) * length, y: s.y0 + Math.sin(angle) * length };
  }
  const side = Math.max(Math.abs(dx), Math.abs(dy));
  return { x: s.x0 + Math.sign(dx || 1) * side, y: s.y0 + Math.sign(dy || 1) * side };
}

function drawStroke(ctx: CanvasRenderingContext2D, op: Stroke) {
  ctx.strokeStyle = op.color;
  ctx.lineWidth = op.type === "marker" ? MARKER : PEN;
  ctx.lineCap = ctx.lineJoin = "round";
  ctx.beginPath();
  op.points.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
  ctx.stroke();
}

function drawArrow(ctx: CanvasRenderingContext2D, op: Span) {
  const length = Math.hypot(op.x1 - op.x0, op.y1 - op.y0);
  const ux = length ? (op.x1 - op.x0) / length : 1, uy = length ? (op.y1 - op.y0) / length : 0;
  const head = op.type === "arrow" ? Math.min(length, PEN * 4.5) : 0;
  const spread = head * 0.62;
  ctx.strokeStyle = ctx.fillStyle = op.color;
  ctx.lineWidth = PEN;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(op.x0, op.y0);
  ctx.lineTo(op.x1 - ux * head * 0.8, op.y1 - uy * head * 0.8);
  ctx.stroke();
  if (!head) return;
  const bx = op.x1 - ux * head, by = op.y1 - uy * head;
  ctx.beginPath();
  ctx.moveTo(op.x1, op.y1);
  ctx.lineTo(bx - uy * spread, by + ux * spread);
  ctx.lineTo(bx + uy * spread, by - ux * spread);
  ctx.closePath();
  ctx.fill();
}

// What the page looks like, for pixelate to sample: a canvas can't read the DOM.
function snapshot(card: HTMLElement, scale: number) {
  const w = innerWidth, h = innerHeight;
  const frame = document.createElement("canvas");
  frame.width = w * scale;
  frame.height = h * scale;
  const ctx = frame.getContext("2d")!;
  ctx.scale(scale, scale);
  const css = getComputedStyle(document.documentElement);
  const color = (name: string) => css.getPropertyValue(name).trim();
  ctx.fillStyle = color("--bg");
  ctx.fillRect(0, 0, w, h);
  const logo = [...card.querySelectorAll("img")].find(img => img.offsetWidth > 0);
  if (logo) {
    const r = box(logo);
    ctx.drawImage(logo, r.x, r.y, r.w, r.h);
  }
  const install = box(card.querySelector(".install"));
  ctx.fillStyle = color("--card");
  ctx.beginPath();
  ctx.roundRect(install.x, install.y, install.w, install.h, 12);
  ctx.fill();
  const code = box(card.querySelector("code"));
  ctx.fillStyle = color("--ink");
  ctx.font = `14px ${color("--mono")}`;
  ctx.textBaseline = "middle";
  ctx.fillText(COMMAND, code.x, code.y + code.h / 2, code.w);
  return frame;
}

function drawPixelated(ctx: CanvasRenderingContext2D, frame: HTMLCanvasElement, scale: number, r: Rect) {
  const tiny = document.createElement("canvas");
  tiny.width = Math.max(1, Math.ceil(r.w / BLOCK));
  tiny.height = Math.max(1, Math.ceil(r.h / BLOCK));
  const tctx = tiny.getContext("2d")!;
  tctx.imageSmoothingQuality = "high"; // or each block is a few sampled pixels, not their average
  tctx.drawImage(frame, r.x * scale, r.y * scale, tiny.width * BLOCK * scale, tiny.height * BLOCK * scale, 0, 0, tiny.width, tiny.height);
  ctx.save();
  ctx.beginPath();
  ctx.rect(r.x, r.y, r.w, r.h); // the last blocks run past the box
  ctx.clip();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(tiny, 0, 0, tiny.width, tiny.height, r.x, r.y, tiny.width * BLOCK, tiny.height * BLOCK);
  ctx.restore();
}

export default function Picker() {
  const card = useRef<HTMLDivElement>(null);
  const installBox = useRef<HTMLDivElement>(null);
  const logoBox = useRef<HTMLHeadingElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const bar = useRef<HTMLDivElement>(null);
  const frame = useRef<HTMLCanvasElement | null>(null);
  const press = useRef<Point | null>(null);

  const [size, setSize] = useState({ w: 0, h: 0 });
  const [barWidth, setBarWidth] = useState(0);
  const [selection, setSelection] = useState<Rect | null>(null);
  const [candidate, setCandidate] = useState<Rect | null>(null);
  const [dragging, setDragging] = useState(false);
  const [tool, setTool] = useState("");
  const [color, setColor] = useState(PALETTE[0]);
  const [swatches, setSwatches] = useState(false);
  const [ops, setOps] = useState<Op[]>([]);
  const [undone, setUndone] = useState<Op[]>([]);
  const [draft, setDraft] = useState<Stroke | Span | null>(null);
  const [typing, setTyping] = useState<Label | null>(null);
  const [closed, setClosed] = useState(false);
  const [copied, setCopied] = useState(false);

  const home = useCallback(() => {
    const pad = Math.min(40, innerWidth / 16);
    return box(card.current, pad);
  }, []);

  // The selection starts around the card, and goes back there when the window changes.
  useLayoutEffect(() => {
    const fit = () => {
      frame.current = null;
      setSize({ w: innerWidth, h: innerHeight });
      setSelection(home());
    };
    fit();
    addEventListener("resize", fit);
    document.fonts?.ready.then(fit);
    return () => removeEventListener("resize", fit);
  }, [home]);

  useLayoutEffect(() => setBarWidth(bar.current?.offsetWidth ?? 0), [selection, closed, size]);

  const redraw = useCallback(() => {
    const el = canvas.current;
    if (!el || !card.current) return;
    const scale = devicePixelRatio || 1;
    el.width = innerWidth * scale;
    el.height = innerHeight * scale;
    const ctx = el.getContext("2d")!;
    ctx.scale(scale, scale);
    const all = draft ? [...ops, draft] : ops;

    // Pixelated boxes at the bottom and highlighter under everything else, like the real one.
    for (const op of all) {
      if (op.type !== "pixelate") continue;
      frame.current ??= snapshot(card.current, scale);
      drawPixelated(ctx, frame.current, scale, spanBox(op));
    }
    const markers = all.filter((op): op is Stroke => op.type === "marker");
    if (markers.length) {
      const layer = document.createElement("canvas");
      layer.width = el.width;
      layer.height = el.height;
      const lctx = layer.getContext("2d")!;
      lctx.scale(scale, scale);
      markers.forEach(op => drawStroke(lctx, op));
      ctx.globalAlpha = 0.42;
      ctx.drawImage(layer, 0, 0, innerWidth, innerHeight);
      ctx.globalAlpha = 1;
    }
    for (const op of all) {
      if (op.type === "pen") drawStroke(ctx, op);
      else if (op.type === "arrow" || op.type === "line") drawArrow(ctx, op);
      else if (op.type === "rect") {
        const r = spanBox(op);
        ctx.strokeStyle = op.color;
        ctx.lineWidth = PEN;
        ctx.beginPath();
        ctx.roundRect(r.x, r.y, r.w, r.h, 4);
        ctx.stroke();
      } else if (op.type === "text") {
        ctx.fillStyle = op.color;
        ctx.font = FONT;
        ctx.textBaseline = "top";
        ctx.fillText(op.text, op.x, op.y + 2);
      }
    }
  }, [ops, draft]);

  useEffect(redraw, [redraw, size]);

  const push = useCallback((op: Op) => {
    setOps(list => [...list, op]);
    setUndone([]);
  }, []);

  const commitText = useCallback(() => {
    setTyping(t => {
      if (t && t.text.trim()) push(t);
      return null;
    });
  }, [push]);

  const undo = useCallback(() => {
    setOps(list => {
      if (list.length) setUndone(u => [...u, list[list.length - 1]]);
      return list.slice(0, -1);
    });
  }, []);

  const redo = useCallback(() => {
    setUndone(list => {
      if (list.length) setOps(o => [...o, list[list.length - 1]]);
      return list.slice(0, -1);
    });
  }, []);

  const pick = useCallback((id: string) => {
    commitText();
    setCandidate(null);
    setTool(id);
    setSwatches(false);
  }, [commitText]);

  // X: the picker goes away and takes its drawings with it.
  const cancel = useCallback(() => {
    setTyping(null);
    setDraft(null);
    setOps([]);
    setUndone([]);
    setTool("");
    setColor(PALETTE[0]);
    setSwatches(false);
    setCandidate(null);
    setClosed(true);
  }, []);

  const reopen = useCallback(() => {
    setSelection(home());
    setClosed(false);
  }, [home]);

  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      const key = e.key.toLowerCase();
      if (e.ctrlKey && e.shiftKey && (e.key === "$" || e.code === "Digit4")) {
        e.preventDefault();
        reopen();
      } else if (closed || (e.target as Element).tagName === "INPUT") {
        return;
      } else if (e.key === "Escape") {
        cancel();
      } else if ((e.ctrlKey || e.metaKey) && key === "z") {
        e.preventDefault();
        (e.shiftKey ? redo : undo)();
      } else if (!e.ctrlKey && !e.metaKey && !e.altKey) {
        const found = TOOLS.find(t => t.key === key);
        if (found) pick(tool === found.id ? "" : found.id);
      }
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [closed, tool, pick, cancel, undo, redo]);

  // The smallest detected element under the pointer, like lilypad-regions finds on a real screen.
  const elementAt = (p: Point): Rect => {
    const inside = (r: Rect) => p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h;
    const found = [box(installBox.current), box(logoBox.current), home()].find(inside);
    return found ?? { x: 0, y: 0, w: innerWidth, h: innerHeight };
  };

  const onDown = (e: ReactPointerEvent) => {
    setSwatches(false);
    const p = { x: e.clientX, y: e.clientY };
    e.currentTarget.setPointerCapture(e.pointerId);
    press.current = p;
    if (tool === "text") {
      e.preventDefault();
      commitText();
      setTyping({ type: "text", color, x: p.x, y: p.y - 14, text: "" });
    } else if (tool === "pen" || tool === "marker") {
      setDraft({ type: tool, color, points: [p, { x: p.x + 0.01, y: p.y }] });
    } else if (tool) {
      setDraft({ type: tool as Span["type"], color, x0: p.x, y0: p.y, x1: p.x, y1: p.y });
    }
  };

  const onMove = (e: ReactPointerEvent) => {
    const p = { x: e.clientX, y: e.clientY };
    const start = press.current;
    if (!tool && !start) {
      setCandidate(elementAt(p));
    } else if (!tool && start) {
      if (dragging || Math.hypot(p.x - start.x, p.y - start.y) > 4) {
        setDragging(true);
        setCandidate(null);
        setSelection({
          x: Math.min(start.x, p.x), y: Math.min(start.y, p.y),
          w: Math.abs(p.x - start.x), h: Math.abs(p.y - start.y),
        });
      }
    } else if (draft) {
      if ("points" in draft) {
        const last = draft.points[draft.points.length - 1];
        if (Math.hypot(p.x - last.x, p.y - last.y) >= 1.5) setDraft({ ...draft, points: [...draft.points, p] });
      } else {
        const end = e.shiftKey ? constrained(draft, p) : p;
        setDraft({ ...draft, x1: end.x, y1: end.y });
      }
    }
  };

  const onUp = (e: ReactPointerEvent) => {
    const p = { x: e.clientX, y: e.clientY };
    if (!tool && press.current) {
      if (!dragging) setSelection(elementAt(p));
      else setSelection(s => (s && s.w > 24 && s.h > 24 ? s : home()));
    }
    press.current = null;
    setDragging(false);
    if (!draft) return;
    setDraft(null);
    if ("points" in draft) push(draft);
    else if (draft.type === "arrow" || draft.type === "line") {
      if (Math.hypot(draft.x1 - draft.x0, draft.y1 - draft.y0) >= 6) push(draft);
    } else if (Math.abs(draft.x1 - draft.x0) >= 3 && Math.abs(draft.y1 - draft.y0) >= 3) push(draft);
  };

  const copy = async () => {
    await navigator.clipboard.writeText(COMMAND);
    setCopied(true);
    setTimeout(() => setCopied(false), 1600);
  };

  const onTextKey = (e: KeyboardEvent) => {
    if (e.key === "Enter") commitText();
    else if (e.key === "Escape") setTyping(null);
  };

  const s = selection;
  const barX = s ? Math.max(barWidth / 2 + 8, Math.min(size.w - barWidth / 2 - 8, s.x + s.w / 2)) : 0;
  const barY = s ? Math.max(8, Math.min(size.h - 44 - 8, s.y + s.h + 16)) : 0;
  const swatchesBelow = barY + 44 + 6 + 40 < size.h;
  const up = !closed && s !== null;

  return (
    <main className={"scene" + (tool ? " drawing" : "")}>
      <div className="card" ref={card}>
        <h1 className="logo" ref={logoBox}>
          <img className="light" src="/logo-light.svg" width="337" height="83" alt="Lilypad" />
          <img className="dark" src="/logo-dark.svg" width="337" height="83" alt="Lilypad" />
        </h1>
        <div className="install" ref={installBox}>
          <code>{COMMAND}</code>
          <button className="copy" onClick={copy} aria-label={copied ? "Copied" : "Copy install command"}>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              {copied ? <path d="M3 8.5 6.5 12 13 4.5" /> : <><rect x="5.5" y="5.5" width="8" height="8" rx="2" /><path d="M10.5 3.5v-.5a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5" /></>}
            </svg>
          </button>
        </div>
      </div>

      <canvas ref={canvas} aria-hidden="true" />

      {up && (
        <>
          <div
            className={"surface" + (tool === "text" ? " text" : "")}
            onPointerDown={onDown}
            onPointerMove={onMove}
            onPointerUp={onUp}
            onPointerLeave={() => setCandidate(null)}
          />
          <div
            className="shade"
            style={{ clipPath: `polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, ${s.x}px ${s.y}px, ${s.x + s.w}px ${s.y}px, ${s.x + s.w}px ${s.y + s.h}px, ${s.x}px ${s.y + s.h}px, ${s.x}px ${s.y}px)` }}
          />
          <div
            className={"outline" + (dragging ? " dragging" : "")}
            style={{ left: s.x - 1, top: s.y - 1, width: s.w + 2, height: s.h + 2 }}
          />
          {candidate && (
            <div
              className="outline hint"
              style={{ left: candidate.x - 1, top: candidate.y - 1, width: candidate.w + 2, height: candidate.h + 2 }}
            />
          )}
          {!tool && (
            <div className="size" style={{ left: Math.max(4, s.x), top: Math.max(4, s.y - 28) }}>
              {Math.round(s.w * (devicePixelRatio || 1))} × {Math.round(s.h * (devicePixelRatio || 1))}
            </div>
          )}
          {typing && (
            <input
              className="label"
              autoFocus
              aria-label="Label text"
              value={typing.text}
              style={{ left: typing.x, top: typing.y, color: typing.color }}
              onChange={e => setTyping({ ...typing, text: e.target.value })}
              onKeyDown={onTextKey}
              onBlur={commitText}
            />
          )}
          <div className="bar" ref={bar} role="toolbar" aria-label="Tools" style={{ left: barX, top: barY }}>
            {TOOLS.map(t => (
              <button
                key={t.icon}
                className="tool"
                aria-label={t.name}
                aria-pressed={tool === t.id}
                title={t.key ? `${t.name} (${t.key.toUpperCase()})` : t.name}
                onClick={() => pick(t.id)}
              >
                <img src={`/icons/${t.icon}.svg`} alt="" />
              </button>
            ))}
            <span className="divider" />
            <button className="tool" aria-label="Colour" aria-pressed={swatches} title="Colour" onClick={() => setSwatches(!swatches)}>
              <span className="dot" style={{ background: color }} />
            </button>
            <button className="tool" aria-label="Undo" title="Undo (Ctrl+Z)" disabled={!ops.length} onClick={undo}>
              <img src="/icons/undo.svg" alt="" />
            </button>
            <span className="divider" />
            <button className="tool" aria-label="Close" title="Close (Esc)" onClick={cancel}>
              <img src="/icons/close.svg" alt="" />
            </button>
          </div>
          {swatches && (
            <div className="swatches" style={{ left: barX, top: swatchesBelow ? barY + 50 : barY - 46 }}>
              {PALETTE.map(c => (
                <button
                  key={c}
                  className="tool"
                  aria-label={c}
                  aria-pressed={c === color}
                  onClick={() => { setColor(c); setSwatches(false); }}
                >
                  <span className="dot" style={{ background: c }} />
                </button>
              ))}
            </div>
          )}
        </>
      )}

      {closed && <button className="reopen" onClick={reopen}>Ctrl+Shift+4 to pick again</button>}
    </main>
  );
}
