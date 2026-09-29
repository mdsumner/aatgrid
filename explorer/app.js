fetch("coast.json")
  .then(r => { if (!r.ok) throw new Error("coast.json: HTTP " + r.status); return r.json(); })
  .then(main)
  .catch(err => {
    const el = document.getElementById("status");
    el.hidden = false;
    el.textContent = "Could not load coastline data (" + err.message + "). Serve this folder over HTTP rather than opening the file directly.";
  });

function main(RAW) {
"use strict";

// ---------------------------------------------------------------- data
const Q = RAW.q || 1000;
function decode(strips) {
  return strips.map(([lon0, polys]) => ({
    lon0,
    polys: polys.map(rings => rings.map(fl => {
      const a = new Float64Array(fl.length);
      let x = 0, y = 0;
      for (let i = 0; i < fl.length; i += 2) {
        x += fl[i]; y += fl[i + 1];
        a[i] = x / Q; a[i + 1] = y / Q;
      }
      return a;
    }))
  }));
}
const COAST = { land: decode(RAW.land), shelf: decode(RAW.shelf) };
const LEVELS = { L1: 60, L2: 10 };
const LON_WINDOW = 46;   // degrees either side of the central meridian we project

const PRESETS = [
  { name: "Heard & McDonald", lon: 73.25, lat: -53.08, km: 110 },
  { name: "Macquarie", lon: 158.87, lat: -54.62, km: 60 },
  { name: "Auster", lon: 64.0, lat: -67.39, km: 40 },
  { name: "Mawson", lon: 62.87, lat: -67.6, km: 40 },
  { name: "Davis", lon: 77.97, lat: -68.58, km: 50 },
  { name: "Casey", lon: 110.53, lat: -66.28, km: 50 },
  { name: "Amery Ice Shelf", lon: 70.5, lat: -70.3, km: 600 },
  { name: "Whole AAT", lon: 96, lat: -70, km: 5600, zone: 46 }
];

// ---------------------------------------------------------------- state
const st = {
  zone: 43, ox: 140000, oy: 20000, px: 720, resList: [10, 20, 60], active: 10,
  cx: 0, cy: 0, s: 0.01, W: 0, H: 0, dpr: 1,
  layers: { land: [], shelf: [] }, lines: { zone: [], aat: [], grat: [] },
  set: new Map(), cmp: [], inspect: null, hover: null
};

const $ = id => document.getElementById(id);
const canvas = $("map"), ctx = canvas.getContext("2d");
const base = document.createElement("canvas"), bctx = base.getContext("2d");
const mask = document.createElement("canvas"), mctx = mask.getContext("2d", { willReadFrequently: true });

// ---------------------------------------------------------------- theme
const TOK = ["ocean", "land", "shelf", "shelf-edge", "grid", "grat", "accent", "t-land", "t-shelf", "hl", "void", "muted", "ink", "surface"];
let T = {};
let hatch = null;
function readTokens() {
  const cs = getComputedStyle(document.documentElement);
  for (const k of TOK) T[k] = cs.getPropertyValue("--" + k).trim();
  const h = document.createElement("canvas"); h.width = h.height = 8;
  const hc = h.getContext("2d");
  hc.strokeStyle = T["shelf-edge"]; hc.lineWidth = 1;
  hc.beginPath(); hc.moveTo(0, 8); hc.lineTo(8, 0); hc.stroke();
  hatch = bctx.createPattern(h, "repeat");
}
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { readTokens(); invalidate(); });
new MutationObserver(() => { readTokens(); invalidate(); }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

// ---------------------------------------------------------------- grid arithmetic (mirrors aatgrid R/)
const cmOf = z => -183 + 6 * z;
const zoneOfLon = lon => Math.floor((lon + 180) / 6) + 1;
const tsz = res => st.px * res;
const pad4 = n => String(n).padStart(4, "0");
const zid = z => String(z).padStart(2, "0") + "S";
function tileId(zone, res, col, row) { return `${zid(zone)}_R${pad4(res)}_${pad4(col)}_${pad4(row)}`; }
function tileExt(col, row, res) {
  const t = tsz(res), x = st.ox + col * t, y = st.oy + row * t;
  return [x, x + t, y, y + t];
}
function tileAt(X, Y, res) {
  const t = tsz(res);
  return [Math.floor((X - st.ox) / t), Math.floor((Y - st.oy) / t)];
}
function parseIds(text) {
  const out = [], re = /(\d{1,2})S_(?:R(\d{1,5})|(L[12]))_(\d+)_(\d+)/g;
  let m;
  while ((m = re.exec(text))) {
    const res = m[2] ? parseInt(m[2], 10) : LEVELS[m[3]];
    out.push({ zone: parseInt(m[1], 10), res, col: parseInt(m[4], 10), row: parseInt(m[5], 10) });
  }
  return out;
}
function factorise(n) {
  const f = []; let k = 2;
  while (n > 1 && k * k <= n) { let e = 0; while (n % k === 0) { n /= k; e++; } if (e) f.push(e > 1 ? `${k}^${e}` : `${k}`); k++; }
  if (n > 1) f.push(String(n));
  return f.join(" x ");
}
function fmtNum(v) { return Number.isInteger(v) ? String(v) : String(parseFloat(v.toFixed(3))); }
function fmtLL(lon, lat) {
  return `${Math.abs(lon).toFixed(4)}&deg;${lon >= 0 ? "E" : "W"} ${Math.abs(lat).toFixed(4)}&deg;${lat >= 0 ? "N" : "S"}`;
}

// ---------------------------------------------------------------- projection of layers into the zone
function projectLayer(strips, cm) {
  const out = [];
  for (const s of strips) {
    if (Math.abs(s.lon0 + 1 - cm) > LON_WINDOW) continue;
    for (const poly of s.polys) {
      const rings = [], rbb = [];
      for (const ll of poly) {
        const r = new Float64Array(ll.length);
        let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
        for (let i = 0; i < ll.length; i += 2) {
          const p = UTM.fwd(ll[i], ll[i + 1], cm);
          r[i] = p[0]; r[i + 1] = p[1];
          if (p[0] < x0) x0 = p[0]; if (p[0] > x1) x1 = p[0];
          if (p[1] < y0) y0 = p[1]; if (p[1] > y1) y1 = p[1];
        }
        rings.push(r); rbb.push([x0, x1, y0, y1]);
      }
      out.push({ rings, rbb, bb: rbb[0] });
    }
  }
  return out;
}
function polyline(pts, cm) {
  const r = new Float64Array(pts.length * 2);
  pts.forEach(([lo, la], i) => { const p = UTM.fwd(lo, la, cm); r[2 * i] = p[0]; r[2 * i + 1] = p[1]; });
  return r;
}
function meridian(lon, la0, la1, cm) { const p = []; for (let la = la0; la <= la1 + 1e-9; la += 0.25) p.push([lon, la]); return polyline(p, cm); }
function parallel(lat, lo0, lo1, cm) { const p = []; for (let lo = lo0; lo <= lo1 + 1e-9; lo += 0.25) p.push([lo, lat]); return polyline(p, cm); }

function setZone(z) {
  st.zone = z;
  const cm = cmOf(z), lo0 = cm - LON_WINDOW, lo1 = cm + LON_WINDOW;
  st.layers.land = projectLayer(COAST.land, cm);
  st.layers.shelf = projectLayer(COAST.shelf, cm);
  const grat = [];
  for (let la = -84; la <= -45; la += 1) grat.push(parallel(la, lo0, lo1, cm));
  for (let lo = Math.ceil(lo0 / 2) * 2; lo <= lo1; lo += 2) grat.push(meridian(lo, -84, -45, cm));
  const aat = [];
  const clampL = (a, b) => [Math.max(a, lo0), Math.min(b, lo1)];
  for (const lo of [44.6333, 136.1833, 142.0333, 160]) if (Math.abs(lo - cm) <= LON_WINDOW) aat.push(meridian(lo, -84, -60, cm));
  for (const [a, b] of [[44.6333, 136.1833], [142.0333, 160]]) { const [p, q] = clampL(a, b); if (q > p) aat.push(parallel(-60, p, q, cm)); }
  st.lines = { zone: [meridian(cm - 3, -84, -40, cm), meridian(cm + 3, -84, -40, cm)], aat, grat };
  $("zone").value = String(z);
}

// ---------------------------------------------------------------- exact geometry
function segHitsRect(ax, ay, bx, by, x0, y0, x1, y1) {
  let t0 = 0, t1 = 1;
  const dx = bx - ax, dy = by - ay;
  const p = [-dx, dx, -dy, dy], q = [ax - x0, x1 - ax, ay - y0, y1 - ay];
  for (let i = 0; i < 4; i++) {
    if (p[i] === 0) { if (q[i] < 0) return false; }
    else {
      const t = q[i] / p[i];
      if (p[i] < 0) { if (t > t1) return false; if (t > t0) t0 = t; }
      else { if (t < t0) return false; if (t < t1) t1 = t; }
    }
  }
  return true;
}
function pointInPoly(rings, x, y) {
  let inside = false;
  for (const r of rings) {
    const n = r.length;
    for (let i = 0, j = n - 2; i < n; j = i, i += 2) {
      const xi = r[i], yi = r[i + 1], xj = r[j], yj = r[j + 1];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}
function rectTouches(layer, x0, x1, y0, y1) {
  for (const p of layer) {
    const b = p.bb;
    if (b[1] < x0 || b[0] > x1 || b[3] < y0 || b[2] > y1) continue;
    for (let k = 0; k < p.rings.length; k++) {
      const rb = p.rbb[k];
      if (rb[1] < x0 || rb[0] > x1 || rb[3] < y0 || rb[2] > y1) continue;
      const r = p.rings[k], n = r.length;
      for (let i = 0, j = n - 2; i < n; j = i, i += 2) {
        if (segHitsRect(r[j], r[j + 1], r[i], r[i + 1], x0, y0, x1, y1)) return true;
      }
    }
    if (pointInPoly(p.rings, (x0 + x1) / 2, (y0 + y1) / 2)) return true;
  }
  return false;
}
function surfaceOf(col, row, res) {
  const [x0, x1, y0, y1] = tileExt(col, row, res);
  if (rectTouches(st.layers.land, x0, x1, y0, y1)) return "land";
  if (rectTouches(st.layers.shelf, x0, x1, y0, y1)) return "shelf";
  return "ocean";
}

// ---------------------------------------------------------------- view
const sx = X => st.W / 2 + (X - st.cx) * st.s;
const sy = Y => st.H / 2 - (Y - st.cy) * st.s;
const wx = x => st.cx + (x - st.W / 2) / st.s;
const wy = y => st.cy - (y - st.H / 2) / st.s;
function vbounds() { return { x0: wx(0), x1: wx(st.W), y0: wy(st.H), y1: wy(0) }; }
function visibleRange(res) {
  const t = tsz(res), vb = vbounds();
  const c0 = Math.max(0, Math.floor((vb.x0 - st.ox) / t)), c1 = Math.floor((vb.x1 - st.ox) / t);
  const r0 = Math.max(0, Math.floor((vb.y0 - st.oy) / t)), r1 = Math.floor((vb.y1 - st.oy) / t);
  return { c0, c1, r0, r1, n: Math.max(0, c1 - c0 + 1) * Math.max(0, r1 - r0 + 1) };
}
function clampS(s) { return Math.min(5, Math.max(1.5e-5, s)); }
function centreOn(lon, lat, km, zone) {
  const z = zone || zoneOfLon(lon);
  if (z !== st.zone) setZone(z);
  const p = UTM.fwd(lon, lat, cmOf(z));
  st.cx = p[0]; st.cy = p[1];
  st.s = clampS(Math.min(st.W, st.H * 1.4) / (km * 1000));
  invalidate();
}
function fitUTM(x0, x1, y0, y1) {
  st.cx = (x0 + x1) / 2; st.cy = (y0 + y1) / 2;
  st.s = clampS(Math.min(st.W / ((x1 - x0) * 1.25), st.H / ((y1 - y0) * 1.25)));
  invalidate();
}

// ---------------------------------------------------------------- render
let needBase = true, frame = 0;
function invalidate() { needBase = true; schedule(); }
function schedule() { if (!frame) frame = requestAnimationFrame(draw); }
function layerPath(layer, vb) {
  const p = new Path2D();
  for (const poly of layer) {
    const b = poly.bb;
    if (b[1] < vb.x0 || b[0] > vb.x1 || b[3] < vb.y0 || b[2] > vb.y1) continue;
    for (const r of poly.rings) {
      for (let i = 0; i < r.length; i += 2) {
        const x = sx(r[i]), y = sy(r[i + 1]);
        if (i === 0) p.moveTo(x, y); else p.lineTo(x, y);
      }
      p.closePath();
    }
  }
  return p;
}
function strokeLines(c, lines, color, width, dash) {
  c.save(); c.strokeStyle = color; c.lineWidth = width; c.setLineDash(dash || []);
  c.beginPath();
  for (const r of lines) for (let i = 0; i < r.length; i += 2) { const x = sx(r[i]), y = sy(r[i + 1]); if (i === 0) c.moveTo(x, y); else c.lineTo(x, y); }
  c.stroke(); c.restore();
}
function rectPath(p, col, row, res, minPx) {
  const [x0, x1, y0, y1] = tileExt(col, row, res);
  let a = sx(x0), b = sx(x1), c = sy(y1), d = sy(y0);
  if (b - a < minPx) { const m = (a + b) / 2; a = m - minPx / 2; b = m + minPx / 2; }
  if (d - c < minPx) { const m = (c + d) / 2; c = m - minPx / 2; d = m + minPx / 2; }
  p.rect(a, c, b - a, d - c);
}

let satL = null, satS = null, satW = 0, satH = 0;
function buildMask(landP, shelfP) {
  const W = Math.max(1, Math.round(st.W)), H = Math.max(1, Math.round(st.H));
  if (mask.width !== W || mask.height !== H) { mask.width = W; mask.height = H; }
  mctx.setTransform(1, 0, 0, 1, 0, 0);
  mctx.globalCompositeOperation = "source-over";
  mctx.fillStyle = "#000"; mctx.fillRect(0, 0, W, H);
  mctx.globalCompositeOperation = "lighter";
  mctx.fillStyle = "#ff0000"; mctx.fill(landP, "evenodd"); mctx.strokeStyle = "#ff0000"; mctx.lineWidth = 1; mctx.stroke(landP);
  mctx.fillStyle = "#00ff00"; mctx.fill(shelfP, "evenodd"); mctx.strokeStyle = "#00ff00"; mctx.stroke(shelfP);
  const d = mctx.getImageData(0, 0, W, H).data;
  const n = (W + 1) * (H + 1);
  if (!satL || satL.length !== n) { satL = new Int32Array(n); satS = new Int32Array(n); }
  satW = W; satH = H;
  for (let y = 0; y < H; y++) {
    let rl = 0, rs = 0;
    const o = (y + 1) * (W + 1), op = y * (W + 1), di = y * W * 4;
    for (let x = 0; x < W; x++) {
      if (d[di + x * 4] > 0) rl++;
      if (d[di + x * 4 + 1] > 0) rs++;
      satL[o + x + 1] = satL[op + x + 1] + rl;
      satS[o + x + 1] = satS[op + x + 1] + rs;
    }
  }
}
function satSum(S, x0, y0, x1, y1) {
  x0 = Math.max(0, Math.min(satW, x0)); x1 = Math.max(0, Math.min(satW, x1));
  y0 = Math.max(0, Math.min(satH, y0)); y1 = Math.max(0, Math.min(satH, y1));
  if (x1 <= x0 || y1 <= y0) return 0;
  const w = satW + 1;
  return S[y1 * w + x1] - S[y0 * w + x1] - S[y1 * w + x0] + S[y0 * w + x0];
}

let statusMsg = "";
function renderBase() {
  const W = st.W, H = st.H, dpr = st.dpr;
  if (base.width !== Math.round(W * dpr) || base.height !== Math.round(H * dpr)) { base.width = Math.round(W * dpr); base.height = Math.round(H * dpr); }
  const c = bctx;
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  c.globalAlpha = 1;
  c.fillStyle = T.ocean; c.fillRect(0, 0, W, H);
  const vb = vbounds();

  strokeLines(c, st.lines.grat, T.grat, 1);

  const shelfP = layerPath(st.layers.shelf, vb), landP = layerPath(st.layers.land, vb);
  c.fillStyle = T.shelf; c.fill(shelfP, "evenodd"); c.strokeStyle = T.shelf; c.lineWidth = 1; c.stroke(shelfP);
  c.fillStyle = hatch; c.fill(shelfP, "evenodd");
  c.fillStyle = T.land; c.fill(landP, "evenodd"); c.strokeStyle = T.land; c.lineWidth = 1; c.stroke(landP);

  // grid domain: negative indices do not exist
  const gx = sx(st.ox), gy = sy(st.oy);
  c.save(); c.globalAlpha = 0.28; c.fillStyle = T.void;
  if (gx > 0) c.fillRect(0, 0, Math.min(gx, W), H);
  if (gy < H) c.fillRect(0, Math.max(gy, 0), W, H - Math.max(gy, 0));
  c.restore();

  // classify active-resolution tiles from the screen mask
  const ar = st.active, tpx = tsz(ar) * st.s, vr = visibleRange(ar);
  statusMsg = "";
  if (tpx >= 2 && vr.n > 0 && vr.n <= 150000) {
    buildMask(landP, shelfP);
    const pl = new Path2D(), ps = new Path2D();
    for (let col = vr.c0; col <= vr.c1; col++) for (let row = vr.r0; row <= vr.r1; row++) {
      if (st.set.has(tileId(st.zone, ar, col, row))) continue;
      const [x0, x1, y0, y1] = tileExt(col, row, ar);
      const a = Math.floor(sx(x0)), b = Math.ceil(sx(x1)), t = Math.floor(sy(y1)), u = Math.ceil(sy(y0));
      if (satSum(satL, a, t, b, u) > 0) pl.rect(sx(x0), sy(y1), tpx, tpx);
      else if (satSum(satS, a, t, b, u) > 0) ps.rect(sx(x0), sy(y1), tpx, tpx);
    }
    c.save();
    c.globalAlpha = 0.34; c.fillStyle = T["t-land"]; c.fill(pl);
    c.globalAlpha = 0.24; c.fillStyle = T["t-shelf"]; c.fill(ps);
    c.restore();
  } else if (vr.n > 0) {
    statusMsg = `Zoom in to see R${pad4(ar)} tiles (${tpx < 0.1 ? tpx.toFixed(3) : tpx.toFixed(1)} px wide here)`;
  }

  // compared ids
  const cmpHere = st.cmp.filter(t => t.zone === st.zone);
  if (cmpHere.length) {
    const p = new Path2D();
    for (const t of cmpHere) rectPath(p, t.col, t.row, t.res, 3);
    c.save(); c.globalAlpha = 0.14; c.fillStyle = T.hl; c.fill(p); c.globalAlpha = 1;
    c.strokeStyle = T.hl; c.lineWidth = 1.5; c.setLineDash([5, 3]); c.stroke(p); c.restore();
  }
  // tile set
  const setHere = [...st.set.values()].filter(t => t.zone === st.zone);
  if (setHere.length) {
    const p = new Path2D();
    for (const t of setHere) rectPath(p, t.col, t.row, t.res, 2);
    c.save(); c.globalAlpha = 0.2; c.fillStyle = T.accent; c.fill(p); c.globalAlpha = 1;
    c.strokeStyle = T.accent; c.lineWidth = 1.6; c.stroke(p); c.restore();
  }

  // lattices, coarse to fine, thicker when coarser
  const sorted = [...st.resList].sort((a, b) => b - a);
  const nres = sorted.length;
  sorted.forEach((res, rank) => {
    const t = tsz(res), tp = t * st.s;
    if (tp < 7) return;
    const vr2 = visibleRange(res);
    if ((vr2.c1 - vr2.c0) + (vr2.r1 - vr2.r0) > 3000) return;
    const lw = nres > 1 ? 1.9 - 1.3 * rank / (nres - 1) : 1.2;
    c.save();
    c.strokeStyle = T.grid; c.lineWidth = lw;
    c.globalAlpha = Math.min(0.55, 0.1 + (tp - 7) / 120);
    c.beginPath();
    const yTop = 0, yBot = Math.min(H, gy), xL = Math.max(0, gx);
    for (let col = vr2.c0; col <= vr2.c1 + 1; col++) { const x = sx(st.ox + col * t); if (x >= xL - 0.5) { c.moveTo(x, yTop); c.lineTo(x, yBot); } }
    for (let row = vr2.r0; row <= vr2.r1 + 1; row++) { const y = sy(st.oy + row * t); if (y <= gy + 0.5) { c.moveTo(xL, y); c.lineTo(W, y); } }
    c.stroke(); c.restore();
  });

  // pixel lattice of the active resolution when individual pixels are visible
  const ppx = ar * st.s;
  if (ppx >= 10) {
    const x0 = Math.max(Math.floor((vb.x0 - st.ox) / ar), 0), x1 = Math.floor((vb.x1 - st.ox) / ar);
    const y0 = Math.max(Math.floor((vb.y0 - st.oy) / ar), 0), y1 = Math.floor((vb.y1 - st.oy) / ar);
    if ((x1 - x0) + (y1 - y0) < 800) {
      c.save(); c.strokeStyle = T.grid; c.globalAlpha = 0.12; c.lineWidth = 0.5; c.beginPath();
      for (let i = x0; i <= x1 + 1; i++) { const x = sx(st.ox + i * ar); c.moveTo(x, 0); c.lineTo(x, Math.min(H, gy)); }
      for (let j = y0; j <= y1 + 1; j++) { const y = sy(st.oy + j * ar); c.moveTo(Math.max(0, gx), y); c.lineTo(W, y); }
      c.stroke(); c.restore();
    }
  }

  strokeLines(c, st.lines.zone, T.muted, 1.5, [8, 5]);
  strokeLines(c, st.lines.aat, T.accent, 1.6);

  // col,row labels
  if (tpx >= 110 && vr.n <= 500) {
    c.save(); c.font = "11px " + getComputedStyle(document.body).getPropertyValue("--f-mono");
    c.fillStyle = T.muted; c.textBaseline = "top";
    for (let col = vr.c0; col <= vr.c1; col++) for (let row = vr.r0; row <= vr.r1; row++) {
      const [x0, , , y1] = tileExt(col, row, ar);
      c.fillText(`${pad4(col)},${pad4(row)}`, sx(x0) + 4, sy(y1) + 4);
    }
    c.restore();
  }

  // inspected tile
  if (st.inspect && st.inspect.zone === st.zone) {
    const t = st.inspect, p = new Path2D(); rectPath(p, t.col, t.row, t.res, 4);
    c.save(); c.strokeStyle = T.ink; c.lineWidth = 2.5; c.stroke(p); c.restore();
  }

  // status + scale
  const el = $("status"); el.hidden = !statusMsg; el.textContent = statusMsg;
  const target = 110 / st.s, pow = Math.pow(10, Math.floor(Math.log10(target)));
  const nice = [1, 2, 5, 10].map(k => k * pow).filter(v => v <= target).pop();
  $("scale-bar").style.width = (nice * st.s).toFixed(1) + "px";
  $("scale-lab").textContent = nice >= 1000 ? `${nice / 1000} km` : `${nice} m`;
}

function draw() {
  frame = 0;
  if (!st.W) return;
  if (needBase) { renderBase(); needBase = false; }
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(base, 0, 0);
  if (st.hover) {
    ctx.setTransform(st.dpr, 0, 0, st.dpr, 0, 0);
    const [col, row] = st.hover;
    if (col >= 0 && row >= 0) {
      const p = new Path2D(); rectPath(p, col, row, st.active, 3);
      ctx.strokeStyle = T.accent; ctx.lineWidth = 1.5; ctx.setLineDash([4, 3]); ctx.stroke(p); ctx.setLineDash([]);
    }
  }
}

// ---------------------------------------------------------------- panels
function esc(s) { return String(s).replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch])); }

