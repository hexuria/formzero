import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test, { type TestContext } from "node:test";

import {
  ARCHIVE_FIXTURES,
  ARCHIVE_KINDS,
  FIXTURE_DIR,
  KNOWN_YEAR_TEMPLATE_IDS,
  WIDGET_FIXTURE,
  WIDGET_TEMPLATE_ID,
  templateDatasetsUrl,
  yearArchivePageUrl,
  yearTemplateKey,
} from "./cms.ts";
import { manilaMidnightUnix, serializeFeed } from "./feed.ts";
import { emptyState, loadState, markExtracted, saveState } from "./state.ts";
import {
  defaultPaths,
  logDateSources,
  parseArgs,
  parseFeedDocument,
  pathsUnder,
  runSync,
  unchangedAtOrigin,
  type Logger,
  type SyncOptions,
} from "./sync.ts";
import type { CircularExtraction, DateSource, Feed, FeedNotice } from "./types.ts";

// Every run in this file is `--offline` and carries an explicit `--now`, so the
// pipeline reads only committed captures and no assertion depends on a clock.
// The online-shaped runs at the bottom are offline too: their `fetch` is a stub
// over those same captures, and it fails the test if a PDF body is ever GET.
const runOneUnix = 1_786_752_000;
const runTwoUnix = runOneUnix + 86_400;
const runThreeUnix = runOneUnix + 172_800;

/** Log lines are behaviour, not contract; the assertions read files instead. */
const discard: Logger = () => {};

async function scratchRoot(): Promise<string> {
  return await mkdtemp(path.join(tmpdir(), "news-sync-e2e-"));
}

function offlineOptions(nowUnix: number, overrides: Partial<SyncOptions> = {}): SyncOptions {
  return { stage: "all", offline: true, force: [], nowUnix, ...overrides };
}

async function readOrNull(target: string): Promise<string | null> {
  try {
    return await readFile(target, "utf8");
  } catch {
    return null;
  }
}

test("parseArgs defaults to the whole pipeline against the live sources", () => {
  const options = parseArgs([], 1_700_000_000);
  assert.deepEqual(options, {
    stage: "all",
    offline: false,
    force: [],
    nowUnix: 1_700_000_000,
  });
});

test("parseArgs reads the subcommand and every flag", () => {
  const options = parseArgs(
    ["extract", "--offline", "--now", "1786752000", "--force", "bir:rmc:2026:089"],
    0,
  );
  assert.deepEqual(options, {
    stage: "extract",
    offline: true,
    force: ["bir:rmc:2026:089"],
    nowUnix: 1_786_752_000,
  });
});

test("parseArgs rejects nonsense instead of guessing", () => {
  assert.throws(() => parseArgs(["publish"], 0), /unknown subcommand/u);
  assert.throws(() => parseArgs(["--wat"], 0), /unknown flag/u);
  assert.throws(() => parseArgs(["--now"], 0), /--now needs/u);
  assert.throws(() => parseArgs(["--now", "yesterday"], 0), /not a unix timestamp/u);
  assert.throws(() => parseArgs(["--force"], 0), /--force needs/u);
  assert.throws(() => parseArgs(["fetch", "compile"], 0), /second subcommand/u);
});

test("parseFeedDocument round-trips a serialized feed and rejects damage", () => {
  const feed: Feed = {
    schema_version: 1,
    generated_at_unix: runOneUnix,
    source_label: "BIR",
    notices: [
      {
        external_id: "bir:rmc:2026:089",
        kind: "RMC",
        title: "RMC No. 89-2026",
        summary: "Providing Extension of the Deadlines",
        url: null,
        published_at_unix: 1_786_291_200,
        month_bucket: "2026-08",
      },
    ],
    overrides: [],
  };

  const parsed = parseFeedDocument(serializeFeed(feed));
  assert.notEqual(parsed, null);
  assert.deepEqual(parsed, feed);

  assert.equal(parseFeedDocument("{ not json"), null);
  assert.equal(parseFeedDocument('{"schema_version":2}'), null);
  assert.equal(
    parseFeedDocument(JSON.stringify({ ...feed, notices: [{ external_id: 7 }] })),
    null,
  );
});

