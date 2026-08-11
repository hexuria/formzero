import assert from "node:assert/strict";
import test from "node:test";

import { fuzzyMonth, levenshtein, normalizeDigits, parseNoisyDate } from "./ocr-normalize.ts";

// Every case below is real text from
// fixtures/2026-08-11/rmc-89-2026-pdftotext-layout.txt or the OCR-noise table
// in fixtures/2026-08-11/CAPTURES.md.

test("normalizeDigits maps letter lookalikes to digits", () => {
  assert.equal(normalizeDigits("4l"), "41"); // RDO No. 4l - Mandaluyong City
  assert.equal(normalizeDigits("T"), "7"); // RDONo.T- Abra
  assert.equal(normalizeDigits("l0"), "10"); // RDONo. l0- Mountain Province
  assert.equal(normalizeDigits("5l"), "51");
  assert.equal(normalizeDigits("|7"), "17");
  assert.equal(normalizeDigits("SB"), "58");
  assert.equal(normalizeDigits("ZG"), "26");
  assert.equal(normalizeDigits("OoI"), "001");
});

test("normalizeDigits strips inner spaces injected by the OCR", () => {
  assert.equal(normalizeDigits("06 1 9-F"), "0619-F");
  assert.equal(normalizeDigits("I 16"), "116"); // RDO No. I 16 - Regular LT Audit Division I
  assert.equal(normalizeDigits("1 l"), "11"); // August 1 l, 2026
  assert.equal(normalizeDigits("  2026  "), "2026");
});

test("normalizeDigits leaves characters outside the lookalike table alone", () => {
  assert.equal(normalizeDigits("1601-C"), "1601-C");
  assert.equal(normalizeDigits(""), "");
});

test("fuzzyMonth resolves OCR-damaged month names within distance 2", () => {
  assert.equal(fuzzyMonth("August"), 8);
  assert.equal(fuzzyMonth("august"), 8);
  assert.equal(fuzzyMonth("A]ugttst"), 8);
  assert.equal(fuzzyMonth("Aueust"), 8);
  assert.equal(fuzzyMonth("Januarv"), 1);
  assert.equal(fuzzyMonth("Decembcr"), 12);
});

test("fuzzyMonth refuses tokens beyond the distance budget", () => {
  assert.equal(fuzzyMonth("Angttst"), null); // distance 3 from "august"
  assert.equal(fuzzyMonth("Sgd"), null);
  assert.equal(fuzzyMonth("No"), null);
  assert.equal(fuzzyMonth(""), null);
});

test("parseNoisyDate reads the damaged dates in the RMC 89-2026 layout text", () => {
  assert.equal(parseNoisyDate("A]ugttst 17,2026")?.iso, "2026-08-17");
  assert.equal(parseNoisyDate("Aueust 17. 2026")?.iso, "2026-08-17");
  assert.equal(parseNoisyDate("August 1 l, 2026")?.iso, "2026-08-11");
  assert.equal(parseNoisyDate("August 13, 2026")?.iso, "2026-08-13");
  assert.equal(parseNoisyDate("August 10,2026")?.iso, "2026-08-10");
  assert.equal(parseNoisyDate("August 17,2026")?.iso, "2026-08-17");
});

test("parseNoisyDate returns null when the extended-date cell is unreadable", () => {
  // The Group D row prints "Angttst 1'? ,2026"; the caller must fall back to the
  // circular-level extended date rather than publish a guessed day.
  assert.equal(parseNoisyDate("Angttst 1'? ,2026"), null);
});

test("parseNoisyDate rejects impossible civil dates", () => {
  assert.equal(parseNoisyDate("February 30, 2026"), null);
  assert.equal(parseNoisyDate("February 29, 2026"), null);
  assert.equal(parseNoisyDate("February 29, 2024")?.iso, "2024-02-29");
  assert.equal(parseNoisyDate("April 31, 2026"), null);
  assert.equal(parseNoisyDate("August 0, 2026"), null);
});

test("parseNoisyDate records every repair it performed", () => {
  assert.deepEqual(parseNoisyDate("August 13, 2026")?.notes, []);

  const damagedMonth = parseNoisyDate("A]ugttst 17,2026");
  assert.equal(damagedMonth?.notes.length, 1);
  assert.match(damagedMonth?.notes[0] ?? "", /A\]ugttst/u);
  assert.match(damagedMonth?.notes[0] ?? "", /August/u);
  assert.match(damagedMonth?.notes[0] ?? "", /edit distance 2/u);

  const damagedDay = parseNoisyDate("August 1 l, 2026");
  assert.deepEqual(damagedDay?.notes, ['OCR day "1 l" read as 11']);
});

test("parseNoisyDate scans past unparseable leading candidates", () => {
  const line = " e-FlLlNG & PAYMENT (Online/Manual)               August 10,2026";
  assert.equal(parseNoisyDate(line)?.iso, "2026-08-10");
  assert.equal(parseNoisyDate("no dates on this line"), null);
});

test("parseNoisyDate takes the first date on a line with a pair", () => {
  assert.equal(
    parseNoisyDate("August 13, 2026            Angttst 1'? ,2026")?.iso,
    "2026-08-13",
  );
});

test("levenshtein measures plain edit distance", () => {
  assert.equal(levenshtein("august", "august"), 0);
  assert.equal(levenshtein("aueust", "august"), 1);
  assert.equal(levenshtein("augttst", "august"), 2);
  assert.equal(levenshtein("angttst", "august"), 3);
  assert.equal(levenshtein("", "august"), 6);
  assert.equal(levenshtein("august", ""), 6);
});
