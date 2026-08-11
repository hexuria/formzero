import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  ARCHIVE_FIXTURES,
  ARCHIVE_KINDS,
  ARCHIVE_PAGE_FIXTURE,
  CMS_REQUEST_HEADERS,
  FIXTURE_DIR,
  KNOWN_YEAR_TEMPLATE_IDS,
  WIDGET_FIXTURE,
  WIDGET_TEMPLATE_ID,
  datasetsFromPayload,
  discoverYearTemplateId,
  extractYearTemplateId,
  fetchTemplateDatasets,
  loadFixtureDataset,
  templateDatasetsUrl,
  yearArchivePageUrl,
  yearTemplateKey,
} from "./cms.ts";
import { extractIssuanceHtml } from "./issuances.ts";

const networkEnabled = process.env.NEWS_SYNC_NETWORK === "1";

/** The verbatim RSC excerpt captured from the live 2026 RMO archive page. */
async function archivePageFixture(): Promise<string> {
  return await readFile(path.join(FIXTURE_DIR, ARCHIVE_PAGE_FIXTURE), "utf8");
}

type FetchCall = { url: string; headers: Record<string, string> };
type FetchArgs = Parameters<typeof globalThis.fetch>;

// Replaces global fetch with a scripted responder so the error paths are
// exercised without a network round trip. Returns the recorded calls.
async function withStubbedFetch(
  responder: (url: string) => Response,
  body: () => Promise<void>,
): Promise<FetchCall[]> {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: FetchArgs[0], init?: FetchArgs[1]): Promise<Response> => {
    const url = typeof input === "string" ? input : String(input);
    calls.push({ url, headers: { ...((init?.headers ?? {}) as Record<string, string>) } });
    return responder(url);
  }) as typeof globalThis.fetch;
  try {
    await body();
  } finally {
    globalThis.fetch = original;
  }
  return calls;
}

test("the request contract matches the headers verified in CAPTURES.md", () => {
  assert.deepEqual({ ...CMS_REQUEST_HEADERS }, {
    "client-website-id": "2",
    origin: "https://www.bir.gov.ph",
    "user-agent": "buwiz-news-sync/1.0",
  });
  assert.equal(WIDGET_TEMPLATE_ID, 9);
  assert.equal(
    templateDatasetsUrl(9),
    "https://bir-cms-ws.bir.gov.ph/api/pub/templates/9/datasets?per_page=3000",
  );
  assert.equal(
    yearArchivePageUrl("RMC", 2026),
    "https://www.bir.gov.ph/2026-Revenue-Memorandum-Circulars",
  );
});

test("each archive kind derives its own year page slug", () => {
  assert.deepEqual([...ARCHIVE_KINDS], ["RMC", "RMO", "RR"]);
  assert.equal(
    yearArchivePageUrl("RMO", 2026),
    "https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders",
  );
  assert.equal(yearArchivePageUrl("RR", 2026), "https://www.bir.gov.ph/2026-Revenue-Regulations");
  // The slug comes from the kind, so a rollover needs no new slug entry.
  assert.equal(
    yearArchivePageUrl("RMO", 2027),
    "https://www.bir.gov.ph/2027-Revenue-Memorandum-Orders",
  );
});

test("the checked-in template-id fallback map covers every 2026 archive", () => {
  assert.equal(KNOWN_YEAR_TEMPLATE_IDS.get(yearTemplateKey("RMC", 2026)), 3752);
  assert.equal(KNOWN_YEAR_TEMPLATE_IDS.get(yearTemplateKey("RMO", 2026)), 3753);
  assert.equal(KNOWN_YEAR_TEMPLATE_IDS.get(yearTemplateKey("RR", 2026)), 3754);
  for (const kind of ARCHIVE_KINDS) {
    assert.ok(
      KNOWN_YEAR_TEMPLATE_IDS.has(yearTemplateKey(kind, 2026)),
      `no 2026 fallback template id for ${kind}`,
    );
  }
});

test("extractYearTemplateId reads the id out of the served RSC payload", () => {
  const html =
    '<script>self.__next_f.push([1,"…{\\"code\\":\\"3628\\"}…' +
    '{"code":"3752","dataMapper":{"content":"Content"},"name":"2026 RMC"}…"])</script>';
  assert.equal(extractYearTemplateId(html), 3752);
});

