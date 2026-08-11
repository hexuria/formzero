import assert from "node:assert/strict";
import test from "node:test";

import { ARCHIVE_FIXTURES, WIDGET_FIXTURE, loadFixtureDataset } from "./cms.ts";
import {
  extractIssuanceHtml,
  externalIdFor,
  mergeIssuances,
  normalizePdfUrl,
  parseArchiveIssuances,
  parseHeading,
  parseWidgetIssuances,
  splitIssuanceBlocks,
  type IssuanceParseWarning,
} from "./issuances.ts";
import type { IssuanceRecord } from "./types.ts";

// Fixed injected clock: nothing in this module may read the wall clock.
const FIRST_SEEN = 1_786_752_000;

async function widgetHtml(): Promise<string> {
  const datasets = await loadFixtureDataset(WIDGET_FIXTURE);
  return extractIssuanceHtml(datasets[0]);
}

async function archiveHtml(kind: keyof typeof ARCHIVE_FIXTURES = "RMC"): Promise<string> {
  const datasets = await loadFixtureDataset(ARCHIVE_FIXTURES[kind]);
  return extractIssuanceHtml(datasets[0]);
}

function byId(records: readonly IssuanceRecord[], externalId: string): IssuanceRecord {
  const record = records.find((candidate) => candidate.externalId === externalId);
  assert.ok(record !== undefined, `expected a record for ${externalId}`);
  return record;
}

test("extractIssuanceHtml reads both CMS content shapes and tolerates neither", () => {
  assert.equal(extractIssuanceHtml({ content: { Issuance: "<p>widget</p>" } }), "<p>widget</p>");
  assert.equal(extractIssuanceHtml({ content: { Content: "<table></table>" } }), "<table></table>");
  assert.equal(extractIssuanceHtml({ content: { Other: "x" } }), "");
  assert.equal(extractIssuanceHtml({ content: null }), "");
  assert.equal(extractIssuanceHtml(null), "");
  assert.equal(extractIssuanceHtml("<p>not a dataset</p>"), "");
});

test("externalIdFor zero-pads the sequence so 89 and 089 collapse to one identity", () => {
  assert.equal(externalIdFor("RMC", "2026", "89"), "bir:rmc:2026:089");
  assert.equal(externalIdFor("RMC", "2026", "089"), "bir:rmc:2026:089");
  assert.equal(externalIdFor("RMO", "2026", "17"), "bir:rmo:2026:017");
  assert.equal(externalIdFor("BANK_BULLETIN", "2026", "3"), "bir:bank_bulletin:2026:003");
});

test("parseHeading takes the first heading only, so cited issuances are not records", () => {
  const heading = parseHeading(
    "Revenue Memorandum Order No. 19-2026 policies, guidelines, and procedures for the " +
      "Availment of a One-Time Abatement of Taxes and/or Penalties for Micro Taxpayers " +
      "Pursuant to Revenue Regulations No. 004-2026.",
  );
  assert.deepEqual(
    { kind: heading?.kind, number: heading?.number, sequence: heading?.sequence },
    { kind: "RMO", number: "19-2026", sequence: "019" },
  );
});

test("parseHeading reads the archive's abbreviated form and normalizes OCR digits", () => {
  assert.equal(parseHeading("RMC No. 89-2026")?.number, "89-2026");
  assert.equal(parseHeading("RMC No. 89-2026")?.sequence, "089");
  // "l" for 1 and "O" for 0 in a pasted, OCR-sourced number.
  assert.equal(parseHeading("RMC No. O89-2026")?.sequence, "089");
  assert.equal(parseHeading("RDAO No. 2-2026")?.kind, "RDAO");
  assert.equal(parseHeading("Bank Bulletin No. 7-2026")?.kind, "BANK_BULLETIN");
  assert.equal(parseHeading("Republic Act (R.A.) No. 10963 (TRAIN Law)"), null);
  assert.equal(parseHeading("no issuance heading at all"), null);
});

test("normalizePdfUrl percent-encodes raw spaces without double-encoding", () => {
  assert.equal(
    normalizePdfUrl("https://bir-cdn.bir.gov.ph/BIR/pdf/RMC No. 89-2026_redacted.pdf"),
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  );
  assert.equal(
    normalizePdfUrl("https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf"),
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  );
  assert.equal(
    normalizePdfUrl("/BIR/pdf/RMC No. 84-2026_Redacted.pdf"),
    "https://www.bir.gov.ph/BIR/pdf/RMC%20No.%2084-2026_Redacted.pdf",
  );
  assert.equal(normalizePdfUrl("   "), null);
});