function renderScheme() {
  $("px600").setAttribute("aria-pressed", String(st.px === 600));
  $("px720").setAttribute("aria-pressed", String(st.px === 720));
  $("px").value = st.px; $("ox").value = st.ox; $("oy").value = st.oy;
  $("res").value = st.resList.join(", ");
  const m16 = st.px % 16 === 0;
  $("px-note").innerHTML = `${st.px} = ${factorise(st.px)}. ` + (m16
    ? "A multiple of 16, so a whole tile can be one GeoTIFF block and packed children stay block-aligned."
    : "Not a multiple of 16, so no GeoTIFF block size lines up with tile edges.");
  const act = $("active");
  act.innerHTML = st.resList.map(r => `<option value="${r}">${r} m (R${pad4(r)})</option>`).join("");
  act.value = String(st.active);
  const rows = st.resList.map(r => {
    const nests = st.resList.filter(q => q > r).map(q => (q % r === 0 ? `${q} m x${q / r}` : `<span style="color:var(--accent)">${q} m no</span>`)).join(", ");
    return `<tr><td>${r} m</td><td>${fmtNum(tsz(r) / 1000)} km</td><td>${nests || "-"}</td></tr>`;
  }).join("");
  $("nest").innerHTML = `<tr><th>Res</th><th>Tile</th><th>Nests in</th></tr>${rows}`;
}

