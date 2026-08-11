// Parses BIR issuance lists out of the two CMS payload shapes:
//
//   template 9    content.Issuance -> homepage "New Issuances" widget (no dates)
//   template <yr> content.Content  -> yearly archive table (authoritative dates)
//
// There is one yearly archive per issuance kind (RMC/RMO/RR), all with the same
// three-column shape, so a single archive parser serves all of them; sync.ts
// concatenates their rows before merging with the widget.
//
// Both blobs are WYSIWYG rich text, so parsing is block-scoped rather than
// document-scoped: a subject line may itself cite another issuance
// ("...Pursuant to Revenue Regulations No. 004-2026."), and a document-wide
// regex sweep would mint a phantom record for the citation. Each block
// therefore contributes at most one record, taken from its FIRST kind+number
// match — which is the heading the CMS wraps in <strong>.

import { findAnchors, splitTableCells, splitTableRows, textOf } from "./html.ts";
import { normalizeDigits, parseNoisyDate } from "./ocr-normalize.ts";
import type { IssuanceKind, IssuanceRecord } from "./types.ts";

const KIND_BY_LABEL: ReadonlyMap<string, IssuanceKind> = new Map([
  ["revenue memorandum circular", "RMC"],
  ["rmc", "RMC"],
  ["revenue memorandum order", "RMO"],
  ["rmo", "RMO"],
  ["revenue regulation", "RR"],
  ["revenue regulations", "RR"],
  ["rr", "RR"],
  ["revenue delegation authority order", "RDAO"],
  ["rdao", "RDAO"],
  ["republic act", "RA"],
  ["ra", "RA"],
  ["bank bulletin", "BANK_BULLETIN"],
  ["bb", "BANK_BULLETIN"],
]);

// Longest labels first so "Revenue Memorandum Circular" wins over a bare "RMC"
// at the same offset. Digit lookalikes (l/I/O/…) are admitted in the number and
// normalized afterwards, because the archive column is CMS-typed but the widget
// text is frequently pasted out of OCR'd mail.
const HEADING_PATTERN = new RegExp(
  String.raw`\b(Revenue Delegation Authority Order|Revenue Memorandum Circular|` +
    String.raw`Revenue Memorandum Order|Revenue Regulations|Revenue Regulation|` +
    String.raw`Bank Bulletin|RDAO|RMC|RMO|RR|BB)\s*` +
    String.raw`No[.,]?\s*([0-9OlI]{1,3})\s*[-–—]\s*([0-9OlI]{4})\b`,
  "giu",
);

const BLOCK_PATTERN = /<p\b[^>]*>/giu;
const BLOCK_CLOSE_PATTERN = /<\/p\s*>/iu;
const ANCHOR_PATTERN = /<a\b[^>]*>[\s\S]*?<\/a\s*>/giu;
const FALLBACK_BLOCK_PATTERN = /<div\b[^>]*>/giu;
const FALLBACK_BLOCK_CLOSE_PATTERN = /<\/div\s*>/iu;

// Trailing link-list punctuation the CMS leaves behind once anchors are removed
// ("... Palace. |", "... Monsoon Digest |").
const TRAILING_LINK_NOISE = /(?:[\s|·]|&nbsp;|\bDigest\b)+$/iu;

const PDF_ANCHOR_LABELS: ReadonlySet<string> = new Set(["more", "full text"]);

/** First cell of an archive table's header row, whether it is `<th>` or `<td>`. */
const HEADER_CELL_LABEL = /^no\.?\s*of\s*issuance$/iu;

export type IssuanceParseWarning = {
  block: string;
  reason: string;
};

function pad3(value: string): string {
  return value.length >= 3 ? value : value.padStart(3, "0");
}

function sliceBlocks(html: string, open: RegExp, close: RegExp): string[] {
  const opens = [...html.matchAll(open)];
  const blocks: string[] = [];
  for (let index = 0; index < opens.length; index += 1) {
    const start = opens[index].index + opens[index][0].length;
    const next = opens[index + 1];
    const segment = html.slice(start, next === undefined ? html.length : next.index);
    const end = close.exec(segment);
    blocks.push(end === null ? segment : segment.slice(0, end.index));
  }
  return blocks;
}

/**
 * Splits the widget blob into one block per issuance. The CMS emits one
 * `<p class="MsoNormal">` per issuance; the `<div>` fallback only matters if
 * the editor's paragraph wrapper ever changes.
 */
export function splitIssuanceBlocks(html: string): string[] {
  const paragraphs = sliceBlocks(html, BLOCK_PATTERN, BLOCK_CLOSE_PATTERN);
  if (paragraphs.length > 0) return paragraphs;
  return sliceBlocks(html, FALLBACK_BLOCK_PATTERN, FALLBACK_BLOCK_CLOSE_PATTERN);
}