test("the widget fixture splits into one block per issuance", async () => {
  assert.equal(splitIssuanceBlocks(await widgetHtml()).length, 8);
});

test("widget parse yields the 8 issuances in the fixture, in printed order", async () => {
  const warnings: IssuanceParseWarning[] = [];
  const records = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN, warnings);

  assert.equal(records.length, 8);
  assert.deepEqual(warnings, []);
  assert.deepEqual(
    records.map((record) => record.externalId),
    [
      "bir:rmc:2026:089",
      "bir:rmc:2026:088",
      "bir:rmc:2026:087",
      "bir:rmc:2026:086",
      "bir:rmc:2026:085",
      "bir:rmo:2026:019",
      "bir:rmo:2026:018",
      "bir:rmo:2026:017",
    ],
  );
  for (const record of records) {
    assert.equal(record.source, "widget");
    assert.equal(record.dateIssued, null, "the widget blob carries no dates");
    assert.equal(record.firstSeenAtUnix, FIRST_SEEN);
  }
});

test("widget RMC 089-2026 keeps the printed number and resolves its PDF URL", async () => {
  const record = byId(parseWidgetIssuances(await widgetHtml(), FIRST_SEEN), "bir:rmc:2026:089");
  assert.equal(record.kind, "RMC");
  // The widget prints the zero-padded form; the archive prints "89-2026".
  assert.equal(record.number, "089-2026");
  assert.equal(
    record.pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  );
  assert.ok(record.subject.startsWith("Providing Extension of the Deadlines for the Filing"));
  assert.ok(record.subject.endsWith("Southwest Monsoon."));
  assert.ok(!record.subject.includes("more"), "the trailing 'more' anchor is not subject text");
});

test("widget subjects survive the CMS's mid-word span splits and entity escapes", async () => {
  const records = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  // "p</span><span …>ublishes" must not become "p ublishes".
  assert.ok(byId(records, "bir:rmc:2026:087").subject.startsWith("publishes the full text"));
  assert.ok(byId(records, "bir:rmc:2026:088").subject.includes("Malacañang Palace"));
});

test("widget parse records the RMO issuances the archive fixture does not carry", async () => {
  const records = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  for (const [externalId, number] of [
    ["bir:rmo:2026:019", "19-2026"],
    ["bir:rmo:2026:018", "18-2026"],
    ["bir:rmo:2026:017", "17-2026"],
  ] as const) {
    const record = byId(records, externalId);
    assert.equal(record.kind, "RMO");
    assert.equal(record.number, number);
    assert.ok(record.pdfUrl?.startsWith("https://bir-cdn.bir.gov.ph/BIR/pdf/RMO%20No."));
  }
});

test("Revenue Regulations 004-2026, cited inside two RMO subjects, is not an issuance", async () => {
  const records = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  assert.equal(
    records.find((record) => record.externalId === "bir:rr:2026:004"),
    undefined,
  );
  assert.equal(records.filter((record) => record.kind === "RR").length, 0);
  // The citation stays in the subject text — it is dropped as a record, not as content.
  assert.ok(byId(records, "bir:rmo:2026:019").subject.includes("Revenue Regulations No. 004-2026"));
  assert.ok(byId(records, "bir:rmo:2026:018").subject.includes("Revenue Regulations No. 004-2026"));
});

test("a block with no recognizable heading is reported, never silently dropped", () => {
  const warnings: IssuanceParseWarning[] = [];
  const records = parseWidgetIssuances(
    '<p class="MsoNormal"><strong>Advisory</strong> on the eFPS downtime this weekend.</p>' +
      '<p class="MsoNormal"><strong>Revenue Memorandum Circular No. 90-2026</strong> something.</p>',
    FIRST_SEEN,
    warnings,
  );
  assert.deepEqual(
    records.map((record) => record.externalId),
    ["bir:rmc:2026:090"],
  );
  assert.equal(warnings.length, 1);
  assert.equal(warnings[0].reason, "no recognized issuance heading");
  assert.match(warnings[0].block, /Advisory on the eFPS downtime/u);
});

test("archive parse yields the 6 fixture rows with their DATE OF ISSUE", async () => {
  const warnings: IssuanceParseWarning[] = [];
  const records = parseArchiveIssuances(await archiveHtml(), FIRST_SEEN, warnings);

  assert.equal(records.length, 6);
  assert.deepEqual(warnings, []);
  assert.deepEqual(
    records.map((record) => [record.number, record.dateIssued]),
    [
      ["89-2026", "2026-08-10"],
      ["88-2026", "2026-08-06"],
      ["87-2026", "2026-08-04"],
      ["86-2026", "2026-07-31"],
      ["85-2026", "2026-07-31"],
      ["84-2026", "2026-07-23"],
    ],
  );
  for (const record of records) {
    assert.equal(record.source, "archive");
    assert.equal(record.kind, "RMC");
    assert.equal(record.dateSource, "archive");
  }
});