function renderInfo() {
  const box = $("info"), t = st.inspect;
  if (!t) { box.innerHTML = `<p class="note">Click a tile on the map.</p>`; return; }
  if (t.col < 0 || t.row < 0) {
    box.innerHTML = `<p class="note">Outside the grid domain: this point has a negative tile index under origin ${st.ox} / ${st.oy}.</p>`;
    return;
  }
  const id = tileId(t.zone, t.res, t.col, t.row);
  const [x0, x1, y0, y1] = tileExt(t.col, t.row, t.res);
  const cm = cmOf(t.zone);
  const cen = UTM.inv((x0 + x1) / 2, (y0 + y1) / 2, cm);
  const off = Math.abs(cen[0] - cm) - 3;
  const surf = t.zone === st.zone ? surfaceOf(t.col, t.row, t.res) : null;
  const surfLab = { land: "touches land", shelf: "touches ice shelf only", ocean: "open water" };
  const parents = [], children = [];
  for (const q of st.resList) {
    if (q > t.res) {
      if (q % t.res === 0) {
        const f = q / t.res, pc = Math.floor(t.col / f), pr = Math.floor(t.row / f);
        const xo = (t.col - pc * f) * st.px, yo = (f - 1 - (t.row - pr * f)) * st.px;
        parents.push(`${tileId(t.zone, q, pc, pr)}<br>window x ${xo}, y ${yo} of ${f * st.px} px`);
      } else parents.push(`R${pad4(q)}: does not nest (ratio ${q}/${t.res})`);
    } else if (q < t.res) {
      if (t.res % q === 0) {
        const f = t.res / q;
        children.push(`R${pad4(q)}: ${f}x${f} = ${f * f} tiles, cols ${t.col * f}-${t.col * f + f - 1}, rows ${t.row * f}-${t.row * f + f - 1}`);
      } else children.push(`R${pad4(q)}: does not nest (ratio ${t.res}/${q})`);
    }
  }
  const inSet = st.set.has(id);
  box.innerHTML = `
    <div class="tid">${id}</div>
    <div class="row">
      ${surf ? `<span class="pill ${surf}">${surfLab[surf]}</span>` : ""}
      ${off > 0 ? `<span class="pill warn">centre ${off.toFixed(2)}&deg; outside zone ${zid(t.zone)}</span>` : `<span class="pill ocean">inside zone ${zid(t.zone)}</span>`}
    </div>
    <dl class="kv">
      <dt>Tile</dt><dd>${t.res} m, ${st.px} x ${st.px} px, ${fmtNum(tsz(t.res) / 1000)} km</dd>
      <dt>Extent</dt><dd>x ${fmtNum(x0)} to ${fmtNum(x1)}<br>y ${fmtNum(y0)} to ${fmtNum(y1)}<br>EPSG:327${String(t.zone).padStart(2, "0")}</dd>
      <dt>Geotransform</dt><dd>${fmtNum(x0)}, ${t.res}, 0, ${fmtNum(y1)}, 0, -${t.res}</dd>
      <dt>Centre</dt><dd>${fmtLL(cen[0], cen[1])}</dd>
      ${parents.length ? `<dt>Parents</dt><dd>${parents.join("<br>")}</dd>` : ""}
      ${children.length ? `<dt>Children</dt><dd>${children.join("<br>")}</dd>` : ""}
    </dl>
    <div class="row">
      <button type="button" id="i-toggle" class="${inSet ? "" : "primary"}">${inSet ? "Remove from set" : "Add to set"}</button>
      <button type="button" id="i-copy">Copy id</button>
      <button type="button" id="i-zoom">Zoom to tile</button>
    </div>`;
  $("i-toggle").onclick = () => { toggleSet(t); };
  $("i-copy").onclick = e => copyText(id, e.currentTarget);
  $("i-zoom").onclick = () => { if (t.zone !== st.zone) setZone(t.zone); fitUTM(x0, x1, y0, y1); };
}