export type IssuanceHeading = {
  kind: IssuanceKind;
  /** Number as printed, after digit normalization: "089-2026", "89-2026". */
  number: string;
  year: string;
  /** Zero-padded to 3 for the external id: "089". */
  sequence: string;
  /** Offset just past the heading in the text it was matched in. */
  endIndex: number;
};

/**
 * Reads the FIRST issuance heading in `text`. Only the first match is
 * considered: later matches inside a subject are citations of other issuances,
 * not new records.
 */
export function parseHeading(text: string): IssuanceHeading | null {
  HEADING_PATTERN.lastIndex = 0;
  const match = HEADING_PATTERN.exec(text);
  if (match === null) return null;

  const kind = KIND_BY_LABEL.get(match[1].toLowerCase().replace(/\s+/gu, " ")) ?? "OTHER";
  const sequenceDigits = normalizeDigits(match[2]);
  const yearDigits = normalizeDigits(match[3]);
  if (!/^[0-9]{1,3}$/u.test(sequenceDigits) || !/^[0-9]{4}$/u.test(yearDigits)) return null;

  return {
    kind,
    number: `${sequenceDigits}-${yearDigits}`,
    year: yearDigits,
    sequence: pad3(sequenceDigits),
    endIndex: match.index + match[0].length,
  };
}

export function externalIdFor(kind: IssuanceKind, year: string, sequence: string): string {
  return `bir:${kind.toLowerCase()}:${year}:${pad3(sequence)}`;
}

/**
 * Absolutizes an href and percent-encodes the raw spaces the CMS stores
 * ("RMC No. 89-2026_redacted.pdf"). `URL` leaves already-encoded sequences
 * alone, so re-running this never double-encodes.
 */
export function normalizePdfUrl(href: string): string | null {
  const trimmed = href.trim();
  if (trimmed === "") return null;
  try {
    return new URL(trimmed, "https://www.bir.gov.ph").href;
  } catch {
    return null;
  }
}

function pickPdfUrl(html: string): string | null {
  const anchors = findAnchors(html);
  if (anchors.length === 0) return null;
  const labelled = anchors.find((anchor) =>
    PDF_ANCHOR_LABELS.has(anchor.text.trim().toLowerCase()),
  );
  return normalizePdfUrl((labelled ?? anchors[0]).href);
}

function stripAnchors(html: string): string {
  return html.replace(ANCHOR_PATTERN, " ");
}

function cleanSubject(text: string): string {
  return text.replace(TRAILING_LINK_NOISE, "").trim();
}

/**
 * Widget parser (template 9, `content.Issuance`). Blocks whose heading cannot
 * be recognized are reported through `warnings` rather than dropped silently.
 */
export function parseWidgetIssuances(
  issuanceHtml: string,
  firstSeenAtUnix: number,
  warnings?: IssuanceParseWarning[],
): IssuanceRecord[] {
  const records: IssuanceRecord[] = [];
  const seen = new Set<string>();

  for (const block of splitIssuanceBlocks(issuanceHtml)) {
    const bodyText = textOf(stripAnchors(block));
    if (bodyText === "") continue;

    const heading = parseHeading(bodyText);
    if (heading === null) {
      warnings?.push({ block: bodyText.slice(0, 160), reason: "no recognized issuance heading" });
      continue;
    }

    const externalId = externalIdFor(heading.kind, heading.year, heading.sequence);
    if (seen.has(externalId)) {
      warnings?.push({ block: bodyText.slice(0, 160), reason: `duplicate block for ${externalId}` });
      continue;
    }
    seen.add(externalId);

    records.push({
      externalId,
      kind: heading.kind,
      number: heading.number,
      subject: cleanSubject(bodyText.slice(heading.endIndex)),
      pdfUrl: pickPdfUrl(block),
      dateIssued: null,
      dateSource: "first_seen",
      source: "widget",
      firstSeenAtUnix,
    });
  }

  return records;
}

/**
 * Archive parser (yearly template, `content.Content`), shared by every kind's
 * archive. Columns are `NO. OF ISSUANCE | SUBJECT | DATE OF ISSUE`; the subject
 * cell ends with a `<br>`-separated link row ("Digest | Full Text | Annex A …")
 * that is not part of the subject.
 */
