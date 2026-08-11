import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { extractRdos, parseStatedOfficeCount, scanRegion } from "./extract-rdos.ts";
import { findRdoByCode } from "./rdo.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const layoutText = readFileSync(
  path.join(here, "fixtures", "2026-08-11", "rmc-89-2026-pdftotext-layout.txt"),
  "utf8",
);

// Plan Appendix A.1: 58 affected offices (53 regular + 5 Large Taxpayer divisions).
const EXPECTED_OFFICES = [
  "002", "003", "004", "005", "006", "007", "008", "009", "010", "012",
  "17A", "17B", "018", "019", "020", "21A", "21B", "21C", "024", "25A",
  "25B", "026", "027", "028", "029", "030", "031", "032", "033", "034",
  "037", "038", "039", "040", "041", "042", "043", "044", "045", "046",
  "047", "048", "049", "050", "051", "052", "53A", "53B", "54A", "54B",
  "058", "059", "063", "116", "121", "124", "125", "126",
];

// `043` is the only emitted code whose reference has lettered branches.
const EXPANSION_ONLY = ["43A", "43B"];

test("golden: RMC 89-2026 yields the 58 Appendix A.1 offices", () => {
  const { rdoCodes } = extractRdos(layoutText);
  assert.deepEqual(rdoCodes, [...EXPECTED_OFFICES, ...EXPANSION_ONLY].toSorted());
  assert.equal(rdoCodes.length, 60);

  const offices = rdoCodes.filter((code) => !EXPANSION_ONLY.includes(code));
  assert.equal(offices.length, 58);
});

test("golden: every emitted code exists in the RDO reference", () => {
  const { rdoCodes } = extractRdos(layoutText);
  for (const code of rdoCodes) {
    assert.notEqual(findRdoByCode(code), null, `${code} is not in data/rdo-reference.json`);
  }
});

test("golden: rdoCodes is sorted and deduped", () => {
  const { rdoCodes } = extractRdos(layoutText);
  assert.deepEqual(rdoCodes, rdoCodes.toSorted());
  assert.equal(new Set(rdoCodes).size, rdoCodes.length);
});

test("golden: one match per printed office, none dropped", () => {
  const { rdos } = extractRdos(layoutText);
  assert.equal(rdos.length, 58);
  assert.equal(rdos.filter((match) => match.code === null).length, 0);
});

test("golden: the OCR-damaged codes resolve", () => {
  const { rdos } = extractRdos(layoutText);
  const codeFor = (fragment: string): string | null => {
    const hits = rdos.filter((match) => match.raw.includes(fragment));
    assert.equal(hits.length, 1, `expected exactly one match containing ${JSON.stringify(fragment)}`);
    return hits[0]?.code ?? null;
  };

  assert.equal(codeFor("RDONo.T- Abra"), "007");
  assert.equal(codeFor("RDONo. l0-"), "010");
  assert.equal(codeFor("RDO No. l7A"), "17A");
  assert.equal(codeFor("RDO No. l78"), "17B");
  assert.equal(codeFor("RDO No. 2lB"), "21B");
  assert.equal(codeFor("RDO No. I 16"), "116");
  assert.equal(codeFor("RDO No. 5l"), "051");
  assert.equal(codeFor("RDO No. 4l"), "041");
  assert.equal(codeFor("RDONo.3l-"), "031");
  assert.equal(codeFor("RDO No- 34"), "034");
  assert.equal(codeFor("RDO No, 26"), "026");
  assert.equal(codeFor("RDO No. 53B"), "53B");
  assert.equal(codeFor("RDO No. 24 -Valenzuela"), "024");
});

test("`RDO No. l78 - North Tarlac` is recovered as a branch code, not 178", () => {
  const { rdos } = extractRdos(layoutText);
  const match = rdos.find((candidate) => candidate.raw.includes("l78"));
  assert.ok(match);
  assert.equal(match.code, "17B");
  assert.equal(match.referenceName, "Paniqui, Tarlac");
  assert.equal(match.confidence, "high");
  assert.ok(match.notes.some((note) => note.includes("178 -> 17B")));
});

test("Large Taxpayer divisions are kept despite conflicting reference names", () => {
  const { rdos, rdoCodes } = extractRdos(layoutText);
  const lt = rdos.find((match) => match.raw.includes("Regular LT Audit Division I"));
  assert.ok(lt);
  assert.equal(lt.code, "116");
  assert.equal(lt.referenceName, "Bislig City");
  assert.equal(lt.matchedBy, "code");
  assert.equal(lt.confidence, "review");
  assert.ok(rdoCodes.includes("116"));
});

test("placeholder reference names count as plausible", () => {
  const { rdos } = extractRdos(layoutText);
  const occidental = rdos.find((match) => match.raw.includes("Occidental Mindoro"));
  assert.ok(occidental);
  assert.equal(occidental.code, "037");
  assert.equal(occidental.referenceName, "RDO 037");
  assert.equal(occidental.matchedBy, "code+name");
  assert.equal(occidental.confidence, "high");
});

test("the lettered expansion of 043 is recorded in notes", () => {
  const { rdos } = extractRdos(layoutText);
  const pasig = rdos.find((match) => match.code === "043");
  assert.ok(pasig);
  assert.ok(pasig.notes.some((note) => note.includes("43A, 43B")));

  // No other emitted office expands.
  const expanders = rdos.filter((match) =>
    match.notes.some((note) => note.startsWith("expanded ")),
  );
  assert.deepEqual(
    expanders.map((match) => match.code),
    ["043"],
  );
});

