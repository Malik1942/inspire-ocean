// Oryn cloud proxy — Phase 1 (Cloudflare Worker).
//
// The Anthropic key lives ONLY here, as a Worker secret. The app never sees
// it. Four purpose-shaped endpoints mirror the app's four Claude uses; the
// server owns every system prompt, model choice, and token budget, so an
// extracted endpoint is useless as a general-purpose LLM — the most an
// abuser can obtain is "a few calm sentences about fragments they typed".
//
// Auth (Phase 1): anonymous install tokens from POST /v1/register, stored
// hashed in KV, rate-limited per device and globally per day. Honest caveat:
// register itself is only IP-limited, so a determined abuser can mint
// tokens — the global daily cap bounds the damage until Phase 2 replaces
// this with App Attest verification.
//
// Privacy: request bodies are never logged or stored; only route + count.

// ---------------------------------------------------------------- prompts
// Ported verbatim from LocalOceanAIService so proxy and on-device tiers
// speak with the same voice. If you edit these, edit the Swift twins.

const REFLECTION_VOICE =
  "You are the quiet, reflective voice of a personal inspiration space " +
  "called the Ocean. You answer ONLY from the user's own captured " +
  "fragments, provided below. Write 2 to 4 calm sentences in plain " +
  "prose — no lists, no headers, no advice-column tone, no exclamation " +
  "marks. Refer to fragments by their quoted titles. Each fragment notes " +
  "when it was captured and its mood — you may quietly draw on how the " +
  "thread has moved over time. If a pattern or question sits underneath " +
  "the fragments, name it plainly. Never invent fragments that are not " +
  "provided.";

const OUTWARD_VOICE =
  "You are the outward-looking voice of a personal inspiration space " +
  "called the Ocean. The user's own notes are answered separately — you " +
  "bring what lies beyond them. From your general knowledge, name two or " +
  "three specific directions worth exploring: thinkers, works, fields, " +
  "or open questions that genuinely extend their interest. Write 2 to 4 " +
  "calm sentences in plain prose — no lists, no exclamation marks. Be " +
  "concrete with names. Never pretend to quote their notes, and never " +
  "invent notes.";

const BRANCH_VOICE =
  'You suggest growth directions ("branches") for thoughts in a personal ' +
  "inspiration space. Reply with EXACTLY two or three lines, each formatted " +
  "`kind: title` and nothing else. kind is one of question, concept, " +
  "project, research. Each title is at most nine words, concrete and " +
  "speculative, and each line should be a different kind of leap — a bridge " +
  "to another domain, a metaphorical reframing, or a physical form it could " +
  "take. Never restate their fragments.";

const UNDERSTAND_VOICE =
  "You interpret entries in a personal inspiration journal.\n" +
  "Reply with EXACTLY two lines and nothing else.\n" +
  "Line 1: a title of at most 6 words — capture the essence or feeling " +
  "rather than restating the text; no quotation marks, no trailing punctuation.\n" +
  "Line 2: 1 to 3 conceptual themes, comma-separated, each one to three " +
  "lowercase words. A theme names the underlying concept, intention, " +
  "emotion, or domain — what the entry is really about, never words " +
  "copied from it. Examples: creative direction, career uncertainty, " +
  "recurring thoughts, social energy, emotional friction.";

const MODE_FRAMING = {
  search: "They are looking for something they captured.",
  synthesis:
    "They want to see the thread running through these fragments — how it " +
    "has drifted over time, where it tightens, what stays unresolved. Name " +
    "the quiet pattern underneath, gently; interpret rather than summarize.",
  expansion:
    "They want to grow these thoughts further. Offer one unexpected angle — " +
    "a bridge to another domain, a metaphorical reframing, or a physical " +
    "form it could take — without losing their voice.",
  research: "They want directions worth exploring next.",
};

// ------------------------------------------------------------- validation

const clamp = (s, n) => String(s ?? "").slice(0, n);

function clampFragments(fragments) {
  if (!Array.isArray(fragments)) return [];
  return fragments.slice(0, 12).map((f) => clamp(f, 600));
}

function clampHistory(history) {
  if (!Array.isArray(history)) return [];
  return history.slice(-6).map((t) => ({
    user: Boolean(t?.user),
    text: clamp(t?.text, 400),
  }));
}

function historyLines(history) {
  return history
    .map((t) => (t.user ? "They said: " : "You said: ") + t.text)
    .join("\n");
}

// ------------------------------------------------------------ token store

async function sha256(text) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text)
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function mintToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function authedDevice(request, env) {
  const header = request.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) return null;
  const hash = await sha256(token);
  const known = await env.OCEAN_KV.get(`tok:${hash}`);
  return known ? hash : null;
}

// ----------------------------------------------------------- rate limits
// KV increments are read-then-write, so limits are approximate under
// concurrency — fine as an abuse bound, not billing-grade accounting.
// Move counters to a Durable Object if exactness ever matters.

