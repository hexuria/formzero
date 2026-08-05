#!/usr/bin/env node

import { createHash } from "node:crypto";
import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ownerValues = new Set([
  "base",
  "form-specific",
  "filing-context",
  "transaction",
]);

interface Evidence {
  readonly page: number;
  readonly region: string;
  readonly officialInstruction?: string;
}

interface FormProfilePolicy {
  readonly storageScope: string;
  readonly initialProjection: string;
  readonly laterQuarterDisplay: string;
}

interface FieldOwnership {
  readonly officialItemId: string;
  readonly officialLabel: string;
  readonly semanticKey: string;
  readonly owner: string;
  readonly applicability: string;
  readonly evidence: Evidence;
  readonly options?: readonly string[];
  readonly formProfilePolicy?: FormProfilePolicy;
}

interface AbsenceAssertion {
  readonly semanticKey: string;
  readonly officialLabel: string;
  readonly presence: string;
  readonly applicability: string;
  readonly evidence: {
    readonly reviewedPages: readonly number[];
    readonly method: string;
    readonly result: string;
  };
}

interface OwnershipManifest {
  readonly schemaVersion: number;
  readonly kind: string;
  readonly approval: {
    readonly status: string;
    readonly basis: string;
  };
  readonly publicationPolicy: {
    readonly semanticOwnershipMayBeAutoInferred: boolean;
    readonly generatorBehavior: string;
    readonly catalogPublication: string;
  };
  readonly form: {
    readonly code: string;
    readonly title: string;
    readonly revision: string;
    readonly revisionLabel: string;
    readonly pageCount: number;
  };
  readonly sourceEvidence: {
    readonly sourceFile: string;
    readonly localSourcePath: string;
    readonly sha256: string;
    readonly reviewedPages: readonly number[];
  };
  readonly fields: readonly FieldOwnership[];
  readonly repeatedProjections: readonly {
    readonly page: number;
    readonly officialLabel: string;
    readonly semanticKey: string;
    readonly owner: string;
  }[];
  readonly absenceAssertions: readonly AbsenceAssertion[];
}

function fail(message: string): never {
  throw new Error(`field ownership manifest: ${message}`);
}

function requireObject(value: unknown, context: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail(`${context} must be an object`);
  }
  return value as Record<string, unknown>;
}

function parseManifest(text: string, filename: string): OwnershipManifest {
  const parsed: unknown = JSON.parse(text);
  const value = requireObject(parsed, filename);
  if (value.schemaVersion !== 1) fail(`${filename} has an unsupported schemaVersion`);
  if (value.kind !== "human-approved-form-field-ownership") {
    fail(`${filename} is not a human-approved ownership manifest`);
  }
  return parsed as OwnershipManifest;
}

async function verifyLocalPdf(manifest: OwnershipManifest): Promise<boolean> {
  const sourcePath = manifest.sourceEvidence.localSourcePath;
  try {
    await access(sourcePath);
  } catch {
    return false;
  }

  const bytes = await readFile(sourcePath);
  const actual = createHash("sha256").update(bytes).digest("hex");
  if (actual !== manifest.sourceEvidence.sha256) {
    fail(
      `${manifest.form.code} ${manifest.form.revision} local PDF hash differs: ` +
        `expected ${manifest.sourceEvidence.sha256}, got ${actual}`,
    );
  }
  return true;
}

function requireField(
  manifest: OwnershipManifest,
  officialItemId: string,
): FieldOwnership {
  const field = manifest.fields.find((candidate) => candidate.officialItemId === officialItemId);
  if (field === undefined) {
    fail(`${manifest.form.code} ${manifest.form.revision} lacks official Item ${officialItemId}`);
  }
  return field;
}

function validateCommon(manifest: OwnershipManifest, filename: string): void {
  if (manifest.approval.status !== "human_approved" || manifest.approval.basis.length === 0) {
    fail(`${filename} must record its human approval basis`);
  }
  if (
    manifest.publicationPolicy.semanticOwnershipMayBeAutoInferred ||
    manifest.publicationPolicy.generatorBehavior !== "validate_only" ||
    manifest.publicationPolicy.catalogPublication !== "explicit_human_change_required"
  ) {
    fail(`${filename} must remain validate-only and cannot auto-publish semantic ownership`);
  }
  if (!/^\d{4}-\d{2}-ENCS$/.test(manifest.form.revision)) {
    fail(`${filename} has a non-exact revision key`);
  }
  if (!/^[0-9a-f]{64}$/.test(manifest.sourceEvidence.sha256)) {
    fail(`${filename} must pin a SHA-256 source digest`);
  }
  if (manifest.sourceEvidence.reviewedPages.length !== manifest.form.pageCount) {
    fail(`${filename} must record review of every exact PDF page`);
  }
  for (let page = 1; page <= manifest.form.pageCount; page += 1) {
    if (!manifest.sourceEvidence.reviewedPages.includes(page)) {
      fail(`${filename} has no page-${page} review evidence`);
    }
  }
  if (manifest.fields.length === 0) fail(`${filename} contains no field ownership rows`);

  const itemIds = new Set<string>();
  for (const field of manifest.fields) {
    if (field.officialItemId.length === 0 || field.officialLabel.length === 0) {
      fail(`${filename} contains a field without an official item id and label`);
    }
    if (itemIds.has(field.officialItemId)) {
      fail(`${filename} repeats official item id ${field.officialItemId}`);
    }
    itemIds.add(field.officialItemId);
    if (!/^[a-z][a-z0-9_]*$/.test(field.semanticKey)) {
      fail(`${filename} item ${field.officialItemId} has invalid semantic key ${field.semanticKey}`);
    }
    if (!ownerValues.has(field.owner)) {
      fail(`${filename} item ${field.officialItemId} has invalid owner ${field.owner}`);
    }
    if (field.applicability.length === 0) {
      fail(`${filename} item ${field.officialItemId} has no applicability rule`);
    }
    if (
      !Number.isInteger(field.evidence.page) ||
      field.evidence.page < 1 ||
      field.evidence.page > manifest.form.pageCount ||
      field.evidence.region.length === 0
    ) {
      fail(`${filename} item ${field.officialItemId} has invalid PDF evidence`);
    }
  }

  for (const projection of manifest.repeatedProjections) {
    if (!ownerValues.has(projection.owner)) {
      fail(`${filename} repeated projection ${projection.semanticKey} has an invalid owner`);
    }
    if (projection.page < 1 || projection.page > manifest.form.pageCount) {
      fail(`${filename} repeated projection ${projection.semanticKey} has invalid page evidence`);
    }
  }
}

