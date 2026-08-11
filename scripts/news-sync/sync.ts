#!/usr/bin/env node
// CLI orchestrator for the BIR news-sync pipeline (execution plan §3, T3.2).
//
//   npm run news:sync -- [fetch|extract|compile|all] [--offline] [--now <unix>]
//                        [--force <externalId>]…
//
// Stages are cumulative, because the pipeline hands each stage's output to the
// next in memory rather than through an on-disk interchange format:
//
//   fetch    CMS widget + one yearly archive per kind -> merge     (no writes)
//   extract  + classify -> PDF text -> RDOs and deadline rows      (+ review/)
//   compile  + feed compilation and validation                     (+ feed/, state/)
//   all      alias for compile, and the default
//
// Two properties this file exists to guarantee:
//
//   * Idempotence. Every output is compared before it is written, and the feed
//     is compared on content excluding `generated_at_unix`. A run that learns
//     nothing new touches no file, so the publishing cron makes no commit.
//   * Never a partial feed. The feed is compiled and validated entirely in
//     memory, then written through a temporary file and renamed into place.
//
// Exit codes: 0 success, 2 missing runner dependency (poppler), 1 anything else.

import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  ARCHIVE_FIXTURES,
  ARCHIVE_KINDS,
  WIDGET_FIXTURE,
  WIDGET_TEMPLATE_ID,
  discoverYearTemplateId,
  fetchTemplateDatasets,
  loadFixtureDataset,
} from "./cms.ts";
import { isDeadlineExtension } from "./classify.ts";
import { extractCircular } from "./extract-rmc-extension.ts";
import {
  compileFeed,
  feedContentEquals,
  manilaCivilDate,
  manilaDateIso,
  serializeFeed,
  validateFeed,
} from "./feed.ts";
import type { DropRecord } from "./feed.ts";
import {
  extractIssuanceHtml,
  mergeIssuances,
  parseArchiveIssuances,
  parseWidgetIssuances,
} from "./issuances.ts";
import type { IssuanceParseWarning } from "./issuances.ts";
import {
  PdftotextUnavailableError,
  downloadPdf,
  ensurePdftotext,
  loadFixtureLayoutText,
  missingDependencyExitCode,
  pdfToLayoutText,
} from "./pdf.ts";
import { renderReviewReport, reviewReportPath } from "./review.ts";
import {
  firstSeenUnix,
  isAlreadyExtracted,
  loadState,
  markExtracted,
  markSeen,
  serializeState,
} from "./state.ts";
import type { SeenState } from "./state.ts";
import type {
  CircularExtraction,
  DateSource,
  Feed,
  FeedNotice,
  FeedOverride,
  IssuanceRecord,
} from "./types.ts";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));

/** Committed outputs. */
export const feedPath = path.join(scriptDirectory, "feed", "feed.json");
export const statePath = path.join(scriptDirectory, "state", "seen.json");
export const reviewDir = path.join(scriptDirectory, "review");
/** Gitignored scratch: downloaded PDFs and cached extraction results. */
export const workDir = path.join(scriptDirectory, "work");
export const pdfCacheDir = path.join(workDir, "pdf");
export const extractionCacheDir = path.join(workDir, "extraction");

/**
 * Where a run reads and writes. Injectable so the end-to-end test can drive the
 * real pipeline into a scratch directory instead of the committed outputs.
 */
export type SyncPaths = {
  feedPath: string;
  statePath: string;
  reviewDir: string;
  pdfCacheDir: string;
  extractionCacheDir: string;
};

export const defaultPaths: SyncPaths = {
  feedPath,
  statePath,
  reviewDir,
  pdfCacheDir,
  extractionCacheDir,
};

/** The same layout as the committed outputs, rooted at `root`. */
export function pathsUnder(root: string): SyncPaths {
  return {
    feedPath: path.join(root, "feed", "feed.json"),
    statePath: path.join(root, "state", "seen.json"),
    reviewDir: path.join(root, "review"),
    pdfCacheDir: path.join(root, "work", "pdf"),
    extractionCacheDir: path.join(root, "work", "extraction"),
  };
}

