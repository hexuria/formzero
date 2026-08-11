import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  emptyState,
  firstSeenUnix,
  forgetIssuance,
  isAlreadyExtracted,
  isRecordedExtraction,
  loadState,
  markExtracted,
  markSeen,
  parseCircularExtraction,
  recordedPdf,
  saveState,
  serializeState,
  type ExtractionRecord,
  type SeenState,
} from "./state.ts";
import type { CircularExtraction } from "./types.ts";

// Clocks are injected, never read from Date.now(), so the serialized state is
// byte-stable and these assertions are deterministic.
const shaRmc89 = "59bba7e9a114cbf7714903fa06513d00fb8113083ecba96dfa01f138cc5134e9";
const shaReplaced = "0000000000000000000000000000000000000000000000000000000000000001";
const extractedAtUnix = 1_754_870_400;

async function scratchFile(name: string): Promise<string> {
  const directory = await mkdtemp(path.join(tmpdir(), "news-sync-state-"));
  return path.join(directory, name);
}

/** A download that recorded nothing beyond its hash (the pre-HEAD-check shape). */
function record(
  pdfSha256: string | null,
  overrides: Partial<ExtractionRecord> = {},
): ExtractionRecord {
  return { pdfSha256, pdfBytes: null, extraction: null, ...overrides };
}

function sampleExtraction(overrides: Partial<CircularExtraction> = {}): CircularExtraction {
  return {
    externalId: "bir:rmc:2026:089",
    headerDateIssued: "2026-08-10",
    globalExtendedDate: "2026-08-17",
    window: { from: "2026-08-10", to: "2026-08-16" },
    statedOfficeCount: 58,
    rdos: [
      {
        raw: "RDO No. 4l - Mandaluyong City",
        code: "041",
        referenceName: "Mandaluyong City",
        matchedBy: "code+name",
        confidence: "high",
        notes: ["digit context: l -> 1"],
      },
    ],
    rdoCodes: ["039", "041"],
    rows: [
      {
        channel: "nonefps",
        rawDescription: "BIR Forms 1601-C — Non-eFPS Filers",
        formCodesDisplay: ["1601-C"],
        formCodesCanonical: ["1601C"],
        originalDate: "2026-08-10",
        extendedDate: "2026-08-17",
        dateAssignment: "same_line",
        confidence: "high",
        notes: [],
      },
    ],
    needsManualReview: false,
    notes: ["prose states 58 offices"],
    ...overrides,
  };
}

function sampleState(): SeenState {
  let state = emptyState();
  state = markExtracted(state, "bir:rmo:2026:019", record(null), extractedAtUnix, 1);
  state = markExtracted(state, "bir:rmc:2026:089", record(shaRmc89), extractedAtUnix, 1);
  state = markExtracted(state, "bir:rmc:2026:088", record(shaReplaced), extractedAtUnix + 60, 2);
  return state;
}

test("loadState tolerates an absent file", async () => {
  const statePath = await scratchFile("seen.json");
  assert.deepEqual(await loadState(statePath), { issuances: {} });
});

test("loadState tolerates an absent directory", async () => {
  const statePath = path.join(await scratchFile("nested"), "state", "seen.json");
  assert.deepEqual(await loadState(statePath), { issuances: {} });
});

test("saveState creates the state directory and writes sorted 2-space JSON", async () => {
  const statePath = path.join(await scratchFile("nested"), "state", "seen.json");
  await saveState(statePath, sampleState());

  const written = await readFile(statePath, "utf8");
  assert.equal(
    written,
    [
      "{",
      '  "issuances": {',
      '    "bir:rmc:2026:088": {',
      `      "pdfSha256": "${shaReplaced}",`,
      '      "pdfBytes": null,',
      `      "firstSeenAtUnix": ${extractedAtUnix + 60},`,
      `      "extractedAtUnix": ${extractedAtUnix + 60},`,
      '      "feedRev": 2',
      "    },",
      '    "bir:rmc:2026:089": {',
      `      "pdfSha256": "${shaRmc89}",`,
      '      "pdfBytes": null,',
      `      "firstSeenAtUnix": ${extractedAtUnix},`,
      `      "extractedAtUnix": ${extractedAtUnix},`,
      '      "feedRev": 1',
      "    },",
      '    "bir:rmo:2026:019": {',
      '      "pdfSha256": null,',
      '      "pdfBytes": null,',
      `      "firstSeenAtUnix": ${extractedAtUnix},`,
      `      "extractedAtUnix": ${extractedAtUnix},`,
      '      "feedRev": 1',
      "    }",
      "  }",
      "}",
      "",
    ].join("\n"),
  );
});

