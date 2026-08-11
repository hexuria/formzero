// Revenue District Office extraction from an extension circular's layout text.
//
// The affected-offices table sits on page 1-2 of an RMC, above the deadline
// table, and its OCR text layer is the worst-damaged part of the document:
// `RDONo.T- Abra`, `RDO No. I 16`, `RDO No. l78 - North Tarlac`. Every code
// that leaves this module is checked against data/rdo-reference.json, so a
// code in `rdoCodes` is always a code the app can scope an override to.
//
// The office *names* printed by the circular are operational labels ("Regular
// LT Audit Division I") and routinely disagree with the app's reference names
// ("Bislig City"). A name conflict therefore downgrades confidence but never
// drops the office — dropping it would silently deny the extension to every
// filer registered there.

import { findRdoByCode, letteredVariants, normalizeRdoCode, rdoEntries } from "./rdo.ts";
import type { RdoMatch } from "./types.ts";

export type RdoExtraction = {
  rdos: RdoMatch[];
  rdoCodes: string[];
  statedOfficeCount: number | null;
};

// Same digit-lookalike alphabet ocr-normalize.ts repairs, so the capture is as
// tolerant as the normalizer that consumes it.
const DIGITISH = "0-9OolI|SBTZG";

/**
 * `RDO No. <code> - <name>` with every separator optional: the OCR loses the
 * space in `RDONo.3l`, turns the period into a hyphen in `RDO No- 34`, and
 * splits the number in `RDO No. I 16`.
 */
const RDO_PATTERN = new RegExp(
  String.raw`\bRDO\s*N[o0O]\s*[.,\-:]?\s*` +
    String.raw`([${DIGITISH}]{1,4}(?:\s+[${DIGITISH}]{1,3})?[A-Ca-c]?)` +
    String.raw`\s*[-–—:]?\s*([^\n]{0,60})`,
  "giu",
);

const TABLE_HEADER_PATTERN = /BIR\s+Forms?\s*\/?\s*Returns/iu;
const DUE_DATE_PATTERN = /Due\s+Date/iu;
const EXTENDED_PATTERN = /Extended/iu;

/** `RDO 037` — the reference's stand-in for an office it has no name for. */
const PLACEHOLDER_NAME_PATTERN = /^rdo\s*[0-9]{1,3}[a-c]?$/iu;

/**
 * A stated count of affected offices, e.g. `fifty-eight (58) Revenue District
 * Offices`. The gap is same-line and digit-free so that a code column entry
 * (`RDO No. 58 - West Batangas`) can never be read as a prose count.
 */
const OFFICE_COUNT_PATTERN = /\(?\b([0-9]{1,3})\b\)?[^\n0-9]{0,40}?Offices?\b/iu;

// Tokens too common across office names to carry any matching signal.
const GENERIC_NAME_TOKENS: ReadonlySet<string> = new Set(["city", "and", "of", "the", "rdo", "no"]);

/**
 * The text above the deadline table. Everything below it is form descriptions
 * and dates, where a stray `RDO` mention would be a false positive.
 */
export function scanRegion(layoutText: string): string {
  const lines = layoutText.split(/\r?\n/u);
  const headerIndex = lines.findIndex(
    (line) =>
      TABLE_HEADER_PATTERN.test(line) || (DUE_DATE_PATTERN.test(line) && EXTENDED_PATTERN.test(line)),
  );
  return (headerIndex === -1 ? lines : lines.slice(0, headerIndex)).join("\n");
}

