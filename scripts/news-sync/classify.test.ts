import assert from "node:assert/strict";
import test from "node:test";

import { isDeadlineExtension } from "./classify.ts";
import { ARCHIVE_FIXTURES, WIDGET_FIXTURE, loadFixtureDataset } from "./cms.ts";
import { extractIssuanceHtml, parseArchiveIssuances, parseWidgetIssuances } from "./issuances.ts";

const FIRST_SEEN = 1_786_752_000;

test("RMC 89-2026 classifies as a deadline extension, its neighbours do not", async () => {
  const widget = await loadFixtureDataset(WIDGET_FIXTURE);
  const records = parseWidgetIssuances(extractIssuanceHtml(widget[0]), FIRST_SEEN);
  const hits = records.filter((record) => isDeadlineExtension(record.subject));

  assert.deepEqual(
    hits.map((record) => record.externalId),
    ["bir:rmc:2026:089"],
  );
});

test("the archive subjects classify identically to the widget ones", async () => {
  const archive = await loadFixtureDataset(ARCHIVE_FIXTURES.RMC);
  const records = parseArchiveIssuances(extractIssuanceHtml(archive[0]), FIRST_SEEN);

  assert.deepEqual(
    records.filter((record) => isDeadlineExtension(record.subject)).map((r) => r.externalId),
    ["bir:rmc:2026:089"],
  );
});

test("no RMO archive row is mistaken for a deadline extension", async () => {
  const archive = await loadFixtureDataset(ARCHIVE_FIXTURES.RMO);
  const records = parseArchiveIssuances(extractIssuanceHtml(archive[0]), FIRST_SEEN);

  assert.equal(records.length, 6);
  assert.deepEqual(
    records.filter((record) => isDeadlineExtension(record.subject)).map((r) => r.externalId),
    [],
  );
});

test("the one RR row that really does extend a deadline is classified as such", async () => {
  const archive = await loadFixtureDataset(ARCHIVE_FIXTURES.RR);
  const records = parseArchiveIssuances(extractIssuanceHtml(archive[0]), FIRST_SEEN);

  // RR 1-2026 "…extend the deadline for system reconfiguration…" — genuine
  // extension language, so the classifier is right to send it to the extractor.
  assert.deepEqual(
    records.filter((record) => isDeadlineExtension(record.subject)).map((r) => r.externalId),
    ["bir:rr:2026:001"],
  );
});

test("'Extension … of the Deadlines' matches even though 'extend' never appears", () => {
  assert.equal(
    isDeadlineExtension(
      "Providing Extension of the Deadlines for the Filing of Tax Retums and Payment of " +
        "Conesponding Taxes Due Thereon, Including Submission of Required Documents",
    ),
    true,
  );
});

test("either word order matches", () => {
  assert.equal(isDeadlineExtension("Extending the deadline for filing"), true);
  assert.equal(isDeadlineExtension("Extension of deadlines"), true);
  assert.equal(isDeadlineExtension("Extends the Deadline"), true);
  assert.equal(isDeadlineExtension("The deadline is hereby extended to August 17, 2026"), true);
  assert.equal(isDeadlineExtension("Deadlines extension"), true);
});

test("matching is case-insensitive and whitespace-tolerant", () => {
  assert.equal(isDeadlineExtension("EXTENSION OF THE DEADLINES"), true);
  assert.equal(isDeadlineExtension("Extension\n  of\tthe\n\ndeadlines"), true);
  assert.equal(isDeadlineExtension("extension of the deadlines"), true);
});

test("publication and other non-extension subjects do not match", () => {
  assert.equal(
    isDeadlineExtension(
      "Publishing the Updated List of Registered Manufacturers/Importers /Exporters with the " +
        "Corresponding Products/Brands/Variants of Cigarettes",
    ),
    false,
  );
  assert.equal(
    isDeadlineExtension("Circularizing Memorandum Circular (MC) No. 122 of the Office of the President"),
    false,
  );
  // One half of the pair alone is not enough.
  assert.equal(isDeadlineExtension("Extension of the amnesty availment period"), false);
  assert.equal(isDeadlineExtension("Reminder on the September filing deadline"), false);
  assert.equal(isDeadlineExtension(""), false);
});
