import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  classifyChannel,
  columnGeometry,
  extractDeadlineRows,
  harvestFormCodes,
  parseCircularAnchors,
  scanDateCandidates,
  splitBlocks,
} from "./extract-deadline-table.ts";
import type { ExtensionRow } from "./types.ts";

// Golden fixture: `pdftotext -layout` of the RMC No. 89-2026 scan, committed
// under fixtures/2026-08-11. Every expectation below is read off that text —
// it is the ground truth for this module, and nothing here touches the network
// or the clock.
const fixturePath = path.join(
  import.meta.dirname,
  "fixtures",
  "2026-08-11",
  "rmc-89-2026-pdftotext-layout.txt",
);
const layoutText = readFileSync(fixturePath, "utf8");
const anchors = parseCircularAnchors(layoutText);
const rows = extractDeadlineRows(layoutText, anchors);

function only(predicate: (row: ExtensionRow) => boolean): ExtensionRow {
  const matches = rows.filter(predicate);
  assert.equal(matches.length, 1, `expected exactly one matching row, got ${matches.length}`);
  return matches[0];
}

test("parseCircularAnchors reads the blanket extended date through OCR damage", () => {
  // Page 1 prose: "...payrnent of taxes due thereon until Aueust 17. 2026,"
  assert.equal(anchors.globalExtendedDate, "2026-08-17");
});

test("parseCircularAnchors reads the stated deadline window", () => {
  // "Deadlines falling fiom August 10,2026to" / "August 16,2026" — the two
  // dates straddle a line break and the second is glued to "2026to".
  assert.deepEqual(anchors.window, { from: "2026-08-10", to: "2026-08-16" });
});

test("parseCircularAnchors returns nulls when the prose carries no anchors", () => {
  assert.deepEqual(parseCircularAnchors("no dates here at all"), {
    globalExtendedDate: null,
    window: null,
  });
});

test("columnGeometry locates both date columns on the table header", () => {
  const header =
    "             BIR Forms/Returns                      Due Date                 Extended Due Date";
  assert.deepEqual(columnGeometry(header), { dueColumn: 52, extendedColumn: 77 });
});

test("columnGeometry rejects a line that is not the table header", () => {
  assert.equal(columnGeometry("BIR Forms/Returns and nothing else"), null);
});

test("scanDateCandidates keeps the column and flags unreadable literals", () => {
  const line = "                                             August 13, 2026            Angttst 1'? ,2026";
  const candidates = scanDateCandidates(line);
  assert.equal(candidates.length, 2);
  assert.deepEqual(
    candidates.map((candidate) => [candidate.column, candidate.iso]),
    [
      [45, "2026-08-13"],
      [72, null],
    ],
  );
});

test("scanDateCandidates does not re-report the tail of a literal it already read", () => {
  const candidates = scanDateCandidates("August 10,2026to August 16,2026");
  assert.deepEqual(
    candidates.map((candidate) => candidate.iso),
    ["2026-08-10", "2026-08-16"],
  );
});

test("classifyChannel follows the documented precedence order", () => {
  assert.equal(
    classifyChannel("e-FlLlNG & PAYMENT (Online/Manual)", "BIR Form 0620 - eFPS & Non-eFPS Filers."),
    "efps_and_nonefps",
  );
  assert.equal(
    classifyChannel("e-FILING", "Withheld) - eFPS Filers under Group E. Month of July 2026"),
    "efps_group_e",
  );
  assert.equal(
    classifyChannel("e-PAYMENT", "Withheld) - eFPS Filers under Group E, D ,C & B. Month of July 2026"),
    "efps_group_multi",
  );
  assert.equal(
    classifyChannel("e-FlLlNG & PAYMENT (Online/Manual)", "0619-F (Monthly) - Non-eFPS Filers."),
    "nonefps",
  );
  assert.equal(classifyChannel("REGISTRATION (Online Thru ORUS or Manual)", "Loose-Leaf Books"), "registration");
  assert.equal(classifyChannel("SUBMISSION", "List ofBuyers of Sugar"), "submission");
  assert.equal(classifyChannel("e-SUBMISSION", "Monthly e-Sales Report"), "submission");
  // OCR variants of the Online/Manual qualifier all mean "not eFPS".
  assert.equal(classifyChannel("eFILING & PAYMENT (Online[vlanual)", "BIR Form 1702 - RT/EX/MX."), "nonefps");
  assert.equal(classifyChannel("e-FlLlNG & PAYMENT (Online/I4anual)", "One-Time Transactions (ONETT)"), "nonefps");
  assert.equal(classifyChannel("e-FILING & e-PAYMENT/REMITTANCE", "National Govemment Agencies (NGAs)."), "unknown");
});

