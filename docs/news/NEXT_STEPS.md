# Remaining-work plan — Important News + BIR deadline overrides

Branch `gol/important-news-google-search-8efadb` · companion to
[the execution plan](IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md)
(29/31 tasks done there; this file tracks shipping and what is left).

**Snapshot 2026-08-11:** implemented, dry-run against the live BIR site, and
open for review as [PR #26](https://github.com/hexuria/formzero/pull/26).
`just verify` exits 0 — Zig **1839/1843** (baseline 1798/1802) and TypeScript
**201 tests / 198 pass / 3 network-gated skips**. Six commits are pushed.
Only **R4** remains, and it cannot run until the PR merges (see below).

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

## R4 — first publish — **BLOCKED until this PR merges**

GitHub only dispatches a `workflow_dispatch` workflow that already exists on
the **default branch**, and `news-sync.yml` lives only on this branch, so the
attempt returns:

```
HTTP 404: workflow news-sync.yml not found on the default branch
```

The `schedule:` trigger is gated the same way, so the 4×/day cron will not fire
before the merge either. Nothing here is broken — this is how GitHub scopes
workflow triggers — but it does mean **R4 cannot be done before review**, and
`raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json` returns 404
until it is. The app degrades to "could not refresh" and keeps its last-good
SQLite cache, which is the designed behaviour for an unreachable feed.

Deliberately **not** worked around by creating the `news-feed` branch by hand:
that would publish outside review, and it would send the workflow's first real
run down its "branch already exists" path, leaving the orphan-creation path
untested exactly once — on the run that matters.

What was verified locally in the meantime: the pipeline produced a publishable
feed against the live site (R3), and the workflow's own pre-publish gate passes
on it (`feed.json: 112 notices, 2 overrides`).

Run immediately after merge:

- [ ] **R4.1 Dispatch `news-sync.yml`** once — `gh workflow run news-sync.yml`
  (no `--ref` needed once it is on `main`). This creates the orphan
  `news-feed` branch and publishes `feed.json`.
- [ ] **R4.2 Verify the loop closed:** raw URL returns HTTP 200 with the
  expected sha; a fresh `just run` with **no** env override fetches it and
  shows "BIR override(s) synced"; a second dispatch makes no commit
  (idempotence in production).
- [ ] **R4.3 Confirm the 4×/day cron fires** after merge (first scheduled slot
  in UTC 4/10/16/22) and update the runbook if anything surprised us.

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
