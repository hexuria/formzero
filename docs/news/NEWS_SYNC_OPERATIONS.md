# BIR news sync operations

This is the runbook for the pipeline that fills the app's Important News pane
and its synced deadline overrides. It assumes no prior knowledge of how the
pipeline was built. The design rationale lives in the
[execution plan](IMPORTANT_NEWS_SYNC_EXECUTION_PLAN_2026-08-11.md); this
document is only about running and repairing it.

The pipeline is `scripts/news-sync/`, written in TypeScript, run by
`.github/workflows/news-sync.yml` four times a day. It reads BIR's own content
API, mines deadline-extension circulars out of their published PDFs, and
compiles one `feed.json`. The desktop app fetches that file at startup and on
the Important News refresh button.

Nothing in this pipeline is authoritative. The extractor is deterministic and
fail-closed: when it cannot read something confidently it publishes the notice
and withholds the override, and the app's own original-date equality guard
means a wrongly dated override matches nothing rather than moving a marker to
the wrong day. The visible failure mode is a marker that does not move, never
a marker that moves to a fabricated date.

## Sources and the header contract

| Source | URL | Used for |
| --- | --- | --- |
| New Issuances widget | `https://bir-cms-ws.bir.gov.ph/api/pub/templates/9/datasets` | Detecting issuances published since the last run. Carries no dates. |
| Yearly RMC archive | `…/templates/3752/datasets` (2026) | Publication dates, completeness, and backfill for Revenue Memorandum Circulars. |
| Yearly RMO archive | `…/templates/3753/datasets` (2026) | The same, for Revenue Memorandum Orders. |
| Yearly RR archive | `…/templates/3754/datasets` (2026) | The same, for Revenue Regulations. |
| Issuance PDFs | `https://bir-cdn.bir.gov.ph/…` | Deep extraction of deadline-extension circulars. |

Every CMS request must carry two headers exactly:

```
client-website-id: 2
origin: https://www.bir.gov.ph
```

They are not optional and they are not cosmetic. The CMS answers `403
forbidden` without them. No cookie, token, or session is involved, and the
pipeline adds only a `user-agent: buwiz-news-sync/1.0` on top. The contract was
verified by direct probing on 2026-08-11; the captured evidence, including the
exact responses, is committed under
`scripts/news-sync/fixtures/2026-08-11/CAPTURES.md`.

`pdftotext -layout` from poppler is the only non-npm dependency. `sync.ts`
checks for it at startup and exits 2 with an install hint
(`brew install poppler`, `sudo apt-get install -y poppler-utils`).

## Schedule

GitHub cron runs in UTC. The Philippines is UTC+8 year round with no daylight
saving, so the mapping is fixed:

| Cron (UTC) | Asia/Manila |
| --- | --- |
| `0 22 * * *` | 06:00 |
| `0 4 * * *` | 12:00 |
| `0 10 * * *` | 18:00 |
| `0 16 * * *` | 00:00 (next day) |

The workflow declares all four in one expression: `0 4,10,16,22 * * *`. GitHub
delays scheduled runs by minutes under load; at this cadence that does not
matter. `concurrency: news-sync` prevents two runs from racing on the
publishing branch, and `workflow_dispatch` allows a manual run at any time.

Most runs are no-ops. An issuance already recorded in `state/seen.json` with an
unchanged PDF checksum skips extraction, and the publish step commits only when
the compiled output actually changed.

## What a run produces, and where the feed is published

One run writes four things inside `scripts/news-sync/`:

- `feed/feed.json` — the compiled feed the app reads (schema 1, notices plus
  overrides, size budget 512 KiB).
- `state/seen.json` — per-issuance dedupe state keyed by external id, holding
  the PDF SHA-256 and the first-seen timestamp.
- `review/<external-id>.md` — one human-readable extraction report per
  deep-extracted circular, for example `review/bir-rmc-2026-089.md`.
- `work/` — downloaded PDFs and cached extraction results. Scratch only, and
  gitignored.

The workflow copies the first three onto the orphan branch `news-feed`, whose
history contains nothing from `main`. The app fetches:

```
https://raw.githubusercontent.com/hexuria/formzero/news-feed/feed.json
```