test("harvestFormCodes reassembles codes the OCR split with spaces", () => {
  assert.deepEqual(harvestFormCodes("and./or 06 1 9-F (Monthly").canonical, ["0619F"]);
  assert.deepEqual(harvestFormCodes("and/or 06 l9-F (Monthly").canonical, ["0619F"]);
  assert.deepEqual(harvestFormCodes("and/or 061 9-F (Monthly").canonical, ["0619F"]);
  assert.deepEqual(harvestFormCodes("BIR Forms l60l -C (Monthly").canonical, ["1601C"]);
  assert.deepEqual(harvestFormCodes("BIR Form 160o-VT (Monthly").canonical, ["1600VT"]);
});

test("harvestFormCodes expands a printed suffix list", () => {
  const harvested = harvestFormCodes("BIR Form 1702 - RT/EX/MX. Fiscal Year ending April 30,2026");
  assert.deepEqual(harvested.display, ["1702-RT", "1702-EX", "1702-MX"]);
  assert.deepEqual(harvested.canonical, ["1702RT", "1702EX", "1702MX"]);
});

test("harvestFormCodes accepts the joined spelling the catalog uses", () => {
  assert.deepEqual(harvestFormCodes("BIR Form 1701Q (Quarterly Income Tax Retum").canonical, ["1701Q"]);
  assert.deepEqual(harvestFormCodes("Nos.1800, 1801, 1706, 1707, 1707 A) -").canonical, [
    "1800",
    "1801",
    "1706",
    "1707",
    "1707A",
  ]);
});

test("harvestFormCodes drops years, stamp numbers and non-catalog debris", () => {
  assert.deepEqual(harvestFormCodes("Fiscal Year ending July 31,2026").canonical, []);
  assert.deepEqual(harvestFormCodes("00000515 RECORDS MANAGEMENT DIVISION AUG 10 2026").canonical, []);
  assert.deepEqual(harvestFormCodes("Sugar Cooperative. Month of July 2026").canonical, []);
});

test("splitBlocks keeps a channel header with its block and carries the seed forward", () => {
  const lines = [
    "  BIR Forms/Returns          Due Date        Extended Due Date",
    " SUBMISSION",
    "",
    " List of Buyers of Sugar. Month of July 2026",
    "",
    " Information Retum on Releases. Month of July 2026",
  ];
  const geometry = columnGeometry(lines[0]);
  assert.ok(geometry !== null);
  const blocks = splitBlocks(lines, geometry, 1, lines.length - 1);
  // The header-only block carries no description and is not a row of its own.
  assert.deepEqual(
    blocks.map((block) => [block.startLine, block.endLine, block.channelSeed]),
    [
      [3, 3, "SUBMISSION"],
      [5, 5, "SUBMISSION"],
    ],
  );
});

test("golden: every extracted row, in document order", () => {
  assert.deepEqual(
    rows.map((row) => [row.channel, row.dateAssignment, row.originalDate, row.extendedDate]),
    [
      ["submission", "window", null, "2026-08-17"], // sugar buyer list + refined sugar release
      ["submission", "window", null, "2026-08-17"], // e-Sales report, odd TIN
      ["nonefps", "window", null, "2026-08-17"], // 2200-M metallic minerals
      ["nonefps", "same_line", "2026-08-10", "2026-08-17"], // 1601-C/0619-E/0619-F Non-eFPS
      ["nonefps", "window", null, "2026-08-17"], // 2200-C cosmetic excise
      ["efps_and_nonefps", "window", null, "2026-08-17"], // 0620 + 1600-VT/PT + MAP
      ["nonefps", "window", null, "2026-08-17"], // 1606
      ["unknown", "window", null, "2026-08-17"], // 1600-VT/PT/1601-C NGAs
      ["efps_group_e", "same_line", "2026-08-11", "2026-08-17"],
      ["efps_group_d", "same_line", "2026-08-13", "2026-08-17"],
      ["efps_group_b", "same_line", "2026-08-14", "2026-08-17"],
      ["registration", "window", null, "2026-08-17"], // loose-leaf books
      ["nonefps", "same_line", "2026-08-15", "2026-08-17"], // 1702 - RT/EX/MX
      ["nonefps", "window", null, "2026-08-17"], // 1707-A fragment
      ["nonefps", "window", null, "2026-08-17"], // "Exchange) - by Corporate Taxpayers" tail
      ["nonefps", "window", null, "2026-08-17"], // 1701Q
      ["efps_and_nonefps", "window", null, "2026-08-17"], // SAWT tail
      ["efps_group_a", "window", null, "2026-08-17"],
      ["efps_group_multi", "window", null, "2026-08-17"], // e-PAYMENT groups E, D, C & B
      ["submission", "same_line", "2026-08-17", "2026-08-17"], // stockbrokers
      ["nonefps", "window", null, "2026-08-17"], // ONETT
      ["nonefps", "window", null, "2026-08-17"], // 0605/0613 tax mapping
    ],
  );
});

test("golden: the only Non-eFPS same_line monthly-remittance row is the Aug 10 pair", () => {
  const row = only(
    (candidate) =>
      candidate.channel === "nonefps" &&
      candidate.dateAssignment === "same_line" &&
      candidate.formCodesCanonical.includes("1601C"),
  );
  assert.deepEqual(row.formCodesCanonical, ["1601C", "0619E", "0619F"]);
  assert.deepEqual(row.formCodesDisplay, ["1601-C", "0619-E", "0619-F"]);
  assert.equal(row.originalDate, "2026-08-10");
  assert.equal(row.extendedDate, "2026-08-17");
  assert.equal(row.confidence, "high");
});

