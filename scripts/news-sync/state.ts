// Dedupe state (plan §T3.2). `state/seen.json` records, per issuance, the
// sha256 of the PDF we extracted from. An issuance whose id is known and whose
// PDF hash is unchanged skips the classify/extract/validate stages; a replaced
// PDF changes the hash and forces a re-extraction. The file is committed by the
// cron, so the serialization has to be byte-stable across runs.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

export type SeenIssuance = {
  pdfSha256: string | null;
  /**
   * When this issuance was first observed, in unix seconds. Persisted because
   * `feed.ts` falls back to it for the `published_at_unix` of an issuance the
   * archive has not dated yet: recomputing it from the current clock on every
   * run would rewrite the feed four times a day for no reason.
   */
  firstSeenAtUnix: number;
  /** 0 for an issuance that was recorded as seen but never PDF-extracted. */
  extractedAtUnix: number;
  /** Feed revision the extraction was folded into; 0 when never extracted. */
  feedRev: number;
};

export type SeenState = {
  issuances: Record<string, SeenIssuance>;
};

/** State used when `state/seen.json` does not exist yet. */
export function emptyState(): SeenState {
  return { issuances: {} };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseIssuance(value: unknown): SeenIssuance | null {
  if (!isRecord(value)) return null;
  const { pdfSha256, firstSeenAtUnix, extractedAtUnix, feedRev } = value;
  if (pdfSha256 !== null && typeof pdfSha256 !== "string") return null;
  if (typeof extractedAtUnix !== "number" || !Number.isFinite(extractedAtUnix)) return null;
  if (typeof feedRev !== "number" || !Number.isFinite(feedRev)) return null;
  // A state file written before firstSeenAtUnix existed still carries a usable
  // lower bound in extractedAtUnix; preferring it to dropping the entry keeps
  // the published timestamps of already-known issuances stable across upgrades.
  const firstSeen =
    typeof firstSeenAtUnix === "number" && Number.isFinite(firstSeenAtUnix)
      ? firstSeenAtUnix
      : extractedAtUnix;
  return { pdfSha256, firstSeenAtUnix: firstSeen, extractedAtUnix, feedRev };
}

/**
 * Reads dedupe state. A missing file is the first-run case and yields empty
 * state; malformed entries are dropped rather than aborting the sync, since a
 * dropped entry only costs one redundant extraction.
 */
export async function loadState(statePath: string): Promise<SeenState> {
  let raw: string;
  try {
    raw = await readFile(statePath, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return emptyState();
    throw error;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return emptyState();
  }
  if (!isRecord(parsed) || !isRecord(parsed.issuances)) return emptyState();

  const issuances: Record<string, SeenIssuance> = {};
  for (const [externalId, value] of Object.entries(parsed.issuances)) {
    const issuance = parseIssuance(value);
    if (issuance !== null) issuances[externalId] = issuance;
  }
  return { issuances };
}

/** Serializes state with sorted keys, 2-space indent and a trailing newline. */
export function serializeState(state: SeenState): string {
  const issuances: Record<string, SeenIssuance> = {};
  for (const externalId of Object.keys(state.issuances).toSorted()) {
    const entry = state.issuances[externalId];
    if (entry === undefined) continue;
    issuances[externalId] = {
      pdfSha256: entry.pdfSha256,
      firstSeenAtUnix: entry.firstSeenAtUnix,
      extractedAtUnix: entry.extractedAtUnix,
      feedRev: entry.feedRev,
    };
  }
  return `${JSON.stringify({ issuances }, null, 2)}\n`;
}

/** Writes dedupe state, creating the containing directory when needed. */
export async function saveState(statePath: string, state: SeenState): Promise<void> {
  await mkdir(path.dirname(path.resolve(statePath)), { recursive: true });
  await writeFile(statePath, serializeState(state), "utf8");
}

/**
 * True only when the issuance is known *and* the PDF hash matches — a new hash
 * (or an entry recorded without one) means the document changed and has to be
 * extracted again.
 */
export function isAlreadyExtracted(
  state: SeenState,
  externalId: string,
  pdfSha256: string | null,
): boolean {
  const entry = state.issuances[externalId];
  if (entry === undefined) return false;
  if (entry.pdfSha256 === null || pdfSha256 === null) return false;
  return entry.pdfSha256 === pdfSha256;
}

/**
 * Pure: returns new state with `externalId` recorded as extracted. An existing
 * `firstSeenAtUnix` is carried over — re-extraction does not make an issuance
 * new again.
 */
export function markExtracted(
  state: SeenState,
  externalId: string,
  pdfSha256: string | null,
  nowUnix: number,
  feedRev: number,
): SeenState {
  const firstSeenAtUnix = state.issuances[externalId]?.firstSeenAtUnix ?? nowUnix;
  return {
    issuances: {
      ...state.issuances,
      [externalId]: { pdfSha256, firstSeenAtUnix, extractedAtUnix: nowUnix, feedRev },
    },
  };
}

/**
 * Pure: records an issuance the pipeline published as a notice without running
 * the PDF stages (not classified as an extension circular, or no PDF at all).
 * A known issuance is returned untouched, so its first-seen stamp never moves.
 */
export function markSeen(state: SeenState, externalId: string, nowUnix: number): SeenState {
  if (state.issuances[externalId] !== undefined) return state;
  return {
    issuances: {
      ...state.issuances,
      [externalId]: {
        pdfSha256: null,
        firstSeenAtUnix: nowUnix,
        extractedAtUnix: 0,
        feedRev: 0,
      },
    },
  };
}

/** When `externalId` was first observed, or null when it is new to this run. */
export function firstSeenUnix(state: SeenState, externalId: string): number | null {
  return state.issuances[externalId]?.firstSeenAtUnix ?? null;
}

/** Pure: returns new state without `externalId`. Backs `sync.ts --force <id>`. */
export function forgetIssuance(state: SeenState, externalId: string): SeenState {
  const issuances: Record<string, SeenIssuance> = { ...state.issuances };
  delete issuances[externalId];
  return { issuances };
}
