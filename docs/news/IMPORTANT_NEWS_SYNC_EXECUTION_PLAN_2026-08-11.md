# Important News rework: BIR-sourced news + automatic deadline overrides

Status: implemented and dry-run against the live BIR site; pending review.
Date: 2026-08-11 (Asia/Manila). Branch: `gol/important-news-google-search-8efadb`.
Author input: replace the Official Gazette RSS feed with BIR's own publications,
extract deadline-extension issuances (e.g. RMC No. 89-2026), and turn them into
calendar deadline overrides that move the dashboard markers.

This plan is written so that each task can be executed mechanically, in order,
by an implementation agent without further research. Every claim about live
BIR endpoints below was verified by direct probing on 2026-08-11; the captured
evidence is committed under `scripts/news-sync/fixtures/2026-08-11/`.

Progress: 29/31 tasks complete (see §6 checkboxes).

**Start here for remaining work:** [NEXT_STEPS.md](NEXT_STEPS.md) — the
remaining-work plan: phases R1–R4 (defect fixes → commit/PR → live dry-run →
first publish), the four decisions awaiting the author, and the backlog.

---

## 0. What this delivers

1. A **deterministic sync pipeline** (`scripts/news-sync/`, TypeScript, no AI,
   no new npm dependencies) that:
   - reads BIR's own CMS JSON API (the same API the bir.gov.ph homepage uses),
   - detects new issuances (RMC/RMO/RR/…) and skips already-seen ones,
   - downloads the issuance PDF for deadline-extension circulars,
   - extracts **affected RDOs**, **original due dates**, **extended due
     dates**, and **affected forms**, distinguishing **eBIRForms/manual
     (non-eFPS)** rows from **eFPS group** rows,
   - compiles one versioned `feed.json` consumed by the app, plus a
     human-readable review report per extracted circular.
2. A **scheduler** that runs the pipeline four times a day at 06:00, 12:00,
   18:00, and 00:00 Asia/Manila and publishes `feed.json`.
3. **App changes** (Zig) so that:
   - Important News is fetched from `feed.json` (source label “BIR”), not the
     Official Gazette RSS,
   - the Global Dashboard news pane shows only the notices whose issue month
     matches the calendar month being viewed, with a default message when a
     month has none,
   - feed overrides are ingested into the existing `calendar_overrides` SQLite
     policy store (schema v3) with a stable external identity, so re-syncs
     update rather than duplicate (“skip duplicates”),
   - overrides are **RDO-scoped**: the taxpayer calendar applies them through
     the profile's RDO (this wiring already exists), and the Global Dashboard
     gains an optional RDO context selector so its markers can move too.

Worked example (the acceptance scenario for the whole feature): RMC No.
89-2026 extends deadlines falling 2026-08-10…08-16 to **2026-08-17** for 58
BIR offices. After sync, a profile registered under RDO 039 (South Quezon
City) sees the 1601C/0619E/0619F marker dot on **Aug 17** (status
“Extended”, source “RMC No. 89-2026”), not Aug 10. eFPS rows (Aug 11/13/14
groups) do **not** move anything, because the app models non-eFPS deadlines.
The dashboard news pane for August shows the RMC 89-2026 notice; switching to
July shows only July notices; a month with none shows the default message.

---

## 1. Verified facts

### 1.1 Live sources (probed 2026-08-11, evidence in fixtures)

| # | Fact | Detail |
| --- | --- | --- |
| S1 | bir.gov.ph is a Next.js SPA; the “What's New” list is **not** in the static HTML. | Plain `curl` of `/home` returns a 132 KB shell without the issuance list. |
| S2 | The site reads a public CMS API: `https://bir-cms-ws.bir.gov.ph/api/pub/templates/{id}/datasets`. | Works from `curl` with exactly two extra headers: `client-website-id: 2` and `origin: https://www.bir.gov.ph`. Missing headers → `403 forbidden`. No cookies, no tokens. |
| S3 | Template **9** = “News and Updates - New Issuances” (the homepage widget). | One dataset; `content.Issuance` is an HTML blob listing the latest issuances with `more` anchors to PDF URLs on `bir-cdn.bir.gov.ph`. **No dates** in this blob. |
| S4 | There is **one yearly archive per issuance kind**, each its own template: **3752** = “2026 Revenue Memorandum Circulars”, **3753** = “2026 Revenue Memorandum Orders”, **3754** = “2026 Revenue Regulations”. | One dataset each; `content.Content` is one HTML `<table>` with the same three columns: `NO. OF ISSUANCE | SUBJECT | DATE OF ISSUE` (90 / 20 / 5 rows at capture time), each row with a `Full Text` anchor to the PDF and a date like `August 10, 2026`. This is where publication dates come from — an RMO or RR is dated only if its own archive is fetched. |
| S5 | Yearly template IDs are discoverable without a browser, per kind. | `GET https://www.bir.gov.ph/{year}-{Revenue-Memorandum-Circulars\|Revenue-Memorandum-Orders\|Revenue-Regulations}` embeds the id in the served HTML — **backslash-escaped**, because it sits inside a JS string literal in the RSC payload: `\"code\":\"3753\",\"dataMapper\":{\"content\":\"Content\"}`. Regex it out tolerating both the escaped and bare forms; keep a checked-in `(kind, year)` map as fallback. |
| S6 | Template **1135** = “BIR Tax Calendar” — 169 dated entries with per-day deadline HTML, including eFPS group staggering. | Not used in v1; recorded as a future cross-check source. |
| S7 | RMC PDFs are scans **with an embedded OCR text layer**. | `pdftotext -layout` on RMC 89-2026 yields usable text with real OCR noise: `A]ugttst 17,2026`, `RDONo.T- Abra`, `RDO No. 4l`, `06 1 9-F`. Noise-tolerant parsing is mandatory. See `fixtures/2026-08-11/CAPTURES.md`. |
| S8 | RMC 89-2026 ground truth. | 58 offices (53 regular RDOs + 5 LT divisions), extension window Aug 10–16 → Aug 17, deadline table distinguishes `Non-eFPS Filers` (due Aug 10) from `eFPS Filers under Group E/D/B…` (due Aug 11/13/14…). Full expected extraction in Appendix A. |

### 1.2 Existing app machinery (all already merged on `main`)

| Area | What exists | Where |
| --- | --- | --- |
| News domain | Bounded notice model; identity = `(source, external_id)`; `max_notices = 25`. | [domain.zig](../../src/news/domain.zig) |
| News feed adapter | RSS/Atom parser (to be replaced by a JSON feed parser). | [feed.zig](../../src/news/feed.zig) |
| News store | Disposable `news.sqlite3` cache, transactional upsert by identity, prunes to the 25 newest, recoverable open. | [store.zig](../../src/news/store.zig) |
| News fetch flow | `refresh_important_news` msg → HTTPS fetch effect → parse → replace cache → UI phases (`idle/loading/loaded/empty/error`). Runs at startup ([main.zig:17709](../../src/main.zig)) and from the dashboard button. Feed URL/source constants at [main.zig:17438-17440](../../src/main.zig). | [main.zig:14449-14535](../../src/main.zig), [ui_state.zig](../../src/news/ui_state.zig) |
| News UI | Global Dashboard “Important News” column: refresh button, error alert, loading, empty state, rows via `importantNewsRows` (no month filtering today). | [global-dashboard.fragment:172-268](../../src/pages/global-dashboard.fragment), [main.zig:1275,8566](../../src/main.zig) |
| Deadline overrides (domain) | `DeadlineOverride{id, title, source_reference, affected_form_codes, original_deadline, adjusted_deadline, affected_regions, affected_taxpayer_types, …}`. Applies only when the form code matches **and** the override's `original_deadline` equals the resolved deadline's original or final date; sets status `.extended` and the source reference. Blank source → rejected. | [domain.zig:318-445,1209](../../src/calendar/domain.zig) |
| Deadline overrides (store) | `calendar.sqlite3` schema v2: `calendar_overrides` + `calendar_override_forms/_regions/_taxpayer_types`; `putOverride/listOverrides/deleteOverride`; migration machinery `migrateFromObservedVersion`. **No external identity column yet.** | [store.zig:16,39,304-333,463](../../src/calendar/store.zig) |
| Scoped resolution | `TaxpayerContext{region, rdo, taxpayer_type}`; scoped overrides are skipped in the nationwide projection and applied when the context's region **or RDO** matches a scope string (case-insensitive exact). The profile calendar already passes the taxpayer's RDO ([main.zig:14373-14385,14403](../../src/main.zig)). | [ui_state.zig:371,481-505,1128-1149](../../src/calendar/ui_state.zig) |
| RDO reference | 138 canonical RDO codes+names (`"024" Valenzuela City`, `"17A" Tarlac City`, …), `findByCode`. Some rows have placeholder names (`"037" → "RDO 037"`) and some names are stale vs. current BIR naming — treat codes as primary, names as secondary evidence. | [rdo_reference.zig](../../src/tax_profile/rdo_reference.zig) |
| Form codes | Canonical alias table (`"1601-C" → "1601C"`, …) and the compiled rule set with display form numbers. | [domain.zig:805-889,538](../../src/calendar/domain.zig) |
| Markers | Dashboard dots derive from resolved deadlines, so an applied override moves the dot with no extra UI work. Status label “Extended” already exists. | [marker.zig](../../src/calendar/marker.zig), [domain.zig:233](../../src/calendar/domain.zig) |
| Tooling conventions | TS under `scripts/` run with `node --experimental-strip-types`, tested with `node --test`, typechecked via a dedicated tsconfig; `just` recipes wrap npm scripts; CI quality gate on macOS. | [package.json](../../package.json), [Justfile](../../Justfile), [ci.yml](../../.github/workflows/ci.yml) |