test("serialization is insertion-order independent and round-trips byte-identically", async () => {
  let reordered = emptyState();
  const later = extractedAtUnix + 60;
  reordered = markExtracted(reordered, "bir:rmc:2026:088", record(shaReplaced), later, 2);
  reordered = markExtracted(reordered, "bir:rmc:2026:089", record(shaRmc89), extractedAtUnix, 1);
  reordered = markExtracted(reordered, "bir:rmo:2026:019", record(null), extractedAtUnix, 1);
  assert.equal(serializeState(reordered), serializeState(sampleState()));

  const statePath = await scratchFile("seen.json");
  await saveState(statePath, sampleState());
  const first = await readFile(statePath, "utf8");
  await saveState(statePath, await loadState(statePath));
  assert.equal(await readFile(statePath, "utf8"), first);
});

test("isAlreadyExtracted is true only for a known id with a matching sha", () => {
  const state = sampleState();
  assert.equal(isAlreadyExtracted(state, "bir:rmc:2026:089", shaRmc89), true);
  // Same issuance, PDF replaced upstream: the sha moved, so re-extract.
  assert.equal(isAlreadyExtracted(state, "bir:rmc:2026:089", shaReplaced), false);
  assert.equal(isAlreadyExtracted(state, "bir:rmc:2026:087", shaRmc89), false);
  // An unhashable side (no download yet, or nothing recorded) never counts.
  assert.equal(isAlreadyExtracted(state, "bir:rmc:2026:089", null), false);
  assert.equal(isAlreadyExtracted(state, "bir:rmo:2026:019", null), false);
  assert.equal(isAlreadyExtracted(state, "bir:rmo:2026:019", shaRmc89), false);
});

test("markExtracted is pure and overwrites an existing entry", () => {
  const before = sampleState();
  const snapshot = serializeState(before);
  const after = markExtracted(
    before,
    "bir:rmc:2026:089",
    record(shaReplaced),
    extractedAtUnix + 120,
    3,
  );

  assert.equal(serializeState(before), snapshot);
  assert.notEqual(after, before);
  assert.deepEqual(after.issuances["bir:rmc:2026:089"], {
    pdfSha256: shaReplaced,
    pdfBytes: null,
    pdfEtag: null,
    extraction: null,
    // Re-extraction updates the hash and the extraction stamp but never the
    // first sighting.
    firstSeenAtUnix: extractedAtUnix,
    extractedAtUnix: extractedAtUnix + 120,
    feedRev: 3,
  });
  assert.equal(Object.keys(after.issuances).length, 3);
  assert.equal(isAlreadyExtracted(after, "bir:rmc:2026:089", shaReplaced), true);
});

test("forgetIssuance removes exactly one entry and leaves the input untouched", () => {
  const before = sampleState();
  const snapshot = serializeState(before);
  const after = forgetIssuance(before, "bir:rmc:2026:089");

  assert.equal(serializeState(before), snapshot);
  assert.deepEqual(Object.keys(after.issuances).toSorted(), [
    "bir:rmc:2026:088",
    "bir:rmo:2026:019",
  ]);
  assert.equal(isAlreadyExtracted(after, "bir:rmc:2026:089", shaRmc89), false);
  // Forgetting an unknown id is a no-op, not an error.
  assert.equal(serializeState(forgetIssuance(after, "bir:rr:2026:004")), serializeState(after));
});

