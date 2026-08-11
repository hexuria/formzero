// Deadline-table extraction from the `pdftotext -layout` rendering of a BIR
// extension circular (plan section 5.6).
//
// The table is a bordered three-column grid, but `-layout` gives us only
// characters on a grid: column identity survives as horizontal position, row
// identity does not. Two facts drive the whole design:
//
//   1. A printed date pair is recognisable purely by *column geometry* — a
//      parseable date sitting under the "Due Date" header and another under
//      "Extended Due Date". The header line supplies both column offsets.
//   2. Row identity does not survive. Blank lines separate description blocks
//      inside a single bordered row just as often as they separate rows, and
//      OCR'd receiving stamps inject noise lines mid-row. So v1 never lends a
//      date pair to a neighbouring block: a block either prints its own pair
//      on its own lines (`same_line`) or it is recorded against the circular's
//      global window (`window`) for the review report. Merged-cell recovery is
//      the documented v2 `pdftotext -tsv` upgrade.

import { canonicalFormCode } from "./form-codes.ts";
import { normalizeDigits, ocrTolerantPhrase, parseNoisyDate } from "./ocr-normalize.ts";
import type { Channel, Confidence, DateAssignment, ExtensionRow } from "./types.ts";

export type CircularAnchors = {
  globalExtendedDate: string | null;
  window: { from: string; to: string } | null;
};

export type ColumnGeometry = {
  dueColumn: number;
  extendedColumn: number;
};

export type DateCandidate = {
  /** Character column where the date literal starts. */
  column: number;
  text: string;
  /** ISO date, or null when the literal is too OCR-damaged to trust. */
  iso: string | null;
  notes: string[];
};

export type DeadlineBlock = {
  /** 0-based inclusive line range in the source text. */
  startLine: number;
  endLine: number;
  channelSeed: string;
  description: string;
  lines: readonly string[];
};

/** How far from the header label a date may start and still count as in-column. */
const COLUMN_TOLERANCE = 10;

/** Characters a digit can be OCR'd as; mirrors `ocr-normalize`'s table. */
const DIGITISH = "0-9OolI|SBTZG";

/**
 * Start of a possible date literal: a word-ish token followed by a digit-ish
 * token. Deliberately looser than the parser so that OCR wreckage such as
 * `Angttst 1'? ,2026` is still *located* (and reported as unparseable) rather
 * than silently vanishing from its column.
 */
const DATE_CANDIDATE_PATTERN = new RegExp(
  String.raw`[A-Za-z][A-Za-z\[\]().,]{2,13}\s{1,3}[${DIGITISH}]`,
  "gu",
);

/** Longest slice of a line a single date literal can occupy. */
const DATE_SLICE_LENGTH = 34;

const HEADER_LINE_PATTERN = /BIR\s*Forms?\s*\/?\s*Returns?/iu;

/**
 * The two column labels, tolerant of one OCR-destroyed letter per word — the
 * whole table hangs off finding them, and RMC 62-2026 prints them as
 * `I)ue Date` and `E:rtended Due Date`. Without the tolerance the header is
 * never located, no column geometry is derived, and the circular yields no
 * rows at all.
 */
export const DUE_DATE_LABEL = new RegExp(ocrTolerantPhrase("Due Date"), "iu");
export const EXTENDED_DUE_DATE_LABEL = new RegExp(
  ocrTolerantPhrase("Extended Due Date"),
  "iu",
);

/**
 * The circular's closing prose. Only consulted after the last printed date
 * pair, so the "This Circular shall extend…" lead-in above the table cannot
 * end the region early.
 */
const SIGNATURE_PATTERN = /this\s+Circular|Digest|Sgd|Commissioner/iu;

/** `e-FILING`, tolerating the OCR spellings `e-FlLlNG`, `e-FILINC`, `eFILING`. */
const EFILING_HEADER = /^e[-\s]?F[Il1][LC][Il1]N[GC]\b/iu;
const SUBMISSION_HEADER = /^e?[-\s]?SUBMISSION\b/iu;
const REGISTRATION_HEADER = /^REGISTRATION\b/iu;
const EPAYMENT_HEADER = /^e[-\s]?PAYMENT\b/iu;

/** `(Online,Manual)`, `(Online[vlanual)`, `(Online/I4anual)`, `(Online/Manual)`. */
const ONLINE_MANUAL = /online/iu;
const MANUAL_TAIL = /anual/iu;