/** Prose count of affected offices, for the caller's invariant check. */
export function parseStatedOfficeCount(text: string): number | null {
  const match = OFFICE_COUNT_PATTERN.exec(text);
  if (match === null) return null;
  const value = Number.parseInt(match[1] ?? "", 10);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function collapse(text: string): string {
  return text.replace(/\s+/gu, " ").trim();
}

function nameTokens(name: string): Set<string> {
  const tokens = name
    .toLowerCase()
    .split(/[^a-z]+/u)
    .filter((token) => token.length >= 2 && !GENERIC_NAME_TOKENS.has(token));
  return new Set(tokens);
}

function sharedTokenCount(a: Set<string>, b: Set<string>): number {
  let shared = 0;
  for (const token of a) if (b.has(token)) shared += 1;
  return shared;
}

/**
 * Code spellings to try, best first. A trailing `B` is the one branch letter
 * with a digit lookalike (`B -> 8`), so `l78` normalizes to `178` but may
 * really be `17B`; both are offered and the reference decides.
 */
function candidateCodes(rawCode: string): string[] {
  const primary = normalizeRdoCode(rawCode);
  if (primary === null) return [];

  const candidates = [primary];
  const trailingEight = /^([0-9]{2})8$/u.exec(primary);
  if (trailingEight !== null && trailingEight[1] !== "00") {
    candidates.push(`${trailingEight[1]}B`);
  }
  return candidates;
}

/** Unique best-scoring reference entry for a captured office name, if any. */
function matchByName(tokens: Set<string>): { code: string; name: string } | null {
  if (tokens.size === 0) return null;

  let best: { code: string; name: string } | null = null;
  let bestScore = 0;
  let bestCount = 0;

  for (const entry of rdoEntries()) {
    const score = sharedTokenCount(tokens, nameTokens(entry.name));
    if (score === 0) continue;
    if (score > bestScore) {
      best = entry;
      bestScore = score;
      bestCount = 1;
    } else if (score === bestScore) {
      bestCount += 1;
    }
  }

  return bestScore > 0 && bestCount === 1 ? best : null;
}

type Resolution = Pick<RdoMatch, "code" | "referenceName" | "matchedBy" | "confidence">;

function resolve(rawCode: string, capturedName: string, notes: string[]): Resolution {
  const tokens = nameTokens(capturedName);
  const candidates = candidateCodes(rawCode);

  let fallback: { code: string; name: string } | null = null;

  for (const candidate of candidates) {
    const entry = findRdoByCode(candidate);
    if (entry === null) continue;

    const placeholder = PLACEHOLDER_NAME_PATTERN.test(entry.name);
    const shared = sharedTokenCount(tokens, nameTokens(entry.name));
    if (placeholder || shared > 0) {
      if (candidate !== candidates[0]) {
        notes.push(`read trailing "8" as branch letter "B": ${candidates[0]} -> ${candidate}`);
      }
      if (placeholder && shared === 0) {
        notes.push(`reference name "${entry.name}" is a placeholder; accepted on code alone`);
      }
      return {
        code: entry.code,
        referenceName: entry.name,
        matchedBy: "code+name",
        confidence: "high",
      };
    }
    fallback ??= entry;
  }

  if (fallback !== null) {
    notes.push(
      `reference name "${fallback.name}" does not overlap the printed name "${capturedName}"; kept on code match`,
    );
    return {
      code: fallback.code,
      referenceName: fallback.name,
      matchedBy: "code",
      confidence: "review",
    };
  }

  const byName = matchByName(tokens);
  if (byName !== null) {
    notes.push(
      `code "${candidates[0] ?? rawCode}" is not in the reference; resolved to ${byName.code} by unique name match`,
    );
    return {
      code: byName.code,
      referenceName: byName.name,
      matchedBy: "name",
      confidence: "review",
    };
  }

  notes.push(
    candidates.length === 0
      ? `could not read "${collapse(rawCode)}" as an RDO code`
      : `code "${candidates[0]}" is not in the reference and the name did not match uniquely`,
  );
  return { code: null, referenceName: null, matchedBy: "code", confidence: "review" };
}

/**
 * Extracts every affected Revenue District Office named above the deadline
 * table. `rdoCodes` is the sorted, deduped set of reference-valid codes,
 * widened by the lettered-variant rule so an override scoped to a parent
 * office also reaches profiles stored under its branch codes.
 */
export function extractRdos(layoutText: string): RdoExtraction {
  const region = scanRegion(layoutText);
  const rdos: RdoMatch[] = [];
  const codes = new Set<string>();

  for (const match of region.matchAll(RDO_PATTERN)) {
    const rawCode = match[1] ?? "";
    const capturedName = collapse(match[2] ?? "");
    const notes: string[] = [];
    const resolved = resolve(rawCode, capturedName, notes);

    if (resolved.code !== null) {
      codes.add(resolved.code);
      const variants = letteredVariants(resolved.code);
      if (variants.length > 0) {
        for (const variant of variants) codes.add(variant);
        notes.push(`expanded ${resolved.code} to lettered variants ${variants.join(", ")}`);
      }
    }

    rdos.push({
      raw: collapse(match[0]),
      code: resolved.code,
      referenceName: resolved.referenceName,
      matchedBy: resolved.matchedBy,
      confidence: resolved.confidence,
      notes,
    });
  }

  return {
    rdos,
    rdoCodes: [...codes].toSorted(),
    statedOfficeCount: parseStatedOfficeCount(region),
  };
}