function renderSet(msg) {
  const ids = [...st.set.keys()].sort();
  $("set-count").textContent = `${ids.length} tile${ids.length === 1 ? "" : "s"}` + (ids.length ? ` (${[...new Set([...st.set.values()].map(t => zid(t.zone) + " R" + pad4(t.res)))].join(", ")})` : "");
  $("set-list").value = ids.join("\n");
  const m = $("set-msg"); m.hidden = !msg; m.textContent = msg || "";
}
function toggleSet(t) {
  const id = tileId(t.zone, t.res, t.col, t.row);
  if (st.set.has(id)) st.set.delete(id); else st.set.set(id, { zone: t.zone, res: t.res, col: t.col, row: t.row });
  renderSet(); renderInfo(); invalidate();
}
function csvText() {
  const lines = ["tile_id,zone_id,res,col,row,xmin,xmax,ymin,ymax,crs"];
  for (const [id, t] of [...st.set.entries()].sort()) {
    const [x0, x1, y0, y1] = tileExt(t.col, t.row, t.res);
    lines.push([id, zid(t.zone), t.res, t.col, t.row, x0, x1, y0, y1, "EPSG:327" + String(t.zone).padStart(2, "0")].join(","));
  }
  return lines.join("\n");
}
function copyText(text, btn) {
  const done = ok => { if (!btn) return; const o = btn.textContent; btn.textContent = ok ? "Copied" : "Select and copy"; setTimeout(() => { btn.textContent = o; }, 1400); };
  try {
    navigator.clipboard.writeText(text).then(() => done(true), () => { $("set-list").select(); done(false); });
  } catch (e) { $("set-list").select(); done(false); }
}