### 1.3 Why not Google Search / AI Overview scraping (v1 non-goal)

The original idea was to scrape Google's AI Overview for BIR announcements.
Probing showed the underlying primary source is strictly better and the
scraping path is strictly worse:

- The AI Overview is nondeterministic, unversioned, has no stable identity for
  dedup, and cites the same BIR pages we can read directly.
- Automated Google scraping is bot-detected (CAPTCHA); we will not build
  CAPTCHA circumvention, and any headless-Google dependency would make the
  4×/day cron flaky.
- The BIR CMS API (S2–S5) is the system of record the AI Overview summarizes,
  is JSON, is dated, and needs two static headers.

A search-API-based secondary source (e.g. Google Programmable Search JSON API
with an API key) remains a documented future enhancement for catching
non-BIR-published news (e.g. bank advisories), and slots in as one more
`source` module without changing any contract in this plan.

---

## 2. Decisions

### 2.1 Locked by this plan (rationale inline)

| # | Decision |
| --- | --- |
| L1 | Primary sources are template 9 (new-issuance detection) + yearly RMC archive template (dates, completeness, July backfill). PDFs come from the `Full Text` links. |
| L2 | v1 extractor is **fully deterministic** (regex + vocabularies + geometry from `pdftotext -layout`). No LLM calls. Ambiguity never guesses: it degrades to “notice without override” plus a review report. |
| L3 | Extraction is **fail-closed at three layers**: (a) vocabulary validation (RDO codes/names, form codes, month names), (b) only rows classified non-eFPS become overrides, (c) the app's existing original-date equality guard means a wrong override date simply never matches a resolved deadline — markers cannot move to a wrong day because of a misparse; the failure mode is “marker doesn't move”, which the review report surfaces. |
| L4 | Feed overrides are RDO-scoped via the existing `regions` scope strings, using canonical `rdo_reference` codes (`"024"`, `"17A"`). The profile calendar needs zero changes to honor them. |
| L5 | Sync writes into the existing `calendar_overrides` store (schema v3 adds `origin` + `external_ref` + a dismissal tombstone table) instead of a parallel store, so the existing override editor, resolver, and `.ics` export all keep working. Synced rows are read-only in the editor (delete = tombstone). |
| L6 | Month bucketing of news uses the issuance date at fixed UTC+8 (the Philippines has no DST); computed in Zig from `published_at_unix`. No news-store schema change. |
| L7 | The app keeps fetching on startup + manual refresh (existing flow). The 4×/day cadence lives server-side in the scheduler; the app just reads the latest compiled feed. |
| L8 | `news/feed.zig` (RSS/Atom) is deleted together with the URL swap; the new parser is `news/feed_json.zig`. Git history preserves the old parser. |
| L9 | Notices cover **all** New Issuances kinds (RMC/RMO/RR/RA/…); only extension-classified RMCs get the PDF deep-extraction pass. |
| L10 | eFPS group rows are extracted and reported (they matter for review and future eFPS modeling) but are **not** emitted as app overrides in v1, since the app models non-eFPS statutory deadlines (README: eFPS groups not yet modeled). |

### 2.2 Open decisions for your review (each has a working default)

| # | Question | Default in this plan | Alternative |
| --- | --- | --- | --- |
| D1 | Where does `feed.json` live? | GitHub Actions cron in this repo commits `feed.json` + state to an orphan branch `news-feed`; app fetches the `raw.githubusercontent.com` URL. Zero new infra, auditable history, free. **Requires the repo to be public** (the CI badge suggests it is). | If the repo is/goes private: a ~40-line Cloudflare Worker serving R2-hosted `feed.json`, uploaded by the same Action via `wrangler r2 object put` (needs `CLOUDFLARE_API_TOKEN` secret). Tasks T4.3/T5.2 isolate the URL so switching later is a one-line app change. |
| D2 | Global Dashboard behavior for RDO-scoped overrides | Add an “RDO context” dropdown (default “Nationwide”, session-only). Nationwide keeps today's honest nationwide schedule (marker stays on Aug 10; the news pane right next to it announces the extension). Selecting an RDO recomputes with `TaxpayerContext{rdo}` and the marker moves. | (a) Persist the selection (needs a small settings store — deferred; noted in T7.4). (b) Skip the selector entirely; only profile calendars move. |
| D3 | OCR fallback for PDFs with no text layer | Not in v1. If `pdftotext` yields < 200 chars/page, the circular is marked `needs_manual_review` in the report and published as a notice without overrides. | Add `tesseract` OCR stage in the runner (documented install), if BIR starts shipping textless scans. |
| D4 | “Advisories” tab as a second notice source | Not in v1 (separate CMS template, same pattern). Fast-follow task noted in §10. | Include now (adds one template discovery + one parser). |

Review shortcut: if you change nothing, implementation proceeds with D1=GitHub
branch publishing, D2=session RDO selector, D3=no OCR, D4=issuances only.

---

## 3. Architecture

```
            ┌─────────────────────────── scheduler (4×/day, Asia/Manila) ───────────────────────────┐
            │ .github/workflows/news-sync.yml   cron: 0 4,10,16,22 * * *  (=12:00,18:00,00:00,06:00 PHT)│
            └───────────────┬───────────────────────────────────────────────────────────────────────┘
                            ▼
   scripts/news-sync/sync.ts  (node --experimental-strip-types, zero deps)
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ 1 fetch    cms.ts        template 9 (widget) + yearly archive template     │
   │ 2 parse    issuances.ts  HTML → IssuanceRecord[{ kind,number,subject,     │
   │                           pdf_url,date_issued }]                           │
   │ 3 dedupe   state/seen.json  skip issuances whose (id, pdf_sha256) is known │
   │ 4 classify classify.ts   subject regex → is this a deadline extension?     │
   │ 5 extract  pdf.ts + extract-rmc-extension.ts                               │
   │            pdftotext -layout → RDO list + deadline table rows              │
   │            (channel-tagged: non-eFPS vs eFPS group A–E vs registration…)   │
   │ 6 validate vocabularies: data/rdo-reference.json, data/form-codes.json     │
   │            low confidence ⇒ review/RMC-89-2026.md, no override emitted     │
   │ 7 compile  feed.ts → feed/feed.json  (notices[] + overrides[])             │
   └────────────────────────────────┬───────────────────────────────────────────┘
                                    ▼ publish (D1: commit to `news-feed` branch)
                     https://…/news-feed/feed.json   (public, versioned)
                                    ▼
   app (Zig)  refresh_important_news (startup + button, unchanged flow)
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ news/feed_json.zig  parse+validate feed.json (bounded)                     │
   │   notices  → news/store.zig        (news.sqlite3, identity upsert)         │
   │   overrides→ calendar/store.zig v3 (upsert by external_ref, tombstones)    │
   │             → calendar reload → resolver applies matching overrides        │
   │ Global Dashboard: month-filtered news pane + default message               │
   │                   RDO context selector (D2) moves nationwide markers       │
   │ Profile calendar: already RDO-scoped — markers move for affected RDOs      │
   └────────────────────────────────────────────────────────────────────────────┘
```

New repo surface:

