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
  loadState,
  markExtracted,
  markSeen,
  saveState,
  serializeState,
  type SeenState,
} from "./state.ts";

// Clocks are injected, never read from Date.now(), so the serialized state is
// byte-stable and these assertions are deterministic.
const shaRmc89 = "59bba7e9a114cbf7714903fa06513d00fb8113083ecba96dfa01f138cc5134e9";
const shaReplaced = "0000000000000000000000000000000000000000000000000000000000000001";
const extractedAtUnix = 1_754_870_400;

async function scratchFile(name: string): Promise<string> {
  const directory = await mkdtemp(path.join(tmpdir(), "news-sync-state-"));
  return path.join(directory, name);
}

function sampleState(): SeenState {
  let state = emptyState();
  state = markExtracted(state, "bir:rmo:2026:019", null, extractedAtUnix, 1);
  state = markExtracted(state, "bir:rmc:2026:089", shaRmc89, extractedAtUnix, 1);
  state = markExtracted(state, "bir:rmc:2026:088", shaReplaced, extractedAtUnix + 60, 2);
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
      `      "firstSeenAtUnix": ${extractedAtUnix + 60},`,
      `      "extractedAtUnix": ${extractedAtUnix + 60},`,
      '      "feedRev": 2',
      "    },",
      '    "bir:rmc:2026:089": {',
      `      "pdfSha256": "${shaRmc89}",`,
      `      "firstSeenAtUnix": ${extractedAtUnix},`,
      `      "extractedAtUnix": ${extractedAtUnix},`,
      '      "feedRev": 1',
      "    },",
      '    "bir:rmo:2026:019": {',
      '      "pdfSha256": null,',
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
  reordered = markExtracted(reordered, "bir:rmc:2026:088", shaReplaced, extractedAtUnix + 60, 2);
  reordered = markExtracted(reordered, "bir:rmc:2026:089", shaRmc89, extractedAtUnix, 1);
  reordered = markExtracted(reordered, "bir:rmo:2026:019", null, extractedAtUnix, 1);
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
  const after = markExtracted(before, "bir:rmc:2026:089", shaReplaced, extractedAtUnix + 120, 3);

  assert.equal(serializeState(before), snapshot);
  assert.notEqual(after, before);
  assert.deepEqual(after.issuances["bir:rmc:2026:089"], {
    pdfSha256: shaReplaced,
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

test("loadState falls back to empty state on unusable JSON", async () => {
  const statePath = await scratchFile("seen.json");
  await writeFile(statePath, "{ not json", "utf8");
  assert.deepEqual(await loadState(statePath), { issuances: {} });

  await writeFile(statePath, JSON.stringify({ issuances: [] }), "utf8");
  assert.deepEqual(await loadState(statePath), { issuances: {} });
});
