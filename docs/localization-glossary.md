# Oryne Localization — Simplified Chinese Glossary

Oryne ships **English (base) + Simplified Chinese (`zh-Hans`)**. The language is
chosen through the **standard iOS per-app control** (Settings › Oryne › Language);
there is no in-app language toggle. UI strings live in the String Catalog at
`Oryne/Resources/Localizable.xcstrings` (value-as-key: the English source string is
the key). Only static interface text is localized — AI-derived titles, themes, and
link summaries (Foundation Models) and speech transcription keep their own language.

**When adding new Chinese strings, follow this glossary** so terminology stays
consistent. Translate by *meaning* in the register of Chinese inspiration/note apps
(flomo, Cubox, Apple Notes, Bear, Notion) — natural and restrained, never literal /
translation-ese. Signature/poetic lines are marked `needs_review` in the catalog for a
human copy pass.

---

## 1. Core / brand terms (English → 简体中文)

| English | 简体中文 | Notes |
|---|---|---|
| Oryne | Oryne | Brand name — keep in English |
| Ocean / the Ocean | 海洋 | **FIXED**. Poetic lines may use 「海」 for flow; the proper noun is always 海洋 |
| Whisper | 语音 | **FIXED** (not 低语). "Catch a whisper"→记一段语音; "Whisper held"→语音已留存 |
| Thought / Thoughts | 灵感 | **FIXED** (not 想法). "Edit thought"→编辑灵感; "Delete this thought?"→删除这条灵感？ |
| Library | 库 | **FIXED** (not 书库) |
| Ask / Ask the Ocean | 提问 | **FIXED**. "Ask the Ocean"/"Ask Ocean"→提问 (not 向海提问/问海) |
| **Branch (verb/noun)** | **延展** | **Canonical** — used everywhere; never 分支/生长 |
| Grow a branch | 延展一条灵感 | |
| Branching from | 延展自 | |
| Branches grown from this | 由此延展的灵感 | |
| Branch type | 延展类型 | |
| Grow / grow an idea | 培育 | "Help me grow an idea…"→帮我培育一个灵感…… |
| Inspiration | 灵感 | Same as Thought; "Add Inspiration"→记录灵感 |
| Capture (verb/noun/tab) | 捕捉 | "Captured"→已捕捉 |
| Fast Capture | 快速捕捉 | Feature name — keep consistent |
| Context Capture | 情境捕捉 | |
| fragment / fragments | 碎片 | "%lld fragments"→%lld 个碎片 |
| Release / Release into the Ocean | 汇入海洋 | Save action. "Release"→汇入; "Released"→已汇入 |
| Save to Ocean | 存入海洋 | Use 存入 when distinguished from Release |
| Resurfacing | 再次浮现 | |
| Themes | 主题 | |
| Transcript | 文字记录 | |
| Transcribe / Re-transcribe | 转写 / 重新转写 | "Transcribing…"→转写中…… |
| Listen / Listen to recording | 播放 / 播放录音 | Not 收听 |
| Record / Stop / Pause | 录音 / 停止 / 暂停 | |
| Link | 链接 | |
| Image | 图片 | |
| Screenshot | 截图 | "Take Screenshot"→截屏 (action); noun 截图 |
| Note | 备注 | |
| Calm Accessibility (Mode) | 宁静无障碍（模式） | |

### NodeKind labels
| Thought | Whisper | Image | Link | Voice |
|---|---|---|---|---|
| 灵感 | 语音 | 图片 | 链接 | 语音 |

### BranchType (延展类型)
| Question | Concept | Research | Project |
|---|---|---|---|
| 问题 | 概念 | 研究 | 项目 |

### DialogueMode
| Search | Synthesis | Expansion | Research |
|---|---|---|---|
| 搜索 | 综合 | 延展 | 研究 |

### Common buttons (terse)
| Settings | Done | Cancel | Save | Delete | Edit | Close | Keep |
|---|---|---|---|---|---|---|---|
| 设置 | 完成 | 取消 | 保存 | 删除 | 编辑 | 关闭 | 保留 |

| Discard | Restore | Archive | Retry | Continue | Skip | Previous | Undo | Replace | Reference |
|---|---|---|---|---|---|---|---|---|---|
| 舍弃 | 恢复 | 归档 | 重试 | 继续 | 跳过 | 上一步 | 撤销 | 替换 | 参考 |

---

## 2. The "drift" ocean motif — translate by sense, not 漂

"drift" is Oryne's core image, but render it by **actual meaning** rather than blanket 漂:

| Sense | Rendering | Example |
|---|---|---|
| flash past / just went by | 闪过 | "What just drifted by?"→刚刚闪过什么？ |
| surface / rise | 浮现、浮起 | "Return when something rises."→有什么浮起时，再回来。 |
| near / related | 相关、相近 | "Nearby thoughts"→相关灵感; "Drifts near “%@”"→与「%@」相近 |
| received into the Ocean | 汇入 | "Drifted into the Ocean"→已汇入海洋 |
| emanate / flow outward | 漫出、流淌 | "Drifting out from your thought…"→正从你的灵感漫出…… |
| train of thought | 漂向 (poetic only, sparingly) | "How has my thinking drifted lately?"→我的思绪最近漂向了何处？ |
| permanent removal (delete copy) | 离开海洋 | "This drifts out of the Ocean for good."→这条灵感将永远离开海洋。 |

Match/search (non-poetic) lines always use 相关, never 漂在附近:
- "Found %lld fragments that drift near this"→找到 %lld 个相关的碎片

---

## 3. Consistency rulings

- **Thought=灵感 vs Inspiration=灵感**: same word, disambiguated by context; never collide on one screen. Branch (延展) is decoupled from both.
- **Release vs Save**: saving to the Ocean defaults to 汇入海洋; use 存入 only when Save must be distinguished from Release.
- **Expansion (mode) vs Branch (action)**: both render as 延展 — contexts don't conflict, and shared wording reinforces consistency.
- **Listen=播放** (playback) must not be confused with 聆听中 (Listening…, the recording state).

---

## 4. Style rules

1. **Full-width punctuation** (？！，：、；) and 「」 for in-app proper nouns. **Keep the source `…` ellipsis (single char)** — never 「......」.
2. **Preserve placeholders verbatim, never rewrite or drop them**: `%lld`, `%@`, `${text}`, `${image}`, `${screenshot}`. Reorder around them for Chinese word order, but don't alter the token.
   - `Add ${text} to Oryne` → 将 ${text} 添加到 Oryne
   - `Start Context Capture with ${screenshot}` → 用 ${screenshot} 开始情境捕捉
3. **Buttons/labels**: terse, verb-first (捕捉、汇入、播放、提问).
4. **Sentences**: smooth product copy; no stacked modifiers; avoid stiff imagery like 漂浮于此.
5. **Poetic lines (`needs_review`)**: keep a touch of ocean imagery but read like real Chinese copy, not translation-ese. Image serves meaning — less 漂, more 对味.
6. **Global consistency**: one Chinese rendering per English term across the whole app; the FIXED entries and 延展 are hard rules.
