# BIR news feature — gap report and completion plan

Written 2026-08-11 (Asia/Manila), after the feature shipped to production.
Every claim in the report section was verified against the live system or the
code on this date — none of it is remembered from earlier documents.

This file is the **active tracker** for finishing the feature. It is written to
be executed top-to-bottom by an agent that does not want to make judgement
calls: every task says exactly what to change, how to prove it worked, and what
to do when it does not. Read §1 (the operating manual) before touching
anything.

Progress: 8/13 tasks complete.

---

## 1. Operating manual for executing agents

Follow this exactly. It encodes the failures that actually happened while
building this feature, not hypothetical ones.

### 1.1 The driver loop

1. Open this file. Find the **first unchecked `- [ ]` task, top to bottom**.
2. Execute it exactly as written. Do not improve, extend, or bundle tasks.
3. Run its **Verify** block. Every command must produce the stated result.
4. Tick the box, update the `Progress:` line at the top, and commit the code
   change and the tracker edit **in one commit** with the task's commit
   message.
5. Repeat until no unchecked tasks remain, then run §5 (closeout).

If a task is marked `(USER)`, stop and tell the user what you need; do not
attempt it yourself and do not skip past it unless it is already satisfied
(each `(USER)` task says how to check that).

### 1.2 Session start checklist (every session, before any task)

```sh
cd <repo>   # this file's repository root
git fetch origin main
# Branch rule: if PR #28 is still OPEN, work on gol/news-backlog.
# If PR #28 is MERGED, create/reuse gol/news-completion off origin/main.
gh pr view 28 --json state --jq .state
```

Then record the baselines by running them — do not trust the numbers printed
in this file without re-running:

```sh
npm run typecheck:news-sync            # expect: clean
npm run test:news-sync                 # expect: 0 fail (238/235/3 when written)
npx native test . --yes -Dplatform=null   # expect: "native test: passed" (1855/1859 when written)
```

If a baseline is red BEFORE you change anything, stop and report; do not begin
a task on a red tree.

### 1.3 Hard rules (each one exists because it was violated once)

1. **Ground truth over reports.** Never claim a state you did not verify with
   a command in this session. A merge "done", a test "passing", a file
   "unchanged" — check it. Twice in this project a merge was reported done and
   was not.
2. **The committed pipeline outputs are live-run snapshots.**
   `scripts/news-sync/feed/feed.json`, `state/seen.json`, and `review/` were
   produced by a real run against bir.gov.ph. A local
   `npm run news:sync -- all --offline` **overwrites them with fixture
   output** (16 notices instead of 112+). After any offline run, restore them
   before committing:
   ```sh
   git checkout -- scripts/news-sync/feed scripts/news-sync/state scripts/news-sync/review
   ```
   unless the task explicitly says the regeneration is the deliverable.
3. **Whitespace hygiene the way CI does it.** Local `git diff --check`
   compares working tree to index and passes committed faults. Before every
   push run:
   ```sh
   git diff --check "$(git merge-base origin/main HEAD)" HEAD
   ```
4. **Exit codes, not pipes.** This shell is zsh: `${PIPESTATUS[0]}` is empty.
   Run a command to completion and check `$?`, or redirect to a file and
   inspect it. Never conclude success from a pipe's tail.
5. **Commits:** `git commit --no-gpg-sign`, message as given in the task, one
   task per commit. Push after each task. Never `git push --force`. Never
   commit on `main`.
6. **Zig specifics.** A new `.zig` file is silently untested unless reachable
   via `@import` from `src/main.zig` — after adding one, the total test count
   MUST rise; if it did not, the file is not in the graph. A build+test cycle
   is 6–8 minutes; budget for two per app task. If you edit any
   `src/pages/*.fragment`, run `just generate` and commit all five regenerated
   `src/app*.native`/`.generated.native` outputs together.
7. **TypeScript specifics.** Strict TS; `import type` for type-only imports;
   relative imports carry the `.ts` extension; node builtins only, no new
   dependencies; tests colocated `*.test.ts` using `node:test` +
   `node:assert/strict`, offline by default; anything needing the network goes
   behind `process.env.NEWS_SYNC_NETWORK === "1"` — but note network-gated
   tests are SKIPPED everywhere including CI, so they are documentation, not
   protection. Every live behavior needs an offline test with a stubbed fetch.
