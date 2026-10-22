# Memory layer: a denser understanding of every thought, and an Ask that can use it

Status: decided 2026-10-22 (Malik). Phase 1 in progress on branch
`am/apple-intelligence-oryne-248869`.

## Why

Oryne's memory today is one layer: up to three free-text themes on each
thought, doing three jobs at once (the chips, the clustering key, and a
retrieval boost). Nothing records what kind of thought it is, which
language it is in, who or what it mentions, or how it relates to anything
but its parent. Currents are a side effect of two thoughts producing the
same theme string. Ask retrieves by one embedding cosine over the whole
Ocean and composes one four-sentence reflection; it cannot list, count,
filter, translate, or cross languages (a Chinese question never reaches an
English thought: Apple's embeddings live in per-script spaces).

The reference points are what mature memory systems share: the raw content
is never touched; a small, dense, structured layer sits on top; a periodic
consolidation keeps it honest; the user can see and delete it. (Claude's
memory: one typed fact per file, an index loaded every session, update not
duplicate. ChatGPT: explicit saved memories always in context, chat-history
details chosen and revised by the system. Mem0: extract, then decide
add / update / delete / no-op per memory.)

## Decisions (Malik, 2026-10-22)

1. **Categories.** Eight, fixed: idea, task, bug, note, quote, question,
   link, memory. Shown in the Library as a filter (phase 2), on the
   thought's page, and queryable by Ask.
2. **Currents become entities** with a stable key, a name the user can
   change, merge and split, a model-written description. Existing
   string-grouped currents migrate once.
3. **One Ocean across languages.** Theme keys are language-neutral English
   slugs with a label per language, so 光与色彩 and "light and color" are
   one current. (Replaces today's per-language candidate split.)
4. **"What Oryne knows about you"** is a Settings page: a short list of
   typed, editable, deletable records.
5. **Memory syncs through iCloud; vectors do not.** Everything written
   below is small text and lives in SwiftData, mirrored by CloudKit like
   the rest of the Ocean, so a new device has it all. Embedding vectors are
   derived, large, and tied to the device's model version, so they live in
   a local cache and are recomputed from the synced text.
6. **Re-understanding after a model upgrade** reruns derived fields only.
   Anything the user edited is never touched.
7. **Consolidation** runs at most once a day, only while charging
   (BGProcessingTask with `requiresExternalPower`).

## The four layers

### 1. The understanding record (per thought)

Produced at capture by one guided-generation call on the on-device model
(`FoundationThoughtReader`), with a deterministic fallback. New fields on
`Node`, all defaulted for CloudKit:

| field | type | from | notes |
|---|---|---|---|
| `categoryRaw` | String? | model | one of the eight; nil = not yet read |
| `languageRaw` | String? | heuristic | zh / en / mixed, by Han share of letters |
| `gistOther` | String? | model | one line in the other language (Chinese for an English thought, English for Chinese or mixed) |
| `entities` | [String] | model | people, places, products, projects; at most 4 |
| `themeKeys` | [String] | model + slug | English, slugged (`light-and-color`); for an English thought the slug of its themes, for a Chinese thought the model's English rendering |
| `statusRaw` | String? | user only | open / done, for task and bug; the system never sets it |
| `understandingVersion` | Int | system | `ThoughtReading.version` when the model produced the record; 0 otherwise, so a later open with a model can enrich it |
| `understandingSourceRaw` | String? | system | model / concepts |

Existing fields keep their meaning: `title` is the essence, `themes` are
the labels in the thought's own language (still the chips and, until
phase 3, still the current key), `mood` stays.

The ownership contract is unchanged: `titleEditedByUser` and
`themesEditedByUser` are final; the new fields are system fields until a
UI lets the user edit them, at which point they get their own flags.

Retrieval uses two vectors per thought, one for its own text and one for
`gistOther`, so a question is compared against each thought in the
question's own language. Vectors are cached on disk per device (layer 5
decision), keyed by backend and text.

### 2. Currents as entities (phase 3)

A `Current` model: `key` (the language-neutral slug), `labels` per
language, `pinnedName` (the user's, final), `summary` (model-written,
refreshed on membership change), `createdAt`, `updatedAt`, `mergedFrom`.
`Node.currentKey` moves from "first theme string" to a key. Migration:
every distinct string key becomes a Current whose label is that string;
Chinese and English currents the model judges to be one topic are merged
with the user's confirmation, never silently.

### 3. What Oryne knows about you (phase 4)

A `MemoryRecord` model: `kind` (concern / project / person / preference /
habit), `text` (one line), `evidenceNodeIDs`, `createdAt`, `updatedAt`,
`userEdited`. Written only by consolidation, read by Ask as a capped
(about 300 tokens) preamble. Shown in Settings; every record deletable.

### 4. Conversation memory (phase 5)

Ask threads are listed and resumable; a thread's sources carry into the
next turn; a long thread gets a model summary. Small on purpose.

## Consolidation (phase 4)

A daily background task while charging: fill missing understanding
records, re-embed with a new model version, propose current merges (user
confirms), and maintain the MemoryRecords with add / update / delete /
no-op decisions made by the model over the recent captures. User edits
teach: a renamed current becomes the label, a corrected category becomes
an example in the reader's prompt.

## What this gives Ask (phase 2)

Tools over the record instead of one prompt: find thoughts by meaning in
either language, list by category / current / date range / entity, read
one thought in full, translate, and later web search. The model decides
which to call; guided generation shapes the final answer. Token budgeting
by `tokenCount(for:)` rather than character cuts. The on-device model runs
all of this on iOS 26; the server model (iOS 27, PCC) slots in behind an
availability check for synthesis and long sets.

## Phases

| | scope | lands |
|---|---|---|
| 1 | Understanding record on Node; one guided reading call with fallback; per-language vectors and a disk cache; backfill on Library open; Mac eval for the reading prompt | this branch |
| 2 | Ask as an agent with tools; category filter in the Library and on the thought page; token budgeting | next |
| 3 | Current entity, migration, rename / merge / split, bilingual merge | |
| 4 | MemoryRecord, Settings page, consolidation task | |
| 5 | Conversation memory | |

Each phase that adds a model field needs the CloudKit schema initialized
(`OCEAN_INIT_CLOUDKIT_SCHEMA=1` on a Debug build on an iCloud-signed
device) and deployed to Production before shipping; the deploy is Malik's
call.

## Budget and privacy

The on-device window is 4K tokens on iOS 26 (8K on newer devices on iOS
27). The reading call fits a thought of a few hundred words with room to
spare; longer whispers are read from their summary. Everything in this
document runs on the device; nothing leaves it unless the cloud seam is
configured, and then only what retrieval already selected.