test("scanning stops at the deadline-table header", () => {
  const region = scanRegion(layoutText);
  assert.ok(region.includes("RDO No. 37 - Occidental Mindoro"));
  assert.ok(!region.includes("BIR Forms/Returns"));
  assert.ok(!region.includes("Extended Due Date"));
  assert.ok(!region.includes("1601-C"));
});

test("RDO mentions below the deadline-table header are ignored", () => {
  const spliced = layoutText.replace(
    "BIR Forms/Returns",
    "BIR Forms/Returns\nRDO No. 99 - Malaybalay City",
  );
  assert.ok(!extractRdos(spliced).rdoCodes.includes("099"));
});

// GROUND TRUTH: the committed layout text carries no prose office count — the
// only "58" in the document is `RDO No. 58 - West Batangas`, a table cell.
// Appendix A.1's "prose count invariant: 58 stated on page 1" is not in the
// fixture, so this circular yields null and the caller's invariant is a no-op.
test("RMC 89-2026 states no office count in prose", () => {
  assert.equal(extractRdos(layoutText).statedOfficeCount, null);
});

test("a stated office count is parsed when a circular prints one", () => {
  assert.equal(
    parseStatedOfficeCount("affecting fifty-eight (58) Revenue District Offices listed below:"),
    58,
  );
  assert.equal(parseStatedOfficeCount("the 12 affected offices"), 12);
  assert.equal(parseStatedOfficeCount("Revenue District Offices of the Bureau"), null);
  assert.equal(parseStatedOfficeCount("RDO No. 58 - West Batangas\nRevenue District Offices"), null);
});

test("an unresolvable code is reported but excluded from rdoCodes", () => {
  const text = "RDO No. 999 - Atlantis Special Zone\n   BIR Forms/Returns   Due Date   Extended Due Date\n";
  const { rdos, rdoCodes } = extractRdos(text);
  assert.equal(rdos.length, 1);
  assert.equal(rdos[0]?.code, null);
  assert.equal(rdos[0]?.confidence, "review");
  assert.deepEqual(rdoCodes, []);
});

test("an unresolvable code falls back to a unique reference name match", () => {
  const { rdos, rdoCodes } = extractRdos("RDO No. 999 - Tagbilaran City\n");
  assert.equal(rdos[0]?.code, "084");
  assert.equal(rdos[0]?.matchedBy, "name");
  assert.equal(rdos[0]?.confidence, "review");
  assert.deepEqual(rdoCodes, ["084"]);
});

// ---------------------------------------------------------------------------
// RMC No. 62-2026 — the second extraction fixture (plan T10.1). One fixture
// taught this module one circular's habits: RMC 89-2026 tabulates its offices
// as `RDO No. 39`, while RMC 62-2026 spells them out in a numbered list and
// prints the plural `Revenue District Offices (RDOs)` in the lead-in prose.

const rmc62LayoutText = readFileSync(
  path.join(here, "fixtures", "2026-08-11", "rmc-62-2026-pdftotext-layout.txt"),
  "utf8",
);

test("RMC 62-2026 reads its spelled-out, OCR-damaged office list", () => {
  const { rdos, rdoCodes } = extractRdos(rmc62LayoutText);

  // `Revenue District Office No. 1 10` and `... No. l l l`, both with the code
  // broken into separate digit-ish runs.
  assert.deepEqual(rdoCodes, ["110", "111"]);
  assert.equal(rdos.length, 2);
  assert.deepEqual(
    rdos.map((match) => match.code),
    ["110", "111"],
  );
});

test("RMC 62-2026's office-count invariant holds", () => {
  const { rdos, statedOfficeCount } = extractRdos(rmc62LayoutText);
  const matched = new Set(rdos.map((match) => match.code).filter((code) => code !== null));

  assert.equal(statedOfficeCount, 2);
  assert.equal(matched.size, 2);
  assert.equal(statedOfficeCount, matched.size);
});

test("RMC 62-2026's offices carry the confidence their names earn", () => {
  const { rdos } = extractRdos(rmc62LayoutText);

  const generalSantos = rdos.find((match) => match.code === "110");
  assert.ok(generalSantos);
  assert.equal(generalSantos.referenceName, "General Santos City");
  assert.equal(generalSantos.matchedBy, "code+name");
  assert.equal(generalSantos.confidence, "high");

  // The circular labels 111 by province ("South Cotabato"), the reference by
  // city ("Koronadal City"). Kept on the code, flagged for a human.
  const koronadal = rdos.find((match) => match.code === "111");
  assert.ok(koronadal);
  assert.equal(koronadal.referenceName, "Koronadal City");
  assert.equal(koronadal.matchedBy, "code");
  assert.equal(koronadal.confidence, "review");
  assert.ok(koronadal.notes.some((note) => note.includes("South Cotabato")));
});

test("the plural `Revenue District Offices (RDOs)` prose is not an office", () => {
  // The sentence that introduces RMC 62-2026's list. Matching it would invent
  // an office and break the count invariant it is printed right above.
  const prose =
    "required attachments and to provide ample time for taxpayers and BIR " +
    "Personnel uncler the following\nRevenue District Offices (RDOs) to comply " +
    "with the statutory tax rleadlines:\n";
  assert.deepEqual(extractRdos(prose).rdos, []);

  // Nor does the region heading in the same circular's subject line.
  assert.deepEqual(
    extractRdos("Revenue Region No. I8 - South Central Mindanao\n").rdos,
    [],
  );
});

test("RMC 62-2026's scan region stops at its OCR-damaged table header", () => {
  const region = scanRegion(rmc62LayoutText);
  assert.ok(region.includes("Revenue District Office No. l l l"));
  assert.ok(!region.includes("I)ue Date"));
  assert.ok(!region.includes("SUBMISSION"));
});