That address is the `important_news_feed_url` constant in `src/main.zig`.
Setting `BUWIZ_NEWS_FEED_URL` overrides it for one launch, which is how a
staging branch or a locally served copy gets exercised without a rebuild. The
effect layer accepts `http` and `https` only, so a local file has to be served
over `http://localhost` rather than named with `file://`.

A failed run publishes nothing. The previously published feed stays live and
the app keeps serving it, and if the fetch itself fails the app keeps its last
good SQLite cache.

Each run restores `feed.json`, `state/seen.json` and `review/` from the
`news-feed` branch before syncing. The checkout only carries the snapshot
committed alongside the last code change, so without that restore a run
rediscovers every issuance published since then, re-downloads its PDF, and
republishes a feed differing only in `generated_at_unix` and `firstSeenAtUnix`
— a commit every six hours whether or not BIR published anything. With it, a
run that finds nothing new makes no commit at all.

## Migrating the feed to Cloudflare R2 + a Worker (decided, not yet scheduled)

GitHub raw is the accepted v1 host (decision Q1, 2026-08-11): zero
infrastructure and an auditable publish history, at the cost that anyone with
write access to this repository can alter a feed that moves filing dates.
When the app has real users, move hosting to Cloudflare. The pipeline,
schema, and app parser are all host-agnostic, so the migration is confined to
the publish step and one constant. Tasks, in order:

1. **Create the bucket:** `wrangler r2 bucket create buwiz-news`.
2. **Add the repository secret** `CLOUDFLARE_API_TOKEN` (R2 object-write
   scope only, single bucket) plus `CLOUDFLARE_ACCOUNT_ID`.
3. **Swap the publish step** in `.github/workflows/news-sync.yml`: replace the
   orphan-branch commit step with
   `npx wrangler r2 object put buwiz-news/feed.json --file scripts/news-sync/feed/feed.json`
   (keep the change-detection guard so unchanged runs still publish nothing;
   keep committing `state/` and `review/` to `news-feed` so the audit trail
   survives the move).
4. **Deploy the Worker:** a ~40-line read-only route (GET only) that serves
   the object with `content-type: application/json` and
   `cache-control: max-age=300`, bound to the bucket via an R2 binding. No
   write path exists in the Worker at all.
5. **Point the app at it:** change `important_news_feed_url` in
   `src/main.zig` to the Worker URL — this is the only app change — and
   update the address shown earlier in this section.
6. **Cutover safely:** publish to *both* hosts for one release so older
   builds keep working, verify the Worker URL serves the same SHA-256 as the
   raw URL, then remove the feed copy from the `news-feed` branch publish.
7. **Rollback** is the same constant changed back; the orphan branch remains
   the fallback host as long as step 6's dual publish is kept.

## Yearly template rollover

The yearly archive templates are per kind and per year: 3752, 3753, and 3754
are the 2026 Revenue Memorandum Circulars, Orders, and Regulations. BIR mints
new template ids each January, so these numbers expire.

`discoverYearTemplateId(kind, year)` re-derives the id on every run by fetching
`https://www.bir.gov.ph/{year}-Revenue-Memorandum-Circulars` (and the Orders
and Regulations equivalents) and pulling the id out of the served HTML. The
marker sits inside a JavaScript string in the Next.js payload, so it arrives
backslash-escaped; both the escaped and bare forms are matched.

`KNOWN_YEAR_TEMPLATE_IDS` in `scripts/news-sync/cms.ts` is the fallback, and it
currently holds 2026 only. Behavior when discovery fails:

- A checked-in id exists for that `(kind, year)` — the run warns on stderr and
  uses it.
- No checked-in id exists — the run **fails** with a message naming the map key
  to add. It does not guess.

So the January check is: after the new year's first run, confirm the log shows
no discovery warning. If it warns, or the run fails outright, resolve the new
ids by hand and commit them:

```sh
for kind in Revenue-Memorandum-Circulars Revenue-Memorandum-Orders Revenue-Regulations; do
  curl -s "https://www.bir.gov.ph/2027-$kind" | grep -o '\\"code\\":\\"[0-9]*\\",\\"dataMapper\\"'
done
```