/** A parenthetical that belongs to the channel header line above it. */
const HEADER_CONTINUATION = /^\(?\s*(?:online|manual)/iu;

const NON_EFPS = /non-?\s?eFPS/giu;
const EFPS = /eFPS/iu;
const EFPS_GROUP =
  /eFPS\s+Filers?\s+under\s+Group\s+([A-E](?:\s*[,&]\s*[A-E])*)/iu;

/**
 * A form code as printed: four digit-ish characters (OCR may inject single
 * spaces, `06 1 9-F`) plus an optional letter suffix, itself optionally the
 * head of a slash list (`1702 - RT/EX/MX`).
 */
const FORM_CODE_PATTERN = new RegExp(
  String.raw`\b[${DIGITISH}](?:\s?[${DIGITISH}]){3}` +
    String.raw`(?:\s{0,2}-\s{0,2}|\s)?([A-Z]{1,3}|\d[A-Z]?)?\b`,
  "gu",
);
const SUFFIX_LIST = /^(?:\/[A-Z]{1,3})+/u;

const WINDOW_PROSE = /fall(?:ing|s)?\b/giu;
const UNTIL_PROSE = /\buntil\b/giu;
/** Enough text after the anchor word to hold two dates plus stamp noise. */
const WINDOW_LOOKAHEAD = 140;
const UNTIL_LOOKAHEAD = 40;

function collapse(text: string): string {
  return text.replace(/\s+/gu, " ").trim();
}

/**
 * Locates every date literal in `text`, keeping the column it starts at.
 * Candidates that fail the strict parser are kept with `iso: null` so callers
 * can tell "nothing printed here" (merged cell) apart from "printed but
 * unreadable" (the damaged-extended fallback).
 */
export function scanDateCandidates(text: string): DateCandidate[] {
  const candidates: DateCandidate[] = [];
  let searchFrom = 0;

  DATE_CANDIDATE_PATTERN.lastIndex = 0;
  for (const match of text.matchAll(DATE_CANDIDATE_PATTERN)) {
    const column = match.index;
    if (column < searchFrom) continue;

    const slice = text.slice(column, column + DATE_SLICE_LENGTH);
    const parsed = parseNoisyDate(slice);
    candidates.push({
      column,
      text: collapse(slice),
      iso: parsed?.iso ?? null,
      notes: parsed?.notes ?? [],
    });
    // A literal consumes its own text; do not re-report its tail as a second
    // candidate (`August 10,2026to August 16` must stay two, not four).
    searchFrom = parsed === null ? column + match[0].length : column + 8;
  }
  return candidates;
}

function candidateAt(
  candidates: readonly DateCandidate[],
  column: number,
): DateCandidate | null {
  let best: DateCandidate | null = null;
  for (const candidate of candidates) {
    const distance = Math.abs(candidate.column - column);
    if (distance > COLUMN_TOLERANCE) continue;
    if (best === null || distance < Math.abs(best.column - column)) best = candidate;
  }
  return best;
}

/**
 * Reads the two circular-level date anchors out of the body prose:
 * the blanket extended date (`…until Aueust 17. 2026`) and the stated window
 * of affected deadlines (`Deadlines falling fiom August 10,2026to August
 * 16,2026`).
 */
export function parseCircularAnchors(layoutText: string): CircularAnchors {
  return {
    globalExtendedDate: parseUntilAnchor(layoutText),
    window: parseWindowAnchor(layoutText),
  };
}

/**
 * The issuance heading on page 1 (`REVENUE MEMORANDUM CIRCULAR NO. 089-2026`),
 * which the issue date is always printed above.
 */
const ISSUANCE_HEADING_LINE =
  /^[^\S\n]*REVENUE\s+(?:MEMORANDUM\s+\w+|REGULATIONS?|DELEGATION\b)/imu;

/**
 * The date printed in the letterhead on page 1, above the issuance heading —
 * the second date tier of plan §T3.1, used when the yearly archive has no row
 * for this issuance yet. Returns null when page 1 prints no readable date, so
 * the caller falls back to first sighting rather than to a guess.
 */
export function parseIssueDateAnchor(layoutText: string): string | null {
  const firstPage = layoutText.split("\f")[0];
  const heading = ISSUANCE_HEADING_LINE.exec(firstPage);
  const letterhead = heading === null ? firstPage : firstPage.slice(0, heading.index);
  const dates = scanDateCandidates(letterhead)
    .map((candidate) => candidate.iso)
    .filter((iso): iso is string => iso !== null);
  return dates.length === 0 ? null : dates[dates.length - 1];
}

function parseUntilAnchor(layoutText: string): string | null {
  UNTIL_PROSE.lastIndex = 0;
  for (const match of layoutText.matchAll(UNTIL_PROSE)) {
    const after = layoutText.slice(
      match.index + match[0].length,
      match.index + match[0].length + UNTIL_LOOKAHEAD,
    );
    const parsed = parseNoisyDate(collapse(after));
    if (parsed !== null) return parsed.iso;
  }
  return null;
}

function parseWindowAnchor(layoutText: string): { from: string; to: string } | null {
  WINDOW_PROSE.lastIndex = 0;
  for (const match of layoutText.matchAll(WINDOW_PROSE)) {
    const after = collapse(
      layoutText.slice(
        match.index + match[0].length,
        match.index + match[0].length + WINDOW_LOOKAHEAD,
      ),
    );
    const dates = scanDateCandidates(after)
      .map((candidate) => candidate.iso)
      .filter((iso): iso is string => iso !== null);
    if (dates.length < 2) continue;
    const [from, to] = dates;
    if (from > to) continue;
    return { from, to };
  }
  return null;
}

/** Character columns of the "Due Date" / "Extended Due Date" headers. */
export function columnGeometry(headerLine: string): ColumnGeometry | null {
  const extendedColumn = headerLine.search(EXTENDED_DUE_DATE_LABEL);
  if (extendedColumn < 0) return null;
  const dueColumn = headerLine.slice(0, extendedColumn).search(DUE_DATE_LABEL);
  if (dueColumn < 0) return null;
  return { dueColumn, extendedColumn };
}

function findHeaderLine(lines: readonly string[]): number {
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!HEADER_LINE_PATTERN.test(line)) continue;
    if (columnGeometry(line) !== null) return index;
  }
  return -1;
}