test("the RMO archive dates the three issuances the widget could only guess at", async () => {
  const warnings: IssuanceParseWarning[] = [];
  const records = parseArchiveIssuances(await archiveHtml("RMO"), FIRST_SEEN, warnings);

  assert.equal(records.length, 6);
  assert.deepEqual(warnings, [], "the RMO header row is a <td> row, not a parse failure");
  assert.deepEqual(
    records.map((record) => [record.externalId, record.dateIssued]),
    [
      ["bir:rmo:2026:019", "2026-07-23"],
      ["bir:rmo:2026:018", "2026-07-23"],
      ["bir:rmo:2026:017", "2026-07-08"],
      ["bir:rmo:2026:016", "2026-07-07"],
      ["bir:rmo:2026:015", "2026-07-07"],
      ["bir:rmo:2026:014", "2026-07-06"],
    ],
  );
  for (const record of records) {
    assert.equal(record.kind, "RMO");
    assert.equal(record.dateSource, "archive");
  }
  assert.equal(
    byId(records, "bir:rmo:2026:019").pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMO%20No.%2019-2026_Redacted.pdf",
  );
});

test("the RR archive zero-pads single-digit numbers into the external id", async () => {
  const warnings: IssuanceParseWarning[] = [];
  const records = parseArchiveIssuances(await archiveHtml("RR"), FIRST_SEEN, warnings);

  assert.deepEqual(warnings, []);
  // "RR No. 4-2026" prints one digit; the identity is always three.
  assert.deepEqual(
    records.map((record) => [record.externalId, record.number, record.dateIssued]),
    [
      ["bir:rr:2026:004", "4-2026", "2026-06-22"],
      ["bir:rr:2026:003", "3-2026", "2026-04-17"],
      ["bir:rr:2026:002", "2-2026", "2026-03-17"],
      ["bir:rr:2026:001", "1-2026", "2026-02-16"],
    ],
  );
  for (const record of records) assert.equal(record.kind, "RR");
  assert.equal(
    byId(records, "bir:rr:2026:004").pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RR%20No.%204-2026_Redacted.pdf",
  );
});

test("archive subjects stop at the link row and keep the Full Text href", async () => {
  const records = parseArchiveIssuances(await archiveHtml(), FIRST_SEEN);

  const rmc89 = byId(records, "bir:rmc:2026:089");
  assert.ok(rmc89.subject.endsWith("Southwest Monsoon"));
  assert.ok(!rmc89.subject.includes("Digest"));
  assert.equal(
    rmc89.pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  );

  // Row 86 carries 14 annex anchors after the Full Text one; the Full Text link wins.
  assert.equal(
    byId(records, "bir:rmc:2026:086").pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2086-2026_redacted-compressed.pdf",
  );
  // Row 88's Full Text anchor has a trailing space in its title attribute.
  assert.equal(
    byId(records, "bir:rmc:2026:088").pdfUrl,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2088-2026_redacted.pdf",
  );
});

test("the archive header row is not mistaken for an issuance", async () => {
  for (const kind of ["RMC", "RMO", "RR"] as const) {
    const records = parseArchiveIssuances(await archiveHtml(kind), FIRST_SEEN);
    assert.ok(records.every((record) => !record.subject.includes("NO. OF ISSUANCE")));
  }
});

test("merge unions both sources and lets the archive win on every shared field", async () => {
  const widget = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  const archive = parseArchiveIssuances(await archiveHtml(), FIRST_SEEN);
  const merged = mergeIssuances(widget, archive);

  // 8 widget + RMC 84-2026, which only the archive carries.
  assert.equal(merged.length, 9);
  assert.equal(new Set(merged.map((record) => record.externalId)).size, 9);

  const rmc89 = byId(merged, "bir:rmc:2026:089");
  assert.equal(rmc89.source, "merged");
  assert.equal(rmc89.dateIssued, "2026-08-10");
  assert.equal(rmc89.number, "89-2026", "the archive's printed number wins");
  assert.ok(rmc89.subject.endsWith("Southwest Monsoon"), "the archive's subject wins");

  const rmc84 = byId(merged, "bir:rmc:2026:084");
  assert.equal(rmc84.source, "archive");
  assert.equal(rmc84.dateIssued, "2026-07-23");

  const rmo19 = byId(merged, "bir:rmo:2026:019");
  assert.equal(rmo19.source, "widget");
  assert.equal(rmo19.dateIssued, null, "this merge was given the RMC archive only");
  assert.equal(rmo19.dateSource, "first_seen");
});