8. **Never dispatch or edit GitHub workflows unless the task says to.**
   Dispatching publishes to production. Read-only GETs (raw feed URL, `gh run
   list`, `gh pr view`) are always fine.
9. **Do not create a CLAUDE.md** — the maintainer removed it deliberately.
   Repo-level agent guidance lives in this section instead.
10. **Scope discipline.** Touch only the files a task lists. If you notice an
    unrelated problem, append one line to §6 ("Discovered during execution")
    and keep going — do not fix it inline.
11. **Failure protocol.** Two genuine attempts at a task, then STOP. Under the
    task's checkbox add:
    `> BLOCKED <date>: <what failed, verbatim error> — <what you tried>`
    Commit that note. If the task is tagged **[blocking]**, do not continue to
    later tasks; report to the user. If not tagged, continue with the next
    task.
12. **Honest reporting.** When you finish a session, state what you verified
    with real numbers, what you did not, and anything you changed outside a
    task's file list (which should be nothing).

---

## 2. Verified current state (2026-08-11 ~13:40 UTC)

| Fact | Evidence |
| --- | --- |
| Feature is live: feed published on the `news-feed` branch, app reads it with no env override, RDO-scoped markers move. | Raw URL serves HTTP 200; app walkthrough screenshots in `screenshots/`. |
| The 4×/day cron fires on its own and quiet runs commit nothing. | `gh run list`: a `schedule` event run at 10:40 UTC completed success; `news-feed` still has exactly two commits (09:49, 09:51). |
| Published feed: **115 notices, 2 overrides**. The two curated records (8 additional forms) exist only on PR #28, not yet in production. | `curl` of the raw feed; PR #28 state OPEN. |
| Gates green: TS 238 tests / 235 pass / 3 network-gated skips; Zig 1855/1859 pass / 4 skip; `just verify` exit 0; all four CI checks pass on PR #28. | Run on this date. |
| PR #28 (branch `gol/news-backlog`, 9 commits) contains: curated supplement, HEAD-based PDF skip, saved-revision RDO scoping, persisted dashboard RDO context, persisted theme/sidebar, T10.1 wider extraction, investigation docs. | `gh pr view 28`. |

## 3. Gap inventory

Severity: **P1** breaks or will soon break production behavior; **P2** produces
wrong or misleading data in reachable cases; **P3** hygiene/coverage.