test("the offline pipeline reproduces Appendix A.3 from the committed captures", async () => {
  const paths = pathsUnder(await scratchRoot());
  const summary = await runSync(offlineOptions(runOneUnix), discard, paths);

  // 8 widget records unioned with the RMC (6), RMO (6) and RR (4) archives.
  assert.equal(summary.issuanceCount, 16);
  assert.equal(summary.newCount, 16);
  assert.equal(summary.extractedCount, 1);
  assert.equal(summary.skippedCount, 0);
  assert.equal(summary.feedChanged, true);
  assert.equal(summary.stateChanged, true);
  assert.equal(summary.reviewsChanged, 1);
  // Every archive row dates its own issuance, so nothing is dated by the clock.
  assert.equal(summary.firstSeenDatedCount, 0);

  const feed = parseFeedDocument(await readFile(paths.feedPath, "utf8"));
  assert.notEqual(feed, null);
  if (feed === null) return;

  assert.equal(feed.schema_version, 1);
  assert.equal(feed.source_label, "BIR");
  assert.equal(feed.generated_at_unix, runOneUnix);

  // Every month bucket the dashboard can switch between.
  assert.equal(feed.notices.length, 16);
  assert.deepEqual(
    [...new Set(feed.notices.map((notice) => notice.month_bucket))].toSorted(),
    ["2026-02", "2026-03", "2026-04", "2026-06", "2026-07", "2026-08"],
  );

  // The defect this run regression-tests: the RMOs used to be stamped with the
  // run clock (2026-08) because only the RMC archive was fetched.
  assert.deepEqual(
    ["bir:rmo:2026:019", "bir:rmo:2026:018", "bir:rmo:2026:017"].map((externalId) => {
      const notice = feed.notices.find((entry) => entry.external_id === externalId);
      return [externalId, notice?.published_at_unix, notice?.month_bucket];
    }),
    [
      ["bir:rmo:2026:019", manilaMidnightUnix("2026-07-23"), "2026-07"],
      ["bir:rmo:2026:018", manilaMidnightUnix("2026-07-23"), "2026-07"],
      ["bir:rmo:2026:017", manilaMidnightUnix("2026-07-08"), "2026-07"],
    ],
  );
  // No notice is dated from this run's clock any more.
  assert.ok(feed.notices.every((notice) => notice.published_at_unix !== runOneUnix));

  const rr4 = feed.notices.find((notice) => notice.external_id === "bir:rr:2026:004");
  assert.equal(rr4?.title, "RR No. 4-2026");
  assert.equal(rr4?.published_at_unix, manilaMidnightUnix("2026-06-22"));

  const rmc89 = feed.notices.find((notice) => notice.external_id === "bir:rmc:2026:089");
  assert.notEqual(rmc89, undefined);
  assert.equal(
    rmc89?.url,
    "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
  );

  // Appendix A.3: two extracted nonefps overrides, each supplemented by the
  // curated record for the rest of its merged table cell. All four are scoped
  // to the 60 emitted RDO strings, and nothing comes from an eFPS-group row.
  assert.equal(feed.overrides.length, 4);
  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    [
      "bir:rmc:2026:089/2026-08-10/nonefps",
      "bir:rmc:2026:089/2026-08-10/nonefps-reviewed",
      "bir:rmc:2026:089/2026-08-15/nonefps",
      "bir:rmc:2026:089/2026-08-15/nonefps-reviewed",
    ],
  );
  assert.deepEqual(feed.overrides[0].form_codes, ["0619E", "0619F", "1601C"]);
  assert.deepEqual(feed.overrides[1].form_codes, [
    "0620",
    "1600PT",
    "1600VT",
    "1606",
    "2200C",
    "2200M",
  ]);
  assert.deepEqual(feed.overrides[2].form_codes, ["1702EX", "1702MX", "1702RT"]);
  assert.deepEqual(feed.overrides[3].form_codes, ["1701Q", "1707A"]);
  for (const override of feed.overrides) {
    assert.equal(override.channel, "nonefps");
    assert.equal(override.adjusted_deadline, "2026-08-17");
    assert.equal(override.source_reference, "RMC No. 89-2026");
    assert.equal(override.notice_external_id, "bir:rmc:2026:089");
    assert.equal(override.rdo_codes.length, 60);
    assert.ok(override.rdo_codes.includes("039"));
  }
  // A curated record inherits its extracted record's scope exactly, so the two
  // can never disagree about who the extension applies to.
  assert.deepEqual(feed.overrides[1].rdo_codes, feed.overrides[0].rdo_codes);
  assert.deepEqual(feed.overrides[3].rdo_codes, feed.overrides[2].rdo_codes);
  assert.equal(feed.overrides[0].original_deadline, "2026-08-10");
  assert.equal(feed.overrides[1].original_deadline, "2026-08-10");
  assert.equal(feed.overrides[2].original_deadline, "2026-08-15");
  assert.equal(feed.overrides[3].original_deadline, "2026-08-15");
  assert.equal(
    feed.overrides[1].title,
    "RMC 89-2026 extension (due 2026-08-10) — curated supplement",
  );
  // No eFPS-group form reaches the feed, curated or not (locked decision L10).
  assert.ok(
    feed.overrides.every((override) => override.channel === "nonefps"),
    "every published override must be non-eFPS",
  );
});