test("markSeen records a notice-only issuance once and never moves its stamp", () => {
  let state = markSeen(emptyState(), "bir:rmo:2026:019", extractedAtUnix);
  assert.deepEqual(state.issuances["bir:rmo:2026:019"], {
    pdfSha256: null,
    pdfBytes: null,
    pdfEtag: null,
    extraction: null,
    firstSeenAtUnix: extractedAtUnix,
    extractedAtUnix: 0,
    feedRev: 0,
  });

  const snapshot = serializeState(state);
  state = markSeen(state, "bir:rmo:2026:019", extractedAtUnix + 86_400);
  assert.equal(serializeState(state), snapshot);
  assert.equal(firstSeenUnix(state, "bir:rmo:2026:019"), extractedAtUnix);
  assert.equal(firstSeenUnix(state, "bir:rmc:2026:089"), null);
});

test("a pre-firstSeenAtUnix state file keeps its entries, dated by extraction", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(
    statePath,
    JSON.stringify({
      issuances: {
        "bir:rmc:2026:089": { pdfSha256: shaRmc89, extractedAtUnix, feedRev: 1 },
      },
    }),
    "utf8",
  );

  const state = await loadState(statePath);
  assert.equal(firstSeenUnix(state, "bir:rmc:2026:089"), extractedAtUnix);
});

test("loadState drops malformed entries instead of failing the sync", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(
    statePath,
    JSON.stringify({
      issuances: {
        "bir:rmc:2026:089": { pdfSha256: shaRmc89, extractedAtUnix, feedRev: 1 },
        "bir:rmc:2026:088": { pdfSha256: 42, extractedAtUnix, feedRev: 1 },
        "bir:rmc:2026:087": { pdfSha256: shaRmc89, feedRev: 1 },
        "bir:rmc:2026:086": "not an object",
      },
    }),
    "utf8",
  );

  const state = await loadState(statePath);
  assert.deepEqual(Object.keys(state.issuances), ["bir:rmc:2026:089"]);
});

test("a recorded size and extraction survive a save/load round trip", async () => {
  const extraction = sampleExtraction();
  const state = markExtracted(
    emptyState(),
    "bir:rmc:2026:089",
    { pdfSha256: shaRmc89, pdfBytes: 618_314, extraction },
    extractedAtUnix,
    1,
  );

  const statePath = await scratchFile("seen.json");
  await saveState(statePath, state);
  const reloaded = await loadState(statePath);

  assert.deepEqual(reloaded.issuances["bir:rmc:2026:089"], {
    pdfSha256: shaRmc89,
    pdfBytes: 618_314,
    pdfEtag: null,
    extraction,
    firstSeenAtUnix: extractedAtUnix,
    extractedAtUnix,
    feedRev: 1,
  });
  assert.deepEqual(recordedPdf(reloaded, "bir:rmc:2026:089"), {
    pdfSha256: shaRmc89,
    pdfBytes: 618_314,
    pdfEtag: null,
    extraction,
  });
  // Byte-stable: reloading and re-serializing must not move a single field.
  assert.equal(serializeState(reloaded), serializeState(state));
});

test("recordedPdf refuses a partial record, so no run skips a download on one", () => {
  const extraction = sampleExtraction();
  const id = "bir:rmc:2026:089";
  const partial = (overrides: Partial<ExtractionRecord>): ExtractionRecord => ({
    pdfSha256: shaRmc89,
    pdfBytes: 618_314,
    extraction,
    ...overrides,
  });

  const complete = markExtracted(emptyState(), id, partial({}), extractedAtUnix, 1);
  assert.notEqual(recordedPdf(complete, id), null);
  // A size with no extraction would skip the download and publish nothing.
  const noExtraction = markExtracted(emptyState(), id, partial({ extraction: null }), 0, 1);
  assert.equal(recordedPdf(noExtraction, id), null);
  // An extraction with no size has nothing to compare a HEAD answer against.
  const noSize = markExtracted(emptyState(), id, partial({ pdfBytes: null }), 0, 1);
  assert.equal(recordedPdf(noSize, id), null);
  const noSha = markExtracted(emptyState(), id, partial({ pdfSha256: null }), 0, 1);
  assert.equal(recordedPdf(noSha, id), null);
  assert.equal(recordedPdf(complete, "bir:rmc:2026:088"), null);
});

