import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { manilaMidnightUnix, serializeFeed } from "./feed.ts";
import {
  defaultPaths,
  logDateSources,
  parseArgs,
  parseFeedDocument,
  pathsUnder,
  runSync,
  type Logger,
  type SyncOptions,
} from "./sync.ts";
import type { DateSource, Feed, FeedNotice } from "./types.ts";

// Every run in this file is `--offline` and carries an explicit `--now`, so the
// pipeline reads only committed captures and no assertion depends on a clock.
const runOneUnix = 1_786_752_000;
const runTwoUnix = runOneUnix + 86_400;

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

  // Appendix A.3: exactly two nonefps overrides, both scoped to the 60 emitted
  // RDO strings, and nothing from an eFPS-group row.
  assert.equal(feed.overrides.length, 2);
  assert.deepEqual(
    feed.overrides.map((override) => override.external_ref),
    ["bir:rmc:2026:089/2026-08-10/nonefps", "bir:rmc:2026:089/2026-08-15/nonefps"],
  );
  assert.deepEqual(feed.overrides[0].form_codes, ["0619E", "0619F", "1601C"]);
  assert.deepEqual(feed.overrides[1].form_codes, ["1702EX", "1702MX", "1702RT"]);
  for (const override of feed.overrides) {
    assert.equal(override.channel, "nonefps");
    assert.equal(override.adjusted_deadline, "2026-08-17");
    assert.equal(override.source_reference, "RMC No. 89-2026");
    assert.equal(override.notice_external_id, "bir:rmc:2026:089");
    assert.equal(override.rdo_codes.length, 60);
    assert.ok(override.rdo_codes.includes("039"));
  }
  assert.equal(feed.overrides[0].original_deadline, "2026-08-10");
  assert.equal(feed.overrides[1].original_deadline, "2026-08-15");
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

test("the committed output paths are the ones the plan documents", () => {
  assert.equal(path.basename(defaultPaths.feedPath), "feed.json");
  assert.equal(path.basename(path.dirname(defaultPaths.feedPath)), "feed");
  assert.equal(path.basename(defaultPaths.statePath), "seen.json");
  assert.equal(path.basename(path.dirname(defaultPaths.statePath)), "state");
  assert.equal(path.basename(defaultPaths.reviewDir), "review");
  assert.equal(path.basename(path.dirname(defaultPaths.pdfCacheDir)), "work");
});