test("the run log accounts for every published date's origin", async () => {
  const paths = pathsUnder(await scratchRoot());
  const lines: string[] = [];
  await runSync(offlineOptions(runOneUnix), (line) => lines.push(line), paths);

  assert.ok(
    lines.includes("dates: 16 from an archive row, 0 from a PDF header, 0 from first sighting"),
    lines.join("\n"),
  );
  // One archive fetch per kind, each named in the log.
  for (const kind of ["RMC", "RMO", "RR"]) {
    assert.ok(
      lines.some((line) => line.startsWith(`fetch: offline — ${kind} archive from `)),
      `no fetch line for the ${kind} archive`,
    );
  }
});

test("a notice with no archive row and no PDF header date is named in the log", () => {
  const notice = (external_id: string, published_at_unix: number): FeedNotice => ({
    external_id,
    kind: "RMC",
    title: "RMC No. 90-2026",
    summary: "",
    url: null,
    published_at_unix,
    month_bucket: "2026-08",
  });
  const feed: Feed = {
    schema_version: 1,
    generated_at_unix: runOneUnix,
    source_label: "BIR",
    notices: [notice("bir:rmc:2026:090", runOneUnix), notice("bir:rmc:2026:089", runOneUnix)],
    overrides: [],
  };
  const dateSources = new Map<string, DateSource>([
    ["bir:rmc:2026:090", "first_seen"],
    ["bir:rmc:2026:089", "archive"],
  ]);

  const lines: string[] = [];
  const firstSeenCount = logDateSources({ feed, dateSources }, (line) => lines.push(line));

  assert.equal(firstSeenCount, 1);
  assert.equal(lines[0], "dates: 1 from an archive row, 0 from a PDF header, 1 from first sighting");
  assert.equal(lines.length, 2);
  assert.match(lines[1], /^date: bir:rmc:2026:090 appears in no archive/u);
  assert.match(lines[1], /first-seen fallback 2026-08-15 PHT \(bucket 2026-08\)/u);
});