const today = () => new Date().toISOString().slice(0, 10);

async function underLimit(env, key, limit) {
  const count = parseInt((await env.OCEAN_KV.get(key)) ?? "0", 10);
  if (count >= limit) return false;
  await env.OCEAN_KV.put(key, String(count + 1), {
    expirationTtl: 60 * 60 * 48,
  });
  return true;
}

// -------------------------------------------------------------- anthropic

async function complete(env, { system, user, maxTokens, model, thinking }) {
  const body = {
    model,
    max_tokens: maxTokens,
    system,
    messages: [{ role: "user", content: user }],
  };
  if (thinking) body.thinking = { type: "adaptive" };

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`anthropic ${response.status}`);
  }
  const data = await response.json();
  return (data.content ?? [])
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("");
}

// ------------------------------------------------------------------ calls
// Each endpoint builds its prompt server-side from clamped client fields.

const CALLS = {
  "/v1/reflect": (env, p) => {
    const framing = MODE_FRAMING[p.mode] ?? MODE_FRAMING.synthesis;
    const turns = historyLines(clampHistory(p.history));
    const fragments = clampFragments(p.fragments).join("\n");
    if (!fragments) throw badRequest("fragments required");
    return {
      system: REFLECTION_VOICE,
      user:
        `${framing}\n` +
        (turns ? `Recent conversation:\n${turns}\n` : "") +
        `\nTheir fragments:\n${fragments}\n\nTheir question: ` +
        clamp(p.query, 4000),
      maxTokens: 1024,
      model: env.MODEL_REFLECT,
      thinking: true,
    };
  },

  "/v1/outward": (env, p) => {
    const titles = (Array.isArray(p.titles) ? p.titles : [])
      .slice(0, 6)
      .map((t) => clamp(t, 200))
      .join(", ");
    const query = clamp(p.query, 4000);
    if (!query) throw badRequest("query required");
    return {
      system: OUTWARD_VOICE,
      user: titles
        ? `They are exploring: ${query}\nTheir related notes touch on: ${titles}`
        : `They are exploring: ${query}`,
      maxTokens: 512,
      model: env.MODEL_REFLECT,
      thinking: true,
    };
  },

  "/v1/branches": (env, p) => {
    const fragments = clampFragments(p.fragments).join("\n");
    if (!fragments) throw badRequest("fragments required");
    return {
      system: BRANCH_VOICE,
      user:
        `Their question: ${clamp(p.query, 4000)}\n` +
        `Their fragments:\n${fragments}`,
      maxTokens: 160,
      model: env.MODEL_FAST,
      thinking: false,
    };
  },

  "/v1/understand": (env, p) => {
    const text = clamp(p.text, 4000).trim();
    if (!text) throw badRequest("text required");
    return {
      system: UNDERSTAND_VOICE,
      user: `Entry:\n${text}`,
      maxTokens: 96,
      model: env.MODEL_FAST,
      thinking: false,
    };
  },
};

// ------------------------------------------------------------------ http

const json = (object, status = 200) =>
  new Response(JSON.stringify(object), {
    status,
    headers: { "Content-Type": "application/json" },
  });

function badRequest(message) {
  const error = new Error(message);
  error.status = 400;
  return error;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    // -- registration: mint an anonymous install token -------------------
    if (url.pathname === "/v1/register") {
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipHash = (await sha256(ip)).slice(0, 16);
      const ok = await underLimit(
        env,
        `rl:reg:${ipHash}:${today()}`,
        parseInt(env.REGISTER_DAILY_LIMIT, 10)
      );
      if (!ok) return json({ error: "try again tomorrow" }, 429);

      const token = mintToken();
      await env.OCEAN_KV.put(
        `tok:${await sha256(token)}`,
        JSON.stringify({ created: today() })
      );
      console.log("register ok");
      return json({ token });
    }

    // -- model calls ------------------------------------------------------
    const build = CALLS[url.pathname];
    if (!build) return json({ error: "not found" }, 404);

    const device = await authedDevice(request, env);
    if (!device) return json({ error: "unauthorized" }, 401);

    const deviceOk = await underLimit(
      env,
      `rl:dev:${device}:${today()}`,
      parseInt(env.DEVICE_DAILY_LIMIT, 10)
    );
    if (!deviceOk) return json({ error: "daily limit reached" }, 429);

    const globalOk = await underLimit(
      env,
      `rl:global:${today()}`,
      parseInt(env.GLOBAL_DAILY_LIMIT, 10)
    );
    if (!globalOk) return json({ error: "service at capacity today" }, 503);

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: "invalid json" }, 400);
    }

    try {
      const call = build(env, payload);
      const text = await complete(env, call);
      console.log(`${url.pathname} ok`);
      return json({ text });
    } catch (error) {
      const status = error.status ?? 502;
      console.log(`${url.pathname} error ${status}`);
      return json({ error: error.message ?? "upstream failure" }, status);
    }
  },
};
