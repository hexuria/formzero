import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  countLayoutPages,
  ensurePdftotext,
  hasUsableTextLayer,
  loadFixtureLayoutText,
  minimumCharactersPerPage,
  missingDependencyExitCode,
  remotePdfIdentity,
  pdfToLayoutText,
  sha256File,
} from "./pdf.ts";

// The default run is offline and does not shell out to poppler: it exercises
// the pure text-layer policy against the committed
// fixtures/2026-08-11/rmc-89-2026-pdftotext-layout.txt. Set
// NEWS_SYNC_NETWORK=1 to additionally smoke-test the pdftotext invocation.
const runsBinaryChecks = process.env.NEWS_SYNC_NETWORK === "1";

const rmc89 = "bir:rmc:2026:089";

test("loadFixtureLayoutText returns the committed RMC 89-2026 layout capture", async () => {
  const text = await loadFixtureLayoutText(rmc89);
  assert.ok(text !== null);
  assert.match(text, /REVENUE MEMORANDUM CIRCULAR NO\.\s+089-2026/u);
  assert.match(text, /RDO No\. 4l - Mandaluyong City/u);
  assert.match(text, /A\]ugttst 17,2026/u);
});

test("loadFixtureLayoutText returns null for issuances with no committed capture", async () => {
  assert.equal(await loadFixtureLayoutText("bir:rmc:2026:088"), null);
  assert.equal(await loadFixtureLayoutText("bir:rmo:2026:019"), null);
  assert.equal(await loadFixtureLayoutText(""), null);
});

test("countLayoutPages counts the fixture's six pages", async () => {
  const text = await loadFixtureLayoutText(rmc89);
  assert.ok(text !== null);
  assert.equal(countLayoutPages(text), 6);
  assert.equal(countLayoutPages("no form feeds here"), 1);
  assert.equal(countLayoutPages(""), 1);
  assert.equal(countLayoutPages("a\fb\f"), 2);
});

test("hasUsableTextLayer accepts the fixture's OCR text layer", async () => {
  const text = await loadFixtureLayoutText(rmc89);
  assert.ok(text !== null);
  assert.equal(hasUsableTextLayer(text, countLayoutPages(text)), true);
  assert.equal(hasUsableTextLayer(text, 6), true);
});

test("hasUsableTextLayer rejects a textless scan (plan D3)", () => {
  assert.equal(hasUsableTextLayer("", 6), false);
  assert.equal(hasUsableTextLayer("\f\f\f\f\f\f", 6), false);
  // A per-page banner and nothing else: real content, still far under budget.
  assert.equal(hasUsableTextLayer("Page header\f".repeat(6), 6), false);
});

test("hasUsableTextLayer measures characters per page, not total characters", () => {
  const onePageWorth = "x".repeat(minimumCharactersPerPage);
  assert.equal(hasUsableTextLayer(onePageWorth, 1), true);
  assert.equal(hasUsableTextLayer(onePageWorth, 2), false);
  assert.equal(hasUsableTextLayer(onePageWorth.repeat(2), 2), true);
  // Whitespace padding must not rescue an empty scan.
  assert.equal(hasUsableTextLayer(" ".repeat(10_000), 6), false);
});

test("hasUsableTextLayer treats a zero or negative page count as one page", () => {
  assert.equal(hasUsableTextLayer("x".repeat(minimumCharactersPerPage), 0), true);
  assert.equal(hasUsableTextLayer("short", 0), false);
  assert.equal(hasUsableTextLayer("x".repeat(minimumCharactersPerPage), -3), true);
});

test("sha256File hashes file bytes", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "news-sync-pdf-"));
  const target = path.join(directory, "sample.bin");
  const bytes = Buffer.from("RMC No. 89-2026", "utf8");
  await writeFile(target, bytes);

  assert.equal(await sha256File(target), createHash("sha256").update(bytes).digest("hex"));
});

test("missing-dependency exit code is 2 (plan §5.4.4)", () => {
  assert.equal(missingDependencyExitCode, 2);
});

test(
  "ensurePdftotext and pdfToLayoutText drive the real poppler binary",
  { skip: runsBinaryChecks ? false : "set NEWS_SYNC_NETWORK=1 to run binary checks" },
  async () => {
    await ensurePdftotext();
    await assert.rejects(
      pdfToLayoutText(path.join(tmpdir(), "news-sync-does-not-exist.pdf")),
      /failed/u,
    );
  },
);

test("the HEAD asks for identity encoding, or the CDN hides what it is asked for", async (t) => {
  // Production regression. Node's fetch negotiates gzip by default; bir-cdn
  // answers a compressed HEAD by dropping Content-Length and weakening its
  // ETag to `W/"…"`. Both signals `remotePdfIdentity` exists to read then come
  // back unusable, `unchangedAtOrigin` can never say "unchanged", and every
  // scheduled run re-downloads every circular — which is exactly what the
  // first two production runs did.
  const seen: Array<string | null> = [];
  const original = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = original;
  });
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    seen.push(headers.get("accept-encoding"));
    void input;
    return new Response(null, {
      status: 200,
      headers: { "content-length": "1970851", etag: '"abc"' },
    });
  }) as typeof globalThis.fetch;

  const identity = await remotePdfIdentity("https://example.test/a.pdf");
  assert.deepEqual(seen, ["identity"]);
  assert.deepEqual(identity, { bytes: 1970851, etag: '"abc"' });
});