test("the review report lists the window and eFPS rows that produced no override", async () => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);

  const reports = await readdir(paths.reviewDir);
  assert.deepEqual(reports, ["bir-rmc-2026-089.md"]);
  const report = await readFile(path.join(paths.reviewDir, reports[0]), "utf8");

  assert.match(report, /^# Review — RMC No\. 89-2026$/mu);
  assert.match(report, /## Dropped \/ needs review/u);
  assert.match(report, /`window_row`/u);
  // eFPS Group E/D/B print a date pair but never become overrides (decision L10).
  assert.match(report, /`channel_not_emittable` \(efps_group_e, same_line\)/u);
  assert.match(report, /`channel_not_emittable` \(efps_group_d, same_line\)/u);
  assert.match(report, /`channel_not_emittable` \(efps_group_b, same_line\)/u);
  assert.match(report, /bir:rmc:2026:089\/2026-08-10\/nonefps/u);
});

test("a second run over unchanged sources rewrites nothing, even on a later clock", async () => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);

  const feedBefore = await readFile(paths.feedPath, "utf8");
  const stateBefore = await readFile(paths.statePath, "utf8");
  const reportPath = path.join(paths.reviewDir, "bir-rmc-2026-089.md");
  const reportBefore = await readFile(reportPath, "utf8");

  const second = await runSync(offlineOptions(runTwoUnix), discard, paths);

  assert.equal(second.newCount, 0);
  assert.equal(second.skippedCount, 1);
  assert.equal(second.extractedCount, 0);
  assert.equal(second.feedChanged, false);
  assert.equal(second.stateChanged, false);
  assert.equal(second.reviewsChanged, 0);

  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);
  assert.equal(await readFile(paths.statePath, "utf8"), stateBefore);
  assert.equal(await readFile(reportPath, "utf8"), reportBefore);
  // The published generated_at_unix is the one from the run that last changed
  // the content, not this run's clock.
  assert.match(feedBefore, new RegExp(`"generated_at_unix": ${runOneUnix}`, "u"));
});

test("losing the work/ cache re-extracts without disturbing the published output", async () => {
  const root = await scratchRoot();
  const paths = pathsUnder(root);
  await runSync(offlineOptions(runOneUnix), discard, paths);
  const feedBefore = await readFile(paths.feedPath, "utf8");
  const stateBefore = await readFile(paths.statePath, "utf8");

  await rm(path.join(root, "work"), { recursive: true, force: true });

  const third = await runSync(offlineOptions(runTwoUnix), discard, paths);
  assert.equal(third.extractedCount, 1);
  assert.equal(third.feedChanged, false);
  assert.equal(third.stateChanged, false);
  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);
  assert.equal(await readFile(paths.statePath, "utf8"), stateBefore);
});

test("the fetch stage writes nothing", async () => {
  const paths = pathsUnder(await scratchRoot());
  const summary = await runSync(
    offlineOptions(runOneUnix, { stage: "fetch" }),
    discard,
    paths,
  );

  assert.equal(summary.issuanceCount, 16);
  assert.equal(summary.newCount, 16);
  assert.equal(summary.noticeCount, 0);
  assert.equal(await readOrNull(paths.feedPath), null);
  assert.equal(await readOrNull(paths.statePath), null);
});

test("the extract stage writes the review report but never the feed or state", async () => {
  const paths = pathsUnder(await scratchRoot());
  const summary = await runSync(
    offlineOptions(runOneUnix, { stage: "extract" }),
    discard,
    paths,
  );

  assert.equal(summary.reviewsChanged, 1);
  assert.equal(summary.feedChanged, false);
  assert.equal(summary.stateChanged, false);
  assert.notEqual(await readOrNull(path.join(paths.reviewDir, "bir-rmc-2026-089.md")), null);
  assert.equal(await readOrNull(paths.feedPath), null);
  assert.equal(await readOrNull(paths.statePath), null);
});

