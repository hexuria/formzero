// Per-circular review report writer (execution plan §4.3).
//
// The extractor is deterministic and deliberately refuses to guess, which only
// works as a trust model if a human can see what it refused. This module turns
// one CircularExtraction plus the compiler's emission decisions into a Markdown
// document: what was published, what was held back, and the printed evidence
// beside each call. Output depends only on its inputs — no clocks, no I/O — so
// an unchanged run regenerates byte-identical reports.

import path from "node:path";

import { rowDropReason } from "./feed.ts";
import type { DropRecord } from "./feed.ts";
import type {
  CircularExtraction,
  DateSource,
  ExtensionRow,
  FeedOverride,
  IssuanceRecord,
  RdoMatch,
} from "./types.ts";

/** How each date tier reads in the report; first-seen is called out as invented. */
const DATE_SOURCE_LABELS: Readonly<Record<DateSource, string>> = Object.freeze({
  archive: "yearly archive `DATE OF ISSUE`",
  pdf_header: "PDF page-1 letterhead date",
  first_seen:
    "**first-seen fallback** — no archive row and no readable PDF header date, so the " +
    "published date is this pipeline's first sighting, not BIR's issue date",
});

export type ReviewReportInput = {
  issuance: IssuanceRecord;
  extraction: CircularExtraction;
  emitted: FeedOverride[];
  dropped: DropRecord[];
};

/** `review/bir-rmc-2026-089.md` for `bir:rmc:2026:089`. */
export function reviewReportPath(reviewDir: string, externalId: string): string {
  return path.join(reviewDir, `${externalId.replaceAll(":", "-")}.md`);
}

function escapeCell(text: string): string {
  return text.replace(/\s+/gu, " ").replaceAll("|", "\\|").trim();
}

function orDash(text: string | null): string {
  return text === null || text.length === 0 ? "—" : text;
}

function formsOf(row: ExtensionRow): string {
  if (row.formCodesCanonical.length > 0) return row.formCodesCanonical.join(", ");
  if (row.formCodesDisplay.length > 0) return `${row.formCodesDisplay.join(", ")} (non-catalog)`;
  return "—";
}

function abbreviate(text: string, limit: number): string {
  const collapsed = text.replace(/\s+/gu, " ").trim();
  return collapsed.length > limit ? `${collapsed.slice(0, limit - 1)}…` : collapsed;
}

function bulletList(items: readonly string[], emptyText: string): string[] {
  if (items.length === 0) return [`_${emptyText}_`];
  return items.map((item) => `- ${escapeCell(item)}`);
}

/** True when the block prints its own date pair, i.e. it can anchor a neighbour. */
function hasPrintedPair(row: ExtensionRow): boolean {
  return (
    row.dateAssignment === "same_line" && row.originalDate !== null && row.extendedDate !== null
  );
}

function describePair(rows: readonly ExtensionRow[], index: number): string {
  const row = rows[index];
  return (
    `row ${index + 1} — ${orDash(row.originalDate)} → ${orDash(row.extendedDate)} ` +
    `(${row.channel})`
  );
}

function nearestPrintedPair(
  rows: readonly ExtensionRow[],
  index: number,
  direction: -1 | 1,
): string {
  for (let cursor = index + direction; cursor >= 0 && cursor < rows.length; cursor += direction) {
    if (hasPrintedPair(rows[cursor])) return describePair(rows, cursor);
  }
  return "none";
}

function rdoTable(rdos: readonly RdoMatch[]): string[] {
  if (rdos.length === 0) return ["_No RDO references were matched in this circular._"];

  const lines = [
    "| Raw text | Code | Matched by | Confidence |",
    "| --- | --- | --- | --- |",
  ];
  for (const rdo of rdos) {
    lines.push(
      `| ${escapeCell(rdo.raw)} | ${orDash(rdo.code)} | ${rdo.matchedBy} | ${rdo.confidence} |`,
    );
  }
  return lines;
}

function rowTable(rows: readonly ExtensionRow[]): string[] {
  if (rows.length === 0) return ["_No deadline-table blocks were extracted._"];

  const lines = [
    "| # | Channel | Forms | Original | Extended | Assignment | Confidence |",
    "| --- | --- | --- | --- | --- | --- | --- |",
  ];
  rows.forEach((row, index) => {
    lines.push(
      `| ${index + 1} | ${row.channel} | ${escapeCell(formsOf(row))} | ` +
        `${orDash(row.originalDate)} | ${orDash(row.extendedDate)} | ${row.dateAssignment} | ` +
        `${row.confidence} |`,
    );
  });
  return lines;
}

function overrideSections(overrides: readonly FeedOverride[]): string[] {
  if (overrides.length === 0) {
    return ["_No override records were emitted for this circular._"];
  }

  const lines = [
    "| External ref | Original | Adjusted | Channel | Form codes | RDO codes |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const override of overrides) {
    lines.push(
      `| \`${override.external_ref}\` | ${override.original_deadline} | ` +
        `${override.adjusted_deadline} | ${override.channel} | ` +
        `${override.form_codes.join(", ")} | ${override.rdo_codes.length} |`,
    );
  }

  for (const override of overrides) {
    lines.push("");
    lines.push(`RDO scope for \`${override.external_ref}\` (${override.rdo_codes.length} codes):`);
    lines.push("");
    lines.push("```");
    for (let start = 0; start < override.rdo_codes.length; start += 10) {
      lines.push(override.rdo_codes.slice(start, start + 10).join(" "));
    }
    lines.push("```");
  }
  return lines;
}