function displayPath(target: string): string {
  const relative = path.relative(scriptDirectory, target);
  return relative.startsWith("..") ? target : relative;
}

export type Stage = "fetch" | "extract" | "compile" | "all";

export type SyncOptions = {
  stage: Stage;
  offline: boolean;
  force: readonly string[];
  nowUnix: number;
};

export type Logger = (line: string) => void;

export type SyncSummary = {
  stage: Stage;
  offline: boolean;
  issuanceCount: number;
  /** Issuances absent from `state/seen.json` before this run. */
  newCount: number;
  /** Extension circulars whose PDF hash was unchanged, so extraction re-ran nothing. */
  skippedCount: number;
  extractedCount: number;
  noticeCount: number;
  overrideCount: number;
  /** Notices whose published date is this pipeline's first sighting, not BIR's. */
  firstSeenDatedCount: number;
  feedChanged: boolean;
  reviewsChanged: number;
  stateChanged: boolean;
};

const USAGE =
  "usage: news:sync [fetch|extract|compile|all] [--offline] [--now <unix-seconds>] " +
  "[--force <externalId>]…";

const STAGES: ReadonlySet<string> = new Set<Stage>(["fetch", "extract", "compile", "all"]);

function isStage(value: string): value is Stage {
  return STAGES.has(value);
}

/** Stage ordering: `extract` implies `fetch`, `compile` implies both. */
function stageAtLeast(stage: Stage, required: Exclude<Stage, "all">): boolean {
  const rank: Record<Stage, number> = { fetch: 0, extract: 1, compile: 2, all: 2 };
  return rank[stage] >= rank[required];
}

export function parseArgs(argv: readonly string[], defaultNowUnix: number): SyncOptions {
  let stage: Stage = "all";
  let stageSeen = false;
  let offline = false;
  let nowUnix = defaultNowUnix;
  const force: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--offline") {
      offline = true;
    } else if (argument === "--now") {
      const value = argv[index + 1];
      index += 1;
      if (value === undefined) throw new Error(`--now needs a unix timestamp. ${USAGE}`);
      const parsed = Number.parseInt(value, 10);
      if (!Number.isSafeInteger(parsed) || parsed < 0) {
        throw new Error(`--now ${JSON.stringify(value)} is not a unix timestamp. ${USAGE}`);
      }
      nowUnix = parsed;
    } else if (argument === "--force") {
      const value = argv[index + 1];
      index += 1;
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`--force needs an issuance external id. ${USAGE}`);
      }
      force.push(value);
    } else if (argument.startsWith("-")) {
      throw new Error(`unknown flag ${JSON.stringify(argument)}. ${USAGE}`);
    } else if (stageSeen) {
      throw new Error(`unexpected second subcommand ${JSON.stringify(argument)}. ${USAGE}`);
    } else if (isStage(argument)) {
      stage = argument;
      stageSeen = true;
    } else {
      throw new Error(`unknown subcommand ${JSON.stringify(argument)}. ${USAGE}`);
    }
  }

  return { stage, offline, force, nowUnix };
}