test("--force re-extracts a known issuance without making it new again", async () => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);
  const feedBefore = await readFile(paths.feedPath, "utf8");

  const forcedRun = await runSync(
    offlineOptions(runTwoUnix, { force: ["bir:rmc:2026:089"] }),
    discard,
    paths,
  );

  assert.equal(forcedRun.newCount, 0);
  assert.equal(forcedRun.skippedCount, 0);
  assert.equal(forcedRun.extractedCount, 1);
  assert.equal(forcedRun.feedChanged, false);
  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);

  // The extraction stamp moves; the first sighting does not.
  const state = JSON.parse(await readFile(paths.statePath, "utf8")) as {
    issuances: Record<string, { firstSeenAtUnix: number; extractedAtUnix: number }>;
  };
  assert.equal(state.issuances["bir:rmc:2026:089"].firstSeenAtUnix, runOneUnix);
  assert.equal(state.issuances["bir:rmc:2026:089"].extractedAtUnix, runTwoUnix);
});

// ---------------------------------------------------------------------------
// Online-shaped runs. `fetch` is stubbed over the committed captures, so these
// stay offline; the point of them is what the pipeline does *not* request.

const rmc89Id = "bir:rmc:2026:089";
const rmc89PdfUrl = "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf";
/** Size the origin serves RMC 89-2026 at, as a completed live run recorded it. */
const rmc89PdfBytes = 4_242_017;
const rmc89PdfSha = "59bba7e9a114cbf7714903fa06513d00fb8113083ecba96dfa01f138cc5134e9";
/**
 * The other extension circular in the captures. It is a textless scan, so a
 * live run records the same empty extraction the work/ cache holds today; it
 * has no committed layout capture, so an offline run never reaches it.
 */
const rr1Id = "bir:rr:2026:001";
const rr1PdfUrl = "https://bir-cdn.bir.gov.ph/BIR/pdf/RR%20No.%201-2026.pdf";
const rr1PdfBytes = 1_004_733;
const rr1PdfSha = "8d9d5fa0e9a374efa4aa2238820991265b85f8b69eb9ca740d12e973b59d8e1d";
const rr1Extraction: CircularExtraction = {
  externalId: rr1Id,
  headerDateIssued: null,
  globalExtendedDate: null,
  window: null,
  statedOfficeCount: null,
  rdos: [],
  rdoCodes: [],
  rows: [],
  needsManualReview: true,
  notes: ["text layer unusable: 0 characters over 3 page(s)"],
};

type FetchCall = { method: string; url: string };

function installFetchStub(
  t: TestContext,
  handler: (method: string, url: string) => Response,
): FetchCall[] {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = original;
  });
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url =
      typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const method = (init?.method ?? "GET").toUpperCase();
    calls.push({ method, url });
    return Promise.resolve(handler(method, url));
  }) as typeof fetch;
  return calls;
}

/** Every CMS response a live run makes, served from the committed captures. */
async function cmsFixtureBodies(): Promise<Map<string, string>> {
  const bodies = new Map<string, string>();
  bodies.set(
    templateDatasetsUrl(WIDGET_TEMPLATE_ID),
    await readFile(path.join(FIXTURE_DIR, WIDGET_FIXTURE), "utf8"),
  );
  for (const kind of ARCHIVE_KINDS) {
    const templateId = KNOWN_YEAR_TEMPLATE_IDS.get(yearTemplateKey(kind, 2026));
    assert.ok(templateId !== undefined);
    bodies.set(
      templateDatasetsUrl(templateId),
      await readFile(path.join(FIXTURE_DIR, ARCHIVE_FIXTURES[kind]), "utf8"),
    );
    bodies.set(
      yearArchivePageUrl(kind, 2026),
      `<script>{"code":"${templateId}","dataMapper":{"content":"Content"}}</script>`,
    );
  }
  return bodies;
}

function headResponse(contentLength: number | null): Response {
  return new Response(null, {
    status: 200,
    headers: contentLength === null ? {} : { "content-length": String(contentLength) },
  });
}

/** Every PDF request the run made, in order, as `"<METHOD> <id>"`. */
function pdfRequests(calls: readonly FetchCall[]): string[] {
  const ids = new Map([
    [rmc89PdfUrl, rmc89Id],
    [rr1PdfUrl, rr1Id],
  ]);
  return calls
    .filter((call) => ids.has(call.url))
    .map((call) => `${call.method} ${ids.get(call.url)}`);
}