test("extractYearTemplateId reads the BACKSLASH-ESCAPED form the live page serves", async () => {
  const html = await archivePageFixture();

  // The regression this fixture exists for: the marker only ever arrives inside
  // a JS string literal, so every quote is escaped. A pattern that matches only
  // the bare form finds nothing here and discovery silently never runs.
  assert.ok(
    html.includes('\\"code\\":\\"3753\\",\\"dataMapper\\":{\\"content\\":\\"Content\\"}'),
    "the committed capture must keep the escaped marker verbatim",
  );
  assert.ok(
    !/"code":"\d/u.test(html),
    "the live page carries no unescaped marker at all",
  );

  assert.equal(extractYearTemplateId(html), 3753);
});

test("extractYearTemplateId returns null when the marker is absent or reshaped", () => {
  assert.equal(extractYearTemplateId("<html><body>no datasets here</body></html>"), null);
  assert.equal(extractYearTemplateId('{"code":"3752","dataMapper":{"content":"Issuance"}}'), null);
  assert.equal(
    extractYearTemplateId('\\"code\\":\\"3752\\",\\"dataMapper\\":{\\"content\\":\\"Issuance\\"}'),
    null,
  );
});

test("fetchTemplateDatasets fails fast on 403 and names the header contract", async () => {
  let thrown: unknown = null;
  const calls = await withStubbedFetch(
    () => new Response('{"error":"forbidden"}', { status: 403 }),
    async () => {
      thrown = await fetchTemplateDatasets(WIDGET_TEMPLATE_ID).then(
        () => null,
        (error: unknown) => error,
      );
    },
  );

  assert.ok(thrown instanceof Error);
  assert.match(thrown.message, /403/u);
  assert.match(thrown.message, /client-website-id/u);
  assert.match(thrown.message, /CAPTURES\.md/u);
  // A 403 is a contract change, never a transient failure: exactly one attempt.
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].headers, { ...CMS_REQUEST_HEADERS });
  assert.equal(calls[0].url, templateDatasetsUrl(WIDGET_TEMPLATE_ID));
});

test("fetchTemplateDatasets does not retry other 4xx responses", async () => {
  let thrown: unknown = null;
  const calls = await withStubbedFetch(
    () => new Response("nope", { status: 404, statusText: "Not Found" }),
    async () => {
      thrown = await fetchTemplateDatasets(1234).then(
        () => null,
        (error: unknown) => error,
      );
    },
  );
  assert.ok(thrown instanceof Error);
  assert.match(thrown.message, /HTTP 404/u);
  assert.equal(calls.length, 1);
});

test("fetchTemplateDatasets returns the data array on success", async () => {
  await withStubbedFetch(
    () => new Response('{"data":[{"id":1}],"meta":{}}', { status: 200 }),
    async () => {
      const datasets = await fetchTemplateDatasets(WIDGET_TEMPLATE_ID);
      assert.deepEqual(datasets, [{ id: 1 }]);
    },
  );
});

/** Runs `body` with stderr captured, so a fallback warning is observable. */
async function withCapturedStderr(body: () => Promise<void>): Promise<string[]> {
  const originalWrite = process.stderr.write.bind(process.stderr);
  const warnings: string[] = [];
  process.stderr.write = ((chunk: string | Uint8Array): boolean => {
    warnings.push(String(chunk));
    return true;
  }) as typeof process.stderr.write;
  try {
    await body();
  } finally {
    process.stderr.write = originalWrite;
  }
  return warnings;
}

