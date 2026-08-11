import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { readFileSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { CANONICAL_FORM_CODES } from "./form-codes.ts";
import {
  compileFeed,
  curatedOverridesPath,
  feedContentEquals,
  isCuratedRef,
  loadCuratedOverrides,
  manilaMidnightUnix,
  manilaMonthBucket,
  maxNotices,
  maxRdoCodeBytes,
  rowDropReason,
  serializeFeed,
  truncateUtf8,
  validateFeed,
} from "./feed.ts";
import { extractDeadlineRows, parseCircularAnchors } from "./extract-deadline-table.ts";
import { extractRdos } from "./extract-rdos.ts";
import type {
  CircularExtraction,
  CuratedOverride,
  ExtensionRow,
  Feed,
  IssuanceRecord,
} from "./types.ts";

const rmc89Id = "bir:rmc:2026:089";
const scopedRdoCodes = ["039", "043", "43A", "43B"];

function issuance(overrides: Partial<IssuanceRecord> = {}): IssuanceRecord {
  return {
    externalId: rmc89Id,
    kind: "RMC",
    number: "89-2026",
    subject: "Providing Extension of the Deadlines for the Filing of Tax Returns.",
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
    rawDescription: "e-FILING & PAYMENT (Online/Manual) — Non-eFPS Filers",
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

function extraction(overrides: Partial<CircularExtraction> = {}): CircularExtraction {
  return {
    externalId: rmc89Id,
    headerDateIssued: "2026-08-10",
    globalExtendedDate: "2026-08-17",
    window: { from: "2026-08-10", to: "2026-08-16" },
    statedOfficeCount: 58,
    rdos: [],
    rdoCodes: [...scopedRdoCodes],
    rows: [],
    needsManualReview: false,
    notes: [],
    ...overrides,
  };
}

/** The Appendix A.3 shape in miniature: two emittable pairs among noise. */
function appendixAExtraction(): CircularExtraction {
  return extraction({
    rows: [
      row({
        channel: "submission",
        rawDescription: "Sugar buyer list / refined sugar release",
        dateAssignment: "window",
        extendedDate: "2026-08-17",
        confidence: "review",
      }),
      row({
        channel: "nonefps",
        rawDescription: "2200-M metallic minerals",
        formCodesDisplay: ["2200-M"],
        formCodesCanonical: ["2200M"],
        dateAssignment: "window",
        extendedDate: "2026-08-17",
        confidence: "review",
      }),
      row({
        channel: "nonefps",
        rawDescription: "1601-C / 0619-E — Non-eFPS Filers",
        formCodesDisplay: ["1601-C", "0619-E"],
        formCodesCanonical: ["1601C", "0619E"],
        originalDate: "2026-08-10",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
      }),
      row({
        channel: "efps_and_nonefps",
        rawDescription: "0619-F — eFPS and Non-eFPS Filers",
        formCodesDisplay: ["06 1 9-F"],
        formCodesCanonical: ["0619F"],
        originalDate: "2026-08-10",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
        notes: ["digit normalization: 06 1 9-F -> 0619-F"],
      }),
      row({
        channel: "efps_group_e",
        rawDescription: "1601-C / 0619-E / 0619-F — eFPS Filers under Group E",
        formCodesDisplay: ["1601-C"],
        formCodesCanonical: ["1601C"],
        originalDate: "2026-08-11",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
        notes: ["day token August 1 l -> 11"],
      }),
      row({
        channel: "nonefps",
        rawDescription: "1702 - RT/EX/MX (FY ending 4/30)",
        formCodesDisplay: ["1702-RT", "1702-EX", "1702-MX"],
        formCodesCanonical: ["1702RT", "1702EX", "1702MX"],
        originalDate: "2026-08-15",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
      }),
      row({
        channel: "submission",
        rawDescription: "Stockbrokers consolidated return (Aug 1-15)",
        originalDate: "2026-08-17",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
      }),
    ],
  });
}

/** A supplement to the Aug 10 record the Appendix A extraction produces. */
function curated(overrides: Partial<CuratedOverride> = {}): CuratedOverride {
  return {
    noticeExternalId: rmc89Id,
    originalDeadline: "2026-08-10",
    adjustedDeadline: "2026-08-17",
    channel: "nonefps",
    formCodes: ["2200M", "1606"],
    reviewed: "the bordered cell on page 3 that prints August 10,2026 -> August 17,2026",
    reviewedOn: "2026-08-11",
    ...overrides,
  };
}

function compileWithCurated(entries: readonly CuratedOverride[]) {
  return compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    curated: entries,
    generatedAtUnix: 1_786_742_400,
  });
}

test("compileFeed emits one override per same_line date pair with merged form codes", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    generatedAtUnix: 1_786_742_400,
  });

  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    [`${rmc89Id}/2026-08-10/nonefps`, `${rmc89Id}/2026-08-15/nonefps`],
  );

  const [first, second] = feed.overrides;
  // The efps_and_nonefps 0619-F row merged into the nonefps record for its pair.
  assert.deepEqual(first.form_codes, ["0619E", "0619F", "1601C"]);
  assert.equal(first.original_deadline, "2026-08-10");
  assert.equal(first.adjusted_deadline, "2026-08-17");
  assert.equal(first.channel, "nonefps");
  assert.equal(first.title, "RMC 89-2026 extension (due 2026-08-10)");
  assert.equal(first.source_reference, "RMC No. 89-2026");
  assert.equal(first.notice_external_id, rmc89Id);
  assert.deepEqual(first.rdo_codes, scopedRdoCodes);

  assert.deepEqual(second.form_codes, ["1702EX", "1702MX", "1702RT"]);
  assert.equal(second.adjusted_deadline, "2026-08-17");

  assert.deepEqual(validateFeed(feed), []);

  // Every non-emitted row is accounted for: two window rows, the eFPS group
  // row, and the stockbroker submission row.
  assert.equal(dropped.length, 4);
  assert.deepEqual(
    dropped.map((entry) => entry.reason).toSorted(),
    ["channel_not_emittable", "channel_not_emittable", "window_row", "window_row"],
  );
  assert.equal(
    dropped.filter((entry) => entry.detail.includes("2200M")).length,
    1,
    "the 2200-M window row must be recoverable from the drop log",
  );
});