async function readFileOrNull(target: string): Promise<string | null> {
  try {
    return await readFile(target, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

/** Writes only when the bytes would change, so unchanged outputs keep their mtime. */
async function writeIfChanged(target: string, content: string): Promise<boolean> {
  if ((await readFileOrNull(target)) === content) return false;
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, content, "utf8");
  return true;
}

/** Write-then-rename, so a crash mid-write can never leave a truncated feed. */
async function writeAtomic(target: string, content: string): Promise<void> {
  await mkdir(path.dirname(target), { recursive: true });
  const temporary = `${target}.tmp`;
  await writeFile(temporary, content, "utf8");
  await rename(temporary, target);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseNotice(value: unknown): FeedNotice | null {
  if (!isRecord(value)) return null;
  const { external_id, kind, title, summary, url, published_at_unix, month_bucket } = value;
  if (typeof external_id !== "string" || typeof kind !== "string") return null;
  if (typeof title !== "string" || typeof summary !== "string") return null;
  if (url !== null && typeof url !== "string") return null;
  if (typeof published_at_unix !== "number" || typeof month_bucket !== "string") return null;
  return {
    external_id,
    kind: kind as FeedNotice["kind"],
    title,
    summary,
    url,
    published_at_unix,
    month_bucket,
  };
}

function parseStringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const items: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") return null;
    items.push(entry);
  }
  return items;
}

function parseOverride(value: unknown): FeedOverride | null {
  if (!isRecord(value)) return null;
  const formCodes = parseStringArray(value.form_codes);
  const rdoCodes = parseStringArray(value.rdo_codes);
  if (formCodes === null || rdoCodes === null) return null;
  const {
    external_ref,
    title,
    source_reference,
    original_deadline,
    adjusted_deadline,
    channel,
    notice_external_id,
  } = value;
  if (typeof external_ref !== "string" || typeof title !== "string") return null;
  if (typeof source_reference !== "string" || typeof channel !== "string") return null;
  if (typeof original_deadline !== "string" || typeof adjusted_deadline !== "string") return null;
  if (typeof notice_external_id !== "string") return null;
  return {
    external_ref,
    title,
    source_reference,
    original_deadline,
    adjusted_deadline,
    form_codes: formCodes,
    rdo_codes: rdoCodes,
    channel: channel as FeedOverride["channel"],
    notice_external_id,
  };
}

/**
 * Reads an already-published feed so this run can decide whether anything
 * changed. Anything unreadable returns null, which simply means "rewrite it".
 */
export function parseFeedDocument(text: string): Feed | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(parsed)) return null;
  if (parsed.schema_version !== 1 || parsed.source_label !== "BIR") return null;
  if (typeof parsed.generated_at_unix !== "number") return null;
  if (!Array.isArray(parsed.notices) || !Array.isArray(parsed.overrides)) return null;

  const notices: FeedNotice[] = [];
  for (const entry of parsed.notices) {
    const notice = parseNotice(entry);
    if (notice === null) return null;
    notices.push(notice);
  }
  const overrides: FeedOverride[] = [];
  for (const entry of parsed.overrides) {
    const override = parseOverride(entry);
    if (override === null) return null;
    overrides.push(override);
  }

  return {
    schema_version: 1,
    generated_at_unix: parsed.generated_at_unix,
    source_label: "BIR",
    notices,
    overrides,
  };
}

function sha256(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function cachePathFor(directory: string, externalId: string, extension: string): string {
  return path.join(directory, `${externalId.replaceAll(":", "-")}${extension}`);
}

type CachedExtraction = {
  pdfSha256: string;
  extraction: CircularExtraction;
};

/**
 * Reads a previous run's extraction result. The cache lives under the
 * gitignored work/ tree, so a fresh CI runner simply misses and re-extracts;
 * a local re-run reuses it and leaves the PDF stages untouched.
 */
async function loadCachedExtraction(
  paths: SyncPaths,
  externalId: string,
  pdfSha256: string,
): Promise<CircularExtraction | null> {
  const text = await readFileOrNull(cachePathFor(paths.extractionCacheDir, externalId, ".json"));
  if (text === null) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(parsed) || parsed.pdfSha256 !== pdfSha256) return null;
  const extraction = parsed.extraction;
  if (!isRecord(extraction) || extraction.externalId !== externalId) return null;
  if (!Array.isArray(extraction.rows) || !Array.isArray(extraction.rdoCodes)) return null;
  if (!Array.isArray(extraction.rdos) || !Array.isArray(extraction.notes)) return null;
  // A cache written before the header-date tier existed has no such field; a
  // miss re-extracts, which is cheaper than publishing an undefined date.
  const headerDate = extraction.headerDateIssued;
  if (headerDate !== null && typeof headerDate !== "string") return null;
  return extraction as unknown as CircularExtraction;
}