function isChannelHeader(leftText: string): boolean {
  return (
    EFILING_HEADER.test(leftText) ||
    SUBMISSION_HEADER.test(leftText) ||
    REGISTRATION_HEADER.test(leftText) ||
    EPAYMENT_HEADER.test(leftText)
  );
}

/** The part of a line left of whichever date column it prints into. */
function leftColumnText(line: string, geometry: ColumnGeometry): string {
  const candidates = scanDateCandidates(line);
  let cut = line.length;
  for (const candidate of candidates) {
    const inDue = Math.abs(candidate.column - geometry.dueColumn) <= COLUMN_TOLERANCE;
    const inExtended =
      Math.abs(candidate.column - geometry.extendedColumn) <= COLUMN_TOLERANCE;
    if ((inDue || inExtended) && candidate.column < cut) cut = candidate.column;
  }
  return line.slice(0, cut).trimEnd();
}

/**
 * Splits the table region into description blocks: contiguous non-blank lines,
 * with a channel-header line always starting a fresh block. The channel seed
 * set by a header carries forward to the following blocks until the next
 * header, because the CMS prints the header once per group of rows and blank
 * lines separate the rows inside that group.
 */
export function splitBlocks(
  lines: readonly string[],
  geometry: ColumnGeometry,
  startLine: number,
  endLine: number,
): DeadlineBlock[] {
  const blocks: DeadlineBlock[] = [];
  let seed = "";
  let current: {
    startLine: number;
    lines: string[];
    seed: string;
    descriptionLines: string[];
  } | null = null;

  const flush = (endIndex: number): void => {
    if (current === null) return;
    const description = collapse(current.descriptionLines.join(" "));
    if (description !== "") {
      blocks.push({
        startLine: current.startLine,
        endLine: endIndex,
        channelSeed: current.seed,
        description,
        lines: current.lines,
      });
    }
    current = null;
  };

  for (let index = startLine; index <= endLine; index += 1) {
    const line = lines[index];
    if (line.trim() === "") {
      flush(index - 1);
      continue;
    }

    const leftText = leftColumnText(line, geometry).trim();
    if (isChannelHeader(leftText)) {
      flush(index - 1);
      seed = leftText;
      current = { startLine: index, lines: [line], seed, descriptionLines: [] };
      continue;
    }

    if (current === null) {
      current = { startLine: index, lines: [line], seed, descriptionLines: [leftText] };
      continue;
    }

    current.lines.push(line);
    // A parenthetical directly under a header ("(Online,Manual)") qualifies the
    // header rather than describing a return.
    const isContinuation =
      current.descriptionLines.length === 0 && HEADER_CONTINUATION.test(leftText);
    if (isContinuation) {
      current.seed = `${current.seed} ${leftText}`;
      seed = current.seed;
    } else {
      current.descriptionLines.push(leftText);
    }
  }
  flush(endLine);
  return blocks;
}