// ---------------------------------------------------------------- set operations
function addLandTiles(res, x0, x1, y0, y1, inclShelf) {
  const t = tsz(res);
  const c0 = Math.max(0, Math.floor((x0 - st.ox) / t)), c1 = Math.floor((x1 - st.ox) / t);
  const r0 = Math.max(0, Math.floor((y0 - st.oy) / t)), r1 = Math.floor((y1 - st.oy) / t);
  const n = (c1 - c0 + 1) * (r1 - r0 + 1);
  if (n > 20000) return { added: 0, msg: `That view holds ${n.toLocaleString()} R${pad4(res)} tiles. Zoom in to under 20,000 and try again.` };
  let added = 0;
  for (let col = c0; col <= c1; col++) for (let row = r0; row <= r1; row++) {
    const [a, b, c, d] = tileExt(col, row, res);
    const hit = rectTouches(st.layers.land, a, b, c, d) || (inclShelf && rectTouches(st.layers.shelf, a, b, c, d));
    if (!hit) continue;
    const id = tileId(st.zone, res, col, row);
    if (!st.set.has(id)) { st.set.set(id, { zone: st.zone, res, col, row }); added++; }
  }
  return { added, msg: `Added ${added} R${pad4(res)} tile${added === 1 ? "" : "s"} touching land${inclShelf ? " or ice shelf" : ""}.` };
}
function growRing() {
  let added = 0;
  for (const t of [...st.set.values()]) {
    for (let dc = -1; dc <= 1; dc++) for (let dr = -1; dr <= 1; dr++) {
      const col = t.col + dc, row = t.row + dr;
      if (col < 0 || row < 0) continue;
      const id = tileId(t.zone, t.res, col, row);
      if (!st.set.has(id)) { st.set.set(id, { zone: t.zone, res: t.res, col, row }); added++; }
    }
  }
  return added;
}