async function saveCachedExtraction(paths: SyncPaths, entry: CachedExtraction): Promise<void> {
  await mkdir(paths.extractionCacheDir, { recursive: true });
  await writeFile(
    cachePathFor(paths.extractionCacheDir, entry.extraction.externalId, ".json"),
    `${JSON.stringify(entry, null, 2)}\n`,
    "utf8",
  );
}

function htmlBlobs(datasets: readonly unknown[]): string[] {
  return datasets.map(extractIssuanceHtml).filter((html) => html.trim() !== "");
}

async function readIssuances(
  options: SyncOptions,
  log: Logger,
): Promise<{ records: IssuanceRecord[]; warnings: IssuanceParseWarning[] }> {
  const warnings: IssuanceParseWarning[] = [];
  const year = manilaCivilDate(options.nowUnix).year;

  let widgetDatasets: unknown[];
  // One archive per issuance kind; their rows share a shape, so they are
  // concatenated and parsed by the one archive parser.
  const archiveDatasets: unknown[] = [];
  if (options.offline) {
    log(`fetch: offline — reading committed captures for ${year}`);
    widgetDatasets = await loadFixtureDataset(WIDGET_FIXTURE);
    for (const kind of ARCHIVE_KINDS) {
      const fixture = ARCHIVE_FIXTURES[kind];
      log(`fetch: offline — ${kind} archive from ${fixture}`);
      archiveDatasets.push(...(await loadFixtureDataset(fixture)));
    }
  } else {
    log(`fetch: CMS template ${WIDGET_TEMPLATE_ID} (New Issuances widget)`);
    widgetDatasets = await fetchTemplateDatasets(WIDGET_TEMPLATE_ID);
    for (const kind of ARCHIVE_KINDS) {
      const archiveTemplateId = await discoverYearTemplateId(kind, year);
      log(`fetch: CMS template ${archiveTemplateId} (${year} ${kind} archive)`);
      archiveDatasets.push(...(await fetchTemplateDatasets(archiveTemplateId)));
    }
  }

  const widget = htmlBlobs(widgetDatasets).flatMap((html) =>
    parseWidgetIssuances(html, options.nowUnix, warnings),
  );
  const archive = htmlBlobs(archiveDatasets).flatMap((html) =>
    parseArchiveIssuances(html, options.nowUnix, warnings),
  );
  log(`parse: ${widget.length} widget issuance(s), ${archive.length} archive row(s)`);

  return { records: mergeIssuances(widget, archive), warnings };
}

/** Replaces the run clock with the persisted first sighting for known issuances. */
function applyFirstSeen(
  records: readonly IssuanceRecord[],
  state: SeenState,
  nowUnix: number,
): IssuanceRecord[] {
  return records.map((record) => ({
    ...record,
    firstSeenAtUnix: firstSeenUnix(state, record.externalId) ?? nowUnix,
  }));
}

type ExtractionOutcome = {
  extraction: CircularExtraction;
  pdfSha256: string;
  reused: boolean;
};

/**
 * Resolves one extension circular's layout text and extraction, reusing the
 * cached result when `state/seen.json` proves the PDF has not changed.
 */
