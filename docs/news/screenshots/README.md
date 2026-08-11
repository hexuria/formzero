# R3 live dry-run — 2026-08-11

Plan task T8.2. Captured from the real app driven headlessly through
`npx native automate` (build with `-Dautomation=true`), reading the feed a
**live** `npm run news:sync -- all` produced from bir.gov.ph, served over
`http://127.0.0.1:8791/feed.json` via `BUWIZ_NEWS_FEED_URL`. No synthetic feed
and no taxpayer data: every notice is a public BIR issuance and the app had no
profiles configured.

| Screenshot | State | Aug 10 | Aug 17 |
| --- | --- | --- | --- |
| `01-august-nationwide-baseline.png` | Nationwide (default) | **9 deadlines** | 1 deadline |
| `02-august-rdo-039-markers-moved.png` | RDO 039 – South Quezon City | **6 deadlines** | **4 deadlines** |
| `03-july-2026-news-pane.png` | July 2026, nationwide | — | — |

The three deadlines that move between the first two shots are
`1601C`, `0619E` and `0619F` — RMC No. 89-2026's non-eFPS extension, applied
because 039 is one of the 60 district codes the circular scopes it to. The
nationwide view deliberately does not move (decision D2), and the amber caption
in shot 02 says so in as many words. Selecting an RDO outside the circular, or
clearing back to Nationwide, returns the markers to 9 and 1.

## What the live run proved

- **112 issuances, 96 new, every one dated from a yearly-archive row** — none
  fell back to the PDF header or to first sighting. The multi-kind archive fix
  holds at full scale, not just on the six-row fixture.
- The feed clears every app-side bound with room to spare: 56 KB of 512 KB,
  112 notices of 120, 3-byte RDO codes against an 8-byte cap.
- Notices span eight month buckets (January–August 2026), so the month-scoped
  pane was exercised across real month boundaries rather than a synthetic pair.

## What the live run found

1. **Notice dates were rendering a day early** (fixed in this pass). The row
   label formatted `published_at_unix` in UTC while bucketing used Manila, and
   the feed stamps midnight Manila — 16:00 the previous day UTC. Every notice
   read one day early, and RMC 73-2026 sat under a "July 2026" pane header
   while its own row said "June 30". `formatNewsTimestamp` now uses
   `manilaCivilDate`, the same reading that buckets the notice, so the two
   cannot disagree. Shot 01 shows the corrected dates (August 10 / 6 / 4).
2. **Six of seven extension circulars this year yield no overrides.** Two
   (RMC 12-2026, RMC 04-2026) are image-only scans with no text layer at all —
   the documented D3 limitation, correctly flagged for manual review. The
   others do have text, and RMC 62-2026 is a real miss: it names its two
   offices as `Revenue District Office No. 1 10` in a numbered list rather than
   the `RDO No. X` form the extractor matches, and OCR mangled its table header
   into `I)ue Date` / `E:rtended Due Date` so the deadline table was never
   located. Its review report flags the failure (`office-count invariant
   FAILED: the prose states 2 office(s) but the extractor matched 0`), which is
   the fail-closed design working — nothing wrong was published, an extension
   was simply not applied. Tracked as T10.1.

## Reproducing

```sh
npm run news:sync -- all                     # live; rewrites feed/state/review
npx native build . --yes -Dautomation=true
(cd scripts/news-sync/feed && python3 -m http.server 8791 --bind 127.0.0.1 &)
eval "$(node scripts/app-identity.mjs prepare --format shell)"
BUWIZ_NEWS_FEED_URL=http://127.0.0.1:8791/feed.json "./zig-out/bin/$BUWIZ_APP_NAME" &
npx native automate wait && npx native automate resize 1400 900
npx native automate snapshot | grep 'Important News'
npx native automate screenshot main-canvas 0.5
```

The effect layer accepts http/https only, so the feed must be served over
localhost rather than named with a `file://` URL.