// ---------------------------------------------------------------- interaction
const ptrs = new Map();
let drag = null, pinch = null;
function local(e) { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
function updateHover(x, y) {
  const X = wx(x), Y = wy(y);
  const ll = UTM.inv(X, Y, cmOf(st.zone));
  const [col, row] = tileAt(X, Y, st.active);
  st.hover = [col, row];
  const ok = col >= 0 && row >= 0;
  $("readout").innerHTML = `${fmtLL(ll[0], ll[1])}<br>x ${X.toFixed(0)}  y ${Y.toFixed(0)}  ${zid(st.zone)}<br>${ok ? tileId(st.zone, st.active, col, row) : "outside grid domain"}`;
  schedule();
}
function zoomAt(x, y, k) {
  const X = wx(x), Y = wy(y);
  st.s = clampS(st.s * k);
  st.cx = X - (x - st.W / 2) / st.s; st.cy = Y + (y - st.H / 2) / st.s;
  invalidate();
}
canvas.addEventListener("pointerdown", e => {
  canvas.setPointerCapture(e.pointerId);
  const p = local(e); ptrs.set(e.pointerId, p);
  if (ptrs.size === 1) drag = { x: p[0], y: p[1], cx: st.cx, cy: st.cy, moved: false, shift: e.shiftKey || e.metaKey || e.ctrlKey };
  if (ptrs.size === 2) {
    const [a, b] = [...ptrs.values()];
    pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]), s: st.s, mx: (a[0] + b[0]) / 2, my: (a[1] + b[1]) / 2, X: wx((a[0] + b[0]) / 2), Y: wy((a[1] + b[1]) / 2) };
    drag = null;
  }
});
canvas.addEventListener("pointermove", e => {
  const p = local(e);
  if (ptrs.has(e.pointerId)) ptrs.set(e.pointerId, p);
  if (pinch && ptrs.size === 2) {
    const [a, b] = [...ptrs.values()];
    const d = Math.hypot(a[0] - b[0], a[1] - b[1]), mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    st.s = clampS(pinch.s * d / Math.max(1, pinch.d));
    st.cx = pinch.X - (mx - st.W / 2) / st.s; st.cy = pinch.Y + (my - st.H / 2) / st.s;
    invalidate(); return;
  }
  if (drag) {
    const dx = p[0] - drag.x, dy = p[1] - drag.y;
    if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true;
    if (drag.moved) { st.cx = drag.cx - dx / st.s; st.cy = drag.cy + dy / st.s; invalidate(); }
  }
  updateHover(p[0], p[1]);
});
function endPtr(e) {
  const p = local(e);
  if (drag && !drag.moved && ptrs.size === 1) {
    const [col, row] = tileAt(wx(p[0]), wy(p[1]), st.active);
    const t = { zone: st.zone, res: st.active, col, row };
    if (drag.shift && col >= 0 && row >= 0) toggleSet(t);
    st.inspect = t; renderInfo(); invalidate();
  }
  ptrs.delete(e.pointerId);
  if (ptrs.size < 2) pinch = null;
  if (ptrs.size === 0) drag = null;
}
canvas.addEventListener("pointerup", endPtr);
canvas.addEventListener("pointercancel", e => { ptrs.delete(e.pointerId); pinch = null; drag = null; });
canvas.addEventListener("pointerleave", () => { if (!drag) { st.hover = null; schedule(); } });
canvas.addEventListener("wheel", e => { e.preventDefault(); const p = local(e); zoomAt(p[0], p[1], Math.exp(-e.deltaY * (e.deltaMode ? 0.05 : 0.0015))); }, { passive: false });
canvas.addEventListener("dblclick", e => { const p = local(e); zoomAt(p[0], p[1], 2); });
canvas.addEventListener("keydown", e => {
  const step = 0.15 * Math.min(st.W, st.H) / st.s;
  const k = e.key;
  if (k === "ArrowLeft") st.cx -= step; else if (k === "ArrowRight") st.cx += step;
  else if (k === "ArrowUp") st.cy += step; else if (k === "ArrowDown") st.cy -= step;
  else if (k === "+" || k === "=") { zoomAt(st.W / 2, st.H / 2, 1.5); e.preventDefault(); return; }
  else if (k === "-" || k === "_") { zoomAt(st.W / 2, st.H / 2, 1 / 1.5); e.preventDefault(); return; }
  else return;
  e.preventDefault(); invalidate();
});
$("zin").onclick = () => zoomAt(st.W / 2, st.H / 2, 1.6);
$("zout").onclick = () => zoomAt(st.W / 2, st.H / 2, 1 / 1.6);