/**
 * Rewrites the state an offline run wrote so it reads like the state a
 * completed live run publishes: for every extension circular in the captures,
 * a real PDF hash and the size the origin served it at, over the extraction
 * that PDF produced.
 */
async function recordAsLiveDownload(statePath: string): Promise<void> {
  let state = await loadState(statePath);
  const entry = state.issuances[rmc89Id];
  assert.notEqual(entry.extraction, null, "a run must persist the extraction it published");
  state = markExtracted(
    state,
    rmc89Id,
    { pdfSha256: rmc89PdfSha, pdfBytes: rmc89PdfBytes, extraction: entry.extraction },
    entry.extractedAtUnix,
    entry.feedRev,
  );
  state = markExtracted(
    state,
    rr1Id,
    { pdfSha256: rr1PdfSha, pdfBytes: rr1PdfBytes, extraction: rr1Extraction },
    entry.extractedAtUnix,
    entry.feedRev,
  );
  await saveState(statePath, state);
}

/** A stub that serves the CMS captures and HEAD, and fails on any PDF body. */
function onlineHandler(
  bodies: ReadonlyMap<string, string>,
  sizes: ReadonlyMap<string, number>,
): (method: string, url: string) => Response {
  return (method, url) => {
    const body = bodies.get(url);
    if (body !== undefined) return new Response(body, { status: 200 });
    const size = sizes.get(url);
    if (size === undefined) assert.fail(`unexpected request ${method} ${url}`);
    if (method !== "HEAD") {
      assert.fail(`${method} ${url}: an unchanged PDF must never be downloaded again`);
    }
    return headResponse(size);
  };
}

function onlineOptions(nowUnix: number): SyncOptions {
  return { stage: "all", offline: false, force: [], nowUnix };
}

test("an online run re-downloads nothing when the origin reports the recorded size", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);
  await recordAsLiveDownload(paths.statePath);
  const feedBefore = await readFile(paths.feedPath, "utf8");
  const stateBefore = await readFile(paths.statePath, "utf8");
  const reportPath = path.join(paths.reviewDir, "bir-rmc-2026-089.md");
  const reportBefore = await readFile(reportPath, "utf8");

  const calls = installFetchStub(
    t,
    onlineHandler(
      await cmsFixtureBodies(),
      new Map([
        [rmc89PdfUrl, rmc89PdfBytes],
        [rr1PdfUrl, rr1PdfBytes],
      ]),
    ),
  );

  const online = await runSync(onlineOptions(runTwoUnix), discard, paths);

  assert.equal(online.skippedCount, 2);
  assert.equal(online.extractedCount, 0);
  assert.equal(online.overrideCount, 4);
  assert.equal(online.feedChanged, false);
  assert.equal(online.stateChanged, false);
  // One HEAD per circular and not one body: 4.2 MB not spent, and every
  // extension still published.
  assert.deepEqual(pdfRequests(calls), [`HEAD ${rmc89Id}`, `HEAD ${rr1Id}`]);
  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);
  assert.equal(await readFile(paths.statePath, "utf8"), stateBefore);
  assert.equal(await readFile(reportPath, "utf8"), reportBefore);

  // A second consecutive online run is download-free for the same reason, and
  // now rewrites nothing at all.
  const second = await runSync(onlineOptions(runThreeUnix), discard, paths);
  assert.equal(second.skippedCount, 2);
  assert.equal(second.extractedCount, 0);
  assert.equal(second.overrideCount, 4);
  assert.equal(second.feedChanged, false);
  assert.equal(second.stateChanged, false);
  assert.equal(second.reviewsChanged, 0);
  assert.deepEqual(pdfRequests(calls), [
    `HEAD ${rmc89Id}`,
    `HEAD ${rr1Id}`,
    `HEAD ${rmc89Id}`,
    `HEAD ${rr1Id}`,
  ]);
  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);
  assert.equal(await readFile(paths.statePath, "utf8"), stateBefore);
});

