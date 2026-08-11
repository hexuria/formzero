import assert from "node:assert/strict";
import test from "node:test";

import { compileFeed } from "./feed.ts";
import { renderReviewReport, reviewReportPath } from "./review.ts";
import type {
  CircularExtraction,
  CuratedOverride,
  ExtensionRow,
  IssuanceRecord,
  RdoMatch,
} from "./types.ts";

const rmc89Id = "bir:rmc:2026:089";

function issuance(overrides: Partial<IssuanceRecord> = {}): IssuanceRecord {
  return {
    externalId: rmc89Id,
    kind: "RMC",
    number: "89-2026",
    subject:
      "Providing Extension of the Deadlines for the Filing of Tax Returns and Payment of Taxes " +
      "Due to the Southwest Monsoon.",
    pdfUrl: "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
    dateIssued: "2026-08-10",
    dateSource: "archive",
    source: "merged",
    firstSeenAtUnix: 1_786_665_600,
    ...overrides,
  };
}

function row(overrides: Partial<ExtensionRow> = {}): ExtensionRow {
  return {
    channel: "nonefps",
    rawDescription: "e-FILING & PAYMENT (Online/Manual)",
    formCodesDisplay: [],
    formCodesCanonical: [],
    originalDate: null,
    extendedDate: null,
    dateAssignment: "window",
    confidence: "high",
    notes: [],
    ...overrides,
  };
}

function rdo(code: string, raw: string, overrides: Partial<RdoMatch> = {}): RdoMatch {
  return {
    raw,
    code,
    referenceName: `RDO ${code}`,
    matchedBy: "code+name",
    confidence: "high",
    notes: [],
    ...overrides,
  };
}

const rows: ExtensionRow[] = [
  row({
    channel: "nonefps",
    rawDescription: "2200-M Excise Tax Return for metallic minerals",
    formCodesDisplay: ["2200-M"],
    formCodesCanonical: ["2200M"],
    extendedDate: "2026-08-17",
    dateAssignment: "window",
    confidence: "review",
    notes: ["no printed pair on the block's lines"],
  }),
  row({
    channel: "nonefps",
    rawDescription: "1601-C / 0619-E / 06 1 9-F — Non-eFPS Filers",
    formCodesDisplay: ["1601-C", "0619-E", "0619-F"],
    formCodesCanonical: ["1601C", "0619E", "0619F"],
    originalDate: "2026-08-10",
    extendedDate: "2026-08-17",
    dateAssignment: "same_line",
  }),
  row({
    channel: "efps_group_d",
    rawDescription: "1601-C — eFPS Filers under Group D",
    formCodesDisplay: ["1601-C"],
    formCodesCanonical: ["1601C"],
    originalDate: "2026-08-13",
    extendedDate: "2026-08-17",
    dateAssignment: "same_line",
    notes: ["extended column read Angttst 1'? ,2026; used globalExtendedDate"],
  }),
  row({
    channel: "efps_and_nonefps",
    rawDescription: "1701Q + SAWT — eFPS and Non-eFPS Filers (quarter ending 6/30) | merged cell",
    formCodesDisplay: ["1701Q"],
    formCodesCanonical: ["1701Q"],
    extendedDate: "2026-08-17",
    dateAssignment: "window",
    confidence: "review",
  }),
];

const extraction: CircularExtraction = {
  externalId: rmc89Id,
  headerDateIssued: "2026-08-10",
  globalExtendedDate: "2026-08-17",
  window: { from: "2026-08-10", to: "2026-08-16" },
  statedOfficeCount: 3,
  rdos: [
    rdo("007", "RDONo.T- Abra", { notes: ["digit context: T -> 7"] }),
    rdo("039", "RDO No. 39 - South Quezon City"),
    rdo("043", "RDO No. 43 - Pasig City"),
    {
      raw: "RDO No. 9Z - Nowhere",
      code: null,
      referenceName: null,
      matchedBy: "code",
      confidence: "review",
      notes: ["code not in reference"],
    },
  ],
  rdoCodes: ["007", "039", "043", "43A", "43B"],
  rows,
  needsManualReview: false,
  notes: ["prose states 3 offices"],
};

const curatedSupplement: CuratedOverride = {
  noticeExternalId: rmc89Id,
  originalDeadline: "2026-08-10",
  adjustedDeadline: "2026-08-17",
  channel: "nonefps",
  formCodes: ["2200M"],
  reviewed: "same bordered cell as the printed August 10 -> August 17 pair, page 3",
  reviewedOn: "2026-08-11",
};

function report(curated: readonly CuratedOverride[] = []): string {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [extraction],
    curated,
    generatedAtUnix: 1_786_742_400,
  });
  return renderReviewReport({
    issuance: issuance(),
    extraction,
    emitted: feed.overrides,
    dropped,
  });
}