// ---------------------------------------------------------------- controls
const zsel = $("zone");
for (let z = 36; z <= 60; z++) {
  const cm = cmOf(z);
  zsel.insertAdjacentHTML("beforeend", `<option value="${z}">${zid(z)} (${cm - 3} to ${cm + 3}&deg;E)</option>`);
}
zsel.onchange = () => {
  const ll = UTM.inv(st.cx, st.cy, cmOf(st.zone));
  const z = parseInt(zsel.value, 10);
  setZone(z);
  const p = UTM.fwd(ll[0], ll[1], cmOf(z)); st.cx = p[0]; st.cy = p[1];
  invalidate();
};
function specChanged(what) {
  const had = st.set.size;
  st.set.clear(); st.inspect = null;
  renderScheme(); renderInfo();
  renderSet(had ? `The ${what} changed, so the set was cleared: the same ids would now name different ground.` : "");
  invalidate();
}
function setPx(v) { if (!Number.isInteger(v) || v < 16 || v === st.px) { renderScheme(); return; } st.px = v; specChanged("tile size"); }
$("px600").onclick = () => setPx(600);
$("px720").onclick = () => setPx(720);
$("px").onchange = () => setPx(parseInt($("px").value, 10));
$("ox").onchange = () => { const v = parseInt($("ox").value, 10); if (Number.isFinite(v) && v !== st.ox) { st.ox = v; specChanged("origin"); } else renderScheme(); };
$("oy").onchange = () => { const v = parseInt($("oy").value, 10); if (Number.isFinite(v) && v !== st.oy) { st.oy = v; specChanged("origin"); } else renderScheme(); };
$("res").onchange = () => {
  const v = [...new Set($("res").value.split(/[^0-9]+/).map(s => parseInt(s, 10)).filter(n => n > 0 && n < 100000))].sort((a, b) => a - b);
  if (!v.length) { renderScheme(); return; }
  st.resList = v;
  if (!v.includes(st.active)) st.active = v[0];
  renderScheme(); renderInfo(); invalidate();
};
$("active").onchange = () => { st.active = parseInt($("active").value, 10); invalidate(); };

