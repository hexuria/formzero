import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { extractCircular } from "./extract-rmc-extension.ts";
import type { IssuanceRecord } from "./types.ts";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.join(
  scriptDirectory,
  "fixtures",
  "2026-08-11",
  "rmc-89-2026-pdftotext-layout.txt",
);

const rmc89: IssuanceRecord = {
  externalId: "bir:rmc:2026:089",
  kind: "RMC",
  number: "89-2026",
  subject: "Providing Extension of the Deadlines for the Filing of Tax Returns",
  pdfUrl: "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  dateIssued: "2026-08-10",
  dateSource: "archive",
  source: "merged",
  firstSeenAtUnix: 1_786_752_000,
};

async function layoutText(): Promise<string> {
  return await readFile(fixturePath, "utf8");
}

test("the RMC 89-2026 capture composes into one CircularExtraction", async () => {
  const extraction = extractCircular({ issuance: rmc89, layoutText: await layoutText() });

  assert.equal(extraction.externalId, "bir:rmc:2026:089");
  assert.equal(extraction.globalExtendedDate, "2026-08-17");
  assert.deepEqual(extraction.window, { from: "2026-08-10", to: "2026-08-16" });
  assert.equal(extraction.needsManualReview, false);

  // Appendix A.1: 58 offices, 60 emitted strings once 043 expands to 43A/43B.
  const distinctOffices = new Set(
    extraction.rdos.map((rdo) => rdo.code).filter((code) => code !== null),
  );
  assert.equal(distinctOffices.size, 58);
  assert.equal(extraction.rdoCodes.length, 60);
  assert.ok(extraction.rdoCodes.includes("43A") && extraction.rdoCodes.includes("43B"));

  assert.ok(extraction.rows.length > 0);
  const sameLine = extraction.rows.filter((row) => row.dateAssignment === "same_line");
  assert.ok(sameLine.length >= 6, `expected the printed date pairs, got ${sameLine.length}`);
});

test("the page-1 letterhead date is read as a second-tier issue date", async () => {
  const extraction = extractCircular({ issuance: rmc89, layoutText: await layoutText() });

  // Printed above "REVENUE MEMORANDUM CIRCULAR NO. 089-2026"; agrees with the
  // archive's DATE OF ISSUE for this circular.
  assert.equal(extraction.headerDateIssued, "2026-08-10");
  assert.ok(
    extraction.notes.some((note) => note.includes("page-1 letterhead issue date: 2026-08-10")),
    extraction.notes.join(" | "),
  );
});

test("a letterhead with no readable date yields no header date rather than a guess", () => {
  const synthetic = [
    "                    REPUBLIC OF THE PHILIPPINES",
    "                      DEPARTMENT OF FINANCE",
    "                     BUREAU OF INTERNAL REVENUE",
    "                       National Office Building",
    "                             Quezon City",
    "",
    "REVENUE MEMORANDUM CIRCULAR NO. 89-2026",
    "",
    "SUBJECT : Providing Extension of the Deadlines for the Filing of Tax Returns",
    "          and Payment of the Corresponding Taxes Due Thereon.",
    "",
    "This Circular extends the deadlines until August 17, 2026.",
    "",
    "BIR Forms/Returns                      Due Date          Extended Due Date",
    "",
  ].join("\n");

  const extraction = extractCircular({ issuance: rmc89, layoutText: synthetic });

  // August 17 is below the heading, so it can never be mistaken for the issue date.
  assert.equal(extraction.headerDateIssued, null);
  assert.equal(extraction.globalExtendedDate, "2026-08-17");
  assert.ok(
    extraction.notes.some((note) => note.includes("no issue date readable")),
    extraction.notes.join(" | "),
  );
});

test("the fixture states no office count, so the invariant is not a failure", async () => {
  const extraction = extractCircular({ issuance: rmc89, layoutText: await layoutText() });

  assert.equal(extraction.statedOfficeCount, null);
  assert.equal(extraction.needsManualReview, false);
  assert.ok(
    extraction.notes.some((note) => note.includes("the prose states no count")),
    extraction.notes.join(" | "),
  );
});

test("a stated count that disagrees with the matched offices demands manual review", () => {
  const synthetic = [
    "REVENUE MEMORANDUM CIRCULAR NO. 89-2026",
    "",
    "Deadlines are extended for the twelve (12) affected Revenue District Offices:",
    "",
    "     RDO No. 39 - South Quezon City",
    "     RDO No. 41 - Mandaluyong City",
    "",
    "BIR Forms/Returns                      Due Date          Extended Due Date",
    "",
  ].join("\n");

  const extraction = extractCircular({ issuance: rmc89, layoutText: synthetic });

  assert.equal(extraction.statedOfficeCount, 12);
  assert.equal(extraction.rdoCodes.length, 2);
  assert.equal(extraction.needsManualReview, true);
  assert.ok(
    extraction.notes.some((note) => note.includes("office-count invariant FAILED")),
    extraction.notes.join(" | "),
  );
});

test("a textless scan is flagged and no parser runs (plan decision D3)", () => {
  // Six near-empty pages: exactly the shape of a scan with no OCR layer.
  const textless = `${"a scanned page\f".repeat(6)}`;

  const extraction = extractCircular({ issuance: rmc89, layoutText: textless });

  assert.equal(extraction.needsManualReview, true);
  assert.deepEqual(extraction.rows, []);
  assert.deepEqual(extraction.rdos, []);
  assert.deepEqual(extraction.rdoCodes, []);
  assert.equal(extraction.globalExtendedDate, null);
  assert.equal(extraction.window, null);
  assert.equal(extraction.statedOfficeCount, null);
  assert.equal(extraction.headerDateIssued, null);
  assert.ok(
    extraction.notes.some((note) => note.includes("text layer unusable")),
    extraction.notes.join(" | "),
  );
});

test("extraction is pure: the same text yields the same record", async () => {
  const text = await layoutText();
  assert.deepEqual(
    extractCircular({ issuance: rmc89, layoutText: text }),
    extractCircular({ issuance: rmc89, layoutText: text }),
  );
});