test("unchangedAtOrigin skips only on a HEAD that matches the recorded size", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);
  await recordAsLiveDownload(paths.statePath);
  const state = await loadState(paths.statePath);

  let head: () => Response = () => headResponse(rmc89PdfBytes);
  const calls = installFetchStub(t, (method, url) => {
    assert.equal(method, "HEAD", `${method} ${url}: the decision may only ever issue a HEAD`);
    return head();
  });
  const decide = async (): Promise<unknown> =>
    await unchangedAtOrigin(rmc89Id, rmc89PdfUrl, state, discard);

  // The one case that skips: same size at the origin.
  const unchanged = await decide();
  assert.notEqual(unchanged, null);
  assert.deepEqual(unchanged, {
    pdfSha256: rmc89PdfSha,
    pdfBytes: rmc89PdfBytes,
    extraction: state.issuances[rmc89Id].extraction,
  });

  // Every other answer degrades to downloading, never to assuming unchanged.
  head = () => headResponse(rmc89PdfBytes + 1);
  assert.equal(await decide(), null, "a changed Content-Length must force a re-download");
  head = () => headResponse(null);
  assert.equal(await decide(), null, "a HEAD without Content-Length must force a re-download");
  head = () => new Response(null, { status: 405 });
  assert.equal(await decide(), null, "a server that refuses HEAD must force a re-download");
  head = () => {
    throw new Error("connection reset by peer");
  };
  assert.equal(await decide(), null, "a failed HEAD must force a re-download");
  assert.equal(calls.length, 5);

  // With nothing recorded there is nothing to compare, and no HEAD is worth
  // sending: the run has to download and extract either way.
  head = () => headResponse(rmc89PdfBytes);
  const withoutExtraction = markExtracted(
    emptyState(),
    rmc89Id,
    { pdfSha256: rmc89PdfSha, pdfBytes: rmc89PdfBytes, extraction: null },
    runOneUnix,
    1,
  );
  assert.equal(await unchangedAtOrigin(rmc89Id, rmc89PdfUrl, withoutExtraction, discard), null);
  assert.equal(await unchangedAtOrigin(rmc89Id, rmc89PdfUrl, emptyState(), discard), null);
  assert.equal(calls.length, 5, "an unusable state record must not even ask the origin");
});

test("a run that skips the download still publishes the circular's overrides", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);
  await recordAsLiveDownload(paths.statePath);

  // Delete everything the run could otherwise fall back on: the work/ caches
  // and the previously published feed. Only state/seen.json survives, exactly
  // as on a fresh CI runner.
  await rm(path.join(paths.pdfCacheDir, ".."), { recursive: true, force: true });
  await rm(paths.feedPath, { force: true });

  const calls = installFetchStub(
    t,
    onlineHandler(
      await cmsFixtureBodies(),
      new Map([
        [rmc89PdfUrl, rmc89PdfBytes],
        [rr1PdfUrl, rr1PdfBytes],
      ]),
    ),
  );

  const online = await runSync(onlineOptions(runTwoUnix), discard, paths);

  assert.equal(online.skippedCount, 2);
  assert.equal(online.feedChanged, true, "the feed was deleted, so it has to be rewritten");
  assert.deepEqual(pdfRequests(calls), [`HEAD ${rmc89Id}`, `HEAD ${rr1Id}`]);

  const feed = parseFeedDocument(await readFile(paths.feedPath, "utf8"));
  assert.notEqual(feed, null);
  if (feed === null) return;
  // The skip must never cost an override: this is the failure the design is
  // built to prevent.
  assert.equal(feed.overrides.length, 4);
  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    [
      `${rmc89Id}/2026-08-10/nonefps`,
      `${rmc89Id}/2026-08-10/nonefps-reviewed`,
      `${rmc89Id}/2026-08-15/nonefps`,
      `${rmc89Id}/2026-08-15/nonefps-reviewed`,
    ],
  );
  for (const override of feed.overrides) assert.equal(override.rdo_codes.length, 60);
});