async function extractOne(
  issuance: IssuanceRecord,
  options: SyncOptions,
  paths: SyncPaths,
  state: SeenState,
  forced: ReadonlySet<string>,
  log: Logger,
): Promise<ExtractionOutcome | null> {
  let layoutText: string | null = null;
  let pdfSha256: string;

  if (options.offline) {
    layoutText = await loadFixtureLayoutText(issuance.externalId);
    if (layoutText === null) {
      log(`extract: ${issuance.externalId} has no committed layout capture — skipped (offline)`);
      return null;
    }
    // Deliberately distinct from a real PDF hash: a later live run must not
    // treat a fixture-derived digest as proof that the published PDF is known.
    pdfSha256 = `offline-layout:${sha256(layoutText)}`;
  } else {
    if (issuance.pdfUrl === null) {
      log(`extract: ${issuance.externalId} is an extension circular with no PDF link — skipped`);
      return null;
    }
    const downloaded = await downloadPdf(
      issuance.pdfUrl,
      cachePathFor(paths.pdfCacheDir, issuance.externalId, ".pdf"),
    );
    pdfSha256 = downloaded.sha256;
    log(
      `extract: ${issuance.externalId} PDF ${downloaded.bytes} bytes ` +
        `(${downloaded.cached ? "cached" : "downloaded"}) sha256 ${pdfSha256.slice(0, 12)}…`,
    );
  }

  const known = isAlreadyExtracted(state, issuance.externalId, pdfSha256);
  if (known && !forced.has(issuance.externalId)) {
    const cached = await loadCachedExtraction(paths, issuance.externalId, pdfSha256);
    if (cached !== null) {
      log(`extract: ${issuance.externalId} unchanged since the last run — reused extraction`);
      return { extraction: cached, pdfSha256, reused: true };
    }
    log(`extract: ${issuance.externalId} unchanged but its work/ cache is gone — re-extracting`);
  }

  if (layoutText === null) {
    const cachedPdf = cachePathFor(paths.pdfCacheDir, issuance.externalId, ".pdf");
    layoutText = await pdfToLayoutText(cachedPdf);
  }
  const extraction = extractCircular({ issuance, layoutText });
  await saveCachedExtraction(paths, { pdfSha256, extraction });
  log(
    `extract: ${issuance.externalId} -> ${extraction.rdoCodes.length} RDO code(s), ` +
      `${extraction.rows.length} table block(s)` +
      (extraction.needsManualReview ? " — NEEDS MANUAL REVIEW" : ""),
  );
  return { extraction, pdfSha256, reused: false };
}

/**
 * Second date tier: an issuance no archive has dated yet still prints its issue
 * date on page 1 of its PDF. Only extracted circulars have layout text, so this
 * can only ever help a circular the yearly archive has not caught up with.
 */
function applyHeaderDates(
  issuances: readonly IssuanceRecord[],
  extractions: readonly CircularExtraction[],
  log: Logger,
): IssuanceRecord[] {
  const headerDates = new Map<string, string>();
  for (const extraction of extractions) {
    if (extraction.headerDateIssued !== null) {
      headerDates.set(extraction.externalId, extraction.headerDateIssued);
    }
  }

  return issuances.map((issuance) => {
    if (issuance.dateIssued !== null) return issuance;
    const headerDate = headerDates.get(issuance.externalId);
    if (headerDate === undefined) return issuance;
    log(
      `date: ${issuance.externalId} has no archive row — dated ${headerDate} from its ` +
        "PDF page-1 letterhead",
    );
    return { ...issuance, dateIssued: headerDate, dateSource: "pdf_header" };
  });
}

/**
 * Reports where every published date came from, and names each notice that had
 * to fall back to first sighting — a date this pipeline invented, which a human
 * should replace by checking the archive.
 */
export function logDateSources(
  compiled: { feed: Feed; dateSources: ReadonlyMap<string, DateSource> },
  log: Logger,
): number {
  const counts: Record<DateSource, number> = { archive: 0, pdf_header: 0, first_seen: 0 };
  for (const notice of compiled.feed.notices) {
    counts[compiled.dateSources.get(notice.external_id) ?? "first_seen"] += 1;
  }
  log(
    `dates: ${counts.archive} from an archive row, ${counts.pdf_header} from a PDF header, ` +
      `${counts.first_seen} from first sighting`,
  );
  for (const notice of compiled.feed.notices) {
    if ((compiled.dateSources.get(notice.external_id) ?? "first_seen") !== "first_seen") continue;
    log(
      `date: ${notice.external_id} appears in no archive and has no readable PDF header date — ` +
        `published_at is the first-seen fallback ${manilaDateIso(notice.published_at_unix)} PHT ` +
        `(bucket ${notice.month_bucket})`,
    );
  }
  return counts.first_seen;
}

