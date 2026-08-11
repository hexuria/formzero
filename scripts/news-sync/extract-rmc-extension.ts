// Per-circular extraction orchestrator (execution plan §5.5 + §5.6).
//
// The two halves of the extractor are independent and separately tested —
// extract-rdos.ts reads the affected-offices region, extract-deadline-table.ts
// reads the table geometry — and this module is the only place that knows they
// describe the same document. It composes them into one `CircularExtraction`,
// applies the cross-cutting fail-closed checks that need both halves (text
// layer usability, the prose office-count invariant), and records why in
// `notes` so the review report can show the reasoning chain.
//
// Pure: no I/O, no clock. `layoutText` comes from pdf.ts, which owns the
// download and the poppler call.

import type { CircularAnchors } from "./extract-deadline-table.ts";
import {
  extractDeadlineRows,
  parseCircularAnchors,
  parseIssueDateAnchor,
} from "./extract-deadline-table.ts";
import { extractRdos } from "./extract-rdos.ts";
import { countLayoutPages, hasUsableTextLayer, minimumCharactersPerPage } from "./pdf.ts";
import type { CircularExtraction, IssuanceRecord } from "./types.ts";

export type ExtractCircularInput = {
  issuance: IssuanceRecord;
  /** `pdftotext -layout` output for the issuance's PDF. */
  layoutText: string;
};

/** An extraction that ran no parsers, because the input could not carry them. */
function emptyExtraction(externalId: string, notes: string[]): CircularExtraction {
  return {
    externalId,
    headerDateIssued: null,
    globalExtendedDate: null,
    window: null,
    statedOfficeCount: null,
    rdos: [],
    rdoCodes: [],
    rows: [],
    needsManualReview: true,
    notes,
  };
}

function distinctOfficeCount(codes: readonly (string | null)[]): number {
  return new Set(codes.filter((code): code is string => code !== null)).size;
}

/**
 * Mines one deadline-extension circular's layout text.
 *
 * `needsManualReview` is set when the document cannot be trusted as a whole:
 * an unusable text layer (plan decision D3) or a prose office count that
 * disagrees with the offices actually matched. Row-level and office-level
 * doubt stays where it belongs — on the row's or match's own `confidence` —
 * because the compiler already refuses to publish those.
 */
export function extractCircular(input: ExtractCircularInput): CircularExtraction {
  const { issuance, layoutText } = input;
  const notes: string[] = [];

  const pageCount = countLayoutPages(layoutText);
  const characters = layoutText.replace(/[\s\f]+/gu, " ").trim().length;
  if (!hasUsableTextLayer(layoutText, pageCount)) {
    notes.push(
      `text layer unusable: ${characters} characters over ${pageCount} page(s), below the ` +
        `${minimumCharactersPerPage} characters/page floor — no extraction attempted ` +
        "(plan decision D3)",
    );
    return emptyExtraction(issuance.externalId, notes);
  }
  notes.push(`text layer: ${characters} characters over ${pageCount} page(s)`);

  const headerDateIssued = parseIssueDateAnchor(layoutText);
  notes.push(
    headerDateIssued === null
      ? "no issue date readable in the page-1 letterhead"
      : `page-1 letterhead issue date: ${headerDateIssued}`,
  );

  const parsedAnchors = parseCircularAnchors(layoutText);
  // The archive's date of issue is typed by the CMS, not read off a scan, so
  // it anchors the year better than anything in the page text.
  const issuedYear =
    issuance.dateIssued === null ? null : Number.parseInt(issuance.dateIssued.slice(0, 4), 10);
  const anchors: CircularAnchors = {
    ...parsedAnchors,
    referenceYear: issuedYear ?? parsedAnchors.referenceYear,
  };
  if (anchors.globalExtendedDate === null) {
    notes.push(
      "no circular-level extended date found in the prose; rows with a damaged extended " +
        "column cannot fall back to one",
    );
  }
  if (anchors.window === null) {
    notes.push("no stated extension window found in the prose");
  }

  const rdoExtraction = extractRdos(layoutText);
  const matchedOffices = distinctOfficeCount(rdoExtraction.rdos.map((rdo) => rdo.code));
  const unresolved = rdoExtraction.rdos.filter((rdo) => rdo.code === null).length;
  notes.push(
    `RDO references: ${rdoExtraction.rdos.length} matched, ${matchedOffices} distinct office(s), ` +
      `${rdoExtraction.rdoCodes.length} emitted code(s) after lettered expansion` +
      (unresolved > 0 ? `, ${unresolved} unresolvable` : ""),
  );
  if (rdoExtraction.rdoCodes.length === 0) {
    notes.push(
      "no RDO scope resolved — an unscoped nationwide override is forbidden in v1, so no " +
        "override can be emitted for this circular",
    );
  }

  let needsManualReview = false;
  if (rdoExtraction.statedOfficeCount === null) {
    notes.push("office-count invariant: the prose states no count, nothing to compare");
  } else if (rdoExtraction.statedOfficeCount === matchedOffices) {
    notes.push(
      `office-count invariant: the prose states ${rdoExtraction.statedOfficeCount} and the ` +
        "extractor matched the same number",
    );
  } else {
    needsManualReview = true;
    notes.push(
      `office-count invariant FAILED: the prose states ${rdoExtraction.statedOfficeCount} ` +
        `office(s) but the extractor matched ${matchedOffices}`,
    );
  }

  const rows = extractDeadlineRows(layoutText, anchors);
  const sameLine = rows.filter((row) => row.dateAssignment === "same_line").length;
  const flagged = rows.filter((row) => row.confidence === "review").length;
  notes.push(
    `deadline table: ${rows.length} block(s), ${sameLine} with a printed date pair, ` +
      `${rows.length - sameLine} recorded against the circular window, ` +
      `${flagged} flagged for review`,
  );
  if (rows.length === 0) {
    notes.push("no deadline-table blocks were found; the table header may have moved");
  }

  return {
    externalId: issuance.externalId,
    headerDateIssued,
    globalExtendedDate: anchors.globalExtendedDate,
    window: anchors.window,
    statedOfficeCount: rdoExtraction.statedOfficeCount,
    rdos: rdoExtraction.rdos,
    rdoCodes: rdoExtraction.rdoCodes,
    rows,
    needsManualReview,
    notes,
  };
}