/**
 * Renders the human checkpoint for one extracted circular: verdict, invariant,
 * every RDO match, every table block, what was emitted, and — the point of the
 * document — everything that was not, with the printed dates nearest to it.
 */
export function renderReviewReport(input: ReviewReportInput): string {
  const { issuance, extraction } = input;
  const emitted = input.emitted.filter(
    (override) => override.notice_external_id === extraction.externalId,
  );
  const rows = extraction.rows;
  const sourceReference = `${issuance.kind} No. ${issuance.number}`;

  const matchedCodes = new Set(
    extraction.rdos.map((rdo) => rdo.code).filter((code): code is string => code !== null),
  );
  const statedCount = extraction.statedOfficeCount;
  const invariantVerdict =
    statedCount === null
      ? "not stated in the prose — nothing to compare"
      : statedCount === matchedCodes.size
        ? "MATCH"
        : `MISMATCH — the prose states ${statedCount}, the extractor found ${matchedCodes.size}`;

  const hasRdoScope = extraction.rdoCodes.length > 0;
  const droppedRows = rows
    .map((row, index) => ({ row, index, reason: rowDropReason(row, { hasRdoScope }) }))
    .filter((entry): entry is { row: ExtensionRow; index: number; reason: string } =>
      entry.reason !== null,
    );

  const lines: string[] = [];
  lines.push(`# Review — ${sourceReference}`);
  lines.push("");
  lines.push(`- External ID: \`${extraction.externalId}\``);
  lines.push(`- Kind: ${issuance.kind}`);
  lines.push(`- Date issued: ${orDash(issuance.dateIssued)}`);
  lines.push(`- Date source: ${DATE_SOURCE_LABELS[issuance.dateSource]}`);
  lines.push(`- Source record: ${issuance.source}`);
  lines.push(`- PDF: ${issuance.pdfUrl === null ? "—" : `<${issuance.pdfUrl}>`}`);
  lines.push(`- Subject: ${escapeCell(issuance.subject)}`);
  lines.push("");

  lines.push("## Classification verdict");
  lines.push("");
  lines.push(
    "- Verdict: **deadline-extension circular** — PDF extraction ran and produced " +
      `${rows.length} block(s).`,
  );
  lines.push(`- Needs manual review: ${extraction.needsManualReview ? "**yes**" : "no"}`);
  lines.push(`- Global extended date: ${orDash(extraction.globalExtendedDate)}`);
  lines.push(
    `- Stated extension window: ${
      extraction.window === null ? "—" : `${extraction.window.from} to ${extraction.window.to}`
    }`,
  );
  lines.push(`- Override records emitted: ${emitted.length}`);
  lines.push("");
  lines.push("Extraction notes:");
  lines.push("");
  lines.push(...bulletList(extraction.notes, "No extraction notes."));
  lines.push("");

  lines.push("## Office count invariant");
  lines.push("");
  lines.push("| Measure | Value |");
  lines.push("| --- | --- |");
  lines.push(`| Stated in prose | ${statedCount === null ? "—" : statedCount} |`);
  lines.push(`| Distinct offices matched | ${matchedCodes.size} |`);
  lines.push(`| Emitted \`rdo_codes\` (incl. lettered variants) | ${extraction.rdoCodes.length} |`);
  lines.push(`| Verdict | ${invariantVerdict} |`);
  lines.push("");

  lines.push("## RDO matches");
  lines.push("");
  lines.push(...rdoTable(extraction.rdos));
  lines.push("");

  lines.push("## Extension rows");
  lines.push("");
  lines.push(...rowTable(rows));
  lines.push("");

  lines.push("## Emitted overrides");
  lines.push("");
  lines.push(...overrideSections(emitted));
  lines.push("");

  lines.push("## Dropped / needs review");
  lines.push("");
  if (droppedRows.length === 0) {
    lines.push("_Every extracted row became part of an override record._");
  } else {
    lines.push(
      `${droppedRows.length} of ${rows.length} block(s) produced no override. Each entry below ` +
        "carries the nearest printed date pairs so a manual override can be entered in the " +
        "calendar editor without reopening the PDF.",
    );
    for (const entry of droppedRows) {
      lines.push("");
      lines.push(
        `### Row ${entry.index + 1} — \`${entry.reason}\` ` +
          `(${entry.row.channel}, ${entry.row.dateAssignment})`,
      );
      lines.push("");
      lines.push(`- Forms: ${escapeCell(formsOf(entry.row))}`);
      lines.push(
        `- Printed dates: ${orDash(entry.row.originalDate)} → ${orDash(entry.row.extendedDate)}`,
      );
      lines.push(`- Confidence: ${entry.row.confidence}`);
      lines.push(`- Nearest printed pair above: ${nearestPrintedPair(rows, entry.index, -1)}`);
      lines.push(`- Nearest printed pair below: ${nearestPrintedPair(rows, entry.index, 1)}`);
      lines.push(`- Description: ${escapeCell(abbreviate(entry.row.rawDescription, 400))}`);
      if (entry.row.notes.length > 0) {
        lines.push("- Notes:");
        for (const note of entry.row.notes) lines.push(`  - ${escapeCell(note)}`);
      }
    }
  }
  lines.push("");

  lines.push("### Compiler drop log");
  lines.push("");
  if (input.dropped.length === 0) {
    lines.push("_The feed compiler recorded no drops for this run._");
  } else {
    lines.push("| Reason | Detail |");
    lines.push("| --- | --- |");
    for (const drop of input.dropped) {
      lines.push(`| \`${escapeCell(drop.reason)}\` | ${escapeCell(drop.detail)} |`);
    }
  }
  lines.push("");

  return lines.join("\n");
}