test("compileFeed publishes no override for an eFPS-only circular", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [
      extraction({
        rows: [
          row({
            channel: "efps_group_e",
            formCodesCanonical: ["1601C"],
            originalDate: "2026-08-11",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.deepEqual(feed.overrides, []);
  assert.equal(feed.notices.length, 1);
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["channel_not_emittable"],
  );
});

test("compileFeed refuses to emit an unscoped nationwide override", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [
      extraction({
        rdoCodes: [],
        rows: [
          row({
            formCodesCanonical: ["1601C"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.deepEqual(feed.overrides, []);
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["empty_rdo_scope"],
  );
});

test("compileFeed drops form codes outside the app catalog but keeps the record", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [
      extraction({
        rows: [
          row({
            formCodesDisplay: ["1601-C", "1601"],
            formCodesCanonical: ["1601C", "1601"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.deepEqual(feed.overrides[0].form_codes, ["1601C"]);
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["non_canonical_form_code"],
  );
  assert.deepEqual(validateFeed(feed), []);
});

test("compileFeed drops a second pair that would collide on external_ref", () => {
  const { feed, dropped } = compileFeed({
    issuances: [issuance()],
    extractions: [
      extraction({
        rows: [
          row({
            formCodesCanonical: ["1601C"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
          row({
            formCodesCanonical: ["0620"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-18",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.equal(feed.overrides.length, 1);
  assert.deepEqual(feed.overrides[0].form_codes, ["1601C"]);
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["duplicate_external_ref"],
  );
  assert.deepEqual(validateFeed(feed), []);
});

test("a curated supplement is published beside the record it supplements", () => {
  const { feed, dropped } = compileWithCurated([curated()]);

  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    [
      `${rmc89Id}/2026-08-10/nonefps`,
      `${rmc89Id}/2026-08-10/nonefps-reviewed`,
      `${rmc89Id}/2026-08-15/nonefps`,
    ],
  );

  const [extracted, supplement] = feed.overrides;
  assert.ok(!isCuratedRef(extracted.external_ref));
  assert.ok(isCuratedRef(supplement.external_ref));
  assert.deepEqual(supplement.form_codes, ["1606", "2200M"]);
  // The scope is inherited from the extraction, never declared by hand, so it
  // follows the extraction if the circular's office list is ever re-read.
  assert.deepEqual(supplement.rdo_codes, extracted.rdo_codes);
  assert.deepEqual(supplement.rdo_codes, scopedRdoCodes);
  assert.equal(supplement.channel, "nonefps");
  assert.equal(supplement.original_deadline, "2026-08-10");
  assert.equal(supplement.adjusted_deadline, "2026-08-17");
  assert.equal(supplement.source_reference, extracted.source_reference);
  assert.equal(supplement.notice_external_id, rmc89Id);
  assert.equal(supplement.title, "RMC 89-2026 extension (due 2026-08-10) — curated supplement");
  // The extracted record is untouched by the supplement.
  assert.deepEqual(extracted.form_codes, ["0619E", "0619F", "1601C"]);

  assert.deepEqual(validateFeed(feed), []);
  assert.ok(!dropped.some((entry) => entry.reason.startsWith("curated_")));
});

test("a curated entry the extraction cannot scope is dropped, never published unscoped", () => {
  // No extracted record for this date pair: there is no RDO scope to inherit.
  const { feed, dropped } = compileWithCurated([curated({ originalDeadline: "2026-08-11" })]);

  assert.equal(feed.overrides.length, 2);
  assert.ok(feed.overrides.every((override) => !isCuratedRef(override.external_ref)));
  assert.deepEqual(
    dropped.filter((entry) => entry.reason.startsWith("curated_")).map((entry) => entry.reason),
    ["curated_no_extracted_record"],
  );
  assert.deepEqual(validateFeed(feed), []);
});

test("a curated entry naming an unknown notice is dropped and the run continues", () => {
  const { feed, dropped } = compileWithCurated([
    curated({ noticeExternalId: "bir:rmc:2026:999" }),
    curated({ formCodes: ["1606"] }),
  ]);

  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    [
      `${rmc89Id}/2026-08-10/nonefps`,
      `${rmc89Id}/2026-08-10/nonefps-reviewed`,
      `${rmc89Id}/2026-08-15/nonefps`,
    ],
  );
  assert.deepEqual(feed.overrides[1].form_codes, ["1606"]);
  assert.ok(dropped.some((entry) => entry.reason === "curated_unknown_notice"));
  assert.deepEqual(validateFeed(feed), []);
});

test("a curated entry's non-canonical form codes are dropped and reported", () => {
  const { feed, dropped } = compileWithCurated([curated({ formCodes: ["2200M", "1601", "2000Z"] })]);

  assert.deepEqual(feed.overrides[1].form_codes, ["2200M"]);
  const reported = dropped.find((entry) => entry.reason === "curated_non_canonical_form_code");
  assert.ok(reported !== undefined);
  assert.ok(reported.detail.includes("1601"));
  assert.ok(reported.detail.includes("2000Z"));
  assert.deepEqual(validateFeed(feed), []);

  // Nothing canonical left: the entry itself goes, and the feed is unaffected.
  const onlyNoise = compileWithCurated([curated({ formCodes: ["1601", "2000Z"] })]);
  assert.equal(onlyNoise.feed.overrides.length, 2);
  assert.ok(
    onlyNoise.dropped.some((entry) => entry.reason === "curated_no_canonical_form_codes"),
  );
  assert.deepEqual(validateFeed(onlyNoise.feed), []);
});

test("a curated entry that misreads the extended date is dropped, not published", () => {
  const { feed, dropped } = compileWithCurated([curated({ adjustedDeadline: "2026-08-18" })]);

  assert.equal(feed.overrides.length, 2);
  assert.deepEqual(
    dropped.filter((entry) => entry.reason.startsWith("curated_")).map((entry) => entry.reason),
    ["curated_date_pair_mismatch"],
  );
});

test("two curated entries for the same record cannot both be published", () => {
  const { feed, dropped } = compileWithCurated([curated(), curated({ formCodes: ["1707A"] })]);

  assert.equal(feed.overrides.length, 3);
  assert.deepEqual(feed.overrides[1].form_codes, ["1606", "2200M"]);
  assert.ok(dropped.some((entry) => entry.reason === "curated_duplicate_external_ref"));
  assert.deepEqual(validateFeed(feed), []);
});

test("validateFeed holds curated records to every rule extracted ones obey", () => {
  const { feed } = compileWithCurated([curated()]);
  assert.deepEqual(validateFeed(feed), []);

  const supplement = feed.overrides[1];
  const broken = (override: Partial<Feed["overrides"][number]>): string[] =>
    validateFeed({ ...feed, overrides: [{ ...supplement, ...override }] });

  assert.ok(broken({ form_codes: ["2200-M"] }).some((m) => m.includes("non-canonical form code")));
  assert.ok(broken({ rdo_codes: [] }).some((m) => m.includes("empty rdo_codes scope")));
  assert.ok(
    broken({ adjusted_deadline: "2026-08-01" }).some((m) => m.includes("precedes original_deadline")),
  );
  assert.ok(
    broken({ channel: "efps_group_a" }).some((m) => m.includes("non-emittable channel")),
  );
  assert.ok(
    broken({ external_ref: `${rmc89Id}/2026-08-10/nonefps-curated` }).some((m) =>
      m.includes("does not match its derived identity"),
    ),
  );
  assert.ok(
    broken({ notice_external_id: "bir:rmc:2026:999" }).some((m) => m.includes("absent from the")),
  );
});

test("the committed curated supplement is well formed and names only catalog codes", async () => {
  const { entries, dropped } = await loadCuratedOverrides();

  assert.deepEqual(dropped, [], "the committed supplement must parse cleanly");
  assert.ok(entries.length > 0);
  for (const entry of entries) {
    assert.equal(entry.channel, "nonefps", "an eFPS-group supplement is forbidden (decision L10)");
    assert.ok(entry.formCodes.length > 0);
    for (const code of entry.formCodes) {
      assert.ok(CANONICAL_FORM_CODES.has(code), `${code} is not a canonical app form code`);
    }
    // Each entry has to name the evidence a human checked, and when.
    assert.ok(entry.reviewed.length > 40, "reviewed must name the printed evidence");
    assert.match(entry.reviewedOn, /^\d{4}-\d{2}-\d{2}$/u);
    assert.ok(entry.adjustedDeadline >= entry.originalDeadline);
  }
  assert.equal(path.basename(curatedOverridesPath), "overrides.json");
});

test("loadCuratedOverrides drops damaged entries and survives a missing file", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "news-sync-curated-"));
  const target = path.join(directory, "overrides.json");
  await writeFile(
    target,
    JSON.stringify({
      entries: [
        { ...curated(), notice_external_id: rmc89Id },
        {
          notice_external_id: rmc89Id,
          original_deadline: "2026-08-10",
          adjusted_deadline: "2026-08-17",
          channel: "nonefps",
          form_codes: ["1606"],
          reviewed: "page 4, same bordered cell",
          reviewed_on: "2026-08-11",
        },
        {
          notice_external_id: rmc89Id,
          original_deadline: "2026-08-10",
          adjusted_deadline: "2026-08-17",
          channel: "efps_group_a",
          form_codes: ["1601C"],
          reviewed: "eFPS Group A cell",
          reviewed_on: "2026-08-11",
        },
        {
          notice_external_id: rmc89Id,
          original_deadline: "2026-08-32",
          adjusted_deadline: "2026-08-17",
          channel: "nonefps",
          form_codes: ["1606"],
          reviewed: "a day that does not exist",
          reviewed_on: "2026-08-11",
        },
        {
          notice_external_id: rmc89Id,
          original_deadline: "2026-08-10",
          adjusted_deadline: "2026-08-17",
          channel: "nonefps",
          form_codes: [],
          reviewed: "no forms at all",
          reviewed_on: "2026-08-11",
        },
        "not an entry",
      ],
    }),
    "utf8",
  );

  const { entries, dropped } = await loadCuratedOverrides(target);
  // Only the camelCase-shaped first entry and the well-formed second survive…
  assert.deepEqual(
    entries.map((entry) => entry.formCodes),
    [["1606"]],
  );
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    Array.from({ length: 5 }, () => "curated_malformed_entry"),
  );

  const missing = await loadCuratedOverrides(path.join(directory, "absent.json"));
  assert.deepEqual(missing.entries, []);
  assert.deepEqual(
    missing.dropped.map((entry) => entry.reason),
    ["curated_file_missing"],
  );

  await writeFile(target, "{ not json", "utf8");
  const damaged = await loadCuratedOverrides(target);
  assert.deepEqual(damaged.entries, []);
  assert.deepEqual(
    damaged.dropped.map((entry) => entry.reason),
    ["curated_file_unreadable"],
  );
});

test("notices carry Manila civil dates, titles and month buckets", () => {
  const { feed } = compileFeed({
    issuances: [
      issuance({ externalId: "bir:rmc:2026:086", number: "86-2026", dateIssued: "2026-07-31" }),
      issuance(),
    ],
    extractions: [],
    generatedAtUnix: 0,
  });

  const july = feed.notices.find((notice) => notice.external_id === "bir:rmc:2026:086");
  assert.ok(july !== undefined);
  assert.equal(july.title, "RMC No. 86-2026");
  assert.equal(july.month_bucket, "2026-07");
  assert.equal(july.published_at_unix, manilaMidnightUnix("2026-07-31"));
  // 00:00 Manila on Jul 31 is 16:00 UTC on Jul 30.
  assert.equal(july.published_at_unix, Date.UTC(2026, 6, 30, 16, 0, 0) / 1000);
  assert.deepEqual(validateFeed(feed), []);
});

test("a missing dateIssued falls back to firstSeenAtUnix at UTC+8", () => {
  const newYearEve = Date.UTC(2025, 11, 31, 16, 0, 0) / 1000;
  const { feed, dateSources } = compileFeed({
    issuances: [
      issuance({ dateIssued: null, dateSource: "first_seen", firstSeenAtUnix: newYearEve }),
    ],
    extractions: [],
    generatedAtUnix: 0,
  });

  assert.equal(feed.notices[0].published_at_unix, newYearEve);
  assert.equal(feed.notices[0].month_bucket, "2026-01");
  assert.equal(manilaMonthBucket(newYearEve - 1), "2025-12");
  assert.equal(dateSources.get(rmc89Id), "first_seen");
});

test("compileFeed reports which date tier produced each published date", () => {
  const { feed, dateSources } = compileFeed({
    issuances: [
      issuance({ externalId: "bir:rmc:2026:089", dateIssued: "2026-08-10" }),
      issuance({
        externalId: "bir:rmo:2026:019",
        number: "19-2026",
        kind: "RMO",
        dateIssued: "2026-07-23",
        dateSource: "pdf_header",
      }),
      issuance({
        externalId: "bir:rmc:2026:090",
        number: "90-2026",
        dateIssued: null,
        dateSource: "first_seen",
        firstSeenAtUnix: 1_786_752_000,
      }),
    ],
    extractions: [],
    generatedAtUnix: 0,
  });

  assert.equal(dateSources.size, feed.notices.length);
  assert.deepEqual(
    [...dateSources.entries()].toSorted(),
    [
      ["bir:rmc:2026:089", "archive"],
      ["bir:rmc:2026:090", "first_seen"],
      ["bir:rmo:2026:019", "pdf_header"],
    ],
  );
});

test("an unparseable dateIssued is reported as first-seen, not as an archive date", () => {
  const { feed, dropped, dateSources } = compileFeed({
    issuances: [issuance({ dateIssued: "2026-02-30", firstSeenAtUnix: 1_786_752_000 })],
    extractions: [],
    generatedAtUnix: 0,
  });

  assert.equal(feed.notices[0].published_at_unix, 1_786_752_000);
  assert.equal(dateSources.get(rmc89Id), "first_seen");
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["invalid_date_issued"],
  );
});

test("notices sort by published date descending then external_id descending", () => {
  const sameDay = { dateIssued: "2026-08-10" };
  const { feed } = compileFeed({
    issuances: [
      issuance({ externalId: "bir:rmc:2026:085", number: "85-2026", dateIssued: "2026-07-31" }),
      issuance({ externalId: "bir:rmo:2026:018", number: "18-2026", kind: "RMO", ...sameDay }),
      issuance({ externalId: "bir:rmc:2026:089", number: "89-2026", ...sameDay }),
    ],
    extractions: [],
    generatedAtUnix: 0,
  });

  assert.deepEqual(
    feed.notices.map((notice) => notice.external_id),
    ["bir:rmo:2026:018", "bir:rmc:2026:089", "bir:rmc:2026:085"],
  );
});

test("the notice cap trims the oldest and records each trimmed id", () => {
  const issuances: IssuanceRecord[] = [];
  for (let index = 0; index < maxNotices + 3; index += 1) {
    const sequence = String(index + 1).padStart(3, "0");
    issuances.push(
      issuance({
        externalId: `bir:rmc:2026:${sequence}`,
        number: `${index + 1}-2026`,
        dateIssued: "2026-08-10",
      }),
    );
  }

  const { feed, dropped } = compileFeed({ issuances, extractions: [], generatedAtUnix: 0 });
  assert.equal(feed.notices.length, maxNotices);
  assert.equal(
    feed.notices[0].external_id,
    `bir:rmc:2026:${String(maxNotices + 3).padStart(3, "0")}`,
  );
  assert.deepEqual(
    dropped.map((entry) => entry.detail.split(" ")[0]),
    ["bir:rmc:2026:003", "bir:rmc:2026:002", "bir:rmc:2026:001"],
  );
  assert.deepEqual(validateFeed(feed), []);
});

test("an override whose notice fell off the cap is dropped, not orphaned", () => {
  const issuances: IssuanceRecord[] = [];
  for (let index = 0; index < maxNotices; index += 1) {
    issuances.push(
      issuance({
        externalId: `bir:rmc:2026:${String(index + 100).padStart(3, "0")}`,
        number: `${index + 100}-2026`,
        dateIssued: "2026-08-10",
      }),
    );
  }
  issuances.push(issuance({ dateIssued: "2026-01-05" }));

  const { feed, dropped } = compileFeed({
    issuances,
    extractions: [
      extraction({
        rows: [
          row({
            formCodesCanonical: ["1601C"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.deepEqual(feed.overrides, []);
  assert.ok(dropped.some((entry) => entry.reason === "notice_not_in_feed"));
  assert.deepEqual(validateFeed(feed), []);
});

test("an extraction with no matching issuance never reaches the feed", () => {
  const { feed, dropped } = compileFeed({
    issuances: [],
    extractions: [
      extraction({
        rows: [
          row({
            formCodesCanonical: ["1601C"],
            originalDate: "2026-08-10",
            extendedDate: "2026-08-17",
            dateAssignment: "same_line",
          }),
        ],
      }),
    ],
    generatedAtUnix: 0,
  });

  assert.deepEqual(feed.overrides, []);
  assert.deepEqual(
    dropped.map((entry) => entry.reason),
    ["unknown_issuance"],
  );
});

test("rowDropReason names the first rule a row fails", () => {
  const scope = { hasRdoScope: true };
  assert.equal(
    rowDropReason(
      row({
        formCodesCanonical: ["1601C"],
        originalDate: "2026-08-10",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
      }),
      scope,
    ),
    null,
  );
  assert.equal(rowDropReason(row({ dateAssignment: "window" }), scope), "window_row");
  assert.equal(
    rowDropReason(
      row({ channel: "registration", dateAssignment: "same_line", originalDate: "2026-08-10" }),
      scope,
    ),
    "channel_not_emittable",
  );
  assert.equal(
    rowDropReason(row({ dateAssignment: "same_line", originalDate: "2026-08-10" }), scope),
    "missing_date_pair",
  );
  assert.equal(
    rowDropReason(
      row({ dateAssignment: "same_line", originalDate: "2026-08-32", extendedDate: "2026-08-17" }),
      scope,
    ),
    "invalid_date",
  );
  assert.equal(
    rowDropReason(
      row({
        dateAssignment: "same_line",
        originalDate: "2026-08-17",
        extendedDate: "2026-08-10",
        formCodesCanonical: ["1601C"],
      }),
      scope,
    ),
    "adjusted_before_original",
  );
  assert.equal(
    rowDropReason(
      row({ dateAssignment: "same_line", originalDate: "2026-08-10", extendedDate: "2026-08-17" }),
      scope,
    ),
    "no_canonical_form_codes",
  );
});

test("summaries truncate on a UTF-8 boundary", () => {
  const subject = `${"a".repeat(4095)}ñ`;
  assert.equal(Buffer.byteLength(subject, "utf8"), 4097);

  const { feed } = compileFeed({
    issuances: [issuance({ subject })],
    extractions: [],
    generatedAtUnix: 0,
  });

  const { summary } = feed.notices[0];
  assert.equal(summary, "a".repeat(4095));
  assert.ok(Buffer.byteLength(summary, "utf8") <= 4096);
  assert.ok(!summary.includes("�"));
  assert.deepEqual(validateFeed(feed), []);
});

test("truncateUtf8 never splits a multi-byte codepoint", () => {
  assert.equal(truncateUtf8("ññññ", 5), "ññ");
  assert.equal(truncateUtf8("abc", 10), "abc");
  assert.equal(truncateUtf8("😀😀", 5), "😀");
});

test("serializeFeed is byte-stable and sorts every array", () => {
  const { feed } = compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    generatedAtUnix: 1_786_742_400,
  });

  const first = serializeFeed(feed);
  assert.equal(serializeFeed(feed), first);
  assert.ok(first.endsWith("}\n"));
  assert.equal(
    first.indexOf('"schema_version"') < first.indexOf('"generated_at_unix"'),
    true,
    "key order must be stable",
  );

  const shuffled: Feed = {
    ...feed,
    notices: [...feed.notices].toReversed(),
    overrides: [...feed.overrides].toReversed().map((override) => ({
      ...override,
      form_codes: [...override.form_codes].toReversed(),
      rdo_codes: [...override.rdo_codes].toReversed(),
    })),
  };
  assert.equal(serializeFeed(shuffled), first);
});

test("feedContentEquals ignores generated_at_unix and nothing else", () => {
  const { feed } = compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    generatedAtUnix: 1_786_742_400,
  });
  const later: Feed = { ...feed, generated_at_unix: feed.generated_at_unix + 21_600 };

  assert.equal(feedContentEquals(feed, later), true);
  assert.notEqual(serializeFeed(feed), serializeFeed(later));

  const retitled: Feed = {
    ...feed,
    notices: feed.notices.map((notice) => ({ ...notice, title: `${notice.title} (rev)` })),
  };
  assert.equal(feedContentEquals(feed, retitled), false);

  const rescoped: Feed = {
    ...feed,
    overrides: feed.overrides.map((override) => ({ ...override, rdo_codes: ["039"] })),
  };
  assert.equal(feedContentEquals(feed, rescoped), false);
});

test("validateFeed reports every contract violation it is given", () => {
  const { feed } = compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    generatedAtUnix: 1_786_742_400,
  });

  const broken: Feed = {
    ...feed,
    schema_version: 2 as unknown as 1,
    notices: [feed.notices[0], { ...feed.notices[0], month_bucket: "2026-07" }],
    overrides: [
      { ...feed.overrides[0], rdo_codes: [] },
      { ...feed.overrides[1], form_codes: ["1601-C"], adjusted_deadline: "2026-08-01" },
    ],
  };

  const violations = validateFeed(broken);
  assert.ok(violations.some((message) => message.includes("schema_version must be 1")));
  assert.ok(violations.some((message) => message.includes("repeats an external_id")));
  assert.ok(violations.some((message) => message.includes("month_bucket")));
  assert.ok(violations.some((message) => message.includes("empty rdo_codes scope")));
  assert.ok(violations.some((message) => message.includes("non-canonical form code")));
  assert.ok(violations.some((message) => message.includes("precedes original_deadline")));
});

test("validateFeed rejects a feed over the 512 KiB budget", () => {
  const issuances: IssuanceRecord[] = [];
  for (let index = 0; index < maxNotices; index += 1) {
    issuances.push(
      issuance({
        externalId: `bir:rmc:2026:${String(index + 1).padStart(3, "0")}`,
        number: `${index + 1}-2026`,
        subject: "x".repeat(4096),
      }),
    );
  }
  const { feed } = compileFeed({ issuances, extractions: [], generatedAtUnix: 0 });
  assert.ok(
    validateFeed(feed).some((message) => message.includes("over the 524288-byte budget")),
    `${maxNotices} max-length summaries must exceed the published size budget`,
  );
});

test("validateFeed refuses an rdo code longer than the app can store", () => {
  const { feed } = compileFeed({
    issuances: [issuance()],
    extractions: [appendixAExtraction()],
    generatedAtUnix: 1_786_742_400,
  });

  assert.deepEqual(validateFeed(feed), [], "the real extraction must stay clean");
  for (const override of feed.overrides) {
    for (const code of override.rdo_codes) {
      assert.ok(
        Buffer.byteLength(code, "utf8") <= maxRdoCodeBytes,
        `emitted rdo code ${code} must fit the app's scope storage`,
      );
    }
  }

  const widened: Feed = {
    ...feed,
    overrides: [{ ...feed.overrides[0], rdo_codes: ["Metro Manila District"] }],
  };
  assert.ok(
    validateFeed(widened).some((message) => message.includes("8-byte cap")),
    "a district name published as a scope must fail at publish time",
  );
});

test("RMC 62-2026 scopes two offices but emits no override", () => {
  // Plan T10.1's end state. The extractor now reads the circular — two RDOs
  // and a 27-block deadline table — but only one block prints a trustworthy
  // date pair, and it is a `submission` row with no form code. Reading a
  // circular and emitting from it are separate bars, and this one clears only
  // the first: the extension shows up in the review report, not in the feed.
  const layoutText = readFileSync(
    path.join(import.meta.dirname, "fixtures", "2026-08-11", "rmc-62-2026-pdftotext-layout.txt"),
    "utf8",
  );
  const { rdoCodes } = extractRdos(layoutText);
  const rows = extractDeadlineRows(layoutText, parseCircularAnchors(layoutText));
  const scope = { hasRdoScope: rdoCodes.length > 0 };

  assert.deepEqual(rdoCodes, ["110", "111"]);
  assert.ok(scope.hasRdoScope);
  assert.equal(
    rows.filter((row) => rowDropReason(row, scope) === null).length,
    0,
    "no RMC 62-2026 row may become an override",
  );
  assert.deepEqual(
    [...new Set(rows.map((row) => rowDropReason(row, scope)))].toSorted(),
    ["channel_not_emittable", "window_row"],
  );
});

test("the notice cap matches the app's, and holds a year of BIR issuance", () => {
  // The app restates this bound as `domain.max_notices` in
  // src/news/domain.zig, where an equivalent test asserts the same number.
  // Nothing imports across the two languages, so the pair is held by these two
  // assertions and nothing else — change one and the other must follow.
  assert.equal(maxNotices, 240);
  // BIR published ~20 issuances a month through 2026. A cap the year outgrows
  // truncates the oldest notices, and the month-scoped pane shows that as an
  // empty month rather than as an error.
  assert.ok(maxNotices >= 12 * 20, "the cap must hold a full year at ~20 a month");
});
