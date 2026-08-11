// feed.json compiler and validator (execution plan §4.1).
//
// The compiler is deliberately conservative: an extension row only becomes an
// app override when the printed evidence is unambiguous (a same-line date pair,
// a non-eFPS channel, catalog-known form codes and a non-empty RDO scope).
// Everything else is returned in `dropped` so the review report (review.ts) can
// hand it to a human instead of silently guessing.
//
// The one exception is the curated supplement (`curated/overrides.json`), which
// carries what a human read off the printed PDF for the merged table cells the
// extractor will not guess. Curated records are merged here, in their own
// external_ref namespace, and are held to the same §4.1 rules as extracted
// ones — including their scope, which they inherit from the extracted record
// they supplement rather than declare for themselves.

import { Buffer } from "node:buffer";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { CANONICAL_FORM_CODES } from "./form-codes.ts";
import type {
  Channel,
  CircularExtraction,
  CuratedOverride,
  DateSource,
  ExtensionRow,
  Feed,
  FeedNotice,
  FeedOverride,
  IssuanceRecord,
} from "./types.ts";

/** A thing the compiler refused to publish, with the evidence for a human. */
export type DropRecord = {
  reason: string;
  detail: string;
};

export type CompileFeedInput = {
  issuances: IssuanceRecord[];
  extractions: CircularExtraction[];
  /** Hand-authored supplements from `curated/overrides.json`; none by default. */
  curated?: readonly CuratedOverride[];
  generatedAtUnix: number;
};

export type CompileFeedResult = {
  feed: Feed;
  dropped: DropRecord[];
  /**
   * Which tier produced each published notice's `published_at_unix`, keyed by
   * `external_id`. `"first_seen"` entries are dates this pipeline invented from
   * its own clock, so callers surface them to a human.
   */
  dateSources: ReadonlyMap<string, DateSource>;
};

export type CivilDate = {
  year: number;
  month: number;
  day: number;
};

/**
 * Notice cap from §4.1; mirrors the app's `domain.max_notices`, and the pair is
 * pinned by a test on each side.
 *
 * Sized to hold a full year: BIR published ~115 issuances in the first eight
 * months of 2026, so ~20 a month. At 120 the cap would have bitten within
 * weeks and silently dropped the oldest months, emptying their dashboard panes
 * — the month-scoped pane failing first, and quietly. 240 clears a year with
 * room to spare and still costs little: notices measure ~500 bytes each, so a
 * full feed is ~120 KiB against the 512 KiB budget.
 */
export const maxNotices = 240;
/** Summary byte cap from §4.1; mirrors the app's notice summary bound. */
export const maxSummaryBytes = 4096;
/** Serialized feed budget from §4.1 (the app rejects oversized bodies). */
export const maxFeedBytes = 512 * 1024;
/**
 * Longest RDO code the app will accept (`max_rdo_code_bytes` in
 * `src/news/feed_json.zig`). Every canonical code is three characters, and the
 * app reserves storage for a full scope list on every override row, so the
 * bound is deliberately tight. Publishing a longer value would make the app
 * reject the whole feed — notices included — so the mismatch is caught here,
 * once at publish time, rather than in every installation.
 */
export const maxRdoCodeBytes = 8;
/** The Philippines has no DST, so Asia/Manila is a fixed UTC+8 (decision L6). */
export const manilaOffsetSeconds = 8 * 3600;

/** Channels that may become app overrides in v1 (locked decision L10). */
export const emittableChannels: ReadonlySet<Channel> = new Set<Channel>([
  "nonefps",
  "efps_and_nonefps",
]);

/**
 * Namespace suffix for a curated override record's `external_ref`.
 *
 * The app stores one override row per `external_ref` and upserts on it, so a
 * curated record must never share an id with the extracted record it
 * supplements: with the same id the two would overwrite each other run after
 * run, and dismissing one would dismiss the other.
 */
export const curatedRefSuffix = "-reviewed";

/** True for an override a human authored, false for one the extractor produced. */
export function isCuratedRef(externalRef: string): boolean {
  return externalRef.endsWith(curatedRefSuffix);
}