function dropsFor(dropped: readonly DropRecord[], issuance: IssuanceRecord): DropRecord[] {
  const sourceReference = `${issuance.kind} No. ${issuance.number}`;
  return dropped.filter(
    (drop) =>
      drop.detail.includes(sourceReference) || drop.detail.includes(issuance.externalId),
  );
}

function nextFeedRev(state: SeenState): number {
  let highest = 0;
  for (const entry of Object.values(state.issuances)) {
    if (entry.feedRev > highest) highest = entry.feedRev;
  }
  return highest + 1;
}

/**
 * Runs the pipeline. Every write is conditional on a content change, so calling
 * this twice over unchanged sources touches nothing the second time.
 */
export async function runSync(
  options: SyncOptions,
  log: Logger,
  paths: SyncPaths = defaultPaths,
): Promise<SyncSummary> {
  let state = await loadState(paths.statePath);
  // A forced issuance re-runs the PDF stages but keeps its first-seen stamp:
  // re-extraction is not a new sighting, and moving the stamp would move the
  // published timestamp of an issuance the archive has not dated.
  const forced = new Set(options.force);
  for (const externalId of forced) {
    log(
      firstSeenUnix(state, externalId) === null
        ? `force: ${externalId} is not in state/seen.json — it will be extracted anyway`
        : `force: rewinding ${externalId} for re-extraction`,
    );
    await rm(cachePathFor(paths.extractionCacheDir, externalId, ".json"), { force: true });
  }

  const { records, warnings } = await readIssuances(options, log);
  for (const warning of warnings) {
    log(`parse: ${warning.reason} — ${warning.block}`);
  }
  const issuances = applyFirstSeen(records, state, options.nowUnix);
  const newIssuances = issuances.filter(
    (issuance) => firstSeenUnix(state, issuance.externalId) === null,
  );

  const summary: SyncSummary = {
    stage: options.stage,
    offline: options.offline,
    issuanceCount: issuances.length,
    newCount: newIssuances.length,
    skippedCount: 0,
    extractedCount: 0,
    noticeCount: 0,
    overrideCount: 0,
    firstSeenDatedCount: 0,
    feedChanged: false,
    reviewsChanged: 0,
    stateChanged: false,
  };

  if (!stageAtLeast(options.stage, "extract")) {
    log(`issuances: ${issuances.length} total, ${summary.newCount} new`);
    return summary;
  }

  const circulars = issuances.filter((issuance) => isDeadlineExtension(issuance.subject));
  if (circulars.length > 0 && !options.offline) {
    // Fail fast and loudly rather than after a multi-megabyte download.
    await ensurePdftotext();
  }

  const extractions: CircularExtraction[] = [];
  const extractedIds = new Map<string, string>();
  for (const issuance of circulars) {
    const outcome = await extractOne(issuance, options, paths, state, forced, log);
    if (outcome === null) continue;
    extractions.push(outcome.extraction);
    if (outcome.reused) summary.skippedCount += 1;
    else {
      summary.extractedCount += 1;
      extractedIds.set(issuance.externalId, outcome.pdfSha256);
    }
  }
  log(
    `issuances: ${issuances.length} total, ${summary.newCount} new, ` +
      `${summary.skippedCount} skipped (${circulars.length} classified as extension circulars, ` +
      `${summary.extractedCount} extracted)`,
  );

  const datedIssuances = applyHeaderDates(issuances, extractions, log);

  const compiled = compileFeed({
    issuances: datedIssuances,
    extractions,
    generatedAtUnix: options.nowUnix,
  });
  const violations = validateFeed(compiled.feed);
  if (violations.length > 0) {
    throw new Error(
      "compiled feed violates the §4.1 contract; nothing was written:\n  " +
        violations.join("\n  "),
    );
  }
  summary.noticeCount = compiled.feed.notices.length;
  summary.overrideCount = compiled.feed.overrides.length;
  summary.firstSeenDatedCount = logDateSources(compiled, log);

  const issuanceById = new Map(
    datedIssuances.map((issuance) => [issuance.externalId, issuance]),
  );
  for (const extraction of extractions) {
    const issuance = issuanceById.get(extraction.externalId);
    if (issuance === undefined) continue;
    const report = renderReviewReport({
      issuance,
      extraction,
      emitted: compiled.feed.overrides,
      dropped: dropsFor(compiled.dropped, issuance),
    });
    const target = reviewReportPath(paths.reviewDir, extraction.externalId);
    if (await writeIfChanged(target, report)) {
      summary.reviewsChanged += 1;
      log(`review: wrote ${displayPath(target)}`);
    } else {
      log(`review: ${displayPath(target)} unchanged`);
    }
  }

  if (!stageAtLeast(options.stage, "compile")) {
    log("compile: skipped (stage `extract`); feed.json and state/seen.json left untouched");
    return summary;
  }

  const existingText = await readFileOrNull(paths.feedPath);
  const existingFeed = existingText === null ? null : parseFeedDocument(existingText);
  if (existingFeed !== null && feedContentEquals(existingFeed, compiled.feed)) {
    log(
      `feed unchanged — ${summary.noticeCount} notice(s), ${summary.overrideCount} override(s)`,
    );
  } else {
    await writeAtomic(paths.feedPath, serializeFeed(compiled.feed));
    summary.feedChanged = true;
    log(
      `feed: wrote ${displayPath(paths.feedPath)} — ` +
        `${summary.noticeCount} notice(s), ${summary.overrideCount} override(s)`,
    );
  }

  const feedRev = nextFeedRev(state);
  for (const issuance of issuances) {
    const pdfSha256 = extractedIds.get(issuance.externalId);
    if (pdfSha256 === undefined) {
      state = markSeen(state, issuance.externalId, options.nowUnix);
      continue;
    }
    // A re-extraction forced only by a missing work/ cache reproduces the same
    // result from the same bytes, so it is not news: leaving the entry alone
    // keeps state/seen.json out of the publishing diff. `--force` is explicit
    // operator intent and does re-stamp the entry.
    if (
      !forced.has(issuance.externalId) &&
      isAlreadyExtracted(state, issuance.externalId, pdfSha256)
    ) {
      continue;
    }
    state = markExtracted(state, issuance.externalId, pdfSha256, options.nowUnix, feedRev);
  }
  summary.stateChanged = await writeIfChanged(paths.statePath, serializeState(state));
  log(
    summary.stateChanged
      ? `state: wrote ${displayPath(paths.statePath)} (${issuances.length} issuance(s))`
      : "state unchanged",
  );

  for (const drop of compiled.dropped) {
    log(`drop: ${drop.reason} — ${drop.detail}`);
  }

  return summary;
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2), Math.floor(Date.now() / 1000));
  const log: Logger = (line) => process.stdout.write(`news-sync: ${line}\n`);
  const summary = await runSync(options, log);
  log(
    `done (${summary.stage}${summary.offline ? ", offline" : ""}): ` +
      `${summary.newCount} new, ${summary.skippedCount} skipped, ` +
      `${summary.extractedCount} extracted, feed ${summary.feedChanged ? "updated" : "unchanged"}`,
  );
  // Stable, greppable last line: .github/workflows/news-sync.yml reads the
  // counts out of it to build the publishing commit message.
  log(
    `summary new=${summary.newCount} skipped=${summary.skippedCount} ` +
      `extracted=${summary.extractedCount} notices=${summary.noticeCount} ` +
      `overrides=${summary.overrideCount} feed=${summary.feedChanged ? "updated" : "unchanged"} ` +
      `firstseen_dated=${summary.firstSeenDatedCount}`,
  );
}

const invokedPath = process.argv[1];
const isEntrypoint =
  invokedPath !== undefined && path.resolve(invokedPath) === fileURLToPath(import.meta.url);

if (isEntrypoint) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`news-sync: ${message}\n`);
    process.exitCode =
      error instanceof PdftotextUnavailableError ? missingDependencyExitCode : 1;
  });
}