| # | Gap | Sev | Disposition |
| --- | --- | --- | --- |
| G1 | **One unfetchable PDF kills the whole publishing run.** The per-circular loop in `sync.ts` (~line 720) has no try/catch; `downloadPdf` throwing propagates and fails the run, so no feed updates publish at all. This is live risk, not theory: bir-cdn answered `403 AccessDenied` for RMC 62-2026's PDF this afternoon, minutes after a run fetched it fine — consistent with hotlink/rate protection. Post-#28 the HEAD check usually avoids the download, but a 403 on the HEAD degrades to a download attempt, which then 403s and fails the run. | P1 | Task C2 |
| G2 | **Notice cap runway: ~3–6 weeks.** Feed and app both cap at 120 notices; the live feed already carries 115 and BIR publishes ~18–20/month. When the cap bites, the oldest months are silently truncated and their dashboard panes go empty. | P1 | Task C3 |
| G3 | **Curated records not yet in production** (they ride PR #28). Until merged+published, 1606/0620/2200-M/… filers still see Aug 10. | P1 | Tasks C0/C1 |
| G4 | **No date-year sanity window.** `parseNoisyDate` accepts any structurally valid year; `June 25,2426` parsed as year 2426 in RMC 62 (spec §5.1 promised ±1 of the issuance year; never implemented). Today it is caught downstream by accident (pair guard), not by design. | P2 | Task C4 |
| G5 | **Office-count invariant is accidentally right.** `OFFICE_COUNT_PATTERN` matches any 1–3 digit number within 40 chars of "Office(s)"; in RMC 62 the list marker `2.` supplied the count and only an OCR accident (`1.` → `L`) kept `1.` from matching first and reporting a false FAILED. | P2 | Task C5 |
| G6 | **Windows tooling has zero news-sync coverage.** `scripts/just-windows.ps1` contains no news verbs, so `just check` on the audited Windows host no longer runs the checks the unix recipe gained, and `just news-sync` has no Windows path. | P3 | Task C6 |
| G7 | **Same-size PDF replacement is invisible** to the HEAD check (Content-Length only; ETag ignored). | P3 | Task C7 |
| G8 | **Synced overrides are never pruned**; long-expired rows accumulate in every user's calendar store forever. | P3 | Task C8 |
| G9 | **Advisories tab not ingested** (plan decision D4 deferred it). Same CMS pattern as issuances; notices-only. | P3 | Task C9 |
| G10 | **Tracker drift.** The execution plan's Progress line says 29/31 but the file has 30 ticked + 2 open (=32); T7.4 is still unticked though delivered; `MERGED_CELL_INVESTIGATION.md` still opens with "decision you need to make" though the decision was made and shipped. | P3 | Task C10 |

### Out of scope, with reasons (do not work on these)

- **Branch Registration Unit scoping** — blocked upstream: the unit tables
  exist only at schema v28 and production pins v27; the only v28 path is an
  env-gated in-memory fixture preview. See `BRANCH_RDO_DESIGN.md` for what
  must land first.
- **eFPS group deadlines** — not a feed gap (rows are already channel-tagged);
  it is a rule-engine change touching every monthly form. Own project.
- **OCR fallback for image-only scans** (RMC 04/12-2026) — both circulars'
  deadlines are months past; tesseract-in-CI is real scope for zero current
  marker value. Triage doc already covers the manual path.
- **Curated entry for RMC 62-2026** — its extension ended 2026-06-30; a
  curated row would move no marker. Rule recorded in C1: curate only
  extensions whose adjusted date is in the future.
- **RDO reference name refresh** (placeholder names like `RDO 037`) — needs a
  human-verified authoritative source; agents must not invent district names.
- **In-app periodic feed refresh** — startup+manual is acceptable against a
  4×/day feed for a desktop app that restarts often; adding runtime timers is
  design work disproportionate to the gain.
- **Google-search secondary source, template 1135 cross-check, Cloudflare R2
  migration** — documented future enhancements (plan §10, runbook).

---

## 4. Execution plan

Tasks are ordered. `[blocking]` means later tasks must not proceed past a
blocker here.

### Phase C-A — ship what is already built

- [ ] **C0 (USER) — merge PR #28.** `gh pr merge 28 --merge` or the GitHub
  button. Check whether already satisfied:
  `gh pr view 28 --json state --jq .state` → `MERGED` means tick this and move
  on. All four CI checks pass; there is nothing agent-side left to do first.
  > BLOCKED 2026-08-11: `gh pr merge 28 --merge` denied by the permission
  > classifier ("Blocked by classifier"). Not a repo or CI problem — PR is
  > MERGEABLE/CLEAN with four green checks. Needs the user, or a Bash
  > permission rule for `gh pr merge`. C1 and C12 wait on this; C2–C10 do not
  > and are proceeding.

- [ ] **C1 [blocking] — first post-merge publish, verified end to end.**
  - Precondition: C0 ticked (verify with the command above, not by trust).
  - Steps:
    ```sh
    gh workflow run news-sync.yml --ref main
    # wait for completion:
    gh run list --workflow=news-sync.yml --limit 1 --json databaseId,status,conclusion
    gh run view <id> --log | grep -E "overrides: .* curated|already current|Published"
    curl -s https://raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json \
      | python3 -c "import json,sys;f=json.load(sys.stdin);print(len(f['overrides']),[o['external_ref'] for o in f['overrides']])"
    ```
  - Acceptance: run concludes `success`; the published feed carries **4**
    override records — the two extracted refs plus
    `bir:rmc:2026:089/2026-08-10/nonefps-reviewed` and
    `bir:rmc:2026:089/2026-08-15/nonefps-reviewed` — each with 60 `rdo_codes`.
    A second dispatch reports `news-feed is already current; no commit made.`
  - Also append to `NEWS_SYNC_OPERATIONS.md` §"The curated supplement" (one
    sentence): curate only extensions whose adjusted date is still in the
    future; past extensions are history, not calendar policy.
  - Commit: `docs: record the curated supplement going live` (tracker tick +
    the ops line; there is no code change).

### Phase C-B — pipeline resilience (P1)

- [x] **C2 [blocking] — a run survives an unfetchable PDF.**
  - Files: `scripts/news-sync/sync.ts`, `scripts/news-sync/sync.test.ts`,
    `docs/news/NEWS_SYNC_OPERATIONS.md` (failure-triage section).
  - Change: wrap the `extractOne` call in the circular loop (sync.ts ~line
    720) so a thrown fetch/download error is handled per circular:
    1. If `recordedPdf(state, id)` returns a recorded size+sha+extraction:
       reuse the recorded extraction, log
       `extract: <id> PDF unavailable (<error>) — reusing the recorded extraction`,
       count it in a new `summary.reusedAfterFetchError`, and continue.
    2. Otherwise: skip the circular with drop reason `pdf_unavailable`
       (surfaces in the run log and the drop list), and continue.
    3. Errors that are NOT fetch/download errors (poppler missing, extraction
       bugs) must still propagate and fail the run — do not blanket-catch.
       Distinguish by wrapping only the fetch/download step, or by a typed
       error from `downloadPdf`/`remoteContentLength`.
  - Tests (offline, stubbed fetch): (a) HEAD 403 + GET 403 with a recorded
    extraction in state → run exits 0, feed still carries that circular's
    overrides, log line present; (b) same 403s with NO recorded extraction →
    run exits 0, circular dropped with `pdf_unavailable`, feed lacks it,
    review/drop log names it; (c) a non-network error still fails the run.
  - Verify: `npm run typecheck:news-sync` clean;
    `npm run test:news-sync` all pass, count strictly above the session
    baseline; offline pipeline run then
    `git checkout -- scripts/news-sync/feed scripts/news-sync/state scripts/news-sync/review`.
  - Commit: `fix: keep publishing when one circular's PDF is unfetchable`

- [x] **C3 [blocking] — raise the notice caps before they truncate.**
  - Files: `src/news/domain.zig` (`max_notices` 120 → **240**, comment updated
    — the cap must hold a full year of BIR issuance at ~20/month),
    `scripts/news-sync/feed.ts` (`maxNotices` 120 → **240**, comment names the
    Zig constant), plus any test asserting 120 on either side (search both
    trees for `120` near notices), plus §4.1 of
    `IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md` (the `≤ 120 entries`
    line → 240).
  - Add a guard test on each side, mirroring the existing cross-boundary
    style: TS asserts `maxNotices === 240` with a comment naming
    `domain.max_notices`; Zig asserts `domain.max_notices == 240` with a
    comment naming `feed.ts` (the vocabularies have generated parity; the
    caps get this pinned pair instead).
  - Size math to keep in the feed.ts comment: 240 notices measured ~500 B each
    ≈ 120 KiB, well under the 512 KiB budget and the app's 1 MiB body cap.
  - Verify: both suites green with counts above baseline;
    `npx native test` ends `native test: passed`. Restore live snapshots if an
    offline run was made (manual rule 1.3.2).
  - Commit: `fix: hold a full year of notices before the cap truncates months`

### Phase C-C — extraction correctness (P2)

- [x] **C4 — reject date literals outside the circular's year window.**
  - Files: `scripts/news-sync/extract-deadline-table.ts` (+ its test file).
  - Change: `extractDeadlineRows` / its date-candidate scan already receives
    the circular's anchors; thread the issuance year (from
    `issuance.dateIssued`, fallback: the year in `anchors.globalExtendedDate`,
    fallback: skip the check) and treat a parsed candidate whose year is
    outside `[issueYear-1, issueYear+1]` as an **unreadable literal** (the
    same class as `Angttst 1'?`), so all existing fallback behavior applies.
    Record a note naming the rejected year.
  - Tests: the real RMC 62 fixture line `June 25,2426` produces no
    2426-dated pair anywhere in the extraction (it must surface as
    window/unreadable, with the note); the RMC 89 golden output is
    byte-identical to before.
  - Verify: TS suite green, count above baseline; snapshots restored.
  - Commit: `fix: refuse OCR date literals outside the circular's year`

