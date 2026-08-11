// Dedupe state (plan §T3.2). `state/seen.json` records, per issuance, the
// sha256 of the PDF we extracted from, the size the origin served it at, and
// the extraction it produced. An issuance whose id is known and whose PDF hash
// is unchanged skips the classify/extract/validate stages; a replaced PDF
// changes the hash and forces a re-extraction. The file is committed by the
// cron, so the serialization has to be byte-stable across runs.
//
// This file is the pipeline's only durable memory: the work/ tree is gitignored
// and absent on every fresh CI runner, while `state/seen.json` is published to
// the news-feed branch and restored before each run. That is why the recorded
// size and the extraction result live here — together they let a run answer
// "unchanged" from one HEAD request and still publish the same overrides,
// instead of re-downloading 4.2 MB of PDFs four times a day.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

import type {
  Channel,
  CircularExtraction,
  Confidence,
  DateAssignment,
  ExtensionRow,
  RdoMatch,
} from "./types.ts";

export type SeenIssuance = {
  pdfSha256: string | null;
  /**
   * `Content-Length` the origin served that PDF at, or null when unknown (no
   * download yet, or an offline run, whose text comes from a fixture). Only a
   * recorded size lets a later run decide "unchanged" from a HEAD request.
   */
  pdfBytes: number | null;
  /**
   * Strong `ETag` the origin served that PDF with, or null when it offered
   * none. Size alone cannot see a same-size replacement; an ETag that has
   * changed proves the bytes did, whatever the length says.
   */
  pdfEtag: string | null;
  /**
   * What extracting that PDF produced, or null when the issuance was never
   * PDF-extracted. Persisted so a run that skips the download still has the
   * overrides: without it, a skipped download would silently shrink the feed.
   */
  extraction: CircularExtraction | null;
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

/** Everything one completed extraction contributes to the persisted state. */
export type ExtractionRecord = {
  pdfSha256: string | null;
  pdfBytes: number | null;
  /**
   * Strong ETag the origin served. Optional: most callers have none, and an
   * absent field records the same fact as an explicit null.
   */
  pdfEtag?: string | null;
  extraction: CircularExtraction | null;
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

// Runtime mirrors of the string unions in types.ts, which stays type-only. A
// persisted extraction is machine-written, but it survives across code
// versions and a hand edit, so it is parsed as untrusted input rather than cast.
const CHANNELS: ReadonlySet<string> = new Set<Channel>([
  "nonefps",
  "efps_group_a",
  "efps_group_b",
  "efps_group_c",
  "efps_group_d",
  "efps_group_e",
  "efps_group_multi",
  "efps_and_nonefps",
  "registration",
  "submission",
  "unknown",
]);
const CONFIDENCES: ReadonlySet<string> = new Set<Confidence>(["high", "review"]);
const DATE_ASSIGNMENTS: ReadonlySet<string> = new Set<DateAssignment>(["same_line", "window"]);

function parseStringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const items: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") return null;
    items.push(entry);
  }
  return items;
}

function parseNullableString(value: unknown): string | null | undefined {
  if (value === null || typeof value === "string") return value;
  return undefined;
}

function parseRdoMatch(value: unknown): RdoMatch | null {
  if (!isRecord(value)) return null;
  const code = parseNullableString(value.code);
  const referenceName = parseNullableString(value.referenceName);
  const notes = parseStringArray(value.notes);
  if (typeof value.raw !== "string" || code === undefined || referenceName === undefined) {
    return null;
  }
  if (notes === null) return null;
  if (value.matchedBy !== "code" && value.matchedBy !== "name" && value.matchedBy !== "code+name") {
    return null;
  }
  if (typeof value.confidence !== "string" || !CONFIDENCES.has(value.confidence)) return null;
  return {
    raw: value.raw,
    code,
    referenceName,
    matchedBy: value.matchedBy,
    confidence: value.confidence as Confidence,
    notes,
  };
}