export function parseArchiveIssuances(
  tableHtml: string,
  firstSeenAtUnix: number,
  warnings?: IssuanceParseWarning[],
): IssuanceRecord[] {
  const records: IssuanceRecord[] = [];
  const seen = new Set<string>();

  for (const row of splitTableRows(tableHtml)) {
    if (/<th\b/iu.test(row)) continue;
    const cells = splitTableCells(row);
    if (cells.length < 3) {
      const preview = textOf(row).slice(0, 160);
      if (preview !== "") warnings?.push({ block: preview, reason: "row has fewer than 3 cells" });
      continue;
    }

    const numberText = textOf(cells[0]);
    // The RMO archive's header row is `<td>`-based, so the `<th>` test above
    // does not catch it; its label is not a parse failure worth reporting.
    if (HEADER_CELL_LABEL.test(numberText)) continue;
    const heading = parseHeading(numberText);
    if (heading === null) {
      warnings?.push({ block: numberText.slice(0, 160), reason: "unparsable issuance number" });
      continue;
    }

    const externalId = externalIdFor(heading.kind, heading.year, heading.sequence);
    if (seen.has(externalId)) {
      warnings?.push({ block: numberText.slice(0, 160), reason: `duplicate row for ${externalId}` });
      continue;
    }
    seen.add(externalId);

    const subjectCell = cells[1];
    const beforeLinkRow = subjectCell.split(/<br\b[^>]*>/iu)[0];
    const subjectSource = textOf(stripAnchors(beforeLinkRow)) === ""
      ? subjectCell
      : beforeLinkRow;
    const dateText = textOf(cells[2]);
    const parsedDate = dateText === "" ? null : parseNoisyDate(dateText);
    if (dateText !== "" && parsedDate === null) {
      warnings?.push({ block: dateText.slice(0, 160), reason: `unparsable DATE OF ISSUE for ${externalId}` });
    }

    records.push({
      externalId,
      kind: heading.kind,
      number: heading.number,
      subject: cleanSubject(textOf(stripAnchors(subjectSource))),
      pdfUrl: pickPdfUrl(subjectCell),
      dateIssued: parsedDate?.iso ?? null,
      dateSource: parsedDate === null ? "first_seen" : "archive",
      source: "archive",
      firstSeenAtUnix,
    });
  }

  return records;
}

function preferArchive<T extends string>(
  archive: T | null | undefined,
  widget: T | null | undefined,
): T | null {
  if (archive !== null && archive !== undefined && archive !== "") return archive;
  return widget ?? null;
}

function compareRecords(a: IssuanceRecord, b: IssuanceRecord): number {
  const left = a.dateIssued ?? "";
  const right = b.dateIssued ?? "";
  if (left !== right) return left < right ? 1 : -1;
  if (a.externalId !== b.externalId) return a.externalId < b.externalId ? 1 : -1;
  return 0;
}

/**
 * Unions both sources by `externalId`. The archive is authoritative wherever it
 * has a value (it carries DATE OF ISSUE and the copy-edited subject); the
 * widget fills the gaps and contributes issuances not yet in the archive.
 * Sorted newest-issued first, then by external id descending.
 */
export function mergeIssuances(
  widget: readonly IssuanceRecord[],
  archive: readonly IssuanceRecord[],
): IssuanceRecord[] {
  const merged = new Map<string, IssuanceRecord>();

  for (const record of widget) merged.set(record.externalId, { ...record });

  for (const record of archive) {
    const existing = merged.get(record.externalId);
    if (existing === undefined) {
      merged.set(record.externalId, { ...record });
      continue;
    }
    const dateIssued = preferArchive(record.dateIssued, existing.dateIssued);
    merged.set(record.externalId, {
      externalId: record.externalId,
      kind: record.kind === "OTHER" ? existing.kind : record.kind,
      number: preferArchive(record.number, existing.number) ?? existing.number,
      subject: preferArchive(record.subject, existing.subject) ?? existing.subject,
      pdfUrl: preferArchive(record.pdfUrl, existing.pdfUrl),
      dateIssued,
      // The provenance follows whichever record supplied the surviving date.
      dateSource:
        dateIssued === null
          ? "first_seen"
          : dateIssued === record.dateIssued
            ? record.dateSource
            : existing.dateSource,
      source: "merged",
      firstSeenAtUnix: Math.min(existing.firstSeenAtUnix, record.firstSeenAtUnix),
    });
  }

  return [...merged.values()].sort(compareRecords);
}

/**
 * Pulls the HTML blob out of one CMS dataset: `content.Issuance` for the
 * widget, `content.Content` for the yearly archive. Returns "" when the
 * dataset carries neither, so callers can report an empty source instead of
 * crashing on a CMS shape change.
 */
export function extractIssuanceHtml(dataset: unknown): string {
  if (typeof dataset !== "object" || dataset === null) return "";
  const content = (dataset as { content?: unknown }).content;
  if (typeof content !== "object" || content === null) return "";
  const fields = content as { Issuance?: unknown; Content?: unknown };
  if (typeof fields.Issuance === "string") return fields.Issuance;
  if (typeof fields.Content === "string") return fields.Content;
  return "";
}