function validateBaseHeaderFields(
  manifest: OwnershipManifest,
  expected: Readonly<Record<string, string>>,
): void {
  for (const [itemId, semanticKey] of Object.entries(expected)) {
    const field = requireField(manifest, itemId);
    if (field.semanticKey !== semanticKey || field.owner !== "base") {
      fail(
        `${manifest.form.code} ${manifest.form.revision} Item ${itemId} must map to ` +
          `base.${semanticKey}`,
      );
    }
  }
}

function validate2551Q(manifest: OwnershipManifest): void {
  validateBaseHeaderFields(manifest, {
    "1": "accounting_period_basis",
    "6": "tin",
    "7": "rdo_code",
    "8": "registered_name",
    "9": "registered_address",
    "9A": "zip_code",
    "10": "contact_number",
    "11": "registered_email",
  });
  const item13 = requireField(manifest, "13");
  if (
    item13.semanticKey !== "income_tax_rate_election" ||
    item13.owner !== "form-specific" ||
    item13.formProfilePolicy?.storageScope !==
      "taxpayer_form_revision_tax_year" ||
    item13.formProfilePolicy.initialProjection !==
      "initial_applicable_quarter_only" ||
    item13.formProfilePolicy.laterQuarterDisplay !== "inherited_read_only" ||
    item13.evidence.officialInstruction !==
      "To be filled out only on the initial quarter of the taxable year"
  ) {
    fail(
      "2551Q Item 13 must remain a form-specific yearly choice projected only initially",
    );
  }
  if (item13.options?.join(",") !== "graduated,eight_percent") {
    fail("2551Q Item 13 must contain exactly the two official election choices");
  }
}

function validate2550Q(manifest: OwnershipManifest): void {
  validateBaseHeaderFields(manifest, {
    "1": "accounting_period_basis",
    "7": "tin",
    "8": "rdo_code",
    "9": "registered_name",
    "10": "registered_address",
    "10A": "zip_code",
    "11": "contact_number",
    "12": "registered_email",
  });
  const item13 = requireField(manifest, "13");
  if (
    item13.semanticKey !== "eopt_tier" ||
    item13.owner !== "base" ||
    item13.options?.join(",") !== "micro,small,medium,large"
  ) {
    fail("2550Q Item 13 must map to the effective Base Tax Profile EOPT tier");
  }
  if (manifest.fields.some((field) => field.semanticKey === "line_of_business")) {
    fail("2550Q 2024-04-ENCS must not project Line of Business");
  }
  const absence = manifest.absenceAssertions.find(
    (assertion) => assertion.semanticKey === "line_of_business",
  );
  if (
    absence?.presence !== "absent_from_exact_revision" ||
    absence.evidence.reviewedPages.join(",") !== "1,2"
  ) {
    fail("2550Q 2024-04-ENCS must assert Line of Business absent across both pages");
  }
}

async function main(): Promise<void> {
  const manifestDirectory = path.dirname(fileURLToPath(import.meta.url));
  const filenames = (await readdir(manifestDirectory))
    .filter((filename) => filename.endsWith(".field-ownership.json"))
    .sort();
  const required = new Set([
    "2550Q-2024-04-ENCS.field-ownership.json",
    "2551Q-2018-01-ENCS.field-ownership.json",
  ]);
  for (const filename of required) {
    if (!filenames.includes(filename)) fail(`required manifest ${filename} is missing`);
  }

  let localPdfCount = 0;
  for (const filename of filenames) {
    const text = await readFile(path.join(manifestDirectory, filename), "utf8");
    const manifest = parseManifest(text, filename);
    validateCommon(manifest, filename);
    if (manifest.form.code === "2551Q" && manifest.form.revision === "2018-01-ENCS") {
      validate2551Q(manifest);
    } else if (manifest.form.code === "2550Q" && manifest.form.revision === "2024-04-ENCS") {
      validate2550Q(manifest);
    }
    localPdfCount += Number(await verifyLocalPdf(manifest));
  }

  console.log(
    `Checked ${filenames.length} human-approved field-ownership manifests; ` +
      `${localPdfCount} exact local PDF hashes verified; semantic publication remains manual.`,
  );
}

await main();