test("reviewReportPath turns the external id into a filename", () => {
  assert.equal(reviewReportPath("review", rmc89Id), "review/bir-rmc-2026-089.md");
  assert.equal(
    reviewReportPath("scripts/news-sync/review", "bir:rmo:2026:019"),
    "scripts/news-sync/review/bir-rmo-2026-019.md",
  );
});

test("the report carries every required section header", () => {
  const markdown = report();
  for (const heading of [
    "# Review — RMC No. 89-2026",
    "## Classification verdict",
    "## Office count invariant",
    "## RDO matches",
    "## Extension rows",
    "## Emitted overrides (machine-extracted)",
    "## Curated supplements (human-authored)",
    "## Dropped / needs review",
  ]) {
    assert.ok(markdown.includes(heading), `missing section: ${heading}`);
  }
});

test("the header names the date and the tier it came from", () => {
  assert.ok(report().includes("- Date source: yearly archive `DATE OF ISSUE`"));

  const fromPdf = renderReviewReport({
    issuance: issuance({ dateSource: "pdf_header" }),
    extraction,
    emitted: [],
    dropped: [],
  });
  assert.ok(fromPdf.includes("- Date source: PDF page-1 letterhead date"));
});

test("a first-seen published date is called out as invented, not as BIR's", () => {
  const markdown = renderReviewReport({
    issuance: issuance({ dateIssued: null, dateSource: "first_seen" }),
    extraction,
    emitted: [],
    dropped: [],
  });

  assert.ok(markdown.includes("- Date issued: —"));
  assert.ok(markdown.includes("**first-seen fallback**"));
  assert.ok(markdown.includes("not BIR's issue date"));
});

test("the classification section states the verdict and the circular anchors", () => {
  const markdown = report();
  assert.ok(markdown.includes("**deadline-extension circular**"));
  assert.ok(markdown.includes("- Needs manual review: no"));
  assert.ok(markdown.includes("- Global extended date: 2026-08-17"));
  assert.ok(markdown.includes("- Stated extension window: 2026-08-10 to 2026-08-16"));
  assert.ok(markdown.includes(`- External ID: \`${rmc89Id}\``));
});

test("the office count invariant compares the prose count with the matches", () => {
  const markdown = report();
  assert.ok(markdown.includes("| Stated in prose | 3 |"));
  assert.ok(markdown.includes("| Distinct offices matched | 3 |"));
  assert.ok(markdown.includes("| Emitted `rdo_codes` (incl. lettered variants) | 5 |"));
  assert.ok(markdown.includes("| Verdict | MATCH |"));
});

test("a stated count that disagrees with the matches is reported as a mismatch", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [{ ...extraction, statedOfficeCount: 58 }],
    generatedAtUnix: 0,
  });
  const markdown = renderReviewReport({
    issuance: issuance(),
    extraction: { ...extraction, statedOfficeCount: 58 },
    emitted: feed.overrides,
    dropped,
  });
  assert.ok(markdown.includes("MISMATCH — the prose states 58, the extractor found 3"));
});

test("the RDO table shows raw text, code, match basis and confidence", () => {
  const markdown = report();
  assert.ok(markdown.includes("| Raw text | Code | Matched by | Confidence |"));
  assert.ok(markdown.includes("| RDONo.T- Abra | 007 | code+name | high |"));
  assert.ok(markdown.includes("| RDO No. 9Z - Nowhere | — | code | review |"));
});

test("the extension-row table lists every block with its channel and dates", () => {
  const markdown = report();
  assert.ok(
    markdown.includes("| # | Channel | Forms | Original | Extended | Assignment | Confidence |"),
  );
  assert.ok(
    markdown.includes(
      "| 2 | nonefps | 1601C, 0619E, 0619F | 2026-08-10 | 2026-08-17 | same_line | high |",
    ),
  );
  assert.ok(
    markdown.includes("| 3 | efps_group_d | 1601C | 2026-08-13 | 2026-08-17 | same_line | high |"),
  );
  assert.ok(markdown.includes("| 1 | nonefps | 2200M | — | 2026-08-17 | window | review |"));
});

test("the emitted-override section prints the record and its full RDO scope", () => {
  const markdown = report();
  assert.ok(
    markdown.includes(
      "| External ref | Original | Adjusted | Channel | Form codes | RDO codes |",
    ),
  );
  assert.ok(
    markdown.includes(
      `| \`${rmc89Id}/2026-08-10/nonefps\` | 2026-08-10 | 2026-08-17 | nonefps | ` +
        "0619E, 0619F, 1601C | 5 |",
    ),
  );
  assert.ok(markdown.includes(`RDO scope for \`${rmc89Id}/2026-08-10/nonefps\` (5 codes):`));
  assert.ok(markdown.includes("007 039 043 43A 43B"));
});

