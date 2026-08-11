# Remaining-work plan — Important News + BIR deadline overrides

Branch `gol/important-news-google-search-8efadb` · companion to
[the execution plan](IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md)
(25/30 tasks done there; this file is the plan for the last 5 plus shipping).

**Snapshot:** feature implemented and green — `just verify` passes, Zig
1830/1834 (baseline 1798/1802, +32), TypeScript 200 tests / 197 pass /
3 network-gated skips. **Nothing is committed**; the whole change sits in the
working tree. The app's default feed URL 404s until the first publish (R4).

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

- [ ] **R1.1 = T9.1 — per-row override copy failure.** `reload()` in
  [ui_state.zig](../../src/calendar/ui_state.zig) does
  `try self.copyOverride(item)` in a loop, so one unrepresentable row blanks
  *all* calendar policy (skips remaining overrides, never loads non-working
  days, never recomputes). Fix: skip-and-count the bad row, surface it like
  `override_records_truncated`. **Do this first — it is the blast-radius fix
  that makes every other bound a one-row problem.**
- [ ] **R1.2 = T9.2 — ScopeList byte budget.** Storage is 2,080 bytes (derived
  from the superseded 16-slot constant) while the list admits 200 entries and
  the feed permits 6,400 bytes. Fix: derive the budget from what it serves —
  ≥ max(200 × 33 feed codes, 16 × 130 manual names) = 6,600 bytes — and add
  two boundary tests (200 max-length feed codes; 16 max-length manual names).
- [ ] **R1.3 = T9.3 — production RDO path test.** Select a real profile whose
  RDO is 039, deliver the feed, assert the profile calendar shows 2026-08-17 —
  through `selectedTaxpayerCalendarContext`, not a literal context. Written
  after R1.1/R1.2 so it also exercises the repaired copy path.

Gate: `just verify` green; test count strictly above 1830.

</details>

## R2 — commit and open the PR (authorized)

- [ ] **R2.1 Commit in reviewable slices**, `--no-gpg-sign`, each message in
  repo style:
  1. `feat(news-sync): BIR issuance pipeline` — scripts/news-sync/, fixtures,
     workflows, Justfile/package.json/tsconfig/.gitignore/ci.yml
  2. `feat(news): bounded BIR JSON feed parser` — feed_json.zig, domain/store
     retention, feed.zig deletion is in slice 4 if inseparable, else here
  3. `feat(calendar): schema v3 synced-override identity and sync API`
  4. `feat(app): ingest feed overrides on news refresh` — main.zig wiring
  5. `feat(app): month-scoped news pane, synced-override UX, RDO context` —
     fragments + all five regenerated shards together (dev rule), E2E test
  6. `docs(news): plan, runbook, remaining-work plan, README, CONTEXT`

  Exact file-to-slice mapping may shift where files are entangled (main.zig
  spans 2/4/5); the invariant is: shards move with their fragments, and HEAD
  passes `just verify`. Intermediate slices need only compile-sanity, not the
  full 8-minute gate.
- [ ] **R2.2 Push + PR.** Push via the git credential helper (no piped git —
  verify exit codes); open the PR against `main` with `curl` (gh is broken
  behind the proxy). PR body links the plan and this file.

## R3 — live dry-run (T8.2, the plan's own sign-off gate)

I execute; you eyeball the screenshots. No push required — runs locally.

- [ ] **R3.1 Live pipeline run:** `npm run news:sync -- all` against the real
  CMS. Expect ~16+ notices, the two RMC-89 overrides, dates all
  archive-sourced. Read `review/bir-rmc-2026-089.md` end to end.
- [ ] **R3.2 App walkthrough:** serve the feed over localhost
  (`python3 -m http.server` in `scripts/news-sync/feed/`), launch with
  `BUWIZ_NEWS_FEED_URL=http://localhost:<port>/feed.json just run`, walk the
  §0 scenario — August pane shows RMC 89-2026, July switch, profile with RDO
  039 shows the 1601C marker on Aug 17 (Extended), RDO selector Nationwide vs
  039 — screenshots into `docs/news/screenshots/`.
- [ ] **R3.3 Tick T8.2** in the plan with a link to the screenshots.

## R4 — first publish and end-to-end-in-production (after R2, ideally after R3)

- [ ] **R4.1 Dispatch `news-sync.yml`** once via the Actions API
  (`workflow_dispatch` with `ref` = this branch; fallback: after merge). This
  creates the orphan `news-feed` branch and publishes `feed.json`.
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
