/**
 * Citadel Defense leaderboard — Cloudflare Worker + KV.
 *
 * Endpoints
 *   POST /score        body: the entry JSON the game sends (see leaderboard.gd)
 *   GET  /top?board=daily|alltime   -> { entries: [...top 10] }
 *   GET  /claim/:id    -> tiny page confirming the entry (what the QR opens)
 *
 * Deliberately small: one KV namespace, two keys per board, no accounts.
 * Anti-abuse: run hash (salted), recomputed score, plausibility bounds,
 * per-IP rate limit, name profanity filter (extend BAD_WORDS before the event).
 */

const RUN_SALT = "erbil-1258-hold-the-gate"; // must match Config.RUN_SALT
const TOP_N = 10;
const KEEP_N = 200;
const WAVE_COUNT = 10;
const RATE_LIMIT_PER_MIN = 6;

// Starter list only. Fill in Kurdish (Sorani/Kurmanji), Arabic and English
// before HITEX. Matched case-insensitively as substrings after normalisation.
const BAD_WORDS = ["fuck", "shit", "bitch", "cunt", "nigg", "كس", "طيز", "خرا", "قحبة", "شرموط", "كير", "قون", "گ‌وو"];

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    try {
      if (url.pathname === "/score" && request.method === "POST") return await postScore(request, env);
      if (url.pathname === "/top" && request.method === "GET") return await getTop(url, env);
      if (url.pathname.startsWith("/claim/") && request.method === "GET") return await claimPage(url, env);
      if (url.pathname === "/" ) return json({ ok: true, service: "citadel-defense-leaderboard" });
      return json({ error: "not found" }, 404);
    } catch (e) {
      return json({ error: "server", detail: String(e) }, 500);
    }
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

function todayKey() {
  return new Date().toISOString().slice(0, 10); // UTC day; the booth resets at UTC midnight
}

async function sha256Hex(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function computeScore(rock, lives, waves, duration, won) {
  const speed = won ? Math.max(0, Math.floor(240 - duration)) * 3 : 0;
  return rock + lives * 500 + waves * 250 + speed;
}

function isProfane(name) {
  const n = name.toLowerCase().replace(/[\s._\-0-9]/g, "");
  return BAD_WORDS.some((w) => n.includes(w));
}

function validName(name) {
  if (typeof name !== "string") return false;
  const n = name.trim();
  if (n.length < 3 || n.length > 12) return false;
  return /^[\p{L}\p{N} _\-.]+$/u.test(n);
}

async function rateLimited(request, env) {
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const minute = Math.floor(Date.now() / 60000);
  const key = `rl:${ip}:${minute}`;
  const n = parseInt((await env.BOARD.get(key)) || "0", 10) + 1;
  await env.BOARD.put(key, String(n), { expirationTtl: 120 });
  return n > RATE_LIMIT_PER_MIN;
}

async function postScore(request, env) {
  if (await rateLimited(request, env)) return json({ error: "rate" }, 429);
  let e;
  try {
    e = await request.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const id = String(e.id || "");
  const name = String(e.name || "").trim();
  const score = Number(e.score), waves = Number(e.waves), lives = Number(e.lives);
  const rock = Number(e.rock), duration = Number(e.duration);
  const won = Boolean(e.won);

  if (!/^[A-Z2-9]{8}$/.test(id)) return json({ error: "bad id" }, 422);
  if (!validName(name)) return json({ error: "bad name" }, 422);
  if (isProfane(name)) return json({ error: "name rejected" }, 422);
  if (![score, waves, lives, rock, duration].every(Number.isFinite)) return json({ error: "bad numbers" }, 422);

  // Plausibility: bounds a real run cannot exceed.
  if (waves < 0 || waves > WAVE_COUNT) return json({ error: "impossible" }, 422);
  if (lives < 0 || lives > 3) return json({ error: "impossible" }, 422);
  if (won && (waves !== WAVE_COUNT || lives < 1)) return json({ error: "impossible" }, 422);
  if (!won && lives !== 0) return json({ error: "impossible" }, 422);
  // Max rock: every kill + every clear bonus across the whole table, with margin.
  if (rock < 0 || rock > 3500) return json({ error: "impossible" }, 422);
  if (duration < 30 || duration > 3600) return json({ error: "impossible" }, 422);
  if (computeScore(rock, lives, waves, duration, won) !== score) return json({ error: "score mismatch" }, 422);

  const expect = await sha256Hex(`${RUN_SALT}|${name}|${score}|${waves}|${lives}|${rock}|${Math.trunc(duration)}`);
  if (expect !== e.hash) return json({ error: "bad hash" }, 422);

  const entry = { id, name, score, waves, lives, rock, duration, won, date: todayKey(), ts: Math.floor(Date.now() / 1000) };

  const dup = await env.BOARD.get(`entry:${id}`);
  if (dup) return json({ error: "duplicate" }, 409);
  await env.BOARD.put(`entry:${id}`, JSON.stringify(entry), { expirationTtl: 60 * 60 * 24 * 90 });

  await addToBoard(env, `board:daily:${todayKey()}`, entry, 60 * 60 * 24 * 3);
  await addToBoard(env, `board:alltime`, entry, undefined);
  return json({ ok: true, id });
}

async function addToBoard(env, key, entry, ttl) {
  const list = JSON.parse((await env.BOARD.get(key)) || "[]");
  list.push(entry);
  list.sort((a, b) => (b.score - a.score) || (a.ts - b.ts));
  const trimmed = list.slice(0, KEEP_N);
  const opts = ttl ? { expirationTtl: ttl } : {};
  await env.BOARD.put(key, JSON.stringify(trimmed), opts);
}

async function getTop(url, env) {
  const board = url.searchParams.get("board") === "alltime" ? "alltime" : "daily";
  const key = board === "alltime" ? "board:alltime" : `board:daily:${todayKey()}`;
  const list = JSON.parse((await env.BOARD.get(key)) || "[]");
  return json({ board, entries: list.slice(0, TOP_N) });
}

async function claimPage(url, env) {
  const id = url.pathname.split("/")[2] || "";
  const raw = await env.BOARD.get(`entry:${id}`);
  const e = raw ? JSON.parse(raw) : null;
  const body = e
    ? `<h1>${escapeHtml(e.name)}</h1><p>Score <b>${e.score}</b> · wave ${e.waves} · ${e.won ? "gate held" : "gate fell"}</p>
       <p>Show this screen at the booth to collect your tower.</p><p class=id>${id}</p>`
    : `<h1>Not found</h1><p>This claim code is unknown. Ask at the booth.</p>`;
  const html = `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Citadel Defense</title><style>body{font-family:system-ui;background:#0a1633;color:#f4ecd8;text-align:center;padding:40px 20px}
h1{color:#f2c14e}.id{font-size:40px;letter-spacing:6px;color:#e3c48a}</style>${body}`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