test("curated records are reported apart from the machine-extracted ones", () => {
  const markdown = report([curatedSupplement]);
  const extractedSection = markdown.slice(
    markdown.indexOf("## Emitted overrides (machine-extracted)"),
    markdown.indexOf("## Curated supplements (human-authored)"),
  );
  const curatedSection = markdown.slice(
    markdown.indexOf("## Curated supplements (human-authored)"),
    markdown.indexOf("## Dropped / needs review"),
  );

  assert.ok(markdown.includes("- Override records emitted: 2 (1 extracted, 1 curated)"));
  // Neither section may carry the other's record.
  assert.ok(extractedSection.includes(`\`${rmc89Id}/2026-08-10/nonefps\``));
  assert.ok(!extractedSection.includes("-reviewed"));
  assert.ok(
    curatedSection.includes(
      `| \`${rmc89Id}/2026-08-10/nonefps-reviewed\` | 2026-08-10 | 2026-08-17 | nonefps | ` +
        "2200M | 5 |",
    ),
  );
  assert.ok(curatedSection.includes("a human read off the printed table"));
  assert.ok(
    curatedSection.includes(`RDO scope for \`${rmc89Id}/2026-08-10/nonefps-reviewed\` (5 codes):`),
  );
});

test("a circular with no curated supplement says so under its own heading", () => {
  const curatedSection = report().slice(
    report().indexOf("## Curated supplements (human-authored)"),
    report().indexOf("## Dropped / needs review"),
  );
  assert.ok(curatedSection.includes("_No curated supplement is published for this circular._"));
});

test("every non-emitted row appears under Dropped with its nearest printed pairs", () => {
  const markdown = report();
  const droppedSection = markdown.slice(markdown.indexOf("## Dropped / needs review"));

  assert.ok(droppedSection.includes("3 of 4 block(s) produced no override."));
  assert.ok(droppedSection.includes("### Row 1 — `window_row` (nonefps, window)"));
  assert.ok(
    droppedSection.includes("### Row 3 — `channel_not_emittable` (efps_group_d, same_line)"),
  );
  assert.ok(droppedSection.includes("### Row 4 — `window_row` (efps_and_nonefps, window)"));
  assert.ok(
    !droppedSection.includes("### Row 2 —"),
    "the emitted row must not be listed as dropped",
  );

  // Row 1 has no pair above it; row 4's nearest pair above is the Group D row.
  assert.ok(
    droppedSection.includes(
      "- Nearest printed pair above: none\n" +
        "- Nearest printed pair below: row 2 — 2026-08-10 → 2026-08-17 (nonefps)",
    ),
  );
  assert.ok(
    droppedSection.includes(
      "- Nearest printed pair above: row 3 — 2026-08-13 → 2026-08-17 (efps_group_d)\n" +
        "- Nearest printed pair below: none",
    ),
  );
  assert.ok(droppedSection.includes("extended column read Angttst 1'? ,2026"));
});

test("the dropped section escapes pipes so the tables stay well formed", () => {
  const markdown = report();
  assert.ok(markdown.includes("(quarter ending 6/30) \\| merged cell"));
});

test("the compiler drop log reproduces the reasons the feed recorded", () => {
  const markdown = report();
  assert.ok(markdown.includes("### Compiler drop log"));
  assert.ok(markdown.includes("| Reason | Detail |"));
  assert.ok(markdown.includes("| `window_row` |"));
  assert.ok(markdown.includes("| `channel_not_emittable` |"));
});

test("a circular with nothing emittable says so in both sections", () => {
  const barren: CircularExtraction = {
    ...extraction,
    rdoCodes: [],
    rdos: [],
    statedOfficeCount: null,
    needsManualReview: true,
    notes: [],
    rows: [rows[0]],
  };
  const markdown = renderReviewReport({
    issuance: issuance(),
    extraction: barren,
    emitted: [],
    dropped: [],
  });

  assert.ok(markdown.includes("- Needs manual review: **yes**"));
  assert.ok(markdown.includes("| Stated in prose | — |"));
  assert.ok(markdown.includes("| Verdict | not stated in the prose — nothing to compare |"));
  assert.ok(markdown.includes("_No RDO references were matched in this circular._"));
  assert.ok(markdown.includes("_No override records were emitted for this circular._"));
  assert.ok(markdown.includes("_No extraction notes._"));
  assert.ok(markdown.includes("_The feed compiler recorded no drops for this run._"));
  assert.ok(markdown.includes("### Row 1 — `window_row` (nonefps, window)"));
});

test("rendering is deterministic across calls", () => {
  assert.equal(report(), report());
});
