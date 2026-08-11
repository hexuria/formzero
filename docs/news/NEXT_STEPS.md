# Remaining-work plan — Important News + BIR deadline overrides

Branch `gol/important-news-google-search-8efadb` · companion to
[the execution plan](IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md)
(29/31 tasks done there; this file tracks shipping and what is left).

**Snapshot 2026-08-11:** shipped. [PR #26](https://github.com/hexuria/formzero/pull/26)
merged as `691f363`, the feed is published, and the app reads it from GitHub
with no override. `just verify` exits 0 — Zig **1839/1843** (baseline
1798/1802) and TypeScript **201 tests / 198 pass / 3 network-gated skips**.

One follow-up is open: **[PR #27](https://github.com/hexuria/formzero/pull/27)**
fixes dedupe state not surviving between scheduled runs (found by R4.2).
Everything else left is backlog.

---

## Decisions — settled 2026-08-11

| # | Question | Decision |
| --- | --- | --- |
| Q1 | Feed host | **GitHub raw for v1.** The Cloudflare R2 + Worker migration is documented as a concrete task list in [NEWS_SYNC_OPERATIONS.md](NEWS_SYNC_OPERATIONS.md) ("Migrating the feed to Cloudflare R2 + a Worker") for when the app has real users. |
| Q2 | RDO gaps (editor-buffer read; branch units) | **Backlog both** — see Backlog below. |
| Q3 | RDO count-mismatch behavior | **Keep as built**: flag for review, still emit; the date-equality guard bounds the damage. |
| Q4 | Commit + push + PR | **Authorized**, six-slice plan below. |

---

## R1 — close the three defects — **DONE 2026-08-11**

All three landed; `just verify` exits 0 with Zig **1837/1841** (was 1830/1834)
and TypeScript **201 tests / 198 pass / 3 network-gated skips**.

One refinement was made on top of the fixes. R1.2's first cut solved the
storage shortfall by widening the per-row scope budget to 200 × 32 = 6400
bytes, which added roughly 830 KB across the three calendar states inside
`Model` and overflowed the test stack in two unrelated tests. Every canonical
RDO code is three characters, so the 32-byte figure came from a generic scope
bound being applied to values that cannot reach it. A dedicated
`max_rdo_code_bytes = 8` now bounds synced scopes at the feed boundary, and the
budget derives from that: **2048 bytes per row, below the original 2080**, with
no memory growth at all. Two consequences worth knowing:

- The editor's joined scope buffer now provably covers every list a record can
  hold (worst manual 2078 B, worst synced 1998 B, buffer 2080 B), so the
  display can no longer truncate a scope list behind the user's back. A
  `comptime` block fails the build if either bound ever drifts past it.
- `validateFeed` in the pipeline now rejects an over-long RDO code at publish
  time. Without it the app would refuse the whole feed — notices included — in
  every installation, for a value only the publisher could have prevented.

The two tests that were switched to heap-allocate `Model` stay that way: it
matches production (`BuwizApp.create(page_allocator)`) and no longer depends on
`Model` staying under any particular size.

<details><summary>Original R1 task list (all complete)</summary>

Full specs live in the plan's **Phase 9**; this is the order and the why.

- [x] **R1.1 = T9.1 — per-row override copy failure.** `reload()` in
  [ui_state.zig](../../src/calendar/ui_state.zig) does
  `try self.copyOverride(item)` in a loop, so one unrepresentable row blanks
  *all* calendar policy (skips remaining overrides, never loads non-working
  days, never recomputes). Fix: skip-and-count the bad row, surface it like
  `override_records_truncated`. **Do this first — it is the blast-radius fix
  that makes every other bound a one-row problem.**
- [x] **R1.2 = T9.2 — ScopeList byte budget.** Storage was 2,080 bytes
  (derived from the superseded 16-slot constant) while the list admits 200
  entries. Landed differently from this brief and better: rather than widening
  the buffer to 6,600 bytes, synced scopes are bounded at RDO-code length, so
  the budget is 2,048 bytes — see the note above.
- [x] **R1.3 = T9.3 — production RDO path test.** Select a real profile whose
  RDO is 039, deliver the feed, assert the profile calendar shows 2026-08-17 —
  through `selectedTaxpayerCalendarContext`, not a literal context. Written
  after R1.1/R1.2 so it also exercises the repaired copy path.

Gate: `just verify` green; test count strictly above 1830.

</details>

## R2 — commit and open the PR — **DONE 2026-08-11**

Six commits on `gol/important-news-google-search-8efadb`, pushed, opened as
[PR #26](https://github.com/hexuria/formzero/pull/26) (67 files,
+15,667/−966, mergeable):

| | Commit |
| --- | --- |
| `3be7118` | `feat: add BIR issuance sync pipeline` |
| `d3fd8fc` | `feat: record synced deadline overrides in the calendar store` |
| `e27e477` | `feat: apply BIR deadline extensions to the calendar` |
| `d03a7bf` | `docs: describe the BIR news sync and its remaining work` |
| `ebbfdd5` | `fix: date Important News notices in Manila time` |
| `6d7bcb4` | `docs: record the live dry-run against bir.gov.ph` |

The planned six-way split collapsed where `main.zig` spanned three slices —
a single file cannot be split across commits without interactive staging — so
the app changes landed as one commit. `gh` turned out to work for both push and
PR creation; the curl fallback was not needed.

## R3 — live dry-run (T8.2) — **DONE 2026-08-11**

Results and screenshots: [screenshots/README.md](screenshots/README.md).
112 issuances, 96 new, every one dated from a yearly-archive row. Nationwide
August shows 9 deadlines on the 10th; under RDO 039 three of them move to the
17th. Two findings: notice dates were rendering a day early (fixed, committed)
and six of seven extension circulars yield no overrides (two are image-only
scans; RMC 62-2026 is a real miss, tracked as T10.1).

## R4 — first publish — **DONE 2026-08-11**

PR #26 merged as `691f363`, which put `news-sync.yml` on the default branch and
made it dispatchable. Two runs followed.

- [x] **R4.1 Publish.** Run
  [31479402242](https://github.com/hexuria/formzero/actions/runs/31479402242)
  succeeded through every step and created the orphan `news-feed` branch:
  `Published 3 new issuance(s)`, `feed.json: 115 notices, 2 overrides`.
- [x] **R4.2 The loop closed.**
  `https://raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json`
  serves HTTP 200 / 57,365 bytes. The app launched with **no**
  `BUWIZ_NEWS_FEED_URL` fetched it and rendered the three issuances BIR
  published that morning — RMC 90-2026, RMC 91-2026 and RMO 20-2026, all dated
  11 August — with no error state. Selecting RDO 039 moved Aug 10 from 9
  markers to 6 and Aug 17 from 1 to 4, from the published feed rather than a
  local file (`screenshots/04-published-feed-rdo-039.png`).
- [x] **R4.3 Idempotence — failed, fixed, needs re-checking.** The second run
  committed again instead of reporting "already current". The two commits
  differ only in `generated_at_unix` and `firstSeenAtUnix`: the workflow read
  its dedupe state from the checkout but wrote it to `news-feed`, so state
  never round-tripped and every run rediscovered the same issuances. Fixed in
  **[PR #27](https://github.com/hexuria/formzero/pull/27)**, which restores the
  published outputs before syncing. Published data was never wrong — dates
  stayed archive-sourced and both overrides were correct throughout.

**Still to do:** merge PR #27, dispatch twice, and confirm the second run logs
`news-feed is already current; no commit made.` Then watch that the 4×/day cron
fires at its first UTC slot (04/10/16/22) and makes no commit on a quiet run.

## Backlog (tracked, deliberately not this cycle)

1. **Gap 3 — branch Registration Unit RDOs** (per-branch override verdicts;
   filing-scope design work). Largest real limitation of the feature.
2. **Gap 2 — context reads the editor buffer**, not the saved revision
   (fail-closed; cosmetic surprise while mid-edit).
3. **T7.4 — persist the dashboard RDO selection** (needs an app settings store).
4. **eFPS group deadlines in the rule engine** — feed already channel-tags
   them; emission is deliberately off until the engine models eFPS dates.
5. **Merged-cell recovery** (`pdftotext -tsv` clustering) to lift the 20-of-22
   review-only blocks — would auto-emit 1606/0620/1600-VT/1701Q extensions.
6. **Advisories tab, search-API secondary source, template 1135 cross-check**
   (plan §10), and pre-adding 2027 template IDs each January.

## Order of operations

All decisions settled; execution order: R1 → R2 → R3 → R4 → merge.
R3 can start in parallel with R2 once R1 lands.