test("golden: the 1702 fiscal-year row is a same_line Aug 15 pair", () => {
  const row = only((candidate) => candidate.formCodesCanonical.includes("1702RT"));
  assert.equal(row.channel, "nonefps");
  assert.equal(row.dateAssignment, "same_line");
  assert.equal(row.originalDate, "2026-08-15");
  assert.equal(row.extendedDate, "2026-08-17");
  assert.deepEqual(row.formCodesCanonical, ["1702RT", "1702EX", "1702MX"]);
});

test("golden: the three eFPS group rows print their own pairs", () => {
  const groupE = only((candidate) => candidate.channel === "efps_group_e");
  assert.deepEqual(
    [groupE.dateAssignment, groupE.originalDate, groupE.extendedDate],
    ["same_line", "2026-08-11", "2026-08-17"],
  );

  const groupD = only((candidate) => candidate.channel === "efps_group_d");
  assert.deepEqual(
    [groupD.dateAssignment, groupD.originalDate, groupD.extendedDate],
    ["same_line", "2026-08-13", "2026-08-17"],
  );
  // The Extended column reads "Angttst 1'? ,2026" — unparseable, so the
  // circular's global extended date fills in and the repair is recorded.
  assert.ok(
    groupD.notes.some((note) => note.includes("Extended Due Date column unreadable")),
    `expected a damaged-extended note, got ${JSON.stringify(groupD.notes)}`,
  );

  const groupB = only((candidate) => candidate.channel === "efps_group_b");
  assert.deepEqual(
    [groupB.dateAssignment, groupB.originalDate, groupB.extendedDate],
    ["same_line", "2026-08-14", "2026-08-17"],
  );
});

test("golden: the stockbrokers row keeps its identity pair as printed", () => {
  const row = only((candidate) => candidate.rawDescription.includes("Stockbrokers"));
  assert.equal(row.channel, "submission");
  assert.equal(row.dateAssignment, "same_line");
  assert.equal(row.originalDate, "2026-08-17");
  assert.equal(row.extendedDate, "2026-08-17");
  assert.deepEqual(row.formCodesCanonical, []);
});

test("golden: blocks that print no form number carry no form codes", () => {
  for (const marker of ["Sugar Cooperative", "e-Sales Report", "Loose-Leaf Books"]) {
    const row = only((candidate) => candidate.rawDescription.includes(marker));
    assert.deepEqual(row.formCodesCanonical, [], `${marker} should have no form codes`);
    assert.deepEqual(row.formCodesDisplay, []);
  }
});

test("golden: window rows record the circular's extended date and ask for review", () => {
  for (const row of rows) {
    if (row.dateAssignment !== "window") continue;
    assert.equal(row.originalDate, null);
    assert.equal(row.extendedDate, anchors.globalExtendedDate);
    assert.equal(row.confidence, "review");
  }
});

test("golden: no row is assigned by any means other than same_line or window", () => {
  for (const row of rows) {
    assert.ok(
      row.dateAssignment === "same_line" || row.dateAssignment === "window",
      `unexpected dateAssignment ${row.dateAssignment}`,
    );
    // v1 never borrows a neighbour's pair.
    if (row.dateAssignment === "window") assert.equal(row.originalDate, null);
  }
});

test("golden: the ONETT row records the range printed on its own lines", () => {
  const row = only((candidate) => candidate.rawDescription.includes("One-Time Transactions"));
  assert.equal(row.dateAssignment, "window");
  assert.ok(
    row.notes.some((note) => note.includes("2026-08-10 to 2026-08-16")),
    `expected the printed range in the notes, got ${JSON.stringify(row.notes)}`,
  );
});

test("golden: the tax-mapping row's range is broken across a stamp, so none is claimed", () => {
  // The circular prints "Deadlines falling from August 10, / 2026 to August
  // 16,2026", but an OCR'd receiving stamp lands between the two halves and
  // splits the block. Only "August 10," survives on this block's lines — no
  // year, hence no range. v1 reports the fact instead of guessing.
  const row = only((candidate) => candidate.rawDescription.includes("Tax Compliance Verification"));
  assert.equal(row.dateAssignment, "window");
  assert.deepEqual(row.formCodesCanonical, ["0605", "0613"]);
  assert.ok(!row.notes.some((note) => note.includes("states its own deadline range")));
});

test("golden: the closing prose and signature block are not table rows", () => {
  for (const row of rows) {
    assert.ok(!row.rawDescription.includes("The extension of the due dates"));
    assert.ok(!row.rawDescription.includes("CHARLITO"));
  }
});

test("extractDeadlineRows returns nothing when the text has no table header", () => {
  assert.deepEqual(extractDeadlineRows("just prose, no table", anchors), []);
});