- [x] **C5 — the office-count invariant only trusts a counted phrase.**
  - Files: `scripts/news-sync/extract-rdos.ts` (+ test file).
  - Change: `OFFICE_COUNT_PATTERN` currently accepts any 1–3 digit number
    within 40 chars before `Office(s)` — list markers and page numbers
    qualify. First read BOTH fixtures and copy the exact counted phrases into
    the tests: RMC 89's page-1 sentence that yields 58, and RMC 62's lines
    where `2.` (a list marker) currently supplies the 2. Then tighten the
    pattern so a count is accepted only with counting context — a
    parenthesized numeral (`(58)`) or a qualifier immediately before the
    number (`following`, `affected`, `covered`, `total of`) — and a list
    marker at line start followed by `Revenue District Office` is explicitly
    NOT a count. If no confident count exists, return `null` (the invariant
    already prints "the prose states no count, nothing to compare").
  - Acceptance: RMC 89 still reports its real stated count with the invariant
    passing (58 = 58 — confirm the true phrase from the fixture, do not
    assume); RMC 62 now reports `statedOfficeCount === null` (its only
    "count" was the list-marker accident), with everything else in its
    extraction unchanged; a synthetic line `2. Revenue District Office No.
    110 - X` yields null.
  - Note: this deliberately REMOVES RMC 62's accidental 2 = 2 pass — update
    its existing test accordingly and say so in the commit body.
  - Verify: TS suite green; snapshots restored.
  - Commit: `fix: only count district offices from a counted phrase`