```
scripts/news-sync/
  sync.ts            CLI orchestrator (fetch|extract|compile|all, --offline)
  cms.ts             CMS API client + yearly template discovery
  issuances.ts       widget + archive HTML parsers
  classify.ts        extension-circular classifier
  pdf.ts             PDF download/cache + pdftotext wrapper
  extract-rmc-extension.ts   RDO + deadline-table extractor (the core)
  ocr-normalize.ts   OCR noise normalization helpers
  feed.ts            feed.json compiler + schema validation
  form-codes.ts      display→canonical form codes (generated, parity-checked)
  data/rdo-reference.json    generated from src/tax_profile/rdo_reference.zig
  fixtures/2026-08-11/…      committed live captures (already present)
  state/seen.json    dedupe state (committed by the cron)
  feed/feed.json     compiled output (committed by the cron)
  review/…           per-circular extraction reports (committed by the cron)
  *.test.ts          node --test suites per module
src/news/feed_json.zig       new bounded JSON feed parser
docs/news/…                  this plan + operations doc (T8.3)
```

---

## 4. Data contracts

### 4.1 `feed.json` (schema_version 1)

Size budget ≤ 512 KiB (app rejects oversized bodies; current cap is 1 MiB in
[domain.zig:10](../../src/news/domain.zig)). All strings UTF-8; all dates
`YYYY-MM-DD` (Asia/Manila civil dates); all timestamps unix seconds UTC.

```json
{
  "schema_version": 1,
  "generated_at_unix": 1786742400,
  "source_label": "BIR",
  "notices": [
    {
      "external_id": "bir:rmc:2026:089",
      "kind": "RMC",
      "title": "RMC No. 89-2026",
      "summary": "Providing Extension of the Deadlines for the Filing of Tax Returns … Southwest Monsoon.",
      "url": "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
      "published_at_unix": 1786636800,
      "month_bucket": "2026-08"
    }
  ],
  "overrides": [
    {
      "external_ref": "bir:rmc:2026:089/2026-08-10/nonefps",
      "title": "RMC 89-2026 monsoon extension (due 2026-08-10)",
      "source_reference": "RMC No. 89-2026",
      "original_deadline": "2026-08-10",
      "adjusted_deadline": "2026-08-17",
      "form_codes": ["1601C", "0619E", "0619F"],
      "rdo_codes": ["002", "003", "…all 58 offices, see Appendix A…", "126"],
      "channel": "nonefps",
      "notice_external_id": "bir:rmc:2026:089"
    }
  ]
}
```

Contract rules (enforce in `feed.ts` and again in `feed_json.zig`):

- `external_id` = `bir:<kind-lowercase>:<year>:<number zero-padded to 3>`;
  stable across runs; never derived from title text.
- `external_ref` = `<notice external_id>/<original_deadline>/<channel>`.
  One override record per (issuance, original date, channel-class) group;
  all form codes of that group are listed in the one record. Re-extraction
  after a fixed parser bug updates the same `external_ref` in place.
- `form_codes` are **canonical app codes** (right-hand side of
  `canonical_aliases`, e.g. `1601C` not `1601-C`); only codes present in
  `form-codes.ts` may appear (compiler drops and reports others).
- `rdo_codes` are canonical `rdo_reference` codes (`"024"`, `"17A"`).
  Empty array is FORBIDDEN in v1 (a nationwide extension would list no RDOs;
  none observed — if BIR issues one, the compiler flags it for review rather
  than silently emitting an unscoped nationwide override).
- `channel` ∈ `nonefps | efps_group_a…efps_group_e | efps_group_multi |
  efps_and_nonefps | registration | submission | unknown`. v1 compiler emits
  override records only for `nonefps` and `efps_and_nonefps`; other channels
  stay review-report-only (locked decision L10).
- `notices` sorted by `published_at_unix` descending; ≤ 120 entries; summary
  ≤ 4096 bytes (matches [domain.zig](../../src/news/domain.zig) bounds);
  `month_bucket` = issue date's `YYYY-MM` in Asia/Manila (app recomputes and
  trusts its own computation; the field exists for humans and diffing).

### 4.2 TypeScript records (internal to the pipeline)

```ts
type IssuanceRecord = {
  externalId: string;        // bir:rmc:2026:089
  kind: "RMC" | "RMO" | "RR" | "RDAO" | "RA" | "BANK_BULLETIN" | "OTHER";
  number: string;            // "89-2026" as printed
  subject: string;           // plain text, tags stripped, entities decoded
  pdfUrl: string | null;
  dateIssued: string | null; // "2026-08-10" from the archive table
  firstSeenAtUnix: number;
};

type ExtensionRow = {       // one description block from the deadline table
  channel: Channel;
  rawDescription: string;
  formCodesDisplay: string[];   // as printed, post OCR-normalization ("1601-C")
  formCodesCanonical: string[]; // catalog-known only
  originalDate: string | null;  // "2026-08-10"; null for window rows
  extendedDate: string | null;  // "2026-08-17"
  dateAssignment: "same_line" | "window";   // §5.6.5 — only same_line emits
  confidence: "high" | "review";
  notes: string[];              // every normalization/inference performed
};

type RdoMatch = {
  raw: string;               // "RDO No. 4l - Mandaluyong City"
  code: string | null;       // "041" (canonical) or null
  matchedBy: "code" | "name" | "code+name";
  confidence: "high" | "review";
};
```

### 4.3 Review report (per extracted circular)

`scripts/news-sync/review/<external_id with ':'→'-'>.md`, regenerated each
run, committed. Contains: the classification verdict, every `RdoMatch` (with
raw text), the full `ExtensionRow` table with date assignments and channel
tags, the emitted override records, and a final section “Dropped / needs
review” listing everything that did not make it into `feed.json` and why.
This is the human checkpoint that makes the no-AI extractor trustworthy.

---

## 5. Extractor specification (deterministic v1)

### 5.1 OCR normalization (`ocr-normalize.ts`)

Applied only inside targeted contexts (never blanket over prose):

- Digit context (RDO numbers, day/year numbers): map `l→1 I→1 |→1 O→0 o→0
  S→5 B→8 T→7 Z→2 G→6`, strip inner spaces (`06 1 9-F → 0619-F`,
  `I 16 → 116`, day token `1 l → 11` as in the fixture's
  `August 1 l, 2026`).
- Month names: case-insensitive match against the 12 English months with
  Levenshtein distance ≤ 2 over letters only, ignoring punctuation/brackets
  (`A]ugttst → August` at distance 2 after dropping `]`; `Aueust → August`).
- Date literal: `<month-fuzzy> <day>[,.] <year>` where day/year pass digit
  normalization; reject if the resulting civil date is invalid or the year
  differs from the issuance year by more than 1.
- Punctuation variants in labels: treat `. , -` and missing spaces as
  equivalent when matching `RDO No.` prefixes (`RDONo.T-`, `RDO No,`).

Every normalization performed is appended to `notes` so the review report
shows the reasoning chain.

### 5.2 Issuance list parsing (`issuances.ts`)

Widget (template 9, `content.Issuance` HTML):

- Split on top-level `<p class="MsoNormal">`/`<div>` blocks; within each,
  `<strong>` holds `"<Kind> No. <number>"` — regex
  `/\b(Revenue Memorandum Circular|Revenue Memorandum Order|Revenue Regulations?|Revenue Delegation Authority Order|Bank Bulletin)\s+No\.\s*([0-9OlI]{1,3}[A-Z]?-\d{4})/i`,
  then digit-normalize the number and zero-pad (`89-2026 → 089`, keeps
  `2026`). The first `more`/`Full Text` anchor in the block is `pdfUrl`
  (URL-encode spaces).
- Blocks without a recognized kind are recorded with `kind: "OTHER"` and
  surface in the review log — never dropped silently.

Archive (yearly template, `content.Content` HTML table):

- Iterate `<tr>`; cell 1 → number (`RMC No. 89-2026`), cell 2 → subject +
  `Full Text` href, cell 3 → `DATE OF ISSUE` via the date parser (this text
  is CMS-typed, not OCR, but reuse the same tolerant parser).
- The archive is authoritative for `dateIssued` and for July/June backfill;
  the widget is authoritative for “new since last run” freshness (it updates
  first). Merge by `externalId`; archive fields win when both present.

Tag stripping/entity decoding: implement the same bounded whitespace-collapse
+ entity decode approach as [feed.zig `normalizeText`](../../src/news/feed.zig)
(`&amp; &lt; &gt; &quot; &apos; &#…;` + `&nbsp;` → space); no external HTML
library.

### 5.3 Extension classifier (`classify.ts`)

`isDeadlineExtension(subject)` = subject matches
`/extend(s|ing|sion)?\b.*\bdeadline/i` OR `/deadline.*\bexten/i`.
Classifier hits trigger PDF extraction. Misses still publish the notice.
(RMC 89-2026 subject matches on “Providing Extension of the Deadlines…”.)

### 5.4 PDF pipeline (`pdf.ts`)

1. Download to `work/pdf/<external_id>.pdf` (skip if present with same
   `Content-Length`); record sha256 into `state/seen.json`.