Add the results to `KNOWN_YEAR_TEMPLATE_IDS` as `"RMC:2027"`, `"RMO:2027"`,
`"RR:2027"`. Committing the map entry is cheap insurance even when discovery is
working, because it turns a future site redesign into a warning instead of an
outage.

## Failure triage

Start from the failed workflow run page. The final step prints the last 40
lines of the sync log and a triage reminder as a `::error` annotation.

| Symptom | Meaning | Action |
| --- | --- | --- |
| `HTTP 403 forbidden` from a CMS request | The header contract drifted. BIR changed what it requires beyond `client-website-id` and `origin`. | Re-probe the API by hand with the curl in Appendix B of the execution plan, compare against `fixtures/2026-08-11/CAPTURES.md`, and update `CMS_REQUEST_HEADERS` in `cms.ts`. Nothing else in the pipeline needs to change. |
| Exit code 2 at startup | `pdftotext` is missing on the runner. | Confirm the `poppler-utils` install step still succeeds. Locally, `brew install poppler`. |
| `cannot resolve the <year> <kind> archive template id` | Discovery failed and no fallback is checked in. | Yearly rollover, above. |
| `template-id discovery … failed; falling back to the checked-in id` | Discovery regex missed but the map saved the run. The feed is still correct. | Not urgent, but it means the page markup moved. Re-check `extractYearTemplateId` before the next January. |
| Report says **Needs manual review: yes** with an unusable text layer | `pdftotext` produced under 200 characters per page, so BIR shipped a scan without an OCR layer. No rows were extracted and no override is emitted. | The notice still publishes. If the circular matters, enter the override by hand in the app's override editor. Adding an OCR stage is tracked as a follow-up, not a v1 behavior. |
| Report says **office-count invariant FAILED** | The circular's prose states a number of affected offices that disagrees with the RDO codes actually matched. | Read `review/<external-id>.md`. The RDO matches section lists every match with its raw OCR text and its confidence, so the missing or spurious office is usually obvious. Overrides are still emitted, scoped to the offices that were matched — treat a mismatch as "the scope may be too narrow", not as "the dates are wrong". |
| A known circular publishes as a notice but moves no marker | Ordinary and expected for most rows. Only rows with a date pair printed on their own lines become overrides; merged-cell rows are held back deliberately. | Read the "Dropped / needs review" section of the review report. Each held-back row is listed with its reason and its nearest printed dates, which is enough to add a manual override in seconds. |
| The feed is stale but no run failed | Every run was a legitimate no-op, or the publish step found no change. | Check `state/seen.json` on the `news-feed` branch against the live archive. Use `--force` (below) to rewind one issuance. |

Parser repairs are developed offline. The committed captures under
`fixtures/2026-08-11/` reproduce the failing input without touching the
network:

```sh
just news-sync-offline
npm run test:news-sync
```

## Forcing re-extraction of one issuance

After fixing an extractor bug, the affected issuance has to be rewound, because
its unchanged checksum otherwise makes the pipeline skip it:

```sh
npm run news:sync -- all --force bir:rmc:2026:089
```

`--force` accepts the issuance external id (`bir:<kind>:<year>:<number padded
to three digits>`), repeats for several issuances, and works with `--offline`.
It clears the cached extraction, re-runs the PDF stages, and preserves the
original first-seen timestamp so the notice does not jump to the top of the
feed. Because an override's identity is
`<external-id>/<original-date>/<channel>`, a corrected extraction updates the
same record in place — in the pipeline and in every app that syncs it. It never
creates a duplicate.

## Dismissing a bad synced override in the app

A synced override that should not apply is removed by the user, not by editing
the feed.

In the app, open **Tax Calendar** and find the override in the overrides list.
Synced rows carry a "Synced from BIR" badge, their source reference, and a
disabled Edit button — a synced row is not editable, because the next sync
would overwrite the edit. Its remove action reads **Dismiss** instead of
Delete. Pressing it once asks for confirmation; pressing it again writes a
tombstone and deletes the row.

The tombstone is permanent for that install: future syncs skip that
`external_ref` and will not re-add it. A different rule for the same deadline
is recorded as a separate manual override, which the sync never touches.

Removing the override from the published feed is the wrong lever for one bad
row. Synced overrides deliberately survive a notice rolling off the feed,
because deadline history has to outlive the 120-notice window.