### Phase C-D — hygiene and coverage (P3)

- [x] **C6 — Windows recipes for the news pipeline.**
  - Files: `scripts/just-windows.ps1`, `Justfile` (windows recipe stubs if the
    existing pattern needs them).
  - Change: mirror what the unix recipes gained: the `check` verb also runs
    `npm run typecheck:news-sync` and `npm run test:news-sync`; add
    `news-sync` and `news-sync-offline` verbs invoking the same npm scripts.
    Follow the file's existing structure exactly (look at how `check`/`test`
    verbs are built there).
  - Honest limit: there is no Windows host or CI here. Acceptance is
    structural: the verbs exist, reference only npm scripts that exist, and
    `pwsh` syntax-checks if `pwsh` is installed
    (`pwsh -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw scripts/just-windows.ps1))"`);
    if `pwsh` is absent, note that in the commit body and move on. Add one
    line to `docs/WINDOWS_DEVELOPMENT.md` naming the new verbs and that they
    are unverified on the audited host.
  - Commit: `chore: give the news pipeline its Windows recipes`

- [x] **C7 — ETag strengthens the unchanged-PDF check.**
  - Files: `scripts/news-sync/state.ts`, `scripts/news-sync/sync.ts`,
    `scripts/news-sync/pdf.ts` (wherever the HEAD is issued), tests.
  - Change: record the response `ETag` (when present) alongside size/sha; the
    HEAD comparison treats a matching strong ETag as unchanged, a
    *mismatching* ETag as changed even when Content-Length matches, and
    absence of ETag as today's size-only behavior. Weak ETags (`W/`) are
    ignored. State serialization stays deterministic; absent etag is omitted,
    not null-printed.
  - Tests: same-size + different ETag → re-download; same ETag → skip without
    body GET; no ETag → size rule as before; existing state files (no etag
    field) parse fine.
  - Verify: TS suite green, count above baseline; snapshots restored.
  - Commit: `feat: notice a same-size PDF replacement via ETag`

- [x] **C8 — prune long-expired synced overrides.**
  - Files: `src/calendar/store.zig` (+ its tests in-file).
  - Change: at the end of `syncOverridesFromFeed`'s transaction, delete rows
    where `origin='synced'` AND `external_ref IS NOT NULL` AND
    `adjusted_deadline < date('now', '-400 days')` (SQLite date on the ISO
    text column is safe — the column is validated ISO). Count them in
    `SyncSummary.pruned_expired`. Manual rows are never touched; dismissal
    tombstones are left alone (they are tiny and keep their meaning).
    400 days keeps a full prior filing year visible.
  - Tests: a synced row adjusted 2+ years ago is pruned by a sync and counted;
    a manual row with the same old date survives; a synced row 300 days old
    survives; the summary counts land in the reload notice only if the
    existing notice already prints sync counts (extend the same seam, do not
    invent a new surface).
  - Verify: `npx native test` passes with count above baseline.
  - Commit: `feat: prune synced overrides a year past their extension`

