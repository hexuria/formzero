// Shared record contracts for the BIR news-sync pipeline. Every module in
// scripts/news-sync/ imports these with `import type { ... } from "./types.ts"`.
// Keep this file free of runtime code so the type contract stays erasable.

export type IssuanceKind =
  | "RMC"
  | "RMO"
  | "RR"
  | "RDAO"
  | "RA"
  | "BANK_BULLETIN"
  | "OTHER";

/**
 * The issuance kinds BIR publishes a yearly archive page for. Each one has its
 * own `{year}-<slug>` page and its own CMS template id, and each one is the
 * authoritative source of `dateIssued` for its kind.
 */
export type ArchiveKind = Extract<IssuanceKind, "RMC" | "RMO" | "RR">;

/**
 * Which tier produced a notice's published date, in preference order:
 * the yearly archive's DATE OF ISSUE, the date printed on page 1 of the PDF,
 * or — last resort — this pipeline's first sighting of the issuance.
 */
export type DateSource = "archive" | "pdf_header" | "first_seen";

export type Channel =
  | "nonefps"
  | "efps_group_a"
  | "efps_group_b"
  | "efps_group_c"
  | "efps_group_d"
  | "efps_group_e"
  | "efps_group_multi"
  | "efps_and_nonefps"
  | "registration"
  | "submission"
  | "unknown";

export type Confidence = "high" | "review";

export type DateAssignment = "same_line" | "window";

export type IssuanceRecord = {
  externalId: string;
  kind: IssuanceKind;
  number: string;
  subject: string;
  pdfUrl: string | null;
  dateIssued: string | null;
  /** Provenance of `dateIssued`; `"first_seen"` while no date has been found. */
  dateSource: DateSource;
  source: "widget" | "archive" | "merged";
  firstSeenAtUnix: number;
};

export type RdoMatch = {
  raw: string;
  code: string | null;
  referenceName: string | null;
  matchedBy: "code" | "name" | "code+name";
  confidence: Confidence;
  notes: string[];
};

export type ExtensionRow = {
  channel: Channel;
  rawDescription: string;
  formCodesDisplay: string[];
  formCodesCanonical: string[];
  originalDate: string | null;
  extendedDate: string | null;
  dateAssignment: DateAssignment;
  confidence: Confidence;
  notes: string[];
};

export type CircularExtraction = {
  externalId: string;
  /** Date printed on page 1 above the issuance heading, when readable. */
  headerDateIssued: string | null;
  globalExtendedDate: string | null;
  window: { from: string; to: string } | null;
  statedOfficeCount: number | null;
  rdos: RdoMatch[];
  rdoCodes: string[];
  rows: ExtensionRow[];
  needsManualReview: boolean;
  notes: string[];
};

/**
 * One hand-authored supplement to an extracted override record, as authored in
 * `curated/overrides.json`.
 *
 * The extractor refuses to guess which description blocks share a merged
 * deadline-table cell (docs/news/MERGED_CELL_INVESTIGATION.md), so the forms
 * printed in the same bordered cell as an extracted date pair are read off the
 * source PDF by a human and merged into the feed at compile time. A curated
 * entry never invents a scope: it supplements an extracted record and inherits
 * that record's `rdo_codes`.
 */
export type CuratedOverride = {
  /** The notice this supplements; must be published in the same feed. */
  noticeExternalId: string;
  /** Must equal the extracted record's `original_deadline`. */
  originalDeadline: string;
  /** Must equal the extracted record's `adjusted_deadline`. */
  adjustedDeadline: string;
  channel: Channel;
  /** Canonical app codes; anything outside the catalog is dropped and reported. */
  formCodes: string[];
  /** The printed evidence a human read, naming the cell and the PDF page. */
  reviewed: string;
  /** `YYYY-MM-DD` the evidence was last checked against the source PDF. */
  reviewedOn: string;
};

export type FeedNotice = {
  external_id: string;
  kind: IssuanceKind;
  title: string;
  summary: string;
  url: string | null;
  published_at_unix: number;
  month_bucket: string;
};

export type FeedOverride = {
  external_ref: string;
  title: string;
  source_reference: string;
  original_deadline: string;
  adjusted_deadline: string;
  form_codes: string[];
  rdo_codes: string[];
  channel: Channel;
  notice_external_id: string;
};

export type Feed = {
  schema_version: 1;
  generated_at_unix: number;
  source_label: "BIR";
  notices: FeedNotice[];
  overrides: FeedOverride[];
};