function parseExtensionRow(value: unknown): ExtensionRow | null {
  if (!isRecord(value)) return null;
  const formCodesDisplay = parseStringArray(value.formCodesDisplay);
  const formCodesCanonical = parseStringArray(value.formCodesCanonical);
  const notes = parseStringArray(value.notes);
  const originalDate = parseNullableString(value.originalDate);
  const extendedDate = parseNullableString(value.extendedDate);
  if (formCodesDisplay === null || formCodesCanonical === null || notes === null) return null;
  if (originalDate === undefined || extendedDate === undefined) return null;
  if (typeof value.rawDescription !== "string") return null;
  if (typeof value.channel !== "string" || !CHANNELS.has(value.channel)) return null;
  if (typeof value.confidence !== "string" || !CONFIDENCES.has(value.confidence)) return null;
  if (typeof value.dateAssignment !== "string" || !DATE_ASSIGNMENTS.has(value.dateAssignment)) {
    return null;
  }
  return {
    channel: value.channel as Channel,
    rawDescription: value.rawDescription,
    formCodesDisplay,
    formCodesCanonical,
    originalDate,
    extendedDate,
    dateAssignment: value.dateAssignment as DateAssignment,
    confidence: value.confidence as Confidence,
    notes,
  };
}

/**
 * Validates a persisted extraction structurally, field by field. Returns null
 * for anything that does not reconstruct exactly, which costs one re-extraction
 * and never publishes a half-parsed record.
 */
export function parseCircularExtraction(value: unknown): CircularExtraction | null {
  if (!isRecord(value)) return null;
  const externalId = value.externalId;
  const headerDateIssued = parseNullableString(value.headerDateIssued);
  const globalExtendedDate = parseNullableString(value.globalExtendedDate);
  const rdoCodes = parseStringArray(value.rdoCodes);
  const notes = parseStringArray(value.notes);
  if (typeof externalId !== "string" || externalId.length === 0) return null;
  if (headerDateIssued === undefined || globalExtendedDate === undefined) return null;
  if (rdoCodes === null || notes === null) return null;
  if (typeof value.needsManualReview !== "boolean") return null;
  if (value.statedOfficeCount !== null && !Number.isSafeInteger(value.statedOfficeCount)) {
    return null;
  }

  let window: CircularExtraction["window"] = null;
  if (value.window !== null) {
    if (!isRecord(value.window)) return null;
    if (typeof value.window.from !== "string" || typeof value.window.to !== "string") return null;
    window = { from: value.window.from, to: value.window.to };
  }

  if (!Array.isArray(value.rdos) || !Array.isArray(value.rows)) return null;
  const rdos: RdoMatch[] = [];
  for (const entry of value.rdos) {
    const rdo = parseRdoMatch(entry);
    if (rdo === null) return null;
    rdos.push(rdo);
  }
  const rows: ExtensionRow[] = [];
  for (const entry of value.rows) {
    const row = parseExtensionRow(entry);
    if (row === null) return null;
    rows.push(row);
  }

  return {
    externalId,
    headerDateIssued,
    globalExtendedDate,
    window,
    statedOfficeCount: value.statedOfficeCount as number | null,
    rdos,
    rdoCodes,
    rows,
    needsManualReview: value.needsManualReview,
    notes,
  };
}