2. `pdftotext -layout <pdf> <txt>`; also `pdftotext -layout -f 1 -l 1` for the
   header date.
3. If total text < 200 chars/page → mark `needs_manual_review` (D3), stop.
4. Runner dependency: `poppler` (`brew install poppler` locally,
   `sudo apt-get install -y poppler-utils` in CI). `sync.ts` verifies
   `pdftotext -v` at startup and fails with an actionable message.

### 5.5 RDO extraction (from the full layout text)

1. Scan the region from the start of text to the deadline-table header
   (first line matching `/BIR\s+Forms?\/?Returns/i` or
   `/Due\s+Date/i`+`/Extended/i`) for every occurrence of
   `/RDO\s*No[.,]?\s*([0-9OlITSB]{1,4}\s?[0-9OlITSB]?[A-C]?)\s*[-–—]?\s*([^\n]{0,60})/i`.
2. Normalize the captured code (digit context; uppercase suffix; numeric-only
   → pad to 3, digit+letter → pad digits to 2: `T → 007`, `l7A → 17A`,
   `I 16 → 116`).
3. Validate: code must exist in `data/rdo-reference.json`. Secondary check:
   captured name fuzzy-overlaps the reference name (token overlap ≥ 1 after
   lowercasing, or reference name is a placeholder like `RDO 037`). Code
   valid + name plausible → `high`; code valid + name conflicting → `review`
   (kept, flagged); code invalid → try unique name-token match against the
   reference list; still nothing → `review`, excluded from `rdo_codes`.
4. Expansion rule: a plain numeric code whose reference has lettered variants
   (`043` with `43A/43B` present, `045` with `45A/45B` if present) emits the
   parent **and** the lettered variants, so profiles stored under either form
   match. Note the expansion in the report.
5. Invariant check (RMC-style extension circulars): if the circular's prose
   states a count (“58 … offices”), compare with `|high ∪ review|` and flag
   mismatch in the report.

### 5.6 Deadline-table extraction

Table region = from the header line (`BIR Forms/Returns … Due Date …
Extended Due Date`) to the signature block (`/This Circular|Digest|Sgd|Commissioner/i`
after the last date pair) — in practice: parse to end of text, ignoring
non-table noise (received stamps OCR as scattered tokens; they never match
the row grammar).

1. **Column geometry**: from the header line, record the character columns of
   `Due Date` and `Extended Due Date`. A “date-pair line” is any line with a
   parsable date in each of those column windows (±10 chars). (In the
   fixture: `e-FlLlNG & PAYMENT (Online/Manual)   August 10,2026   A]ugttst 17,2026`.)
2. **Blocks**: contiguous non-empty left-column text separated by blank lines
   forms a description block. A channel header line
   (`SUBMISSION`, `e-SUBMISSION`, `REGISTRATION…`, `e-FILING & PAYMENT…`,
   `e-FILING & e-PAYMENT/REMITTANCE`, `e-FILING`, `eFILING & PAYMENT…` —
   OCR-tolerant regexes) starts a new block and sets the block's channel
   seed.
3. **Channel classification** per block (order matters):
   - description contains `/Non-?eFPS/i` AND `/eFPS/i` both → `efps_and_nonefps`
   - `/eFPS\s+Filers?\s+under\s+Group\s+([A-E](?:\s*[,&]\s*[A-E])*)/is`
     (the letter may sit on the next line, and lists occur:
     `Group E, D ,C & B`) → single letter ⇒ `efps_group_<x>`, list ⇒
     `efps_group_multi`
   - `/Non-?eFPS/i` alone → `nonefps`
   - header seed `REGISTRATION…` → `registration`; `SUBMISSION`/`e-SUBMISSION`
     → `submission`
   - header seed contains `Online/Manual` (OCR variants: `Online,Manual`,
     `Online[vlanual`, `Online/I4anual`) with no eFPS qualifier → `nonefps`
   - otherwise → `unknown` (review-only).
   Channel-header regexes must tolerate OCR letter damage in the header word
   itself: `e-FlLlNG`, `e-FILINC`, `eFILING` all mean `e-FILING` (match
   `/e[-\s]?F[Il1][LC][Il1]N[GC]/i` plus the plain spellings).
4. **Form codes**: within a block, harvest
   `/\b(\d{4})\s?-?\s?([A-Z]{1,3}|\d[A-Z]?)?\b/` candidates after digit
   normalization; keep only codes whose canonical form exists in
   `form-codes.ts` (`1601-C → 1601C ✓`, `2550Q`, `0620`, …). Non-catalog
   mentions (e.g. sugar lists with no form number) leave the block with an
   empty `formCodesCanonical` — publishable in the report, never an override.
