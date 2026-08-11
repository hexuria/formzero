import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import { CANONICAL_FORM_CODES, canonicalFormCode } from "./form-codes.ts";
import {
  buildArtifacts,
  expectedRdoEntryCount,
  formCodesPath,
  parseFormCodeAliases,
  parseRdoEntries,
  projectRoot,
  rdoReferencePath,
} from "./generate-data.ts";
import { findRdoByCode, letteredVariants, normalizeRdoCode, rdoEntries } from "./rdo.ts";

const execFileAsync = promisify(execFile);

test("committed vocabularies are byte-identical to a fresh generation", async () => {
  const artifacts = await buildArtifacts();
  assert.deepEqual(
    artifacts.map((artifact) => artifact.relativePath),
    [rdoReferencePath, formCodesPath],
  );

  for (const artifact of artifacts) {
    const onDisk = await readFile(path.join(projectRoot, artifact.relativePath), "utf8");
    assert.equal(
      onDisk,
      artifact.content,
      `${artifact.relativePath} drifted from its Zig source; run npm run generate:news-sync-data`,
    );
  }
});

test("generate-data.ts --check exits zero against the committed artifacts", async () => {
  const { stdout } = await execFileAsync(
    process.execPath,
    ["--experimental-strip-types", "scripts/news-sync/generate-data.ts", "--check"],
    { cwd: projectRoot },
  );
  assert.match(stdout, /verified 2 generated vocabularies/u);
});

test("the Zig RDO reference yields exactly 138 entries", async () => {
  const source = await readFile(
    path.join(projectRoot, "src/tax_profile/rdo_reference.zig"),
    "utf8",
  );
  assert.equal(parseRdoEntries(source).length, expectedRdoEntryCount);
  assert.equal(rdoEntries().length, expectedRdoEntryCount);
  assert.equal(new Set(rdoEntries().map((entry) => entry.code)).size, expectedRdoEntryCount);
});

test("every canonical alias round-trips through canonicalFormCode", async () => {
  const source = await readFile(path.join(projectRoot, "src/calendar/domain.zig"), "utf8");
  for (const alias of parseFormCodeAliases(source)) {
    assert.equal(canonicalFormCode(alias.display), alias.canonical);
    assert.ok(CANONICAL_FORM_CODES.has(alias.canonical));
  }
});

test("canonicalFormCode maps the printed codes the extractor harvests", () => {
  assert.equal(canonicalFormCode("1601-C"), "1601C");
  assert.equal(canonicalFormCode("0619-E"), "0619E");
  assert.equal(canonicalFormCode("0619-F"), "0619F");
  assert.equal(canonicalFormCode("1702-RT"), "1702RT");
  assert.equal(canonicalFormCode("1702-EX"), "1702EX");
  assert.equal(canonicalFormCode("1702-MX"), "1702MX");
  assert.equal(canonicalFormCode("2550Q"), "2550Q");
  assert.equal(canonicalFormCode("0620"), "0620");
  assert.equal(canonicalFormCode(" 1601c "), "1601C");
});

test("canonicalFormCode rejects codes outside the calendar engine's table", () => {
  assert.equal(canonicalFormCode("9999"), null);
  assert.equal(canonicalFormCode("1601"), null);
  assert.equal(canonicalFormCode(""), null);
});

test("findRdoByCode resolves canonical codes case-insensitively", () => {
  assert.equal(findRdoByCode("024")?.name, "Valenzuela City");
  assert.equal(findRdoByCode("17A")?.code, "17A");
  assert.equal(findRdoByCode("17a")?.code, "17A");
  assert.equal(findRdoByCode("999"), null);
  assert.equal(findRdoByCode(""), null);
});

test("normalizeRdoCode canonicalizes the OCR forms in the RMC 89-2026 scan", () => {
  assert.equal(normalizeRdoCode("24"), "024");
  assert.equal(normalizeRdoCode("7"), "007");
  assert.equal(normalizeRdoCode("T"), "007"); // RDONo.T- Abra
  assert.equal(normalizeRdoCode("l0"), "010"); // RDONo. l0- Mountain Province
  assert.equal(normalizeRdoCode("l7A"), "17A"); // RDO No. l7A - South Tarlac
  assert.equal(normalizeRdoCode("2lB"), "21B"); // RDO No. 2lB - South Pampansa
  assert.equal(normalizeRdoCode("I 16"), "116"); // RDO No. I 16 - Regular LT Audit Division I
  assert.equal(normalizeRdoCode("5l"), "051");
  assert.equal(normalizeRdoCode("53B"), "53B");
  assert.equal(normalizeRdoCode("4l"), "041"); // RDO No. 4l - Mandaluyong City
});

test("normalizeRdoCode is idempotent and tolerant of stray punctuation", () => {
  for (const entry of rdoEntries()) {
    assert.equal(normalizeRdoCode(entry.code), entry.code);
  }
  assert.equal(normalizeRdoCode(" 043 -"), "043");
  assert.equal(normalizeRdoCode("021b"), "21B");
});

test("normalizeRdoCode returns null for tokens that are not code shapes", () => {
  assert.equal(normalizeRdoCode(""), null);
  assert.equal(normalizeRdoCode("-"), null);
  assert.equal(normalizeRdoCode("Abra"), null);
  assert.equal(normalizeRdoCode("1234"), null);
});

test("letteredVariants expands a parent office into its branch codes", () => {
  assert.deepEqual(letteredVariants("043"), ["43A", "43B"]);
  assert.deepEqual(letteredVariants("43"), ["43A", "43B"]);
  assert.deepEqual(letteredVariants("053"), ["53A", "53B"]);
  assert.deepEqual(letteredVariants("021"), ["21A", "21B", "21C"]);
});

test("letteredVariants returns nothing for branchless and already-lettered codes", () => {
  assert.deepEqual(letteredVariants("024"), []);
  assert.deepEqual(letteredVariants("116"), []);
  assert.deepEqual(letteredVariants("43A"), []);
  assert.deepEqual(letteredVariants("not a code"), []);
});