/** Plan 5.6 step 3, in the documented precedence order. */
export function classifyChannel(seed: string, description: string): Channel {
  const withoutNonEfps = description.replace(NON_EFPS, " ");
  const mentionsNonEfps = withoutNonEfps !== description;
  const mentionsEfps = EFPS.test(withoutNonEfps);

  if (mentionsNonEfps && mentionsEfps) return "efps_and_nonefps";

  const group = EFPS_GROUP.exec(description);
  if (group !== null) {
    const letters = group[1].toUpperCase().replace(/[^A-E]/gu, "");
    if (letters.length > 1) return "efps_group_multi";
    switch (letters) {
      case "A":
        return "efps_group_a";
      case "B":
        return "efps_group_b";
      case "C":
        return "efps_group_c";
      case "D":
        return "efps_group_d";
      case "E":
        return "efps_group_e";
      default:
        break;
    }
  }

  if (mentionsNonEfps) return "nonefps";
  if (REGISTRATION_HEADER.test(seed)) return "registration";
  if (SUBMISSION_HEADER.test(seed)) return "submission";
  if (ONLINE_MANUAL.test(seed) && MANUAL_TAIL.test(seed)) return "nonefps";
  return "unknown";
}

export type HarvestedFormCodes = {
  display: string[];
  canonical: string[];
};

/**
 * Harvests printed form codes from a block. Digit normalization runs per token
 * (never over whole prose), and only catalog-known codes survive — which is
 * what keeps years, receiving-stamp numbers and OCR debris out of the result.
 */
export function harvestFormCodes(description: string): HarvestedFormCodes {
  const display: string[] = [];
  const canonical: string[] = [];
  const seen = new Set<string>();

  // The catalog spells some codes hyphenated (`1601-C`) and some joined
  // (`1701Q`); prefer whichever the document printed, then accept the other.
  const push = (base: string, suffix: string | null, hyphenated: boolean): void => {
    const spellings =
      suffix === null
        ? [base]
        : hyphenated
          ? [`${base}-${suffix}`, `${base}${suffix}`]
          : [`${base}${suffix}`, `${base}-${suffix}`];
    for (const printed of spellings) {
      const code = canonicalFormCode(printed);
      if (code === null) continue;
      if (seen.has(code)) return;
      seen.add(code);
      display.push(printed);
      canonical.push(code);
      return;
    }
  };

  FORM_CODE_PATTERN.lastIndex = 0;
  for (const match of description.matchAll(FORM_CODE_PATTERN)) {
    const suffix = match[1] ?? null;
    const printedBase =
      suffix === null ? match[0] : match[0].slice(0, match[0].length - suffix.length);
    const hyphenated = printedBase.includes("-");
    // `06 1 9-F` — digit normalization runs on the token, never on the prose.
    const base = normalizeDigits(printedBase.replace(/[-\s]+$/u, ""));
    if (!/^[0-9]{4}$/u.test(base)) continue;

    push(base, suffix, hyphenated);
    if (suffix === null) continue;

    // `1702 - RT/EX/MX` — the slash list continues right after the match.
    const tail = description.slice(match.index + match[0].length);
    const list = SUFFIX_LIST.exec(tail);
    if (list === null) continue;
    for (const extra of list[0].split("/")) {
      if (extra !== "") push(base, extra, hyphenated);
    }
  }

  return { display, canonical };
}

type DatePair = {
  originalDate: string;
  extendedDate: string | null;
  notes: string[];
  confidence: Confidence;
};

function datePairOnLine(
  line: string,
  geometry: ColumnGeometry,
  anchors: CircularAnchors,
): DatePair | null {
  const candidates = scanDateCandidates(line);
  const due = candidateAt(candidates, geometry.dueColumn);
  if (due === null || due.iso === null) return null;

  const extended = candidateAt(candidates, geometry.extendedColumn);

  // An empty Extended column is a merged cell, not a damaged one, and §5.6.5
  // forbids reconstructing merged cells in v1. It also stops a single literal
  // sitting between two close-set header labels from being read as a whole
  // row: RMC 62-2026's labels are 17 characters apart, so their ±10 windows
  // overlap, and its later pages shift the printed columns out from under the
  // page-1 header entirely. Either way the row belongs in the review report.
  if (extended === null || extended === due) return null;

  const notes = [...due.notes];

  if (extended.iso === null) {
    notes.push(
      `Extended Due Date column unreadable (${extended.text}); ` +
        `used the circular's global extended date ${anchors.globalExtendedDate ?? "(none)"}`,
    );
    return {
      originalDate: due.iso,
      extendedDate: anchors.globalExtendedDate,
      notes,
      confidence: "high",
    };
  }

  notes.push(...extended.notes);
  const disagrees =
    anchors.globalExtendedDate !== null && extended.iso !== anchors.globalExtendedDate;
  if (disagrees) {
    notes.push(
      `Printed extended date ${extended.iso} differs from the circular's ` +
        `global extended date ${anchors.globalExtendedDate}; kept as printed`,
    );
  }
  return {
    originalDate: due.iso,
    extendedDate: extended.iso,
    notes,
    confidence: disagrees ? "review" : "high",
  };
}