export function parseIsoDate(text: string): CivilDate | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(text);
  if (match === null) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (
    probe.getUTCFullYear() !== year ||
    probe.getUTCMonth() + 1 !== month ||
    probe.getUTCDate() !== day
  ) {
    return null;
  }
  return { year, month, day };
}

/** Unix seconds for 00:00 Asia/Manila on the given `YYYY-MM-DD` civil date. */
export function manilaMidnightUnix(iso: string): number | null {
  const civil = parseIsoDate(iso);
  if (civil === null) return null;
  return Date.UTC(civil.year, civil.month - 1, civil.day) / 1000 - manilaOffsetSeconds;
}

/** The Asia/Manila civil date a unix timestamp falls on. */
export function manilaCivilDate(unix: number): CivilDate {
  const shifted = new Date((unix + manilaOffsetSeconds) * 1000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** `YYYY-MM-DD` of the Asia/Manila civil date a unix timestamp falls on. */
export function manilaDateIso(unix: number): string {
  const civil = manilaCivilDate(unix);
  return (
    `${String(civil.year).padStart(4, "0")}-${String(civil.month).padStart(2, "0")}-` +
    String(civil.day).padStart(2, "0")
  );
}

/** `YYYY-MM` of the Asia/Manila civil date a unix timestamp falls on. */
export function manilaMonthBucket(unix: number): string {
  return manilaDateIso(unix).slice(0, 7);
}

/** Truncates to at most `maxBytes` UTF-8 bytes without splitting a codepoint. */
export function truncateUtf8(text: string, maxBytes: number): string {
  const bytes = Buffer.from(text, "utf8");
  if (bytes.length <= maxBytes) return text;

  let end = maxBytes;
  while (end > 0 && (bytes[end] & 0xc0) === 0x80) end -= 1;
  return bytes.subarray(0, end).toString("utf8");
}

function sortedUnique(values: readonly string[]): string[] {
  return [...new Set(values)].toSorted();
}

function compareStrings(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function compareNotices(a: FeedNotice, b: FeedNotice): number {
  if (a.published_at_unix !== b.published_at_unix) {
    return b.published_at_unix - a.published_at_unix;
  }
  return compareStrings(b.external_id, a.external_id);
}

/** A short, table-safe description of a row for drop details and reports. */
export function describeRow(row: ExtensionRow): string {
  const forms =
    row.formCodesCanonical.length > 0
      ? row.formCodesCanonical.join("/")
      : row.formCodesDisplay.length > 0
        ? `${row.formCodesDisplay.join("/")} (non-catalog)`
        : "no form codes";
  const dates = `${row.originalDate ?? "?"} -> ${row.extendedDate ?? "?"}`;
  const description = row.rawDescription.replace(/\s+/gu, " ").trim();
  const abbreviated =
    description.length > 120 ? `${description.slice(0, 119)}…` : description;
  return `[${row.channel}/${row.dateAssignment}] ${forms} ${dates} — ${abbreviated}`;
}

/**
 * Why a row cannot become an override, or null when it can.
 *
 * Single source of truth for the emission filter: feed.ts drops on it and
 * review.ts reports on it, so the report can never disagree with the feed.
 */
export function rowDropReason(
  row: ExtensionRow,
  context: { hasRdoScope: boolean },
): string | null {
  if (row.dateAssignment !== "same_line") return "window_row";
  if (!emittableChannels.has(row.channel)) return "channel_not_emittable";
  if (row.originalDate === null || row.extendedDate === null) return "missing_date_pair";

  const original = parseIsoDate(row.originalDate);
  const extended = parseIsoDate(row.extendedDate);
  if (original === null || extended === null) return "invalid_date";
  if (row.extendedDate < row.originalDate) return "adjusted_before_original";

  const canonical = row.formCodesCanonical.filter((code) => CANONICAL_FORM_CODES.has(code));
  if (canonical.length === 0) return "no_canonical_form_codes";
  if (!context.hasRdoScope) return "empty_rdo_scope";
  return null;
}

type OverrideGroup = {
  originalDate: string;
  extendedDate: string;
  formCodes: string[];
};

type BuiltNotice = {
  notice: FeedNotice;
  /** Which tier actually produced `published_at_unix`. */
  dateSource: DateSource;
};

function buildNotice(issuance: IssuanceRecord, dropped: DropRecord[]): BuiltNotice {
  let publishedAtUnix: number | null = null;
  let dateSource: DateSource = "first_seen";
  if (issuance.dateIssued !== null) {
    publishedAtUnix = manilaMidnightUnix(issuance.dateIssued);
    if (publishedAtUnix === null) {
      dropped.push({
        reason: "invalid_date_issued",
        detail:
          `${issuance.externalId} dateIssued ${JSON.stringify(issuance.dateIssued)} is not a ` +
          "valid YYYY-MM-DD civil date; fell back to firstSeenAtUnix",
      });
    } else {
      dateSource = issuance.dateSource;
    }
  }
  if (publishedAtUnix === null) publishedAtUnix = Math.trunc(issuance.firstSeenAtUnix);

  return {
    notice: {
      external_id: issuance.externalId,
      kind: issuance.kind,
      title: `${issuance.kind} No. ${issuance.number}`,
      summary: truncateUtf8(issuance.subject, maxSummaryBytes),
      url: issuance.pdfUrl,
      published_at_unix: publishedAtUnix,
      month_bucket: manilaMonthBucket(publishedAtUnix),
    },
    dateSource,
  };
}

function collectGroups(
  extraction: CircularExtraction,
  dropped: DropRecord[],
  sourceReference: string,
): OverrideGroup[] {
  const hasRdoScope = sortedUnique(extraction.rdoCodes).length > 0;
  const groups = new Map<string, OverrideGroup>();

  for (const row of extraction.rows) {
    const reason = rowDropReason(row, { hasRdoScope });
    if (reason !== null) {
      dropped.push({ reason, detail: `${sourceReference} ${describeRow(row)}` });
      continue;
    }
    // rowDropReason already proved both dates are present and parseable; this
    // re-narrows them for the type checker without a cast.
    const { originalDate, extendedDate } = row;
    if (originalDate === null || extendedDate === null) continue;

    const canonical: string[] = [];
    const rejected: string[] = [];
    for (const code of row.formCodesCanonical) {
      if (CANONICAL_FORM_CODES.has(code)) canonical.push(code);
      else rejected.push(code);
    }
    if (rejected.length > 0) {
      dropped.push({
        reason: "non_canonical_form_code",
        detail:
          `${sourceReference} ${originalDate}: dropped form code(s) ` +
          `${sortedUnique(rejected).join(", ")} — not in the app catalog`,
      });
    }

    const key = `${originalDate}|${extendedDate}`;
    const existing = groups.get(key);
    if (existing === undefined) {
      groups.set(key, { originalDate, extendedDate, formCodes: [...canonical] });
      continue;
    }
    existing.formCodes.push(...canonical);
  }

  return [...groups.values()].toSorted(
    (a, b) =>
      compareStrings(a.originalDate, b.originalDate) ||
      compareStrings(a.extendedDate, b.extendedDate),
  );
}

/** The committed curated supplement; the file documents itself in its `note`. */
export const curatedOverridesPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "curated",
  "overrides.json",
);

export type CuratedLoadResult = {
  entries: CuratedOverride[];
  /** Why any entry (or the whole file) was not usable. */
  dropped: DropRecord[];
};

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

/** A validated entry, or the reason this one cannot be trusted. */
function parseCuratedEntry(value: unknown): CuratedOverride | string {
  if (!isJsonObject(value)) return "entry is not a JSON object";

  const noticeExternalId = nonEmptyString(value.notice_external_id);
  if (noticeExternalId === null) return "notice_external_id must be a non-empty string";

  const originalDeadline = nonEmptyString(value.original_deadline);
  const adjustedDeadline = nonEmptyString(value.adjusted_deadline);
  if (originalDeadline === null || parseIsoDate(originalDeadline) === null) {
    return `original_deadline ${JSON.stringify(value.original_deadline)} is not a valid date`;
  }
  if (adjustedDeadline === null || parseIsoDate(adjustedDeadline) === null) {
    return `adjusted_deadline ${JSON.stringify(value.adjusted_deadline)} is not a valid date`;
  }
  if (adjustedDeadline < originalDeadline) {
    return `adjusted_deadline ${adjustedDeadline} precedes original_deadline ${originalDeadline}`;
  }

  const channel = nonEmptyString(value.channel);
  if (channel === null || !emittableChannels.has(channel as Channel)) {
    return `channel ${JSON.stringify(value.channel)} is not an emittable channel`;
  }

  if (!Array.isArray(value.form_codes) || value.form_codes.length === 0) {
    return "form_codes must be a non-empty array";
  }
  const formCodes: string[] = [];
  for (const code of value.form_codes) {
    const parsed = nonEmptyString(code);
    if (parsed === null) return `form_codes carries ${JSON.stringify(code)}, not a form code`;
    formCodes.push(parsed);
  }

  const reviewed = nonEmptyString(value.reviewed);
  if (reviewed === null) {
    return "reviewed must name the printed evidence a human checked";
  }
  const reviewedOn = nonEmptyString(value.reviewed_on);
  if (reviewedOn === null || parseIsoDate(reviewedOn) === null) {
    return `reviewed_on ${JSON.stringify(value.reviewed_on)} is not a valid date`;
  }

  return {
    noticeExternalId,
    originalDeadline,
    adjustedDeadline,
    channel: channel as Channel,
    formCodes,
    reviewed,
    reviewedOn,
  };
}

/**
 * Reads and validates the curated supplement.
 *
 * Nothing here is fatal: an unreadable file or a malformed entry is recorded in
 * `dropped` and the run continues on the extracted records alone. The
 * supplement can only ever add records a human vouched for, so losing it costs
 * coverage, never correctness.
 */
export async function loadCuratedOverrides(
  filePath: string = curatedOverridesPath,
): Promise<CuratedLoadResult> {
  let raw: string;
  try {
    raw = await readFile(filePath, "utf8");
  } catch (error) {
    const reason =
      (error as NodeJS.ErrnoException).code === "ENOENT"
        ? "curated_file_missing"
        : "curated_file_unreadable";
    return {
      entries: [],
      dropped: [{ reason, detail: `${filePath}: ${(error as Error).message}` }],
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    return {
      entries: [],
      dropped: [
        { reason: "curated_file_unreadable", detail: `${filePath}: ${(error as Error).message}` },
      ],
    };
  }
  if (!isJsonObject(parsed) || !Array.isArray(parsed.entries)) {
    return {
      entries: [],
      dropped: [
        { reason: "curated_file_unreadable", detail: `${filePath}: no "entries" array` },
      ],
    };
  }

  const entries: CuratedOverride[] = [];
  const dropped: DropRecord[] = [];
  parsed.entries.forEach((value, index) => {
    const entry = parseCuratedEntry(value);
    if (typeof entry === "string") {
      dropped.push({
        reason: "curated_malformed_entry",
        detail: `${filePath} entries[${index}]: ${entry}`,
      });
      return;
    }
    entries.push(entry);
  });
  return { entries, dropped };
}

/**
 * Merges the curated supplement into the already-compiled extracted records.
 *
 * A curated entry is only ever an addition to an extracted record: it is
 * matched to one by `(notice, original date, channel)`, inherits that record's
 * RDO scope so the two can never disagree about who is affected, and is dropped
 * with a reason whenever that record is absent from this run.
 */
function mergeCurated(
  curated: readonly CuratedOverride[],
  overrides: FeedOverride[],
  emittedRefs: Set<string>,
  publishedNoticeIds: ReadonlySet<string>,
  dropped: DropRecord[],
): void {
  const extractedByRef = new Map(overrides.map((override) => [override.external_ref, override]));

  for (const entry of curated) {
    const baseRef = `${entry.noticeExternalId}/${entry.originalDeadline}/${entry.channel}`;
    const at = `curated ${baseRef}`;

    if (!publishedNoticeIds.has(entry.noticeExternalId)) {
      dropped.push({
        reason: "curated_unknown_notice",
        detail: `${at} names ${entry.noticeExternalId}, which this feed does not publish`,
      });
      continue;
    }

    const base = extractedByRef.get(baseRef);
    if (base === undefined) {
      dropped.push({
        reason: "curated_no_extracted_record",
        detail:
          `${at} supplements an override this run did not extract, so it has no RDO scope to ` +
          "inherit; dropped rather than published unscoped",
      });
      continue;
    }
    if (base.adjusted_deadline !== entry.adjustedDeadline) {
      dropped.push({
        reason: "curated_date_pair_mismatch",
        detail:
          `${at} was reviewed as extending to ${entry.adjustedDeadline}, but the extracted ` +
          `record reads ${base.adjusted_deadline}; one of the two misread the printed cell`,
      });
      continue;
    }

    const canonical: string[] = [];
    const rejected: string[] = [];
    for (const code of entry.formCodes) {
      if (CANONICAL_FORM_CODES.has(code)) canonical.push(code);
      else rejected.push(code);
    }
    if (rejected.length > 0) {
      dropped.push({
        reason: "curated_non_canonical_form_code",
        detail:
          `${at}: dropped form code(s) ${sortedUnique(rejected).join(", ")} — not in the app ` +
          "catalog",
      });
    }
    if (canonical.length === 0) {
      dropped.push({
        reason: "curated_no_canonical_form_codes",
        detail: `${at} names no form code the app catalog knows`,
      });
      continue;
    }

    const externalRef = `${baseRef}${curatedRefSuffix}`;
    if (emittedRefs.has(externalRef)) {
      dropped.push({
        reason: "curated_duplicate_external_ref",
        detail: `${at} collides with an already emitted ${externalRef}`,
      });
      continue;
    }
    emittedRefs.add(externalRef);
    overrides.push({
      external_ref: externalRef,
      title: `${base.title} — curated supplement`,
      source_reference: base.source_reference,
      original_deadline: entry.originalDeadline,
      adjusted_deadline: entry.adjustedDeadline,
      form_codes: sortedUnique(canonical),
      rdo_codes: [...base.rdo_codes],
      channel: entry.channel,
      notice_external_id: entry.noticeExternalId,
    });
  }
}

/**
 * Compiles issuances plus PDF extractions into the published feed.
 *
 * Notices are published for every issuance; overrides only for evidence that
 * clears every §4.1 rule. `dropped` is the audit trail of everything held back;
 * `dateSources` records where each published date actually came from.
 */
export function compileFeed(input: CompileFeedInput): CompileFeedResult {
  const dropped: DropRecord[] = [];

  const issuanceById = new Map<string, IssuanceRecord>();
  const notices: FeedNotice[] = [];
  const builtDateSources = new Map<string, DateSource>();
  for (const issuance of input.issuances) {
    if (issuanceById.has(issuance.externalId)) {
      dropped.push({
        reason: "duplicate_notice",
        detail: `${issuance.externalId} appeared more than once; kept the first record`,
      });
      continue;
    }
    issuanceById.set(issuance.externalId, issuance);
    const built = buildNotice(issuance, dropped);
    notices.push(built.notice);
    builtDateSources.set(built.notice.external_id, built.dateSource);
  }

  notices.sort(compareNotices);
  if (notices.length > maxNotices) {
    for (const trimmed of notices.slice(maxNotices)) {
      dropped.push({
        reason: "notices_cap",
        detail:
          `${trimmed.external_id} (${trimmed.month_bucket}) exceeds the ` +
          `${maxNotices}-notice cap`,
      });
    }
    notices.length = maxNotices;
  }
  const publishedNoticeIds = new Set(notices.map((notice) => notice.external_id));
  const dateSources = new Map<string, DateSource>();
  for (const notice of notices) {
    dateSources.set(notice.external_id, builtDateSources.get(notice.external_id) ?? "first_seen");
  }

  const overrides: FeedOverride[] = [];
  const emittedRefs = new Set<string>();
  for (const extraction of input.extractions) {
    const issuance = issuanceById.get(extraction.externalId);
    if (issuance === undefined) {
      dropped.push({
        reason: "unknown_issuance",
        detail:
          `${extraction.externalId} has ${extraction.rows.length} extracted row(s) but no ` +
          "matching issuance record",
      });
      continue;
    }

    const sourceReference = `${issuance.kind} No. ${issuance.number}`;
    const rdoCodes = sortedUnique(extraction.rdoCodes);
    const groups = collectGroups(extraction, dropped, sourceReference);

    if (!publishedNoticeIds.has(extraction.externalId)) {
      for (const group of groups) {
        dropped.push({
          reason: "notice_not_in_feed",
          detail:
            `${sourceReference} ${group.originalDate} -> ${group.extendedDate} has no notice in ` +
            "this feed (trimmed by the notice cap)",
        });
      }
      continue;
    }

    for (const group of groups) {
      const externalRef = `${extraction.externalId}/${group.originalDate}/nonefps`;
      if (emittedRefs.has(externalRef)) {
        dropped.push({
          reason: "duplicate_external_ref",
          detail:
            `${sourceReference} ${group.originalDate} -> ${group.extendedDate} collides with an ` +
            `already emitted ${externalRef}; the printed table disagrees with itself`,
        });
        continue;
      }
      emittedRefs.add(externalRef);
      overrides.push({
        external_ref: externalRef,
        title: `${issuance.kind} ${issuance.number} extension (due ${group.originalDate})`,
        source_reference: sourceReference,
        original_deadline: group.originalDate,
        adjusted_deadline: group.extendedDate,
        form_codes: sortedUnique(group.formCodes),
        rdo_codes: rdoCodes,
        channel: "nonefps",
        notice_external_id: extraction.externalId,
      });
    }
  }

  if (input.curated !== undefined && input.curated.length > 0) {
    mergeCurated(input.curated, overrides, emittedRefs, publishedNoticeIds, dropped);
  }

  overrides.sort((a, b) => compareStrings(a.external_ref, b.external_ref));

  const feed: Feed = {
    schema_version: 1,
    generated_at_unix: Math.trunc(input.generatedAtUnix),
    source_label: "BIR",
    notices,
    overrides,
  };
  return { feed, dropped, dateSources };
}

/**
 * Renders the feed deterministically: fixed key order, sorted arrays, 2-space
 * JSON, trailing newline. Two runs over equal content produce equal bytes, so
 * the publishing step can commit only on a real change.
 */
export function serializeFeed(feed: Feed): string {
  const document = {
    schema_version: feed.schema_version,
    generated_at_unix: feed.generated_at_unix,
    source_label: feed.source_label,
    notices: feed.notices.toSorted(compareNotices).map((notice) => ({
      external_id: notice.external_id,
      kind: notice.kind,
      title: notice.title,
      summary: notice.summary,
      url: notice.url,
      published_at_unix: notice.published_at_unix,
      month_bucket: notice.month_bucket,
    })),
    overrides: feed.overrides
      .toSorted((a, b) => compareStrings(a.external_ref, b.external_ref))
      .map((override) => ({
        external_ref: override.external_ref,
        title: override.title,
        source_reference: override.source_reference,
        original_deadline: override.original_deadline,
        adjusted_deadline: override.adjusted_deadline,
        form_codes: sortedUnique(override.form_codes),
        rdo_codes: sortedUnique(override.rdo_codes),
        channel: override.channel,
        notice_external_id: override.notice_external_id,
      })),
  };
  return `${JSON.stringify(document, null, 2)}\n`;
}

/**
 * Content equality for idempotent publishing: everything except the run's
 * `generated_at_unix`, so a no-op sync makes no commit.
 */
export function feedContentEquals(a: Feed, b: Feed): boolean {
  return (
    serializeFeed({ ...a, generated_at_unix: 0 }) ===
    serializeFeed({ ...b, generated_at_unix: 0 })
  );
}

/** Contract violations in a compiled feed; an empty array means it is valid. */
export function validateFeed(feed: Feed): string[] {
  const violations: string[] = [];

  if (feed.schema_version !== 1) {
    violations.push(`schema_version must be 1, got ${JSON.stringify(feed.schema_version)}`);
  }
  if (feed.source_label !== "BIR") {
    violations.push(`source_label must be "BIR", got ${JSON.stringify(feed.source_label)}`);
  }
  if (!Number.isSafeInteger(feed.generated_at_unix) || feed.generated_at_unix < 0) {
    violations.push(
      `generated_at_unix must be a non-negative integer, got ${feed.generated_at_unix}`,
    );
  }

  const serializedBytes = Buffer.byteLength(serializeFeed(feed), "utf8");
  if (serializedBytes > maxFeedBytes) {
    violations.push(
      `serialized feed is ${serializedBytes} bytes, over the ${maxFeedBytes}-byte budget`,
    );
  }
  if (feed.notices.length > maxNotices) {
    violations.push(`feed carries ${feed.notices.length} notices, over the ${maxNotices} cap`);
  }

  const noticeIds = new Set<string>();
  feed.notices.forEach((notice, index) => {
    const at = `notices[${index}] ${notice.external_id}`;
    if (notice.external_id.trim().length === 0) {
      violations.push(`notices[${index}] has an empty external_id`);
    } else if (noticeIds.has(notice.external_id)) {
      violations.push(`${at} repeats an external_id`);
    } else {
      noticeIds.add(notice.external_id);
    }
    if (notice.title.trim().length === 0) violations.push(`${at} has an empty title`);

    const summaryBytes = Buffer.byteLength(notice.summary, "utf8");
    if (summaryBytes > maxSummaryBytes) {
      violations.push(
        `${at} summary is ${summaryBytes} bytes, over the ${maxSummaryBytes}-byte cap`,
      );
    }
    if (!Number.isSafeInteger(notice.published_at_unix)) {
      violations.push(`${at} published_at_unix ${notice.published_at_unix} is not an integer`);
    } else if (notice.month_bucket !== manilaMonthBucket(notice.published_at_unix)) {
      violations.push(
        `${at} month_bucket ${JSON.stringify(notice.month_bucket)} does not match the Manila ` +
          `month ${manilaMonthBucket(notice.published_at_unix)} of published_at_unix`,
      );
    }
  });

  const overrideRefs = new Set<string>();
  feed.overrides.forEach((override, index) => {
    const at = `overrides[${index}] ${override.external_ref}`;
    if (override.external_ref.trim().length === 0) {
      violations.push(`overrides[${index}] has an empty external_ref`);
    } else if (overrideRefs.has(override.external_ref)) {
      violations.push(`${at} repeats an external_ref`);
    } else {
      overrideRefs.add(override.external_ref);
    }

    // A curated record shares its supplemented record's identity plus the
    // curated suffix; everything else must be exactly the derived identity.
    const expectedRef =
      `${override.notice_external_id}/${override.original_deadline}/${override.channel}`;
    if (
      override.external_ref !== expectedRef &&
      override.external_ref !== `${expectedRef}${curatedRefSuffix}`
    ) {
      violations.push(`${at} does not match its derived identity ${expectedRef}`);
    }
    if (!noticeIds.has(override.notice_external_id)) {
      violations.push(
        `${at} references notice ${override.notice_external_id}, absent from the feed`,
      );
    }
    if (!emittableChannels.has(override.channel)) {
      violations.push(`${at} has non-emittable channel ${override.channel}`);
    }
    if (override.source_reference.trim().length === 0) {
      violations.push(`${at} has an empty source_reference`);
    }
    if (override.title.trim().length === 0) violations.push(`${at} has an empty title`);

    const original = parseIsoDate(override.original_deadline);
    const adjusted = parseIsoDate(override.adjusted_deadline);
    if (original === null) {
      violations.push(
        `${at} original_deadline ${JSON.stringify(override.original_deadline)} is not a ` +
          "valid date",
      );
    }
    if (adjusted === null) {
      violations.push(
        `${at} adjusted_deadline ${JSON.stringify(override.adjusted_deadline)} is not a ` +
          "valid date",
      );
    }
    if (
      original !== null &&
      adjusted !== null &&
      override.adjusted_deadline < override.original_deadline
    ) {
      violations.push(
        `${at} adjusted_deadline ${override.adjusted_deadline} precedes original_deadline ` +
          `${override.original_deadline}`,
      );
    }

    if (override.rdo_codes.length === 0) {
      violations.push(`${at} has an empty rdo_codes scope, forbidden in v1`);
    }
    for (const code of override.rdo_codes) {
      if (Buffer.byteLength(code, "utf8") > maxRdoCodeBytes) {
        violations.push(
          `${at} carries rdo code ${JSON.stringify(code)}, over the ` +
            `${maxRdoCodeBytes}-byte cap the app enforces`,
        );
      }
    }
    if (override.form_codes.length === 0) {
      violations.push(`${at} has no form_codes`);
    }
    for (const code of override.form_codes) {
      if (!CANONICAL_FORM_CODES.has(code)) {
        violations.push(`${at} carries non-canonical form code ${JSON.stringify(code)}`);
      }
    }
  });

  return violations;
}
