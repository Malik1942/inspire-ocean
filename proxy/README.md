# Oryn cloud proxy (Phase 1)

A thin Cloudflare Worker that carries the Anthropic API key so the app never
does. Four purpose-shaped endpoints mirror the app's four Claude uses — the
server owns every system prompt, model choice, and token budget, so an
extracted endpoint cannot be repurposed as a general LLM.

The app stays local-first: when this proxy is unreachable, rate-limited, or
not yet deployed, `CloudOceanAIService` already falls back to the grounded
on-device response. Nothing here makes Oryn cloud-dependent.

## Endpoints

| Route             | Purpose                  | Model          | max_tokens |
| ----------------- | ------------------------ | -------------- | ---------- |
| `POST /v1/register`   | mint anonymous install token | —          | —          |
| `POST /v1/reflect`    | dialogue reflection      | MODEL_REFLECT  | 1024       |
| `POST /v1/outward`    | Research's outward note  | MODEL_REFLECT  | 512        |
| `POST /v1/branches`   | Expansion's branch leaps | MODEL_FAST     | 160        |
| `POST /v1/understand` | capture title + themes   | MODEL_FAST     | 96         |

Request shapes (all JSON, all clamped server-side):

- `/v1/reflect` — `{ query, mode, fragments: [string ≤600] ≤12, history: [{user, text}] ≤6 }`
- `/v1/outward` — `{ query, titles: [string] ≤6 }`
- `/v1/branches` — `{ query, fragments }`
- `/v1/understand` — `{ text }`

All model routes require `Authorization: Bearer <token>` from `/v1/register`.
Responses are `{ text }` — the app parses them exactly as it parses the
direct Anthropic replies today (`kind: title` lines, two-line understand).

## Deploy

```bash
cd proxy
npx wrangler kv namespace create OCEAN_KV   # paste the id into wrangler.toml
npx wrangler secret put ANTHROPIC_API_KEY   # key from a DEDICATED workspace
npx wrangler deploy
```

Set a **monthly spend cap** on the workspace in the Anthropic console — that
is the true worst-case bound, independent of anything in this Worker.

Smoke test:

```bash
TOKEN=$(curl -s -X POST https://oryn-cloud.<you>.workers.dev/v1/register | jq -r .token)
curl -s -X POST https://oryn-cloud.<you>.workers.dev/v1/understand \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"text":"The tide keeps returning my ideas"}'
```

## Design notes / honest caveats

- **Prompts are ported verbatim** from `LocalOceanAIService` (the shared
  statics). If you change the voice in Swift, change it here too.
- **Rate limits are approximate.** KV counters are read-then-write, so
  concurrent requests can slip past by a few — an abuse bound, not
  billing-grade accounting. Durable Objects would make them exact; not
  worth it for v1.
- **`/v1/register` is the soft spot.** It is only IP-rate-limited, so a
  determined abuser can mint tokens from many IPs. The global daily cap
  bounds the damage. Phase 2 replaces registration with App Attest
  (`DCAppAttestService`) so only the genuine app can obtain tokens.
- **No content is logged or stored** — only route names and counts. Say in
  the privacy policy that Ask fragments transit this proxy; retain nothing.
- **Cost levers**: titles fire on every capture, hence Haiku for
  `/v1/understand` and `/v1/branches`. Drop `MODEL_REFLECT` to
  `claude-sonnet-4-6` if reflection spend matters before scale does.

## Swift side (when wiring up)

`CloudOceanAIService.Configuration` becomes `{ endpoint, deviceToken }`:
on first launch call `/v1/register`, keep the token in the **Keychain**
(never UserDefaults), and point the four `completeText` call sites at the
four routes. The DEBUG-gated direct-key path can remain for local dev with
a mock server; Release uses only the proxy.