test("discoverYearTemplateId reads the real served page without any fallback", async () => {
  const html = await archivePageFixture();
  let calls: FetchCall[] = [];

  const warnings = await withCapturedStderr(async () => {
    calls = await withStubbedFetch(
      () => new Response(html, { status: 200 }),
      async () => {
        assert.equal(await discoverYearTemplateId("RMO", 2026), 3753);
      },
    );
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders");
  assert.deepEqual(calls[0].headers, { ...CMS_REQUEST_HEADERS });
  // The point of the regression test: discovery answered from the HTML itself,
  // so the checked-in map was never consulted and nothing warned.
  assert.deepEqual(warnings, []);
});

test("discoverYearTemplateId falls back to the checked-in id when discovery fails", async () => {
  const warnings = await withCapturedStderr(async () => {
    await withStubbedFetch(
      () => new Response("<html>redesigned page</html>", { status: 200 }),
      async () => {
        assert.equal(await discoverYearTemplateId("RMC", 2026), 3752);
        assert.equal(await discoverYearTemplateId("RMO", 2026), 3753);
        assert.equal(await discoverYearTemplateId("RR", 2026), 3754);
      },
    );
  });

  assert.equal(warnings.length, 3);
  assert.match(warnings[0], /discovery for 2026 RMC failed/u);
  assert.match(warnings[0], /falling back to the checked-in id 3752/u);
  assert.match(warnings[1], /discovery for 2026 RMO failed/u);
  assert.match(warnings[1], /falling back to the checked-in id 3753/u);
  assert.match(warnings[2], /falling back to the checked-in id 3754/u);
});

test("discoverYearTemplateId throws for a year with neither discovery nor fallback", async () => {
  await withStubbedFetch(
    () => new Response("<html>redesigned page</html>", { status: 200 }),
    async () => {
      await assert.rejects(
        discoverYearTemplateId("RMC", 2031),
        /cannot resolve the 2031 RMC archive template id/u,
      );
      await assert.rejects(
        discoverYearTemplateId("RR", 2031),
        /Add "RR:2031" to KNOWN_YEAR_TEMPLATE_IDS/u,
      );
    },
  );
});

test("datasetsFromPayload rejects bodies that lost their data array", () => {
  assert.throws(() => datasetsFromPayload(null, "probe"), /not a JSON object/u);
  assert.throws(() => datasetsFromPayload({ items: [] }, "probe"), /no "data" array/u);
  assert.deepEqual(datasetsFromPayload({ data: [] }, "probe"), []);
});

test("loadFixtureDataset serves every committed capture without the network", async () => {
  const widget = await loadFixtureDataset(WIDGET_FIXTURE);
  assert.equal(widget.length, 1);
  assert.match(extractIssuanceHtml(widget[0]), /Revenue Memorandum Circular No\. 089-2026/u);

  for (const kind of ARCHIVE_KINDS) {
    const archive = await loadFixtureDataset(ARCHIVE_FIXTURES[kind]);
    assert.equal(archive.length, 1, `${kind} archive fixture`);
    assert.match(extractIssuanceHtml(archive[0]), /NO\. OF ISSUANCE/u);
  }

  // Each fixture is the capture of the template id the fallback map records.
  assert.match(ARCHIVE_FIXTURES.RMC, /template-3752/u);
  assert.match(ARCHIVE_FIXTURES.RMO, /template-3753/u);
  assert.match(ARCHIVE_FIXTURES.RR, /template-3754/u);
});

test("loadFixtureDataset reports a missing capture by path", async () => {
  await assert.rejects(loadFixtureDataset("not-a-capture.json"), /ENOENT/u);
});

test(
  "live CMS widget template still answers with the documented contract",
  { skip: networkEnabled ? false : "set NEWS_SYNC_NETWORK=1 to exercise the network" },
  async () => {
    const datasets = await fetchTemplateDatasets(WIDGET_TEMPLATE_ID);
    assert.ok(datasets.length >= 1);
    assert.match(extractIssuanceHtml(datasets[0]), /Revenue Memorandum/u);
  },
);

test(
  "live template-id discovery finds every 2026 archive template",
  { skip: networkEnabled ? false : "set NEWS_SYNC_NETWORK=1 to exercise the network" },
  async () => {
    const warnings = await withCapturedStderr(async () => {
      assert.equal(await discoverYearTemplateId("RMC", 2026), 3752);
      assert.equal(await discoverYearTemplateId("RMO", 2026), 3753);
      assert.equal(await discoverYearTemplateId("RR", 2026), 3754);
    });
    // Every id came from the live HTML; none was a silent fallback.
    assert.deepEqual(warnings, []);
  },
);