test("isRecordedExtraction sees a changed size or a changed extraction", () => {
  const extraction = sampleExtraction();
  const id = "bir:rmc:2026:089";
  const stored: ExtractionRecord = { pdfSha256: shaRmc89, pdfBytes: 618_314, extraction };
  const state = markExtracted(emptyState(), id, stored, extractedAtUnix, 1);

  assert.equal(isRecordedExtraction(state, id, { ...stored }), true);
  assert.equal(isRecordedExtraction(state, id, { ...stored, pdfBytes: 618_315 }), false);
  assert.equal(isRecordedExtraction(state, id, { ...stored, pdfSha256: shaReplaced }), false);
  assert.equal(
    isRecordedExtraction(state, id, {
      ...stored,
      extraction: sampleExtraction({ rdoCodes: ["039"] }),
    }),
    false,
  );
  assert.equal(isRecordedExtraction(state, id, { ...stored, extraction: null }), false);
  assert.equal(isRecordedExtraction(state, "bir:rmc:2026:088", stored), false);
});

test("parseCircularExtraction rejects damage instead of half-parsing it", () => {
  const extraction = sampleExtraction();
  assert.deepEqual(parseCircularExtraction(JSON.parse(JSON.stringify(extraction))), extraction);

  const damaged: unknown[] = [
    null,
    "not an object",
    { ...extraction, externalId: 7 },
    { ...extraction, rows: [{ ...extraction.rows[0], channel: "efps_group_z" }] },
    { ...extraction, rows: [{ ...extraction.rows[0], dateAssignment: "guessed" }] },
    { ...extraction, rows: [{ ...extraction.rows[0], confidence: "maybe" }] },
    { ...extraction, rows: [{ ...extraction.rows[0], formCodesCanonical: [1601] }] },
    { ...extraction, rdos: [{ ...extraction.rdos[0], matchedBy: "vibes" }] },
    { ...extraction, rdoCodes: "039" },
    { ...extraction, window: { from: "2026-08-10" } },
    { ...extraction, needsManualReview: "no" },
    { ...extraction, statedOfficeCount: 58.5 },
  ];
  for (const value of damaged) {
    assert.equal(parseCircularExtraction(value), null, JSON.stringify(value)?.slice(0, 80));
  }
});

test("a damaged extraction costs the extraction, not the whole state entry", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(
    statePath,
    JSON.stringify({
      issuances: {
        "bir:rmc:2026:089": {
          pdfSha256: shaRmc89,
          pdfBytes: 618_314,
          firstSeenAtUnix: extractedAtUnix,
          extractedAtUnix,
          feedRev: 1,
          extraction: { externalId: "bir:rmc:2026:089", rows: "truncated" },
        },
      },
    }),
    "utf8",
  );

  const state = await loadState(statePath);
  // The first sighting still anchors the published date; only the shortcut is
  // lost, which costs one download and one re-extraction.
  assert.equal(firstSeenUnix(state, "bir:rmc:2026:089"), extractedAtUnix);
  assert.equal(state.issuances["bir:rmc:2026:089"].extraction, null);
  assert.equal(recordedPdf(state, "bir:rmc:2026:089"), null);
});

test("a state file written before pdfBytes existed still loads", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(
    statePath,
    JSON.stringify({
      issuances: {
        "bir:rmc:2026:089": {
          pdfSha256: shaRmc89,
          firstSeenAtUnix: extractedAtUnix,
          extractedAtUnix,
          feedRev: 1,
        },
      },
    }),
    "utf8",
  );

  const state = await loadState(statePath);
  assert.equal(isAlreadyExtracted(state, "bir:rmc:2026:089", shaRmc89), true);
  assert.equal(state.issuances["bir:rmc:2026:089"].pdfBytes, null);
  assert.equal(recordedPdf(state, "bir:rmc:2026:089"), null);
});

test("loadState falls back to empty state on unusable JSON", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(statePath, "{ not json", "utf8");
  assert.deepEqual(await loadState(statePath), { issuances: {} });

  await writeFile(statePath, JSON.stringify({ issuances: [] }), "utf8");
  assert.deepEqual(await loadState(statePath), { issuances: {} });
});