function parseIssuance(value: unknown): SeenIssuance | null {
  if (!isRecord(value)) return null;
  const { pdfSha256, pdfBytes, pdfEtag, firstSeenAtUnix, extractedAtUnix, feedRev } = value;
  if (pdfSha256 !== null && typeof pdfSha256 !== "string") return null;
  if (typeof extractedAtUnix !== "number" || !Number.isFinite(extractedAtUnix)) return null;
  if (typeof feedRev !== "number" || !Number.isFinite(feedRev)) return null;
  // Both were added after the first published state files; a state file written
  // without them is still usable, it just cannot answer "unchanged" from a HEAD
  // request until the next download records them.
  const size =
    typeof pdfBytes === "number" && Number.isSafeInteger(pdfBytes) && pdfBytes > 0
      ? pdfBytes
      : null;
  const extraction =
    value.extraction === undefined || value.extraction === null
      ? null
      : parseCircularExtraction(value.extraction);
  // A state file written before firstSeenAtUnix existed still carries a usable
  // lower bound in extractedAtUnix; preferring it to dropping the entry keeps
  // the published timestamps of already-known issuances stable across upgrades.
  const firstSeen =
    typeof firstSeenAtUnix === "number" && Number.isFinite(firstSeenAtUnix)
      ? firstSeenAtUnix
      : extractedAtUnix;
  return {
    pdfSha256,
    pdfBytes: size,
    pdfEtag: typeof pdfEtag === "string" && pdfEtag.length > 0 ? pdfEtag : null,
    extraction,
    firstSeenAtUnix: firstSeen,
    extractedAtUnix,
    feedRev,
  };
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

/** Fixed field order, so an unchanged extraction re-serializes byte-identically. */
function serializableExtraction(extraction: CircularExtraction): unknown {
  return {
    externalId: extraction.externalId,
    headerDateIssued: extraction.headerDateIssued,
    globalExtendedDate: extraction.globalExtendedDate,
    window:
      extraction.window === null
        ? null
        : { from: extraction.window.from, to: extraction.window.to },
    statedOfficeCount: extraction.statedOfficeCount,
    rdos: extraction.rdos.map((rdo) => ({
      raw: rdo.raw,
      code: rdo.code,
      referenceName: rdo.referenceName,
      matchedBy: rdo.matchedBy,
      confidence: rdo.confidence,
      notes: [...rdo.notes],
    })),
    rdoCodes: [...extraction.rdoCodes],
    rows: extraction.rows.map((row) => ({
      channel: row.channel,
      rawDescription: row.rawDescription,
      formCodesDisplay: [...row.formCodesDisplay],
      formCodesCanonical: [...row.formCodesCanonical],
      originalDate: row.originalDate,
      extendedDate: row.extendedDate,
      dateAssignment: row.dateAssignment,
      confidence: row.confidence,
      notes: [...row.notes],
    })),
    needsManualReview: extraction.needsManualReview,
    notes: [...extraction.notes],
  };
}

/**
 * Serializes state with sorted keys, 2-space indent and a trailing newline.
 * `extraction` is written only for the issuances that have one — most entries
 * are notice-only, and a null blob on each would be pure noise in the diff.
 */
export function serializeState(state: SeenState): string {
  const issuances: Record<string, unknown> = {};
  for (const externalId of Object.keys(state.issuances).toSorted()) {
    const entry = state.issuances[externalId];
    if (entry === undefined) continue;
    issuances[externalId] = {
      pdfSha256: entry.pdfSha256,
      pdfBytes: entry.pdfBytes,
      ...(entry.pdfEtag === null ? {} : { pdfEtag: entry.pdfEtag }),
      firstSeenAtUnix: entry.firstSeenAtUnix,
      extractedAtUnix: entry.extractedAtUnix,
      feedRev: entry.feedRev,
      ...(entry.extraction === null
        ? {}
        : { extraction: serializableExtraction(entry.extraction) }),
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
 * True when state already records exactly this extraction result — same PDF
 * hash, same served size, same extraction. Re-recording it would only churn the
 * published state file; a difference in any of the three has to be written.
 */
export function isRecordedExtraction(
  state: SeenState,
  externalId: string,
  record: ExtractionRecord,
): boolean {
  const entry = state.issuances[externalId];
  if (entry === undefined) return false;
  if (!isAlreadyExtracted(state, externalId, record.pdfSha256)) return false;
  if (entry.pdfBytes !== record.pdfBytes) return false;
  if (entry.pdfEtag !== (record.pdfEtag ?? null)) return false;
  return isDeepStrictEqual(entry.extraction, record.extraction);
}

export type RecordedPdf = {
  pdfSha256: string;
  pdfBytes: number;
  /** Null when the origin served no strong ETag at extraction time. */
  pdfEtag: string | null;
  extraction: CircularExtraction;
};

/**
 * What a previous run recorded about an issuance's PDF, or null unless all
 * three parts are on file. All three are required before a run may skip a
 * download: without the size there is nothing to compare a HEAD answer
 * against, and without the extraction a skipped download would silently drop
 * that circular's overrides from the feed.
 */
export function recordedPdf(state: SeenState, externalId: string): RecordedPdf | null {
  const entry = state.issuances[externalId];
  if (entry === undefined) return null;
  const { pdfSha256, pdfBytes, pdfEtag, extraction } = entry;
  if (pdfSha256 === null || pdfBytes === null || extraction === null) return null;
  return { pdfSha256, pdfBytes, pdfEtag, extraction };
}

/**
 * Pure: returns new state with `externalId` recorded as extracted. An existing
 * `firstSeenAtUnix` is carried over — re-extraction does not make an issuance
 * new again.
 */
export function markExtracted(
  state: SeenState,
  externalId: string,
  record: ExtractionRecord,
  nowUnix: number,
  feedRev: number,
): SeenState {
  const firstSeenAtUnix = state.issuances[externalId]?.firstSeenAtUnix ?? nowUnix;
  return {
    issuances: {
      ...state.issuances,
      [externalId]: {
        pdfSha256: record.pdfSha256,
        pdfBytes: record.pdfBytes,
        pdfEtag: record.pdfEtag ?? null,
        extraction: record.extraction,
        firstSeenAtUnix,
        extractedAtUnix: nowUnix,
        feedRev,
      },
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
        pdfBytes: null,
        pdfEtag: null,
        extraction: null,
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
