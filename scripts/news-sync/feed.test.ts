import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import test from "node:test";

import {
  compileFeed,
  feedContentEquals,
  manilaMidnightUnix,
  manilaMonthBucket,
  maxNotices,
  maxRdoCodeBytes,
  rowDropReason,
  serializeFeed,
  truncateUtf8,
  validateFeed,
} from "./feed.ts";
import type {
  CircularExtraction,
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
    "120 max-length summaries must exceed the published size budget",
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