5. **Date assignment**. Precondition: parse two circular-level anchors from
   the prose once — `globalExtendedDate` (`/until\s+<date>/i`, page 1:
   `until Aueust 17. 2026` → 2026-08-17) and the stated extension window
   (`/falling (?:between|from)?\s*<date>\s*(?:to|and|until|-)\s*<date>/i` →
   2026-08-10…2026-08-16; absent that, `[issue date, globalExtendedDate)`).
   Then per block, exactly one of:
   - `same_line` — a date-pair line whose y (line index) falls inside the
     block's own line range → that pair, taken as printed even when outside
     the window (e.g. the stockbrokers row's Aug 17 → Aug 17). **Only
     `same_line` blocks can become overrides.**
   - **Damaged-extended fallback** (still `same_line`): a line with a
     parseable date in the Due-Date column but garbage in the Extended
     column (fixture: `August 13, 2026   Angttst 1'? ,2026`) counts as a
     pair using `globalExtendedDate` as the extended value, with a note. If
     both columns parse but extended ≠ `globalExtendedDate`, keep the
     parsed value and flag `review`.
   - `window` — no pair on the block's lines. The document's merged/empty
     date cells cannot be reconstructed reliably from `-layout` text (blank
     lines both separate blocks inside one bordered row and separate rows;
     OCR'd stamps inject noise lines mid-row), so v1 does **not** guess a
     neighbor's pair. The block is recorded against the circular window
     (`originalDate = null`, `extendedDate = globalExtendedDate`),
     confidence `review`, and emits **no override**. The review report
     prints these blocks with the nearest pairs above/below so a human can
     add a manual override in the existing editor in seconds if one matters.
     (Blocks that state their own range — `Deadlines falling from <date> to
     <date>`, the ONETT and 0605/0613 rows — are the same `window` case
     with the range recorded; the affected app forms are event-based ONETT,
     which the override mechanism ignores by design anyway.)
   The v2 upgrade path for merged-cell recovery is `pdftotext -tsv`
   word-coordinate clustering (or the §10.4 review-assist stage); the
   contract in §4 already carries everything v2 needs.
6. **Form-code list expansion**: `1702 - RT/EX/MX` style suffix lists expand
   to `1702RT, 1702EX, 1702MX` before catalog filtering.
7. **Override grouping**: `same_line` rows with identical `(originalDate,
   extendedDate, emittable channel-class)` merge into one override record
   (`efps_and_nonefps` merges into the `nonefps` record for the same pair);
   forms deduplicate.

RMC 89-2026 walk-through of these rules and the exact expected output is
Appendix A — implement against it as the golden test.

### 5.7 Vocabulary files

- `data/rdo-reference.json`: generated by `npm run generate:news-sync-data`
  (task T1.2) which parses `src/tax_profile/rdo_reference.zig` entries with a
  regex; a `node --test` parity test regenerates and diffs so the JSON can
  never drift from the Zig source of truth.
- `form-codes.ts`: same approach against `canonical_aliases` in
  [domain.zig:805](../../src/calendar/domain.zig) (display→canonical pairs).

---

## 6. Work plan

Execute phases in order; tasks inside a phase are ordered too. Every task
ends with its **Verify** commands green plus `just verify` for app-affecting
tasks. Commit per task with the message prefix shown.

Progress is tracked with the checkboxes below. When a task's Verify commands
pass and its commit is made, tick its box and bump the phase counter in the
phase heading. `grep -c '^- \[x\]' ` on this file gives the completed count out
of 27 total tasks.

### Phase 1 — pipeline skeleton and source parsers (no app changes) — 3/3 complete

- [x] **T1.1 `news-sync` scaffolding** — `feat(news-sync): scaffold pipeline`
- Files: `scripts/news-sync/{sync.ts,cms.ts,util.ts}`,
  `tsconfig.news-sync.json` (copy `tsconfig.tax-catalog.json`, adjust
  include), package.json scripts:
  `"news:sync": "node --experimental-strip-types scripts/news-sync/sync.ts"`,
  `"test:news-sync": "node --experimental-strip-types --test scripts/news-sync/"`,
  `"typecheck:news-sync": "tsc --noEmit -p tsconfig.news-sync.json"`.
- `cms.ts`: `fetchTemplateDatasets(templateId: number): Promise<CmsDataset[]>`
  using global `fetch` with headers exactly `{"client-website-id": "2",
  "origin": "https://www.bir.gov.ph", "user-agent": "buwiz-news-sync/1.0"}`,
  20 s timeout (AbortController), one retry after 30 s on network error or
  HTTP ≥ 500; HTTP 403 fails immediately with a message pointing at
  `CAPTURES.md` (header contract drift). `discoverYearTemplateId(year)`:
  GET `https://www.bir.gov.ph/{year}-Revenue-Memorandum-Circulars`, regex
  `/"code":"(\d{1,6})","dataMapper":\{"content":"Content"\}/`; on failure
  fall back to the checked-in map `{2026: 3752}` and warn.
- `sync.ts` subcommands: `fetch`, `extract`, `compile`, `all` (default), plus
  `--offline` which substitutes `fixtures/2026-08-11/` captures for network
  calls (used by tests and CI).
- Acceptance: `npm run news:sync -- fetch --offline` prints the parsed
  issuance count from fixtures; typecheck green.
- Verify: `npm run typecheck:news-sync && npm run test:news-sync`

- [x] **T1.2 vocabulary generation + parity tests** — `feat(news-sync): vocabularies`
- Files: `scripts/news-sync/generate-data.ts`, `data/rdo-reference.json`,
  `form-codes.ts` (generated content pasted as source with a
  `// GENERATED from src/... — run npm run generate:news-sync-data` header),
  `generate-data.test.ts` parity test (regenerate → string-equal).
- package.json: `"generate:news-sync-data"`.
- Acceptance: 138 RDO entries; alias table contains `1601-C→1601C`,
  `0619-E→0619E`; parity test fails if either Zig file changes without
  regeneration.

- [x] **T1.3 issuance parsers over fixtures** — `feat(news-sync): issuance parsers`
- Files: `issuances.ts`, `issuances.test.ts`, `ocr-normalize.ts`,
  `ocr-normalize.test.ts`.
- Tests pin against the two committed fixtures: widget parse yields ≥ 8
  records including `bir:rmc:2026:089` with the exact PDF URL; archive
  excerpt parse yields 6 records with `dateIssued: "2026-08-10"` for 089;
  merge prefers archive dates; normalization table cases from
  `CAPTURES.md` (each row of the OCR-noise table becomes a unit test).
- Acceptance: all listed tests pass; unknown-kind block appears in parse
  diagnostics, not dropped.

### Phase 2 — PDF extraction core — 4/4 complete

- [x] **T2.1 pdf wrapper + layout ingestion** — `feat(news-sync): pdf pipeline`
- Files: `pdf.ts`, `pdf.test.ts` (tests operate on the committed layout text,
  not the binary; the pdftotext invocation itself gets a smoke test guarded
  by `process.env.NEWS_SYNC_NETWORK==="1"`).
- Startup check: `pdftotext -v` present, else exit 2 with install hint.

- [x] **T2.2 RDO extractor** — `feat(news-sync): rdo extraction`
- Files: `extract-rmc-extension.ts` (RDO half), tests using
  `fixtures/2026-08-11/rmc-89-2026-pdftotext-layout.txt`.
- Acceptance (golden): exactly the 58 codes of Appendix A.1 at confidence
  `high` or `review`; zero codes outside the reference list; `RDONo.T- Abra`
  → `007`; `RDO No. I 16` → `116`; `043` expansion emits `043,43A,43B`
  (then Appendix A.1 counts them as one office but the emitted set contains
  the variants — assert the set equality given in A.1-emitted).
- Verify: `npm run test:news-sync`

- [x] **T2.3 deadline-table extractor** — `feat(news-sync): deadline table extraction`
- Files: `extract-rmc-extension.ts` (table half), tests on the same fixture.
- Acceptance (golden): reproduce Appendix A.2 exactly — the
  1601C/0619E/0619F non-eFPS block and the 1702-RT/EX/MX block are the only
  emittable `same_line` blocks; Groups E/D/B classified with their pairs
  (incl. the `August 1 l` day fix and the Group-D damaged-extended
  fallback); every other block lands as `window` with the documented
  channel; sugar/e-sales/loose-leaf blocks have empty `formCodesCanonical`;
  the ONETT/0605 range rows carry their stated windows.

- [x] **T2.4 review report writer** — `feat(news-sync): review reports`
- Files: `review.ts`, test snapshotting the RMC-89 report (assert the
  section headers and override table rows, not byte-exact prose).

### Phase 3 — feed compilation, state, CLI end-to-end — 3/3 complete

- [x] **T3.1 feed compiler** — `feat(news-sync): feed compiler`
- Files: `feed.ts`, `feed.test.ts`.
- Implements §4.1 exactly: grouping to override records, channel emission
  filter (`nonefps`, `efps_and_nonefps` only), canonical-code filter,
  `rdo_codes` non-empty guard, 512 KiB budget, notices cap 120 sorted desc,
  `month_bucket` from `dateIssued` (fallback: PDF page-1 header date;
  fallback: `firstSeenAtUnix` converted at UTC+8 — record which source won
  into the review report).
- Acceptance (golden, Appendix A.3): the RMC-89 fixture pipeline emits
  exactly the two records of A.3 — `…/2026-08-10/nonefps` with
  `form_codes = {1601C,0619E,0619F}` and `…/2026-08-15/nonefps` with
  `form_codes = {1702RT,1702EX,1702MX}` — both with `rdo_codes` equal to
  the A.1-emitted set; no record for any `efps_group_*` channel; the review
  report lists every A.2 `window` row under “Dropped / needs review”.

- [x] **T3.2 dedupe state + orchestrator** — `feat(news-sync): state and orchestration`
- Files: `state.ts` (`seen.json`: `{ issuances: { [externalId]: {pdfSha256,
  extractedAt, feedRev} } }`), wiring in `sync.ts`.
- Behavior: an issuance already in `seen.json` with an unchanged sha skips
  stages 4–6 (“duplicate → skip extraction”); `feed.json` is still
  recompiled from cached stage outputs (`work/` is gitignored,
  `state/`+`feed/`+`review/` are committed); `--force <externalId>` rewinds
  one issuance.
- Acceptance: second `all --offline` run is a no-op (byte-identical
  feed.json, log says “0 new”).

- [x] **T3.3 Just + docs wiring** — `chore(news-sync): just recipes`
- Justfile: `news-sync` (`npm run news:sync -- all`), `news-sync-offline`;
  extend the `check` recipe chain with `typecheck:news-sync` mirroring the
  tax-catalog pattern; README source-map + product-status rows.
- Verify: `just check` green with no network.

### Phase 4 — scheduler + publishing (decision D1) — 4/4 complete

- [x] **T4.1 workflow** — `ci(news-sync): scheduled sync`
- File: `.github/workflows/news-sync.yml`. Triggers: `schedule:
  [{cron: "0 4,10,16,22 * * *"}]` (UTC = 12:00/18:00/00:00/06:00 PHT) +
  `workflow_dispatch`. Single job, `ubuntu-latest`:
  checkout → setup-node 22 → `sudo apt-get install -y poppler-utils` →
  `npm ci` → `npm run news:sync -- all` → commit changed
  `scripts/news-sync/{state,feed,review}` to the publishing branch (T4.2).
  `concurrency: news-sync` to prevent overlap. Failure leaves the previous
  feed untouched (app keeps serving last-good).
- Note: do not add this job to `ci.yml`; CI gets only the offline tests
  (T4.4).

- [x] **T4.2 publishing branch** — `ci(news-sync): publish feed`
- Orphan branch `news-feed` holding `feed.json`, `state/`, `review/` at the
  root; the workflow worktree-checkouts it, copies outputs, commits with
  message `sync: <generated_at ISO> (<n> new)` only when content changed
  (duplicate runs make no commit). Document the resulting raw URL:
  `https://raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json`.
- **[D1 checkpoint]** If the repo turns out to be private, swap this task for
  the Cloudflare R2 variant (workflow step `wrangler r2 object put
  buwiz-news/feed.json --file …`; Worker route serving it with
  `cache-control: max-age=300`); everything else in the plan is unchanged.

- [x] **T4.3 failure alerting** — `ci(news-sync): failure visibility`
- Scheduled-run failures already email the repo owner; additionally the
  workflow's last step posts a `::error` annotation with the review-report
  diff summary so selector/OCR drift is diagnosable from the run page alone.

- [x] **T4.4 CI test hook** — `ci: run news-sync offline tests`
- Add `npm run typecheck:news-sync && npm run test:news-sync` to the existing
  quality-gate job in `ci.yml` (macOS has no poppler dependency for offline
  tests — they consume committed text fixtures only).

### Phase 5 — app: JSON feed ingestion (news pane still month-agnostic) — 3/3 complete

- [x] **T5.1 `news/feed_json.zig`** — `feat(news): JSON feed parser`
- New file implementing `parse(allocator, source_label, body,
  fetched_at_unix) Error!Parsed` where `Parsed = { notices: NoticeList,
  overrides: OverrideRecordList }` using `std.json` with an arena +
  explicit bounds: reject `schema_version != 1`, body > 1 MiB (reuse
  `domain.max_feed_bytes`), > 120 notices, > 64 overrides, > 32 forms or
  > 200 RDO codes per override; every notice passes the existing
  `NoticeWrite.validate`; dates parsed with `calendar.domain.Date.parseIso`.
  `OverrideRecord` mirrors §4.1 fields (slices arena-owned).
- Tests: happy path (embed a trimmed feed.json literal), schema-version
  reject, bound rejects, invalid date reject, unknown extra fields ignored.
- Delete `src/news/feed.zig` and its tests **in this same task**; migrate the
  two RSS test fixtures' intent (identity dedupe, oversized reject) onto the
  JSON parser.

- [x] **T5.2 swap the fetch target** — `feat(news): fetch BIR feed`
- [main.zig:17438-17440](../../src/main.zig): `important_news_feed_url` →
  the D1 URL; `important_news_source` → `"BIR"`; keep the fetch key.
- `handleImportantNewsResponse` (main.zig:14475-14535): call
  `feed_json.parse`, store notices exactly as today (`store.replaceAll`
  pattern unchanged), stash `parsed.overrides` on the model for Phase 6
  (until T6.2 lands, log-and-drop them behind a comment referencing T6.2).
  Error strings: keep the existing user-facing phrasing (“The news provider
  returned an invalid feed.” etc.).
- Update the startup-refresh test at main.zig:22286 to serve a JSON fixture
  body instead of RSS.
- Verify: `just verify`; manual: `just run`, dashboard shows BIR notices
  after refresh.

- [x] **T5.3 retention bump** — `feat(news): retain 120 notices`
- `domain.max_notices` 25 → 120 ([domain.zig:9](../../src/news/domain.zig));
  adjust the store prune constant/comment and its boundary test; adjust
  `news/ui_state.zig` `validateCount` bound if it references the constant.
- Rationale: month-scoped display (Phase 7) needs more than a rolling 25.

### Phase 6 — app: override ingestion into the calendar policy store — 3/3 complete

- [x] **T6.1 calendar store schema v3** — `feat(calendar): synced override identity`
- [store.zig](../../src/calendar/store.zig): `latest_schema_version = 3`;
  `migration_v3` (follow the `migration_v2` pattern inside
  `migrateFromObservedVersion`):

```sql
ALTER TABLE calendar_overrides ADD COLUMN origin TEXT NOT NULL DEFAULT 'manual'
    CHECK (origin IN ('manual','synced'));
ALTER TABLE calendar_overrides ADD COLUMN external_ref TEXT
    CHECK (external_ref IS NULL OR length(trim(external_ref)) > 0);
CREATE UNIQUE INDEX calendar_overrides_external_ref_idx
    ON calendar_overrides(external_ref) WHERE external_ref IS NOT NULL;
CREATE TABLE calendar_override_dismissals (
    external_ref TEXT PRIMARY KEY CHECK (length(trim(external_ref)) > 0),
    dismissed_at INTEGER NOT NULL DEFAULT (unixepoch())
);
```

- Extend `OverrideWrite`/`OwnedOverride`/`readOverride`/`putOverride` with
  the two fields (defaults keep every existing caller compiling: `origin =
  "manual"`, `external_ref = null`).
- Tests: v2→v3 migration on a populated store preserves rows as
  `origin='manual'`; unique index enforced; SchemaTooNew guard still works.

- [x] **T6.2 sync upsert API** — `feat(calendar): syncOverridesFromFeed`
- New store methods:
  `getOverrideIdByExternalRef(ref) !?i64`,
  `isDismissed(ref) !bool`,
  `dismissSyncedOverride(id) !void` (writes tombstone + deletes row),
  `syncOverridesFromFeed(records: []const FeedOverrideRecord) !SyncSummary`
  — per record: dismissed → skip; existing by ref → `putOverride` with that
  id (update in place); else insert with `origin='synced'`. Records carry
  `rdo_codes` into the `regions` scope list verbatim and
  `source_reference` into `source`. Manual rows are never touched. Synced
  rows absent from the current feed are **kept** (feeds roll off after 120
  notices; deadline history must survive) — pruning only via
  `expires_at`-style cleanup is future work, noted in §10.
- Wire into `handleImportantNewsResponse` (replaces the T5.2 stash):
  after notices commit, run sync against the calendar store handle already
  on the model (opened at [main.zig:18082](../../src/main.zig)), then
  trigger the same reload path the override editor uses
  (`calendar_ui.State.reload` + dashboard recompute) so markers move within
  the same session, and surface `SyncSummary` in the reload notice
  (“Calendar rules and SQLite overrides loaded. 1 BIR override synced.”).
- Tests (store level): insert/update/tombstone-skip/manual-untouched;
  (ui level, follow the patterns at
  [ui_state.zig:2040-2230](../../src/calendar/ui_state.zig)): a synced
  1601C override 2026-08-10→2026-08-17 scoped to `039` moves the resolved
  deadline for a `TaxpayerContext{.rdo="039"}` recompute, stays put for
  `.rdo="113"` and for the nationwide projection.

- [x] **T6.3 editor surfacing** — `feat(calendar): synced override UX`
- Override editor rows (calendar explorer page): show a “Synced from BIR”
  badge (origin) + the source reference; disable the edit action for synced
  rows; the delete action on a synced row calls `dismissSyncedOverride`
  (tombstone) with confirm copy “Deleting a synced override stops future
  syncs from re-adding it.”
- Fragment + `just generate`; ui_state tests for the read-only gating.

### Phase 7 — app: month-scoped news pane + RDO context — 3/4 complete

- [x] **T7.1 Manila month bucketing** — `feat(news): month bucket helper`
- Add `pub fn manilaYearMonth(unix: i64) struct { year: i32, month: u8 }`
  to [news/domain.zig](../../src/news/domain.zig): `days =
  @divFloor(unix + 8*3600, 86400)`, then the standard civil-from-days
  algorithm (the inverse of the era/day-of-era math the deleted
  `feed.zig` used in `civilToUnix`; keep the helper local to news/domain).
  Tests: epoch edges, Dec 31 16:00 UTC → Jan 1 Manila, leap day.

- [x] **T7.2 month-filtered rows + default message** — `feat(news): month-scoped pane`
- [main.zig](../../src/main.zig): `importantNewsRows` filters by
  `manilaYearMonth(published_at) == (globalDashboard.calendar.selected_year,
  selected_month)`; new bindings `importantNewsMonthLabel` (“August 2026”,
  reuse `fullMonthName`), `importantNewsEmptyForMonth` (loaded-but-zero-rows
  for the viewed month), keep `importantNewsEmpty` for the never-fetched
  case.
- [global-dashboard.fragment](../../src/pages/global-dashboard.fragment):
  header becomes “Important News — {importantNewsMonthLabel}”; add the
  `importantNewsEmptyForMonth` card: “No BIR announcements recorded for
  {importantNewsMonthLabel}. Deadlines shown follow the standard schedule.”
  Run `just generate`, commit regenerated `.native` shards per the
  development rule.
- Tests: model-level rows-filtering test with three notices across two
  months; month switch changes the row set; empty month asserts the binding.

- [x] **T7.3 RDO context selector (D2)** — `feat(global-dashboard): RDO context`
- [global_dashboard/ui_state.zig](../../src/global_dashboard/ui_state.zig):
  add `rdo_context: ?FixedText(8)` + setters; when set, dashboard recompute
  calls `calendar.recomputeForTaxpayer(.{ .rdo = ctx })` instead of
  `recompute()` (mirror the profile-calendar call at
  [main.zig:14403](../../src/main.zig)).
- UI: dropdown fed by `rdo_reference.entries` (code — name), first option
  “Nationwide” (clears), placed in the dashboard calendar header row;
  caption under it when active: “Showing RDO {code} policy view”.
- Tests: selecting `039` applies the Phase 6 synced override to the global
  projection; “Nationwide” restores the unscoped schedule.

- [ ] **T7.4 (deferred, tracked)** persistence of the selector — needs an app
settings store; explicitly out of v1. Recorded in §10.

### Phase 8 — end-to-end proof, docs, cleanup — 3/3 complete

- [x] **T8.1 fixture-to-marker E2E test** — `test: feed to marker E2E`
- One Zig test (main.zig test block, following the startup-refresh test at
  [main.zig:22275](../../src/main.zig)): serve the Appendix-A feed.json via
  the fake fetch effect → assert news rows for August contain RMC 89-2026,
  calendar store contains the synced override, profile calendar for RDO 039
  resolves 1601C July-2026 to 2026-08-17 `Extended`, RDO 113 stays
  2026-08-10, July news view is empty with the default message.

- [x] **T8.2 live dry-run** — manual checklist, not code
- `npm run news:sync -- all` against the live site; inspect
  `review/bir-rmc-2026-089.md`; confirm feed matches Appendix A; `just run`,
  point the app at the published feed (or a `file://`-served copy via a dev
  override env var added in T5.2 if quicker), walk the §0 worked example on
  screen; screenshot into `docs/news/screenshots/`.
- **Gate: no phase-8 sign-off without this walkthrough.**

- [x] **T8.3 documentation** — `docs(news): operations guide`
- `docs/news/NEWS_SYNC_OPERATIONS.md`: endpoints + headers contract, cron
  timetable (UTC↔PHT), yearly template rollover (every January: run
  `discoverYearTemplateId(newYear)`, commit the map entry — or rely on
  auto-discovery and just re-verify), failure triage (403 → header drift;
  empty text → D3; count-invariant mismatch → read review report), how to
  `--force` re-extraction, how to dismiss a bad override in-app.
- README: replace the Official Gazette mention; product-status table rows for
  Important News and synced overrides; CONTEXT.md is unaffected (no new
  domain terms beyond “Synced Override”, which reuses Policy Revision
  language — add that one entry).

### Phase 9 — defects found after implementation — 3/3 complete

Added 2026-08-11 after the implementation passed `just verify`. Full analysis
in [NEXT_STEPS.md](NEXT_STEPS.md) §2. Neither defect is reachable with today's
data; both are the same class as the 16-slot region cap that nearly shipped
(a bound that real feed data overflows), so they are cheap to close now.

- [x] **T9.1 per-row override copy failure** — `fix(calendar): isolate override row failures`
- Problem: `reload()` in [ui_state.zig](../../src/calendar/ui_state.zig) does
  `try self.copyOverride(item)` inside its loop, so ONE unrepresentable row
  abandons the whole reload — remaining overrides skipped, non-working days
  never loaded, `recompute()` never run, calendar left in an error state. This
  is why the 16-slot bug blanked every override instead of one.
- Fix: skip and count the offending row instead of propagating; surface it the
  way `override_records_truncated` already surfaces list truncation.
- Acceptance: a store holding one oversized override plus two good ones
  reloads both good ones, reports one skipped, and still recomputes.

- [x] **T9.2 ScopeList byte budget** — `fix(calendar): size region storage to its own cap`
- Problem: `ScopeList.storage` is `max_joined_scopes_bytes` = 16 × 130 = 2080
  bytes, derived from the superseded `max_scopes_per_record`, while the list
  admits `max_regions_per_override` = 200 entries of up to 128 bytes and the
  feed permits 200 × 32 = 6400 bytes. Today's 3–4 byte RDO codes use ~240
  bytes, so the headroom is an accident of the data, not an invariant.
- Fix: derive the budget from the values it serves
  (`max_regions_per_override * (max_scope_value_bytes + 1)`), or bound region
  entries separately from the 128-byte generic scope text.
- Acceptance: 200 maximum-length scopes round-trip through `copyOverride`.

- [x] **T9.3 production RDO path test** — `test: profile RDO applies a synced override`
- Problem: every scoping test calls `recomputeForTaxpayer` with a literal code.
  Nothing exercises `selectedTaxpayerCalendarContext`, the function that
  derives the RDO from the selected profile — so the profile → context →
  match chain is verified only by reading it.
- Fix: select a profile whose RDO is inside the circular, deliver the feed,
  assert the profile calendar shows the extended date, driving the same
  messages the UI does.
- Acceptance: the test fails if `selectedTaxpayerCalendarContext` stops
  passing the profile's RDO.

### Phase 10 — found by the live dry-run — 1/2 complete

Added 2026-08-11 from the T8.2 walkthrough (see
[screenshots/README.md](screenshots/README.md)). The notice-date defect that
run also found was fixed in the same pass and needs no task.

- [x] **T10.1 extractor misses circulars that spell out their offices** — `feat(news-sync): widen RDO and table-header matching`
- Problem: of the seven 2026 extension circulars, only RMC 89-2026 produced
  overrides. Two are image-only scans (documented D3 limit, flagged correctly).
  RMC 62-2026 is a genuine miss: it has a clean text layer but names its
  offices as `Revenue District Office No. 1 10 - General Santos City` in a
  numbered list, which the `RDO No. X` pattern does not match, and its table
  header OCR'd to `I)ue Date` / `E:rtended Due Date`, which the header probe
  does not match, so no deadline table was located at all.
- Fix: accept the spelled-out `Revenue District Office No.` form alongside the
  abbreviation, and make the table-header probe OCR-tolerant the way the
  channel-header regexes already are. Commit the RMC 62-2026 layout text as a
  second extraction fixture — one fixture taught the extractor one circular's
  habits.
- Acceptance: RMC 62-2026 yields RDO codes 110 and 111, its office-count
  invariant passes, and its deadline rows extract; RMC 89-2026's golden output
  is unchanged.

- [ ] **T10.2 merged deadline-table cells** — decision needed, see [MERGED_CELL_INVESTIGATION.md](MERGED_CELL_INVESTIGATION.md)
- Investigated 2026-08-11; no code shipped. The plan's own `-tsv` upgrade path
  (§5.6 step 5) rests on a false premise: RMC 89-2026's table has 8 bordered
  rows, not 22, and a row prints its pair once against an arbitrary paragraph,
  so word coordinates carry no row-boundary signal — measured true boundaries
  (15.5–16.3 pt) sit strictly inside the intra-row paragraph gaps (13.5–40.4 pt).
- Consequence worth acting on: the published feed **under-applies** RMC 89-2026.
  2200-M, 2200-C, 0620, 1600-VT/PT, 1606 and the NGAs block share the Aug-10
  cell with 1601C, and 1701Q and 1707-A share the Aug-15 cell with 1702. They
  are named in the review report but absent from the feed. Error is in the safe
  direction (an earlier date is shown), but the gap is real.
- Options, with recommendation: enter the missing rows as manual overrides now;
  or ship raster rule detection with an implausibility guard; or accept
  correct-by-omission. See the investigation for why raster detection alone was
  refused — its failure mode fabricates overrides silently.

---

## 7. Testing and verification summary

| Layer | Mechanism |
| --- | --- |
| TS unit | `node --test` per module; OCR-noise table cases; fixture-pinned parsers. |
| TS golden | Full offline pipeline over the committed RMC-89 fixture must reproduce Appendix A exactly (assertions on sets, not prose). |
| TS regression | `--offline` re-run produces byte-identical `feed.json` (idempotence). |
| Zig unit | feed_json bounds/validation; manilaYearMonth; store v3 migration; sync upsert/tombstone; month filtering; RDO-context recompute. |
| Zig E2E | T8.1 feed→marker test. |
| Repo gate | `just verify` (check, test, build, whitespace) green after every app task; CI runs offline news-sync tests (T4.4). |
| Live | T8.2 manual walkthrough with screenshots. |

---

## 8. Operations

- **Schedule**: `0 4,10,16,22 * * *` UTC ⇒ 12:00, 18:00, 00:00(+1), 06:00
  Asia/Manila — the requested 6am/12pm/6pm/12am cadence. GitHub cron drifts
  minutes; irrelevant at this cadence.
- **Duplicate handling**: `state/seen.json` sha-keyed skip (§T3.2); publish
  commit only on content change, so 3 of 4 daily runs are usually no-ops.
- **Feed availability**: app keeps last-good cache on any fetch/parse failure
  (existing `openRecoverableCache` + error phases). A broken sync run
  publishes nothing (previous feed stays live).
- **Yearly rollover**: auto-discovery (S5) + checked-in map fallback;
  operations doc T8.3 documents the January check.
- **Site redesign risk**: the 403/regex failures are loud (T4.3);
  fixtures let a fix be developed offline against the last-good captures.

---

## 9. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| BIR changes CMS host/headers/template IDs | Loud pipeline failure (never silent staleness); header contract + discovery trail documented in `CAPTURES.md`; fixtures enable offline repair. |
| OCR noise beyond the normalization table | Confidence gating: unmatched rows go to the review report; the app-side original-date equality guard makes any wrongly-dated override a no-op instead of a wrong marker. |
| A future RMC with a textless scan | D3: classified circular publishes as a notice flagged `needs_manual_review`; the override can be entered manually in the existing editor (which is why synced+manual coexist). |
| PDF taken down/replaced after extraction | `state/seen.json` stores sha256; overrides already extracted persist in the app store independent of feed retention. |
| Feed rollover hides old months | Store retains 120 notices; synced overrides are never pruned by feed absence (T6.2). Default month message covers true gaps. |
| Repo visibility blocks raw URL (D1) | Cloudflare R2 alternative pre-specified in T4.2; app URL isolated in one constant. |
| Marker moves for the wrong taxpayer | Overrides are RDO-scoped; nationwide projection intentionally unaffected unless the user picks an RDO context (D2); taxpayer calendars use the profile's registered RDO. |

---

## 10. Explicit non-goals in v1 (tracked follow-ups)

1. Google Search / AI Overview ingestion (§1.3) — future secondary source
   via a proper search API only.
2. “Advisories” tab notices (D4) — same pattern, one more template.
3. eFPS group deadline modeling in the rule engine — the extractor already
   channel-tags eFPS rows and the feed schema reserves the channel values,
   so this becomes purely an app-side rules feature later.
4. LLM-assisted extraction stage for low-confidence rows — slot is the
   `confidence:"review"` set; a future stage may propose (never auto-apply)
   structured rows from review items.
5. RDO-context persistence (T7.4) and synced-override retention pruning.
6. BIR Tax Calendar template 1135 as a rules cross-check oracle.

---

## Appendix A — RMC No. 89-2026 golden expectations

Source: committed layout text `scripts/news-sync/fixtures/2026-08-11/rmc-89-2026-pdftotext-layout.txt`.

### A.1 RDOs (58 offices; 53 regular + 5 Large Taxpayer divisions)

Canonical codes after normalization and reference validation:

```
002 003 004 005 006 007 008 009 010 012
17A 17B 018 019 020 21A 21B 21C 024 25A
25B 026 027 028 029 030 031 032 033 034
037 038 039 040 041 042 043 044 045 046
047 048 049 050 051 052 53A 53B 54A 54B
058 059 063 116 121 124 125 126
```

Emitted `rdo_codes` set additionally contains `43A 43B` from the expansion
rule (`043` has lettered variants in the reference), i.e. 60 strings for 58
offices. Notable OCR cases the extractor must land: `RDONo.T- Abra → 007`,
`RDONo. l0- Mountain Province → 010`, `RDO No. l7A → 17A`, `RDO No. 2lB →
21B`, `RDO No. I 16 → 116`, `RDO No. 5l → 051`, `RDO No. 53B - Muntinlu… →
53B`. Prose count invariant: “58” stated on page 1 must equal the office
count.

### A.2 Deadline-table blocks (complete enumeration, v1 outcomes)

`same_line` = a printed date pair on the block's own lines ⇒ override-eligible.
`window` = no pair printed on the block's lines ⇒ review-report only (§5.6.5).

| Block (abbrev., in document order) | Channel | Pair on block's lines | v1 outcome |
| --- | --- | --- | --- |
| Sugar buyer list / refined sugar release | `submission` | none | window (no form codes) |
| e-Sales report, odd TIN | `submission` | none | window (no form codes) |
| 2200-M metallic minerals | `nonefps` | none | window → review |
| **1601-C / 0619-E / 0619-F — Non-eFPS** | `nonefps` | **Aug 10 → Aug 17** | **same_line → override** |
| 2200-C cosmetic excise | `nonefps` | none | window → review |
| 0620 — eFPS & Non-eFPS | `efps_and_nonefps` | none | window → review |
| 1600-VT / 1600-PT + MAP — eFPS & Non-eFPS | `efps_and_nonefps` | none | window → review |
| 1606 | `nonefps` | none | window → review |
| 1600-VT/1600-PT/1601-C — NGAs | `nonefps` | none | window → review |
| 1601-C/0619-E/0619-F — eFPS **Group E** | `efps_group_e` | Aug 11 → Aug 17 (`August 1 l`) | same_line, eFPS ⇒ no override |
| … — eFPS **Group D** | `efps_group_d` | Aug 13 → Aug 17 (extended col is `Angttst 1'?` ⇒ globalExtendedDate fallback) | same_line, eFPS ⇒ no override |
| … — eFPS **Group B** | `efps_group_b` | Aug 14 → Aug 17 | same_line, eFPS ⇒ no override |
| REGISTRATION loose-leaf books (FY 7/31) | `registration` | none | window (no form codes) |
| 1702 - RT/EX/MX (FY 4/30) | `nonefps` (`eFILING & PAYMENT (Online[vlanual)`) | Aug 15 → Aug 17 | same_line → override (harmless in-app) |
| 1707-A block fragment (split off by stamp noise) | `unknown` | none | window → review |
| 1701Q + SAWT — eFPS & Non-eFPS (Q ending 6/30) | `efps_and_nonefps` | none | window → review (¹) |
| 1601-C/0619-E/0619-F — eFPS **Group A** | `efps_group_a` | none | window, eFPS |
| e-PAYMENT — eFPS Groups `E, D ,C & B` | `efps_group_multi` | none | window, eFPS |
| Stockbrokers consolidated return (Aug 1–15) | `submission` | Aug 17 → Aug 17 | same_line (no form codes; identity pair) |
| ONETT 1800/1801/1706/1707/1707-A, deadlines Aug 10–16 | `nonefps` | extended-only `Aug 17` | window/range → review (²) |
| 0605/0613 tax-mapping payments, deadlines Aug 10–16 | `nonefps` | extended-only `Aug 17` | window/range → review (²) |

(¹) 1701Q's true pair per the printed table geometry is Aug 15 → Aug 17
(merged cell), and its app deadline (Q2-2026 = Aug 15, a Saturday) would
match. v1 deliberately leaves it to the review report + manual editor rather
than guess merged cells; the §10.4/v2 `-tsv` stage recovers it automatically.
(²) ONETT forms are event-based in the rule engine; the override mechanism
ignores event-based deadlines by design ([domain.zig:442](../../src/calendar/domain.zig)),
so nothing is lost in-app.

### A.3 Emitted override records (golden assertion)

Exactly two records, both `nonefps`, both scoped to the A.1 emitted RDO set
(60 strings):

```
bir:rmc:2026:089/2026-08-10/nonefps   2026-08-10 → 2026-08-17
    form_codes = { 1601C, 0619E, 0619F }          ← moves markers (the §0 scenario)
bir:rmc:2026:089/2026-08-15/nonefps   2026-08-15 → 2026-08-17
    form_codes = { 1702RT, 1702EX, 1702MX }       ← kept; matches no resolved
                                                     deadline (fiscal-year 1702 is
                                                     not modeled), guard makes it a no-op
```

**No `efps_group_*` records.** The review report must list every `window` row
of A.2 under “Dropped / needs review”, each with its nearest printed pairs so
a human can add a manual override in the editor when it matters (1606, 0620,
1600-VT/PT, 2200-M, NGAs, 1701Q are the candidates worth eyeballing).

App-side end state: 1601C July-2026 for an RDO-039 profile resolves to
2026-08-17 with status `Extended`, source `RMC No. 89-2026`; an RDO-113
profile and the nationwide view keep 2026-08-10.

## Appendix B — quick reference

```
# CMS API (both headers mandatory)
curl -H 'client-website-id: 2' -H 'origin: https://www.bir.gov.ph' \
  'https://bir-cms-ws.bir.gov.ph/api/pub/templates/9/datasets?per_page=3000'
# yearly archive discovery (one page per kind; the marker is BACKSLASH-ESCAPED
# in the served HTML because it sits inside a JS string in the RSC payload)
curl -s https://www.bir.gov.ph/2026-Revenue-Memorandum-Circulars \
  | grep -o '\\"code\\":\\"[0-9]*\\",\\"dataMapper\\"'      # -> 3752
curl -s https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders \
  | grep -o '\\"code\\":\\"[0-9]*\\",\\"dataMapper\\"'      # -> 3753
curl -s https://www.bir.gov.ph/2026-Revenue-Regulations \
  | grep -o '\\"code\\":\\"[0-9]*\\",\\"dataMapper\\"'      # -> 3754
# cron (UTC) ⇔ Asia/Manila
0 22 * * *  → 06:00 PHT     0 4 * * *  → 12:00 PHT
0 10 * * *  → 18:00 PHT     0 16 * * * → 00:00 PHT
# pipeline
npm run news:sync -- all [--offline] [--force bir:rmc:2026:089]
just news-sync-offline && npm run test:news-sync
```