/**
 * Extracts one `ExtensionRow` per description block of the deadline table.
 * `anchors` must come from `parseCircularAnchors` on the same text.
 */
export function extractDeadlineRows(
  layoutText: string,
  anchors: CircularAnchors,
): ExtensionRow[] {
  const lines = layoutText.split("\n");
  const headerIndex = findHeaderLine(lines);
  if (headerIndex < 0) return [];
  const geometry = columnGeometry(lines[headerIndex]);
  if (geometry === null) return [];

  const blocks = splitBlocks(lines, geometry, headerIndex + 1, lines.length - 1);
  const tableBlocks = trimToSignature(blocks, lines, geometry, anchors);

  return tableBlocks.map((block) => toRow(block, geometry, anchors));
}

/** Drops the closing prose and signature block that follow the last date pair. */
function trimToSignature(
  blocks: readonly DeadlineBlock[],
  lines: readonly string[],
  geometry: ColumnGeometry,
  anchors: CircularAnchors,
): DeadlineBlock[] {
  let lastPairLine = -1;
  for (let index = 0; index < lines.length; index += 1) {
    if (datePairOnLine(lines[index], geometry, anchors) !== null) lastPairLine = index;
  }
  const kept: DeadlineBlock[] = [];
  for (const block of blocks) {
    if (block.startLine > lastPairLine && SIGNATURE_PATTERN.test(block.description)) break;
    kept.push(block);
  }
  return kept;
}

function toRow(
  block: DeadlineBlock,
  geometry: ColumnGeometry,
  anchors: CircularAnchors,
): ExtensionRow {
  const channel = classifyChannel(block.channelSeed, block.description);
  const forms = harvestFormCodes(block.description);
  const notes: string[] = [];
  if (block.channelSeed !== "") notes.push(`Channel header: "${block.channelSeed}"`);

  let pair: DatePair | null = null;
  for (const line of block.lines) {
    pair = datePairOnLine(line, geometry, anchors);
    if (pair !== null) break;
  }

  const statedRange = statedRangeOf(block.description);
  if (statedRange !== null) {
    notes.push(`Block states its own deadline range ${statedRange.from} to ${statedRange.to}`);
  }

  let dateAssignment: DateAssignment;
  let originalDate: string | null;
  let extendedDate: string | null;
  let confidence: Confidence;

  if (pair !== null) {
    dateAssignment = "same_line";
    originalDate = pair.originalDate;
    extendedDate = pair.extendedDate;
    confidence = pair.confidence;
    notes.push(...pair.notes);
  } else {
    dateAssignment = "window";
    originalDate = null;
    extendedDate = anchors.globalExtendedDate;
    confidence = "review";
    notes.push(
      "No date pair printed on this block's lines; recorded against the " +
        "circular window (no override emitted)",
    );
  }

  return {
    channel,
    rawDescription: block.description,
    formCodesDisplay: forms.display,
    formCodesCanonical: forms.canonical,
    originalDate,
    extendedDate,
    dateAssignment,
    confidence,
    notes,
  };
}

/** `Deadlines falling from August 10, 2026 to August 16, 2026` inside a block. */
function statedRangeOf(description: string): { from: string; to: string } | null {
  WINDOW_PROSE.lastIndex = 0;
  for (const match of description.matchAll(WINDOW_PROSE)) {
    const after = description.slice(
      match.index + match[0].length,
      match.index + match[0].length + WINDOW_LOOKAHEAD,
    );
    const dates = scanDateCandidates(after)
      .map((candidate) => candidate.iso)
      .filter((iso): iso is string => iso !== null);
    if (dates.length >= 2 && dates[0] <= dates[1]) {
      return { from: dates[0], to: dates[1] };
    }
  }
  return null;
}
