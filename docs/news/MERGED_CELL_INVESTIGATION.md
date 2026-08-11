# Merged deadline-table cells — investigation and outcome

2026-08-11. Investigated the plan's documented upgrade path for the rows the
extractor refuses to guess (§5.6 step 5, plan task T10.2). The documented
approach rests on a false premise, and the honest alternative trades away the
property the whole extractor is built on, so **no geometry pass was built**.

**Resolved.** The gap this investigation found — the feed under-applying
RMC 89-2026 — was closed instead by option 1 below: the missing forms ship as a
human-reviewed curated supplement in `scripts/news-sync/curated/overrides.json`,
merged into the feed under a `-reviewed` reference namespace and listed
separately in the review report. The analysis that follows stands as the record
of why options 2 and 3 were not taken, and of what a future attempt would face.

## The finding that matters most (since closed)

**The feed under-applied RMC 89-2026.** Its Aug 10 → Aug 17 extension is printed
inside one bordered table cell that also contains **2200-M, 2200-C, 0620,
1600-VT, 1600-PT, 1606** and the NGAs block — not only the 1601C/0619E/0619F the
extractor could read. Likewise the Aug 15 → Aug 17 cell contains **1701Q and
1707-A** alongside 1702-RT/EX/MX.

A taxpayer filing 1606 or 0620 in an affected district was therefore shown
**10 August** when BIR had moved them to the 17th. The error ran in the safe
direction — an earlier date, so nobody filed late on our advice — and every row
was already named in `review/bir-rmc-2026-089.md` under "Dropped / needs
review". The curated supplement now carries all eight forms, so the published
feed states the extension in full.

## Why the documented `-tsv` path cannot work

The plan assumed "a date cell belongs to the description block whose vertical
span contains it". The real grid, read from the rendered page, is not shaped
that way: RMC 89-2026's table has **8 bordered rows, not 22**. One row holds up
to ten description paragraphs, spans a page break, and prints its date pair
**once, top-aligned with an arbitrary paragraph inside the row** — never centred
on the merged span.

| Row | Extent | Printed pair | Contains |
| --- | --- | --- | --- |
| A | p3 138.7 → p4 254.9 | Aug 10 → Aug 17 | sugar list, sugar release, e-Sales, 2200-M, **1601C/0619E/0619F**, 2200-C, 0620, 1600-VT/PT, 1606, NGAs |
| B–D | p4 | Aug 11 / 13 / 14 → Aug 17 | eFPS Groups E, D, B |
| E | p4 637.0 → p5 432.5 | Aug 15 → Aug 17 | loose-leaf, **1702-RT/EX/MX**, 1707-A, 1701Q+SAWT, eFPS Group A, e-PAYMENT Groups E/D/C&B |
| F | p5 | Aug 17 → Aug 17 | stockbrokers |
| G | p5 | blank → Aug 17 | ONETT, 0605/0613 |

Word coordinates carry no row-boundary signal. Measured across the table:

- true row boundaries: gaps of **15.5–16.3 pt**
- intra-row paragraph gaps: **13.5–40.4 pt**

The boundary set sits strictly *inside* the paragraph set, so no threshold
separates them, and the single largest gap in the table — 40.4 pt, between the
2200-M and 1601-C paragraphs — is *intra-row*. Gap magnitude does not merely
fail to help; it points the wrong way. `-bbox` carries the same coordinates and
fails identically.

## Why the working alternative was still refused

Every table page is one grayscale JPEG, so the rules exist only as pixels. A
horizontal-projection detector over the raster does find them, correctly, 12/12
on RMC 89-2026 and 12/12 on RMC 62-2026.

It was still not shipped, because **its failure mode inverts the guarantee the
extractor is built on**. Damaged OCR announces itself as an unparseable literal;
a rule missed to scan noise, a receiving stamp, or skew announces nothing and is
indistinguishable from a genuine merged cell. Concretely: miss the rule at
p5 496.8 and rows F and G merge, so ONETT — `1800, 1801, 1706, 1707, 1707-A,
0605, 0613` — silently inherits Aug 17 → Aug 17 and emits a **fabricated**
non-eFPS override. Today those rows are `window` and reach a human. Trading
"an extension is missed, and the report says so" for "an extension is invented,
and nothing says so" is the wrong direction for this app.

It would also add five thresholds tuned on two documents, a second poppler
binary, ~2.2 MB of PGM parsed per page, and cross-page row stitching as a second
unverifiable inference.

## The decision

Any *correct* geometry pass necessarily changes the two published records:

| Record | Today | After a correct geometry pass |
| --- | --- | --- |
| `…/2026-08-10/nonefps` | 1601C, 0619E, 0619F | + 2200M, 2200C, 0620, 1600VT, 1600PT, 1606 |
| `…/2026-08-15/nonefps` | 1702RT, 1702EX, 1702MX | + 1701Q, 1707A |

That is not a regression — it is the circular being read correctly. It does mean
"recover 1701Q" and "leave the existing records unchanged" cannot both hold, and
that §5.6.7's grouping rule would need rewriting, since 1701Q at
2026-08-15 → 2026-08-17 has nowhere to land except the 1702 record.

Three ways forward, in the order they were considered. **Option 1 was taken**,
in the shipped form described at the top of this file rather than as
editor-entered rows, because a manual override reaches one local database and
this had to reach every reader of the feed:

1. **Enter the missing rows as reviewed overrides** (chosen). The
   editor exists, synced and manual rows already coexist, and
   `review/bir-rmc-2026-089.md` names every affected row with its dates. Eight
   forms, a few minutes, no new failure mode, and it closes the real-world gap
   this investigation found. It does not scale to every future circular.
2. **Ship raster rule detection**, accepting a silent failure mode, ideally with
   a guard: refuse to emit when a detected row's paragraph count or page span
   looks implausible, so a missed rule degrades to `window` instead of to a
   fabricated override. That guard is the piece that would make it defensible,
   and it was not designed.
3. **Leave it.** The review report already surfaces these rows, and the app's
   date-equality guard means nothing wrong is ever shown — only something
   missing.

Whichever is chosen, the extractor's current behaviour is correct-by-omission,
not wrong.