test("the committed output paths are the ones the plan documents", () => {
  assert.equal(path.basename(defaultPaths.feedPath), "feed.json");
  assert.equal(path.basename(path.dirname(defaultPaths.feedPath)), "feed");
  assert.equal(path.basename(defaultPaths.statePath), "seen.json");
  assert.equal(path.basename(path.dirname(defaultPaths.statePath)), "state");
  assert.equal(path.basename(defaultPaths.reviewDir), "review");
  assert.equal(path.basename(path.dirname(defaultPaths.pdfCacheDir)), "work");
});

/** Serves the CMS captures; refuses every PDF request with `status`. */
function refusingHandler(
  bodies: ReadonlyMap<string, string>,
  refused: ReadonlySet<string>,
  status: number,
): (method: string, url: string) => Response {
  return (method, url) => {
    const body = bodies.get(url);
    if (body !== undefined) return new Response(body, { status: 200 });
    if (!refused.has(url)) assert.fail(`unexpected request ${method} ${url}`);
    return new Response("AccessDenied", { status, statusText: "Forbidden" });
  };
}

test("a refused PDF falls back to the recorded extraction and still publishes", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  await runSync(offlineOptions(runOneUnix), discard, paths);
  await recordAsLiveDownload(paths.statePath);
  const feedBefore = await readFile(paths.feedPath, "utf8");

  // bir-cdn has answered 403 to a URL it served minutes earlier. Both the HEAD
  // and the GET are refused, which is the shape that used to end the run.
  installFetchStub(
    t,
    refusingHandler(
      await cmsFixtureBodies(),
      new Set([rmc89PdfUrl, rr1PdfUrl]),
      403,
    ),
  );

  const run = await runSync(onlineOptions(runTwoUnix), discard, paths);

  assert.equal(run.reusedAfterFetchError, 2);
  assert.equal(run.unavailableCount, 0);
  assert.equal(run.extractedCount, 0);
  // The whole point: RMC 89-2026's extensions still reach the feed.
  assert.equal(run.overrideCount, 4);
  assert.equal(run.feedChanged, false);
  assert.equal(await readFile(paths.feedPath, "utf8"), feedBefore);
});

test("a refused PDF this run has never read drops that circular and keeps going", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  installFetchStub(
    t,
    refusingHandler(
      await cmsFixtureBodies(),
      new Set([rmc89PdfUrl, rr1PdfUrl]),
      403,
    ),
  );

  // No prior state, so nothing can be reused: the run must still finish and
  // publish its notices rather than failing outright.
  const lines: string[] = [];
  const run = await runSync(onlineOptions(runOneUnix), (line) => lines.push(line), paths);

  assert.equal(run.unavailableCount, 2);
  assert.equal(run.reusedAfterFetchError, 0);
  assert.equal(run.overrideCount, 0);
  assert.ok(run.noticeCount > 0, "notices publish even when every circular is refused");

  // A circular that was never read has no review report of its own, so the run
  // log is where a reader learns the extension was missed rather than absent.
  const log = lines.join("\n");
  assert.match(log, /PDF unavailable/);
  assert.match(log, /pdf_unavailable/);
});

test("a failure that is not the origin refusing still ends the run", async (t) => {
  const paths = pathsUnder(await scratchRoot());
  const bodies = await cmsFixtureBodies();
  installFetchStub(t, (_method, url) => {
    const body = bodies.get(url);
    if (body !== undefined) return new Response(body, { status: 200 });
    throw new RangeError("not a network refusal");
  });

  await assert.rejects(
    runSync(onlineOptions(runOneUnix), discard, paths),
    /not a network refusal/,
    "only PdfUnavailableError is absorbed; every other fault fails the run",
  );
});