- [x] **C9 — ingest the Advisories tab as notices — INVESTIGATED, DECLINED.**
  The template exists and was found mechanically: **template 2, "Advisories"**
  (the same scan also names 4 = Programs, 9 = New Issuances, 15 = News, so the
  homepage's four What's New tabs are templates 2/4/9/15). It was not ingested,
  because the dataset cannot serve the feature it would feed:

  - **It is abandoned.** All 20 rows are 2023 content — 32 mentions of `2023`
    across the payload and not one of 2024, 2025 or 2026. The newest is a
    December 2023 public-auction notice. Nothing has been added in ~2.5 years.
  - **It carries no date.** Each row is a numeric CMS id, a
    `URL|Label` pair and an HTML blurb. Dates appear only incidentally inside
    prose or filenames (`Tax Advisory eSales System 12.13.2023.pdf`), and many
    rows have none at all.

  Together those are disqualifying rather than merely inconvenient. Undated
  notices fall back to first-seen dating, so all twenty would be stamped with
  the run clock and filed under the current month — a 2023 auction notice
  presented as this month's news, in the very pane whose whole purpose is
  showing what belongs to the month on screen. Ingesting would make the
  headline feature actively misleading in exchange for content BIR itself
  stopped maintaining.

  Revisit only if BIR resumes publishing advisories **and** the dataset gains a
  date field. The template id and payload shape are recorded here so the next
  attempt starts from evidence rather than a fresh scan.

### Phase C-E — reconciliation

- [ ] **C10 — make every tracker tell the truth.**
  - Files: `docs/news/IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md`,
    `docs/news/MERGED_CELL_INVESTIGATION.md`, `docs/news/NEXT_STEPS.md`.
  - Fix, verifying each count by grep rather than arithmetic in your head:
    1. Execution plan: recount `- [x]`/`- [ ]`; fix the `Progress:` line
       (currently claims 29/31 while the file holds 30+2); tick **T7.4**
       (delivered: persisted dashboard RDO context, commit
       `feat: remember the dashboard's district context across launches`) and
       **T10.2** (resolved: curated supplement + investigation; edit its
       checkbox line to say resolution rather than "decision needed"); update
       the two phase counters those sit under.
    2. `MERGED_CELL_INVESTIGATION.md`: replace the "decision you need to
       make" framing in the title/intro with a dated resolution note: option 1
       (curated supplement) shipped in `curated/overrides.json`; the analysis
       stands as the reason options 2/3 were not taken.
    3. `NEXT_STEPS.md`: top pointer says this file
       (`COMPLETION_PLAN_2026-08-11.md`) is now the active tracker.
  - Verify: `grep -c '^- \[x\]'` and `'^- \[ \]'` on the execution plan sum
    to the number its Progress line states; this plan's own Progress line is
    current; `git diff --check "$(git merge-base origin/main HEAD)" HEAD`
    clean.
  - Commit: `docs: reconcile the feature trackers with what shipped`

- [ ] **C11 (USER) — merge the completion branch.** Whatever branch C1–C10
  landed on (see §1.2 branch rule): open/refresh the PR
  (`gh pr create` if none exists for it), hand the URL to the user, and stop.
  After the user merges, verify like C0 taught: `main` contains the last task
  commit, CI green.

- [ ] **C12 [blocking] — post-merge production check.**
  - After C11: dispatch once (`gh workflow run news-sync.yml --ref main`),
    confirm success, confirm the published feed still validates
    (override count unchanged or grown only by curated/advisory additions,
    every `rdo_codes` count intact), and confirm the **next scheduled slot**
    (UTC 04/10/16/22) ran with conclusion `success` and made **no commit** on
    a quiet cycle (`gh api repos/<owner>/<repo>/commits?sha=news-feed` —
    newest commit unchanged). Record the observed run id and timestamps in
    §6.
  - Commit (docs only): `docs: record the completion verification`

---

## 5. Closeout checklist (run after the last box is ticked)

```sh
just verify                          # exit 0
npm run test:news-sync               # 0 fail
git diff --check "$(git merge-base origin/main HEAD)" HEAD   # clean, if a branch is still open
curl -s https://raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json \
  | python3 -c "import json,sys;f=json.load(sys.stdin);assert f['schema_version']==1;print('OK',len(f['notices']),'notices',len(f['overrides']),'overrides')"
```

Then update this file's `Progress:` line to `13/13`, set a final
`Status: complete <date>` line under the title, and report to the user: the
per-task results with real numbers, anything left in §6, and the final
production state.

## 6. Discovered during execution

- C9: the homepage's four What's New tabs are CMS templates 2 (Advisories),
  4 (Programs), 9 (New Issuances) and 15 (News). Only 9 is ingested. Templates
  4 and 15 were not assessed; if either is ever wanted, check first whether it
  carries a date field, which template 2 does not.
- C2: `remoteContentLength` swallows every HEAD failure and returns null, so a
  403 there degrades to a download attempt rather than being distinguishable.
  That is safe but means an origin refusing HEAD and GET costs one wasted
  request before the refusal is recognised.