const presetBox = $("presets");
PRESETS.forEach(p => {
  const b = document.createElement("button"); b.type = "button"; b.className = "chip"; b.textContent = p.name;
  b.onclick = () => centreOn(p.lon, p.lat, p.km, p.zone);
  presetBox.appendChild(b);
});
$("goto-form").addEventListener("submit", e => {
  e.preventDefault();
  const v = $("goto").value.trim(), err = $("goto-err");
  err.hidden = true;
  const ids = parseIds(v);
  if (ids.length) {
    const t = ids[0];
    if (t.zone !== st.zone) setZone(t.zone);
    if (!st.resList.includes(t.res)) { st.resList = [...st.resList, t.res].sort((a, b) => a - b); }
    st.active = t.res; renderScheme();
    const [x0, x1, y0, y1] = tileExt(t.col, t.row, t.res);
    st.inspect = t; renderInfo();
    fitUTM(x0 - (x1 - x0) * 2, x1 + (x1 - x0) * 2, y0 - (y1 - y0) * 2, y1 + (y1 - y0) * 2);
    return;
  }
  const m = v.match(/^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (m) {
    const lon = parseFloat(m[1]), lat = parseFloat(m[2]);
    if (lat > -40 || lat < -84 || lon < -180 || lon > 180) { err.textContent = "Use longitude, latitude with latitude between -84 and -40."; err.hidden = false; return; }
    centreOn(lon, lat, 60);
    return;
  }
  err.textContent = "Enter longitude, latitude (for example 73.5, -53.1) or a tile id."; err.hidden = false;
});

$("add-land").onclick = () => {
  const vb = vbounds();
  const r = addLandTiles(st.active, vb.x0, vb.x1, vb.y0, vb.y1, $("incl-shelf").checked);
  renderSet(r.msg); renderInfo(); invalidate();
};
$("grow").onclick = () => { const n = growRing(); renderSet(`Added ${n} neighbouring tile${n === 1 ? "" : "s"}.`); renderInfo(); invalidate(); };
$("clear").onclick = () => { st.set.clear(); renderSet(); renderInfo(); invalidate(); };
$("copy-ids").onclick = e => copyText($("set-list").value, e.currentTarget);
$("copy-csv").onclick = e => copyText(csvText(), e.currentTarget);
$("show-ids").onclick = () => {
  st.cmp = parseIds($("paste").value);
  const zones = [...new Set(st.cmp.map(t => zid(t.zone)))];
  const here = st.cmp.filter(t => t.zone === st.zone).length;
  $("cmp-msg").textContent = st.cmp.length
    ? `${st.cmp.length} id${st.cmp.length === 1 ? "" : "s"} read, in ${zones.join(", ")}; ${here} in the current zone. Drawn with ${st.px} px tiles and origin ${st.ox} / ${st.oy}.`
    : "No tile ids found. Expected ids like 43S_R0010_0033_0571 or 43S_L1_0006_0114.";
  invalidate();
};
$("go-ids").onclick = () => {
  if (!st.cmp.length) $("show-ids").onclick();
  if (!st.cmp.length) return;
  const z = st.cmp[0].zone, ts = st.cmp.filter(t => t.zone === z);
  if (z !== st.zone) setZone(z);
  let a = Infinity, b = -Infinity, c = Infinity, d = -Infinity;
  for (const t of ts) { const e = tileExt(t.col, t.row, t.res); a = Math.min(a, e[0]); b = Math.max(b, e[1]); c = Math.min(c, e[2]); d = Math.max(d, e[3]); }
  fitUTM(a, b, c, d);
};

// ---------------------------------------------------------------- size + boot
let booted = false;
function resize() {
  const r = $("mapwrap").getBoundingClientRect();
  st.dpr = Math.min(window.devicePixelRatio || 1, 2);
  const W = Math.max(1, r.width), H = Math.max(1, r.height);
  if (booted) {
    // keep the centre; keep the scale
  }
  st.W = W; st.H = H;
  canvas.width = Math.round(W * st.dpr); canvas.height = Math.round(H * st.dpr);
  if (!booted) { booted = true; boot(); }
  invalidate();
}
function boot() {
  readTokens();
  renderScheme();
  const p = PRESETS[0];
  setZone(43);
  centreOn(p.lon, p.lat, p.km, 43);
  // Example working state: Heard Island land tiles at 10 m, one tile inspected
  const q0 = UTM.fwd(72.5, -53.25, cmOf(43)), q1 = UTM.fwd(73.95, -52.9, cmOf(43));
  const r = addLandTiles(10, q0[0], q1[0], q0[1], q1[1], false);
  renderSet(`Example: ${r.added} R0010 tiles touching Heard Island in the 720 px scheme. CGAZ does not include the McDonald Islands.`);
  const c = UTM.fwd(73.5, -53.1, cmOf(43)), [col, row] = tileAt(c[0], c[1], 10);
  st.inspect = { zone: 43, res: 10, col, row };
  renderInfo();
}
new ResizeObserver(resize).observe($("mapwrap"));
}