test("merging all three archives dates every widget issuance from its own kind", async () => {
  const widget = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  const archive = [
    ...parseArchiveIssuances(await archiveHtml("RMC"), FIRST_SEEN),
    ...parseArchiveIssuances(await archiveHtml("RMO"), FIRST_SEEN),
    ...parseArchiveIssuances(await archiveHtml("RR"), FIRST_SEEN),
  ];
  const merged = mergeIssuances(widget, archive);

  // 8 widget + RMC 84 + RMO 14/15/16 + RR 1-4.
  assert.equal(merged.length, 16);
  assert.ok(
    merged.every((record) => record.dateIssued !== null),
    "every merged record is dated by an archive row",
  );
  assert.ok(merged.every((record) => record.dateSource === "archive"));

  // The defect this covers: the RMOs used to reach the feed undated.
  assert.deepEqual(
    [
      byId(merged, "bir:rmo:2026:019"),
      byId(merged, "bir:rmo:2026:018"),
      byId(merged, "bir:rmo:2026:017"),
    ].map((record) => [record.externalId, record.dateIssued, record.source]),
    [
      ["bir:rmo:2026:019", "2026-07-23", "merged"],
      ["bir:rmo:2026:018", "2026-07-23", "merged"],
      ["bir:rmo:2026:017", "2026-07-08", "merged"],
    ],
  );
});

test("merge sorts by issue date descending, then by external id descending", async () => {
  const widget = parseWidgetIssuances(await widgetHtml(), FIRST_SEEN);
  const archive = parseArchiveIssuances(await archiveHtml(), FIRST_SEEN);

  assert.deepEqual(
    mergeIssuances(widget, archive).map((record) => [record.externalId, record.dateIssued]),
    [
      ["bir:rmc:2026:089", "2026-08-10"],
      ["bir:rmc:2026:088", "2026-08-06"],
      ["bir:rmc:2026:087", "2026-08-04"],
      // Same date: external id breaks the tie, descending.
      ["bir:rmc:2026:086", "2026-07-31"],
      ["bir:rmc:2026:085", "2026-07-31"],
      ["bir:rmc:2026:084", "2026-07-23"],
      // Undated records sort last.
      ["bir:rmo:2026:019", null],
      ["bir:rmo:2026:018", null],
      ["bir:rmo:2026:017", null],
    ],
  );
});

test("merge keeps the widget value when the archive field is missing", () => {
  const widget: IssuanceRecord = {
    externalId: "bir:rmc:2026:089",
    kind: "RMC",
    number: "089-2026",
    subject: "Widget subject.",
    pdfUrl: "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
    dateIssued: null,
    dateSource: "first_seen",
    source: "widget",
    firstSeenAtUnix: FIRST_SEEN,
  };
  const archive: IssuanceRecord = {
    ...widget,
    subject: "",
    pdfUrl: null,
    dateIssued: "2026-08-10",
    dateSource: "archive",
    source: "archive",
    firstSeenAtUnix: FIRST_SEEN + 3600,
  };

  const [merged] = mergeIssuances([widget], [archive]);
  assert.equal(merged.subject, "Widget subject.");
  assert.equal(merged.pdfUrl, widget.pdfUrl);
  assert.equal(merged.dateIssued, "2026-08-10");
  assert.equal(merged.dateSource, "archive");
  assert.equal(merged.source, "merged");
  assert.equal(merged.firstSeenAtUnix, FIRST_SEEN, "first-seen is the earliest sighting");
});

test("merging an undated archive row keeps the widget's date and its provenance", () => {
  const widget: IssuanceRecord = {
    externalId: "bir:rmc:2026:090",
    kind: "RMC",
    number: "90-2026",
    subject: "Widget subject.",
    pdfUrl: null,
    dateIssued: null,
    dateSource: "first_seen",
    source: "widget",
    firstSeenAtUnix: FIRST_SEEN,
  };
  const archive: IssuanceRecord = {
    ...widget,
    dateIssued: null,
    dateSource: "first_seen",
    source: "archive",
    firstSeenAtUnix: FIRST_SEEN,
  };

  const [merged] = mergeIssuances([widget], [archive]);
  assert.equal(merged.dateIssued, null);
  assert.equal(merged.dateSource, "first_seen");
});
