#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  editorForms,
  filingCadenceValues,
  filingPeriodPolicy,
  formDisplayMetadata,
  formDisplayMetadataByCode,
  profileCardinalityValues,
  provenanceValues,
  profileFieldKeyValues,
  profilePresenceValues,
  profileRoleValues,
  profileSubjectKindValues,
  registryCodes,
  roleValues,
  taxCategoryValues,
  taxFormProfileAvailabilityValues,
  taxFormProfileOwnershipValues,
  taxFormProfilePresenceValues,
  taxFormProfileSemanticDefinitions,
  taxFormProfileSemanticKeyValues,
  taxFormProfileSetupModeValues,
  taxFormProfileSourceKindValues,
  taxFormProfileValidationRuleValues,
  taxFormProfileValueTypeValues,
  taxpayerYearSettingKeyValues,
  valueTypeValues,
  type EditorFormSpec,
  type FieldStatus,
  type FilingCadence,
  type FormStatus,
  type ProfileFieldKey,
  type ProfilePresence,
  type ProfileRoleSpec,
  type Provenance,
  type Role,
  type TaxCategory,
  type TaxFormProfileAvailability,
  type TaxFormProfileEditorContract,
  type TaxFormProfileOwnership,
  type TaxFormProfilePresence,
  type TaxFormProfileSemanticDefinition,
  type TaxFormProfileSemanticKey,
  type TaxFormProfileSetupMode,
  type TaxFormProfileSourceKind,
  type TaxFormProfileValidationRule,
  type TaxFormProfileValueType,
  type TaxpayerYearSettingKey,
  type ValueType,
} from "./catalog.ts";

interface FieldDefinition {
  readonly id: string;
  readonly label: string;
  readonly provenance: Provenance;
  readonly role: Role;
  readonly valueType: ValueType;
  readonly status: FieldStatus;
  readonly profileField: ProfileFieldKey | null;
  readonly profilePresence: ProfilePresence | null;
  readonly sourceKey: string | null;
  readonly fixedValue: string | null;
  readonly sourcePath: string;
  readonly sourceLine: number | null;
  readonly control: "input" | "table";
}

interface TaxFormProfileValueDefinition {
  readonly semanticKey: TaxFormProfileSemanticKey;
  readonly valueType: TaxFormProfileValueType;
  readonly role: ProfileRoleSpec["role"];
  readonly presence: TaxFormProfilePresence;
  readonly validationRule: TaxFormProfileValidationRule;
  readonly ownership: TaxFormProfileOwnership;
  readonly sourceKind: TaxFormProfileSourceKind;
  readonly availability: TaxFormProfileAvailability;
  readonly sourceEvidence: string;
  readonly evidenceGate: string | null;
}

interface TaxFormProfileDefinition {
  readonly mode: TaxFormProfileSetupMode;
  readonly specRevision: number | null;
  readonly specHash: string | null;
  readonly sourceEvidence: string;
  readonly values: readonly TaxFormProfileValueDefinition[];
}

interface FormDefinition {
  readonly code: string;
  readonly displayTitle: string;
  readonly taxCategory: TaxCategory;
  readonly revision: string | null;
  readonly status: FormStatus;
  readonly cadence: FilingCadence;
  readonly minPeriod: number | null;
  readonly maxPeriod: number | null;
  readonly sourcePath: string | null;
  readonly roles: readonly Role[];
  readonly profileRoles: readonly ProfileRoleSpec[];
  readonly consumedTaxpayerYearSettings: readonly TaxpayerYearSettingKey[];
  readonly taxFormProfile: TaxFormProfileDefinition;
  readonly fields: readonly FieldDefinition[];
}

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "../..");
const generatedZigPath = "src/forms/generated/catalog.zig";
const generatedMarkdownPath = "docs/tax-profile/FORM_FIELD_CATALOG.md";
const expectedRegistryCount = 51;
const expectedEditorCount = 10;
const expectedCalendarOnlyCount = 41;
const expectedInputCount = 326;
const expectedProfileTargetCount = 91;
const expectedOptionalProfileTargetCount = 33;
const expectedTaxpayerYearTargetCount = 1;
const expectedTaxpayerYearConsumerFormCount = 2;
const expectedTaxpayerYearConsumptionCount = 4;
const expectedFormPolicyTargetCount = 4;
const expectedSetupContractCount = 4;
const expectedNoSetupContractCount = 6;
const expectedSetupValueCount = 4;
const expectedEvidenceRequiredSetupValueCount = 0;

function fail(message: string): never {
  throw new Error(message);
}

function decodeText(value: string): string {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replace(/\s+/gu, " ")
    .trim();
}

function slug(value: string): string {
  const result = value
    .normalize("NFKD")
    .replace(/^\d+[A-Z]?\s+/u, "")
    .replace(/['’]/gu, "")
    .replace(/[^A-Za-z0-9]+/gu, "_")
    .replace(/^_+|_+$/gu, "")
    .toLowerCase();

  if (!result) fail(`Cannot derive a stable field id from label: ${value}`);
  return result;
}

function sourceLineAt(source: string, offset: number): number {
  let line = 1;
  for (let index = 0; index < offset; index += 1) {
    if (source.charCodeAt(index) === 10) line += 1;
  }
  return line;
}

function parseInputs(spec: EditorFormSpec, source: string): FieldDefinition[] {
  // A form field is one of three shapes: a bare <input> paired with the
  // preceding <text> label, or a form-field / form-field-bound template
  // include, which carries its label and placeholder as attributes.
  const tokenPattern =
    /<text\b[^>]*>([^<]*)<\/text>|<input\b([^>]*)\/?>|<!--\s*@include-template\s+form-field(?:-bound)?\b([\s\S]*?)-->/gu;
  const duplicateIds = new Map<string, number>();
  const fields: FieldDefinition[] = [];
  let lastLabel = "";

  for (const match of source.matchAll(tokenPattern)) {
    if (match[1] !== undefined) {
      const candidate = decodeText(match[1]);
      if (candidate) lastLabel = candidate;
      continue;
    }

    if (match[3] !== undefined) {
      const includeLabel = /\blabel="([^"]*)"/u.exec(match[3]);
      if (!includeLabel) {
        fail(`${spec.sourcePath}:${sourceLineAt(source, match.index)} form-field include has no label`);
      }
      lastLabel = decodeText(includeLabel[1]);
    } else if (match[2] !== undefined) {
      // Bare inputs still use their exact stable ID contract below. Their
      // placeholder is display copy, never ownership/type authority.
    } else {
      continue;
    }
    if (!lastLabel) {
      fail(`${spec.sourcePath}:${sourceLineAt(source, match.index)} input has no label`);
    }
    const baseId = slug(lastLabel);
    const occurrence = (duplicateIds.get(baseId) ?? 0) + 1;
    duplicateIds.set(baseId, occurrence);
    const localId = occurrence === 1 ? baseId : `${baseId}_${occurrence}`;
    const id = `${spec.code}.${spec.revision}.input.${localId}`;
    const metadata = spec.inputFields[id];
    if (!metadata) {
      fail(
        `${spec.sourcePath}:${sourceLineAt(source, match.index)} input ${id} ` +
          "has no explicit ownership metadata",
      );
    }

    fields.push({
      id,
      label: lastLabel,
      provenance: metadata.provenance,
      role: metadata.role,
      valueType: metadata.valueType,
      status: "unbound_input",
      profileField: metadata.profileField ?? null,
      profilePresence:
        metadata.provenance === "profile"
          ? spec.profileTargetPresence?.[id] ?? "required"
          : null,
      sourceKey: metadata.sourceKey ?? null,
      fixedValue: metadata.fixedValue ?? null,
      sourcePath: spec.sourcePath,
      sourceLine: sourceLineAt(source, match.index),
      control: "input",
    });
  }

  if (fields.length !== spec.expectedInputCount) {
    fail(
      `${spec.sourcePath} contains ${fields.length} inputs; catalog expects ` +
        `${spec.expectedInputCount}`,
    );
  }
  const discovered = fields.map((field) => field.id).toSorted();
  const declared = Object.keys(spec.inputFields).toSorted();
  if (JSON.stringify(discovered) !== JSON.stringify(declared)) {
    const discoveredSet = new Set(discovered);
    const declaredSet = new Set(declared);
    const missing = discovered.filter((id) => !declaredSet.has(id));
    const stale = declared.filter((id) => !discoveredSet.has(id));
    fail(
      `${spec.code} explicit input ownership differs from discovered controls.\n` +
        `undeclared: ${missing.join(", ") || "none"}\n` +
        `stale: ${stale.join(", ") || "none"}`,
    );
  }
  return fields;
}

function validateTableSource(spec: EditorFormSpec, source: string): void {
  const tableCount = [...source.matchAll(/<table(?:\s|>)/gu)].length;
  if (tableCount !== spec.expectedTableCount) {
    fail(
      `${spec.sourcePath} contains ${tableCount} tables; catalog expects ` +
        `${spec.expectedTableCount}`,
    );
  }
  if (spec.tableFields.length !== spec.expectedTableHeaders.length) {
    fail(
      `${spec.code} declares ${spec.tableFields.length} table fields but ` +
        `${spec.expectedTableHeaders.length} source headers`,
    );
  }
  validateUnique(spec.expectedTableHeaders, `${spec.code} expected table headers`);

  const cells = [...source.matchAll(/<table-cell\b[^>]*>([\s\S]*?)<\/table-cell>/gu)]
    .map((match) => decodeText(match[1]?.replace(/<[^>]+>/gu, " ") ?? ""))
    .filter(Boolean);
  for (const header of spec.expectedTableHeaders) {
    if (!cells.includes(header)) {
      fail(`${spec.sourcePath} is missing cataloged table header ${header}`);
    }
  }
}

function validateTaxFormProfileVocabulary(): void {
  validateUnique(
    taxFormProfileSetupModeValues,
    "Tax Form Profile setup modes",
  );
  validateUnique(
    taxFormProfileOwnershipValues,
    "Tax Form Profile ownership kinds",
  );
  validateUnique(
    taxFormProfileAvailabilityValues,
    "Tax Form Profile availability policies",
  );
  validateUnique(
    taxFormProfilePresenceValues,
    "Tax Form Profile presence policies",
  );
  validateUnique(
    taxFormProfileValueTypeValues,
    "Tax Form Profile value types",
  );
  validateUnique(
    taxFormProfileSourceKindValues,
    "Tax Form Profile source kinds",
  );
  validateUnique(
    taxFormProfileValidationRuleValues,
    "Tax Form Profile validation rules",
  );
  validateUnique(
    taxFormProfileSemanticKeyValues,
    "Tax Form Profile semantic keys",
  );

  const declaredKeys = Object.keys(taxFormProfileSemanticDefinitions).toSorted();
  const expectedKeys = [...taxFormProfileSemanticKeyValues].toSorted();
  if (JSON.stringify(declaredKeys) !== JSON.stringify(expectedKeys)) {
    fail(
      "Tax Form Profile semantic definitions differ from the closed key vocabulary.\n" +
        `definitions: ${declaredKeys.join(", ")}\n` +
        `vocabulary: ${expectedKeys.join(", ")}`,
    );
  }

  const referenceTypes = new Set<TaxFormProfileValueType>(["profile_id"]);
  const bindingSources = new Set<TaxFormProfileSourceKind>([
    "named_profile_role",
  ]);
  const authoredSources = new Set<TaxFormProfileSourceKind>([
    "user_entry",
    "catalog_default",
  ]);

  for (const key of taxFormProfileSemanticKeyValues) {
    const definition: TaxFormProfileSemanticDefinition =
      taxFormProfileSemanticDefinitions[key];
    if (!taxFormProfileValueTypeValues.includes(definition.valueType)) {
      fail(`${key} has unknown Tax Form Profile value type ${definition.valueType}`);
    }
    if (!profileRoleValues.includes(definition.role)) {
      fail(`${key} has unknown Tax Form Profile role ${definition.role}`);
    }
    if (!taxFormProfilePresenceValues.includes(definition.presence)) {
      fail(`${key} has unknown Tax Form Profile presence ${definition.presence}`);
    }
    if (!taxFormProfileValidationRuleValues.includes(definition.validationRule)) {
      fail(
        `${key} has unknown Tax Form Profile validation rule ` +
          definition.validationRule,
      );
    }
    if (!taxFormProfileOwnershipValues.includes(definition.ownership)) {
      fail(`${key} has unknown Tax Form Profile ownership ${definition.ownership}`);
    }
    if (!taxFormProfileSourceKindValues.includes(definition.sourceKind)) {
      fail(`${key} has unknown Tax Form Profile source ${definition.sourceKind}`);
    }

    if (definition.ownership === "binding_selection") {
      if (!referenceTypes.has(definition.valueType)) {
        fail(`${key} binding_selection must use a stable reference value type`);
      }
      if (!bindingSources.has(definition.sourceKind)) {
        fail(`${key} binding_selection must select a stable role/component source`);
      }
    } else {
      if (referenceTypes.has(definition.valueType)) {
        fail(`${key} ${definition.ownership} cannot masquerade as a binding`);
      }
      if (!authoredSources.has(definition.sourceKind)) {
        fail(
          `${key} ${definition.ownership} must be user-authored or a catalog default`,
        );
      }
    }

    if (
      definition.ownership === "transaction_default" &&
      definition.presence === "required"
    ) {
      fail(`${key} transaction_default cannot block setup readiness`);
    }
  }
}

function resolveTaxFormProfile(
  code: string,
  revision: string,
  contract: TaxFormProfileEditorContract | undefined,
): TaxFormProfileDefinition {
  if (!contract) fail(`${code} ${revision} lacks a Tax Form Profile contract`);
  if (contract.mode !== "no_setup" && contract.mode !== "setup") {
    fail(`${code} ${revision} has unknown Tax Form Profile mode`);
  }
  if (!Number.isSafeInteger(contract.specRevision) || contract.specRevision < 1) {
    fail(`${code} ${revision} has invalid Tax Form Profile spec revision`);
  }
  if (!contract.sourceEvidence.trim()) {
    fail(`${code} ${revision} Tax Form Profile contract lacks source evidence`);
  }
  if (contract.mode === "no_setup" && contract.values.length !== 0) {
    fail(`${code} ${revision} no_setup contract declares values`);
  }
  if (contract.mode === "setup" && contract.values.length === 0) {
    fail(`${code} ${revision} setup contract has no values`);
  }

  validateUnique(
    contract.values.map((value) => value.semanticKey),
    `${code} ${revision} Tax Form Profile semantic keys`,
  );

  const definitions = taxFormProfileSemanticDefinitions as Readonly<
    Record<
      string,
      (typeof taxFormProfileSemanticDefinitions)[TaxFormProfileSemanticKey]
        | undefined
    >
  >;
  const values = contract.values.map<TaxFormProfileValueDefinition>((value) => {
    if (!taxFormProfileSemanticKeyValues.includes(value.semanticKey)) {
      fail(
        `${code} ${revision} declares unknown Tax Form Profile semantic key ` +
          value.semanticKey,
      );
    }
    const definition = definitions[value.semanticKey];
    if (!definition) {
      fail(
        `${code} ${revision} semantic key ${value.semanticKey} lacks a definition`,
      );
    }
    if (!taxFormProfileAvailabilityValues.includes(value.availability)) {
      fail(
        `${code} ${revision} ${value.semanticKey} has unknown availability ` +
          value.availability,
      );
    }
    if (!value.sourceEvidence.trim()) {
      fail(`${code} ${revision} ${value.semanticKey} lacks source evidence`);
    }
    if (
      value.availability === "evidence_required" &&
      !value.evidenceGate.trim()
    ) {
      fail(`${code} ${revision} ${value.semanticKey} lacks an evidence gate`);
    }
    if (
      value.availability === "supported" &&
      "evidenceGate" in value
    ) {
      fail(`${code} ${revision} ${value.semanticKey} is supported but gated`);
    }

    return {
      semanticKey: value.semanticKey,
      valueType: definition.valueType,
      role: definition.role,
      presence: definition.presence,
      validationRule: definition.validationRule,
      ownership: definition.ownership,
      sourceKind: definition.sourceKind,
      availability: value.availability,
      sourceEvidence: value.sourceEvidence,
      evidenceGate:
        value.availability === "evidence_required" ? value.evidenceGate : null,
    };
  });

  const canonical = JSON.stringify({
    schema: "tax-form-profile-spec/v1",
    code,
    revision,
    mode: contract.mode,
    specRevision: contract.specRevision,
    values: values.map((value) => ({
      semanticKey: value.semanticKey,
      valueType: value.valueType,
      role: value.role,
      presence: value.presence,
      validationRule: value.validationRule,
      ownership: value.ownership,
      sourceKind: value.sourceKind,
      availability: value.availability,
    })),
  });
  const specHash = createHash("sha256").update(canonical).digest("hex");

  return {
    mode: contract.mode,
    specRevision: contract.specRevision,
    specHash,
    sourceEvidence: contract.sourceEvidence,
    values,
  };
}

async function loadEditorForm(spec: EditorFormSpec): Promise<FormDefinition> {
  const source = await readFile(path.join(projectRoot, spec.sourcePath), "utf8");
  if (!source.includes(`>${spec.revisionLabel}</text>`)) {
    fail(
      `${spec.sourcePath} does not contain expected revision label ` +
        `${spec.revisionLabel}`,
    );
  }
  validateTableSource(spec, source);
  const inputFields = parseInputs(spec, source);
  const tableFields: FieldDefinition[] = spec.tableFields.map((field) => ({
    id: `${spec.code}.${spec.revision}.table.${field.id}`,
    label: field.label,
    provenance: field.provenance,
    role: field.role,
    valueType: field.valueType,
    status: field.status ?? "static_table",
    profileField: field.profileField ?? null,
    profilePresence:
      field.provenance === "profile"
        ? spec.profileTargetPresence?.[
            `${spec.code}.${spec.revision}.table.${field.id}`
          ] ?? "required"
        : null,
    sourceKey: null,
    fixedValue: null,
    sourcePath: spec.sourcePath,
    sourceLine: null,
    control: "table",
  }));

  const fields = [...inputFields, ...tableFields];
  for (const [targetId, presence] of Object.entries(
    spec.profileTargetPresence ?? {},
  )) {
    if (!profilePresenceValues.includes(presence)) {
      fail(`${spec.code} target ${targetId} has unknown presence ${presence}`);
    }
    const target = fields.find((field) => field.id === targetId);
    if (!target) {
      fail(`${spec.code} profile-presence policy targets unknown field ${targetId}`);
    }
    if (target.provenance !== "profile") {
      fail(`${spec.code} profile-presence policy targets non-profile field ${targetId}`);
    }
  }

  return {
    code: spec.code,
    ...formDisplayMetadata(spec.code),
    revision: spec.revision,
    status: "static_layout",
    ...filingPeriodPolicy(spec.code),
    sourcePath: spec.sourcePath,
    roles: spec.roles,
    profileRoles: spec.profileRoles,
    consumedTaxpayerYearSettings: spec.consumedTaxpayerYearSettings,
    taxFormProfile: resolveTaxFormProfile(
      spec.code,
      spec.revision,
      spec.taxFormProfile,
    ),
    fields,
  };
}

function validateUnique(values: readonly string[], context: string): void {
  const seen = new Set<string>();
  for (const value of values) {
    if (!value) fail(`${context} contains an empty value`);
    if (seen.has(value)) fail(`${context} contains duplicate value ${value}`);
    seen.add(value);
  }
}

async function validateSourceCoverage(): Promise<void> {
  const sourceDirectory = path.join(projectRoot, "src/pages/forms");
  const actual = (await readdir(sourceDirectory))
    .filter((name) => name.endsWith(".native"))
    .map((name) => `src/pages/forms/${name}`)
    .sort();
  const declared = editorForms.map((form) => form.sourcePath).toSorted();

  if (JSON.stringify(actual) !== JSON.stringify(declared)) {
    fail(
      "Native form source coverage differs from the catalog.\n" +
        `actual: ${actual.join(", ")}\n` +
        `catalog: ${declared.join(", ")}`,
    );
  }
}

async function validateRegistryCoverage(): Promise<void> {
  const mainSource = await readFile(path.join(projectRoot, "src/main.zig"), "utf8");
  if (
    mainSource.includes("const calendar_form_codes = blk:") &&
    mainSource.includes("for (form_catalog.forms, 0..)")
  ) {
    // The calendar picker derives its stable option order directly from this
    // generated catalog. Calendar-only obligations may be appended without
    // turning the generated form registry into a hand-maintained duplicate.
    return;
  }
  const registryMatch =
    /const form_filter_codes = \[_\]\[\]const u8\{([\s\S]*?)\n\};/u.exec(mainSource);
  if (!registryMatch?.[1]) fail("Cannot locate form_filter_codes in src/main.zig");
  const actual = [...registryMatch[1].matchAll(/"([^"]+)"/gu)].map(
    (match) => match[1],
  );

  if (JSON.stringify(actual) !== JSON.stringify(registryCodes)) {
    fail(
      "src/main.zig form_filter_codes differs from the TypeScript catalog.\n" +
        `main.zig: ${actual.join(", ")}\n` +
        `catalog: ${registryCodes.join(", ")}`,
    );
  }
}

async function validateReusableFieldVocabulary(): Promise<void> {
  const fieldSource = await readFile(
    path.join(projectRoot, "src/tax_profile/field.zig"),
    "utf8",
  );
  const enumMatch =
    /pub const ReusableField = enum \{([\s\S]*?)\n\};/u.exec(fieldSource);
  if (!enumMatch?.[1]) {
    fail("Cannot locate ReusableField in src/tax_profile/field.zig");
  }
  const zigFields = [...enumMatch[1].matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*,/gmu)]
    .map((match) => match[1]);
  if (JSON.stringify(zigFields) !== JSON.stringify(profileFieldKeyValues)) {
    fail(
      "TypeScript profile-field vocabulary differs from Zig ReusableField.\n" +
        `Zig: ${zigFields.join(", ")}\n` +
        `TypeScript: ${profileFieldKeyValues.join(", ")}`,
    );
  }
}

async function validateSubjectKindVocabulary(): Promise<void> {
  const modelSource = await readFile(
    path.join(projectRoot, "src/tax_profile/model.zig"),
    "utf8",
  );
  const enumMatch =
    /pub const SubjectKind = enum \{([\s\S]*?)\n\};/u.exec(modelSource);
  if (!enumMatch?.[1]) {
    fail("Cannot locate SubjectKind in src/tax_profile/model.zig");
  }
  const zigKinds = [
    ...enumMatch[1].matchAll(
      /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*,/gmu,
    ),
  ].map((match) => match[1]);
  if (
    JSON.stringify(zigKinds) !==
    JSON.stringify(profileSubjectKindValues)
  ) {
    fail(
      "TypeScript profile-subject vocabulary differs from Zig SubjectKind.\n" +
        `Zig: ${zigKinds.join(", ")}\n` +
        `TypeScript: ${profileSubjectKindValues.join(", ")}`,
    );
  }
}

function validateCatalog(forms: readonly FormDefinition[]): void {
  if (registryCodes.length !== expectedRegistryCount) {
    fail(`Expected ${expectedRegistryCount} registry codes, got ${registryCodes.length}`);
  }
  if (editorForms.length !== expectedEditorCount) {
    fail(`Expected ${expectedEditorCount} editor forms, got ${editorForms.length}`);
  }
  validateUnique(registryCodes, "registry codes");
  validateUnique(editorForms.map((form) => form.code), "editor form codes");
  validateUnique(editorForms.map((form) => form.sourcePath), "editor source paths");

  const displayMetadataCodes = Object.keys(formDisplayMetadataByCode).toSorted();
  const expectedDisplayMetadataCodes = [...registryCodes].toSorted();
  if (
    JSON.stringify(displayMetadataCodes) !==
    JSON.stringify(expectedDisplayMetadataCodes)
  ) {
    fail(
      "Display metadata differs from the 51-code registry.\n" +
        `metadata: ${displayMetadataCodes.join(", ")}\n` +
        `registry: ${expectedDisplayMetadataCodes.join(", ")}`,
    );
  }

  const editorCodes = new Set(editorForms.map((form) => form.code));
  for (const code of editorCodes) {
    if (!registryCodes.includes(code as (typeof registryCodes)[number])) {
      fail(`Editor code ${code} is absent from the 51-code registry`);
    }
  }

  for (const code of registryCodes) {
    const metadata = formDisplayMetadata(code);
    if (!metadata.displayTitle.trim()) {
      fail(`${code} has an empty display title`);
    }
    if (metadata.displayTitle !== metadata.displayTitle.trim()) {
      fail(`${code} display title has leading or trailing whitespace`);
    }
    if (!taxCategoryValues.includes(metadata.taxCategory)) {
      fail(`${code} has an unknown tax category ${metadata.taxCategory}`);
    }

    const policy = filingPeriodPolicy(code);
    if (!filingCadenceValues.includes(policy.cadence)) {
      fail(`${code} has an unknown filing cadence ${policy.cadence}`);
    }
    if (
      (policy.minPeriod === null) !== (policy.maxPeriod === null) ||
      (policy.minPeriod !== null &&
        (policy.minPeriod < 1 || policy.maxPeriod! < policy.minPeriod))
    ) {
      fail(`${code} has invalid filing period bounds`);
    }
  }

  const calendarOnly = forms.filter((form) => form.status === "calendar_only");
  if (calendarOnly.length !== expectedCalendarOnlyCount) {
    fail(
      `Expected ${expectedCalendarOnlyCount} calendar-only forms, got ` +
        `${calendarOnly.length}`,
    );
  }

  const inputCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.control === "input").length;
  if (inputCount !== expectedInputCount) {
    fail(`Expected ${expectedInputCount} input fields, got ${inputCount}`);
  }
  const profileTargets = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "profile");
  if (profileTargets.length !== expectedProfileTargetCount) {
    fail(
      `Expected ${expectedProfileTargetCount} profile targets, got ` +
        profileTargets.length,
    );
  }
  const optionalProfileTargets = profileTargets.filter(
    (field) => field.profilePresence === "optional",
  );
  if (
    optionalProfileTargets.length !==
    expectedOptionalProfileTargetCount
  ) {
    fail(
      `Expected ${expectedOptionalProfileTargetCount} optional profile ` +
      `targets, got ${optionalProfileTargets.length}`,
    );
  }
  const taxpayerYearTargets = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "taxpayer_year");
  const taxpayerYearConsumerForms = forms.filter(
    (form) => form.consumedTaxpayerYearSettings.length !== 0,
  );
  const taxpayerYearConsumptionCount = taxpayerYearConsumerForms.reduce(
    (count, form) => count + form.consumedTaxpayerYearSettings.length,
    0,
  );
  if (taxpayerYearTargets.length !== expectedTaxpayerYearTargetCount) {
    fail(
      `Expected ${expectedTaxpayerYearTargetCount} visible taxpayer-year targets, got ` +
        taxpayerYearTargets.length,
    );
  }
  if (
    taxpayerYearConsumerForms.length !== expectedTaxpayerYearConsumerFormCount
  ) {
    fail(
      `Expected ${expectedTaxpayerYearConsumerFormCount} taxpayer-year ` +
        `consumer forms, got ${taxpayerYearConsumerForms.length}`,
    );
  }
  if (taxpayerYearConsumptionCount !== expectedTaxpayerYearConsumptionCount) {
    fail(
      `Expected ${expectedTaxpayerYearConsumptionCount} consumed taxpayer-year ` +
        `settings, got ${taxpayerYearConsumptionCount}`,
    );
  }
  const formPolicyTargets = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "form_policy");
  if (formPolicyTargets.length !== expectedFormPolicyTargetCount) {
    fail(
      `Expected ${expectedFormPolicyTargetCount} fixed form-policy targets, got ` +
        formPolicyTargets.length,
    );
  }

  const setupContracts = forms.filter(
    (form) => form.taxFormProfile.mode === "setup",
  );
  const noSetupContracts = forms.filter(
    (form) => form.taxFormProfile.mode === "no_setup",
  );
  const setupValues = setupContracts.flatMap(
    (form) => form.taxFormProfile.values,
  );
  const evidenceRequiredSetupValues = setupValues.filter(
    (value) => value.availability === "evidence_required",
  );
  if (setupContracts.length !== expectedSetupContractCount) {
    fail(
      `Expected ${expectedSetupContractCount} nonempty Tax Form Profile ` +
        `contracts, got ${setupContracts.length}`,
    );
  }
  if (noSetupContracts.length !== expectedNoSetupContractCount) {
    fail(
      `Expected ${expectedNoSetupContractCount} no_setup Tax Form Profile ` +
        `contracts, got ${noSetupContracts.length}`,
    );
  }
  if (setupValues.length !== expectedSetupValueCount) {
    fail(
      `Expected ${expectedSetupValueCount} Tax Form Profile values, got ` +
        setupValues.length,
    );
  }
  if (
    evidenceRequiredSetupValues.length !==
    expectedEvidenceRequiredSetupValueCount
  ) {
    fail(
      `Expected ${expectedEvidenceRequiredSetupValueCount} evidence-required ` +
        `Tax Form Profile values, got ${evidenceRequiredSetupValues.length}`,
    );
  }

  validateUnique(
    forms.flatMap((form) => form.fields.map((field) => field.id)),
    "field ids",
  );

  const fieldById = new Map(
    forms.flatMap((form) => form.fields.map((field) => [field.id, field] as const)),
  );
  const expectOwnership = (
    id: string,
    provenance: Provenance,
    role: Role,
  ): void => {
    const field = fieldById.get(id);
    if (!field) fail(`Ownership guardrail targets missing field ${id}`);
    if (field.provenance !== provenance || field.role !== role) {
      fail(
        `${id} ownership drifted; expected ${provenance}/${role}, got ` +
          `${field.provenance}/${field.role}`,
      );
    }
    if (provenance !== "profile" && field.profileField !== null) {
      fail(`${id} non-profile ownership guardrail retained a profile key`);
    }
  };
  const expectSourceContract = (
    id: string,
    sourceKey: string | null,
    fixedValue: string | null,
  ): void => {
    const field = fieldById.get(id);
    if (!field) fail(`Source guardrail targets missing field ${id}`);
    if (
      field.sourceKey !== sourceKey ||
      field.fixedValue !== fixedValue
    ) {
      fail(`${id} explicit source contract drifted`);
    }
  };
  expectOwnership(
    "0605.1999-07-ENCS.input.atc_only_source_proven_pairs",
    "transaction",
    "filing",
  );
  expectOwnership(
    "0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs",
    "transaction",
    "filing",
  );
  expectOwnership(
    "0605.1999-07-ENCS.input.line_of_business_occupation",
    "profile",
    "filer",
  );
  expectOwnership("1601C.2018-01-ENCS.input.atc", "form_policy", "system");
  expectSourceContract(
    "1601C.2018-01-ENCS.input.atc",
    "form_policy.atc",
    "WW010",
  );
  expectOwnership(
    "0619F.2018-01-ENCS.input.tax_type_code",
    "form_policy",
    "system",
  );
  expectSourceContract(
    "0619F.2018-01-ENCS.input.tax_type_code",
    "form_policy.tax_type",
    "WB",
  );
  expectOwnership("0619E.2018-01-ENCS.input.atc", "form_policy", "system");
  expectSourceContract(
    "0619E.2018-01-ENCS.input.atc",
    "form_policy.atc",
    "WME10",
  );
  expectOwnership(
    "0619E.2018-01-ENCS.input.tax_type_code",
    "form_policy",
    "system",
  );
  expectSourceContract(
    "0619E.2018-01-ENCS.input.tax_type_code",
    "form_policy.tax_type",
    "WE",
  );
  expectOwnership(
    "1701Q.2018-01-ENCS.input.income_tax_rate_election",
    "taxpayer_year",
    "filing",
  );
  expectSourceContract(
    "1701Q.2018-01-ENCS.input.income_tax_rate_election",
    "income_tax_rate_election",
    null,
  );
  expectOwnership(
    "2551Q.2018-01-ENCS.input.what_income_tax_rates_are_you_availing",
    "tax_form_profile",
    "filer",
  );
  expectSourceContract(
    "2551Q.2018-01-ENCS.input.what_income_tax_rates_are_you_availing",
    "income_tax_rate_election",
    null,
  );

  for (const form of forms) {
    validateUnique(form.roles, `${form.code} roles`);
    validateUnique(
      form.profileRoles.map((role) => role.role),
      `${form.code} profile roles`,
    );
    validateUnique(
      form.consumedTaxpayerYearSettings,
      `${form.code} consumed taxpayer-year settings`,
    );
    for (const key of form.consumedTaxpayerYearSettings) {
      if (!taxpayerYearSettingKeyValues.includes(key)) {
        fail(`${form.code} consumes unknown taxpayer-year setting ${key}`);
      }
    }
    const expectedTaxpayerYearSettings: readonly TaxpayerYearSettingKey[] =
      form.code === "1701" || form.code === "1701Q"
        ? ["income_tax_rate_election", "deduction_method"]
        : [];
    if (
      JSON.stringify(form.consumedTaxpayerYearSettings) !==
      JSON.stringify(expectedTaxpayerYearSettings)
    ) {
      fail(
        `${form.code} taxpayer-year consumer contract drifted; expected ` +
          `${expectedTaxpayerYearSettings.join(", ") || "none"}, got ` +
          `${form.consumedTaxpayerYearSettings.join(", ") || "none"}`,
      );
    }
    if (form.status === "calendar_only" && form.fields.length !== 0) {
      fail(`${form.code} is calendar_only but has field definitions`);
    }
    if (
      form.status === "calendar_only" &&
      form.profileRoles.length !== 0
    ) {
      fail(`${form.code} is calendar_only but has profile-role definitions`);
    }
    if (form.status === "static_layout" && (!form.revision || !form.sourcePath)) {
      fail(`${form.code} static layout lacks revision/source path`);
    }
    if (
      form.status === "calendar_only" &&
      form.taxFormProfile.mode !== "calendar_only"
    ) {
      fail(`${form.code} calendar_only form exposes a Tax Form Profile`);
    }
    if (
      form.status === "calendar_only" &&
      (form.taxFormProfile.specRevision !== null ||
        form.taxFormProfile.specHash !== null ||
        form.taxFormProfile.values.length !== 0)
    ) {
      fail(`${form.code} calendar_only form has editable setup metadata`);
    }
    if (
      form.status === "static_layout" &&
      form.taxFormProfile.mode === "calendar_only"
    ) {
      fail(`${form.code} editor lacks a Tax Form Profile setup/no_setup contract`);
    }
    if (
      form.status === "static_layout" &&
      (form.taxFormProfile.specRevision === null ||
        form.taxFormProfile.specHash === null)
    ) {
      fail(`${form.code} editor Tax Form Profile contract lacks revision/hash`);
    }
    if (
      form.taxFormProfile.mode === "no_setup" &&
      form.taxFormProfile.values.length !== 0
    ) {
      fail(`${form.code} no_setup contract declares values`);
    }
    if (
      form.taxFormProfile.mode === "setup" &&
      form.taxFormProfile.values.length === 0
    ) {
      fail(`${form.code} setup contract has no values`);
    }
    validateUnique(
      form.taxFormProfile.values.map((value) => value.semanticKey),
      `${form.code} generated Tax Form Profile semantic keys`,
    );
    for (const value of form.taxFormProfile.values) {
      if (
        !form.profileRoles.some((profileRole) => profileRole.role === value.role)
      ) {
        fail(
          `${form.code} Tax Form Profile key ${value.semanticKey} uses ` +
            `undeclared profile role ${value.role}`,
        );
      }
      if (
        value.availability === "evidence_required" &&
        value.evidenceGate === null
      ) {
        fail(`${form.code} ${value.semanticKey} lacks an evidence gate`);
      }
      if (
        value.availability === "supported" &&
        value.evidenceGate !== null
      ) {
        fail(`${form.code} ${value.semanticKey} is supported but gated`);
      }
    }

    for (const profileRole of form.profileRoles) {
      if (!profileRoleValues.includes(profileRole.role)) {
        fail(`${form.code} has unknown profile role ${profileRole.role}`);
      }
      if (!profileCardinalityValues.includes(profileRole.cardinality)) {
        fail(
          `${form.code} ${profileRole.role} has unknown cardinality ` +
            profileRole.cardinality,
        );
      }
      if (!form.roles.includes(profileRole.role)) {
        fail(
          `${form.code} profile role ${profileRole.role} is undeclared`,
        );
      }
      if (profileRole.allowedSubjectKinds.length === 0) {
        fail(`${form.code} ${profileRole.role} allows no subject kinds`);
      }
      validateUnique(
        profileRole.allowedSubjectKinds,
        `${form.code} ${profileRole.role} allowed subject kinds`,
      );
      const distinctFrom = profileRole.distinctFrom ?? [];
      validateUnique(
        distinctFrom,
        `${form.code} ${profileRole.role} distinct profile roles`,
      );
      for (const otherRole of distinctFrom) {
        if (otherRole === profileRole.role) {
          fail(
            `${form.code} ${profileRole.role} cannot be distinct from itself`,
          );
        }
        if (!form.profileRoles.some((candidate) => candidate.role === otherRole)) {
          fail(
            `${form.code} ${profileRole.role} is distinct from undeclared ` +
              `profile role ${otherRole}`,
          );
        }
        const inverse = form.profileRoles
          .find((candidate) => candidate.role === otherRole)
          ?.distinctFrom?.includes(profileRole.role) ?? false;
        if (inverse && profileRole.role > otherRole) {
          fail(
            `${form.code} duplicates distinct-profile relation ` +
              `${profileRole.role}/${otherRole}`,
          );
        }
      }
      for (const kind of profileRole.allowedSubjectKinds) {
        if (!profileSubjectKindValues.includes(kind)) {
          fail(
            `${form.code} ${profileRole.role} has unknown subject kind ${kind}`,
          );
        }
      }
    }

    for (const field of form.fields) {
      if (!field.label || !field.provenance || !field.role || !field.valueType) {
        fail(`${field.id} has incomplete field metadata`);
      }
      if (!provenanceValues.includes(field.provenance)) {
        fail(`${field.id} has unknown provenance ${field.provenance}`);
      }
      if (!roleValues.includes(field.role)) {
        fail(`${field.id} has unknown role ${field.role}`);
      }
      if (!valueTypeValues.includes(field.valueType)) {
        fail(`${field.id} has unknown value type ${field.valueType}`);
      }
      if (!form.roles.includes(field.role)) {
        fail(`${field.id} uses undeclared role ${field.role}`);
      }
      if (
        field.profileField !== null &&
        !profileFieldKeyValues.includes(field.profileField)
      ) {
        fail(`${field.id} has unknown profile field ${field.profileField}`);
      }
      if (field.provenance === "profile" && field.profileField === null) {
        fail(`${field.id} profile field lacks a canonical profile key`);
      }
      if (
        field.provenance === "profile" &&
        field.profilePresence === null
      ) {
        fail(`${field.id} profile field lacks required/optional presence`);
      }
      if (field.provenance !== "profile" && field.profileField !== null) {
        fail(`${field.id} non-profile field has profile key ${field.profileField}`);
      }
      if (
        field.provenance !== "profile" &&
        field.profilePresence !== null
      ) {
        fail(`${field.id} non-profile field has profile presence`);
      }
      if (
        field.profilePresence !== null &&
        !profilePresenceValues.includes(field.profilePresence)
      ) {
        fail(`${field.id} has unknown profile presence ${field.profilePresence}`);
      }
      if (
        (field.provenance === "taxpayer_year" ||
          field.provenance === "tax_form_profile" ||
          field.provenance === "form_policy") !==
        (field.sourceKey !== null)
      ) {
        fail(
          `${field.id} taxpayer-year/form-profile/form-policy ownership must have exactly ` +
            "one explicit source key",
        );
      }
      if (
        (field.provenance === "form_policy") !== (field.fixedValue !== null)
      ) {
        fail(
          `${field.id} fixed values are required only for exact form policy`,
        );
      }
      if (
        field.provenance === "form_policy" &&
        (field.role !== "system" || !field.fixedValue?.trim())
      ) {
        fail(`${field.id} form policy must be a nonempty locked system value`);
      }
      if (
        field.provenance === "taxpayer_year" && field.role !== "filing"
      ) {
        fail(`${field.id} taxpayer-year setting must be consumed by filing`);
      }
      if (
        field.provenance === "tax_form_profile" &&
        field.role !== "filer" &&
        field.role !== "spouse"
      ) {
        fail(`${field.id} Tax Form Profile value must use a named profile role`);
      }
      if (
        field.provenance === "tax_form_profile" &&
        (!field.sourceKey ||
          !taxFormProfileSemanticKeyValues.includes(
            field.sourceKey as TaxFormProfileSemanticKey,
          ) ||
          !form.taxFormProfile.values.some(
            (value) => value.semanticKey === field.sourceKey,
          ))
      ) {
        fail(
          `${field.id} visible Tax Form Profile source is absent from the form's ` +
            "closed setup contract",
        );
      }
      if (
        field.provenance === "taxpayer_year" &&
        (!field.sourceKey ||
          !taxpayerYearSettingKeyValues.includes(
            field.sourceKey as TaxpayerYearSettingKey,
          ) ||
          !form.consumedTaxpayerYearSettings.includes(
            field.sourceKey as TaxpayerYearSettingKey,
          ))
      ) {
        fail(
          `${field.id} visible taxpayer-year source is absent from the form's ` +
            "closed consumer contract",
        );
      }
      if (
        field.provenance === "profile" &&
        field.role !== "filer" &&
        field.role !== "spouse"
      ) {
        fail(`${field.id} profile field must use a named profile role`);
      }
      if (
        field.provenance === "profile" &&
        !form.profileRoles.some((role) => role.role === field.role)
      ) {
        fail(`${field.id} has no profile-role specification`);
      }
    }

    for (const profileRole of form.profileRoles) {
      if (
        !form.fields.some(
          (field) =>
            field.provenance === "profile" &&
            field.role === profileRole.role,
        )
      ) {
        fail(
          `${form.code} profile role ${profileRole.role} has no targets`,
        );
      }
    }
  }
}

async function buildCatalog(): Promise<FormDefinition[]> {
  validateTaxFormProfileVocabulary();
  await Promise.all([
    validateSourceCoverage(),
    validateRegistryCoverage(),
    validateReusableFieldVocabulary(),
    validateSubjectKindVocabulary(),
  ]);
  const loadedEditors = await Promise.all(editorForms.map(loadEditorForm));
  const editorByCode = new Map(loadedEditors.map((form) => [form.code, form]));
  const forms = registryCodes.map<FormDefinition>(
    (code) =>
      editorByCode.get(code) ?? {
        code,
        ...formDisplayMetadata(code),
        revision: null,
        status: "calendar_only",
        ...filingPeriodPolicy(code),
        sourcePath: null,
        roles: [],
        profileRoles: [],
        consumedTaxpayerYearSettings: [],
        taxFormProfile: {
          mode: "calendar_only",
          specRevision: null,
          specHash: null,
          sourceEvidence: "calendar_only: no Native editor contract",
          values: [],
        },
        fields: [],
      },
  );
  validateCatalog(forms);
  return forms;
}

function zigString(value: string): string {
  return JSON.stringify(value)
    .replace(/\u2028/gu, "\\u{2028}")
    .replace(/\u2029/gu, "\\u{2029}");
}

function zigIdentifier(value: string): string {
  return value.replace(/[^A-Za-z0-9_]/gu, "_").toLowerCase();
}

function generateZig(forms: readonly FormDefinition[]): string {
  const catalogRevision = "tax-catalog-v2";
  const catalogSha256 = createHash("sha256")
    .update(JSON.stringify(forms))
    .digest("hex");
  const tableFieldCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.control === "table").length;
  const profileTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "profile").length;
  const optionalProfileTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.profilePresence === "optional").length;
  const taxpayerYearTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "taxpayer_year").length;
  const taxpayerYearConsumerFormCount = forms.filter(
    (form) => form.consumedTaxpayerYearSettings.length !== 0,
  ).length;
  const taxpayerYearConsumptionCount = forms.reduce(
    (count, form) => count + form.consumedTaxpayerYearSettings.length,
    0,
  );
  const formPolicyTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "form_policy").length;
  const setupContracts = forms.filter(
    (form) => form.taxFormProfile.mode === "setup",
  );
  const noSetupContracts = forms.filter(
    (form) => form.taxFormProfile.mode === "no_setup",
  );
  const setupValues = setupContracts.flatMap(
    (form) => form.taxFormProfile.values,
  );
  const evidenceRequiredSetupValues = setupValues.filter(
    (value) => value.availability === "evidence_required",
  );
  const sections: string[] = [
    "// GENERATED FILE - DO NOT EDIT.",
    "// Generated by scripts/tax-catalog/generate.ts from the TypeScript catalog",
    "// and the exact Native form sources.",
    "",
    'const std = @import("std");',
    "",
    `pub const catalog_revision = ${zigString(catalogRevision)};`,
    `pub const catalog_sha256 = ${zigString(catalogSha256)};`,
    "",
    `pub const Provenance = enum { ${provenanceValues.join(", ")} };`,
    `pub const Role = enum { ${roleValues.join(", ")} };`,
    `pub const ProfileCardinality = enum { ${profileCardinalityValues.join(", ")} };`,
    `pub const ProfilePresence = enum { ${profilePresenceValues.join(", ")} };`,
    `pub const ProfileSubjectKind = enum { ${profileSubjectKindValues.join(", ")} };`,
    `pub const ValueType = enum { ${valueTypeValues.join(", ")} };`,
    "pub const FieldStatus = enum { unbound_input, static_table, derived_display };",
    "pub const FormStatus = enum { calendar_only, static_layout };",
    "pub const FilingCadence = enum { monthly, quarterly, annual, on_demand };",
    `pub const TaxCategory = enum { ${taxCategoryValues.join(", ")} };`,
    `pub const TaxpayerYearSettingKey = enum { ${taxpayerYearSettingKeyValues.join(", ")} };`,
    `pub const TaxFormProfileSetupMode = enum { ${taxFormProfileSetupModeValues.join(", ")} };`,
    `pub const TaxFormProfileOwnership = enum { ${taxFormProfileOwnershipValues.join(", ")} };`,
    `pub const TaxFormProfileAvailability = enum { ${taxFormProfileAvailabilityValues.join(", ")} };`,
    `pub const TaxFormProfilePresence = enum { ${taxFormProfilePresenceValues.join(", ")} };`,
    `pub const TaxFormProfileValueType = enum { ${taxFormProfileValueTypeValues.join(", ")} };`,
    `pub const TaxFormProfileSourceKind = enum { ${taxFormProfileSourceKindValues.join(", ")} };`,
    `pub const TaxFormProfileValidationRule = enum { ${taxFormProfileValidationRuleValues.join(", ")} };`,
    `pub const TaxFormProfileSemanticKey = enum { ${taxFormProfileSemanticKeyValues.join(", ")} };`,
    "",
    "pub const FieldDefinition = struct {",
    "    id: []const u8,",
    "    label: []const u8,",
    "    provenance: Provenance,",
    "    role: Role,",
    "    value_type: ValueType,",
    "    status: FieldStatus,",
    "    profile_key: ?[]const u8,",
    "    profile_presence: ?ProfilePresence,",
    "    source_key: ?[]const u8,",
    "    fixed_value: ?[]const u8,",
    "    source_path: []const u8,",
    "    source_line: ?u32,",
    "    control: enum { input, table },",
    "};",
    "",
    "pub const ProfileRoleDefinition = struct {",
    "    role: Role,",
    "    cardinality: ProfileCardinality,",
    "    allowed_subjects: []const ProfileSubjectKind,",
    "    distinct_from: []const Role,",
    "};",
    "",
    "pub const TaxFormProfileValueDefinition = struct {",
    "    semantic_key: TaxFormProfileSemanticKey,",
    "    value_type: TaxFormProfileValueType,",
    "    role: Role,",
    "    presence: TaxFormProfilePresence,",
    "    validation_rule: TaxFormProfileValidationRule,",
    "    ownership: TaxFormProfileOwnership,",
    "    source_kind: TaxFormProfileSourceKind,",
    "    availability: TaxFormProfileAvailability,",
    "    source_evidence: []const u8,",
    "    evidence_gate: ?[]const u8,",
    "};",
    "",
    "pub const TaxFormProfileSpec = struct {",
    "    mode: TaxFormProfileSetupMode,",
    "    spec_revision: ?u32,",
    "    spec_hash: ?[]const u8,",
    "    source_evidence: []const u8,",
    "    values: []const TaxFormProfileValueDefinition,",
    "};",
    "",
    "pub const FormDefinition = struct {",
    "    code: []const u8,",
    "    display_title: []const u8,",
    "    tax_category: TaxCategory,",
    "    revision: ?[]const u8,",
    "    status: FormStatus,",
    "    cadence: FilingCadence,",
    "    min_period: ?u8,",
    "    max_period: ?u8,",
    "    source_path: ?[]const u8,",
    "    roles: []const Role,",
    "    profile_roles: []const ProfileRoleDefinition,",
    "    consumed_taxpayer_year_settings: []const TaxpayerYearSettingKey,",
    "    tax_form_profile: TaxFormProfileSpec,",
    "    fields: []const FieldDefinition,",
    "};",
    "",
  ];

  for (const form of forms.filter((item) => item.status === "static_layout")) {
    const name = zigIdentifier(`${form.code}_${form.revision}`);
    sections.push(`const roles_${name} = [_]Role{`);
    for (const role of form.roles) sections.push(`    .${role},`);
    sections.push("};", "");
    sections.push(`const profile_roles_${name} = [_]ProfileRoleDefinition{`);
    for (const role of form.profileRoles) {
      const distinctRoles = (role.distinctFrom ?? []).map(
        (other) => `.${other}`,
      );
      const distinctLiteral =
        distinctRoles.length === 0
          ? "&.{}"
          : distinctRoles.length === 1
            ? `&.{${distinctRoles[0]}}`
            : `&.{ ${distinctRoles.join(", ")} }`;
      sections.push(
        "    .{",
        `        .role = .${role.role},`,
        `        .cardinality = .${role.cardinality},`,
        `        .allowed_subjects = &.{ ${role.allowedSubjectKinds.map((kind) => `.${kind}`).join(", ")} },`,
        `        .distinct_from = ${distinctLiteral},`,
        "    },",
      );
    }
    sections.push("};", "");
    sections.push(
      `const tax_form_profile_values_${name} = [_]TaxFormProfileValueDefinition{`,
    );
    for (const value of form.taxFormProfile.values) {
      sections.push(
        "    .{",
        `        .semantic_key = .${value.semanticKey},`,
        `        .value_type = .${value.valueType},`,
        `        .role = .${value.role},`,
        `        .presence = .${value.presence},`,
        `        .validation_rule = .${value.validationRule},`,
        `        .ownership = .${value.ownership},`,
        `        .source_kind = .${value.sourceKind},`,
        `        .availability = .${value.availability},`,
        `        .source_evidence = ${zigString(value.sourceEvidence)},`,
        `        .evidence_gate = ${value.evidenceGate === null ? "null" : zigString(value.evidenceGate)},`,
        "    },",
      );
    }
    sections.push(
      "};",
      "",
      `const tax_form_profile_spec_${name} = TaxFormProfileSpec{`,
      `    .mode = .${form.taxFormProfile.mode},`,
      `    .spec_revision = ${form.taxFormProfile.specRevision ?? "null"},`,
      `    .spec_hash = ${form.taxFormProfile.specHash === null ? "null" : zigString(form.taxFormProfile.specHash)},`,
      `    .source_evidence = ${zigString(form.taxFormProfile.sourceEvidence)},`,
      `    .values = &tax_form_profile_values_${name},`,
      "};",
      "",
    );
    sections.push(`const fields_${name} = [_]FieldDefinition{`);
    for (const field of form.fields) {
      sections.push(
        "    .{",
        `        .id = ${zigString(field.id)},`,
        `        .label = ${zigString(field.label)},`,
        `        .provenance = .${field.provenance},`,
        `        .role = .${field.role},`,
        `        .value_type = .${field.valueType},`,
        `        .status = .${field.status},`,
        `        .profile_key = ${field.profileField === null ? "null" : zigString(field.profileField)},`,
        `        .profile_presence = ${field.profilePresence === null ? "null" : `.${field.profilePresence}`},`,
        `        .source_key = ${field.sourceKey === null ? "null" : zigString(field.sourceKey)},`,
        `        .fixed_value = ${field.fixedValue === null ? "null" : zigString(field.fixedValue)},`,
        `        .source_path = ${zigString(field.sourcePath)},`,
        `        .source_line = ${field.sourceLine ?? "null"},`,
        `        .control = .${field.control},`,
        "    },",
      );
    }
    sections.push("};", "");
  }

  sections.push("pub const forms = [_]FormDefinition{");
  for (const form of forms) {
    if (form.status === "calendar_only") {
      sections.push(
        "    .{",
        `        .code = ${zigString(form.code)},`,
        `        .display_title = ${zigString(form.displayTitle)},`,
        `        .tax_category = .${form.taxCategory},`,
        "        .revision = null,",
        "        .status = .calendar_only,",
        `        .cadence = .${form.cadence},`,
        `        .min_period = ${form.minPeriod === null ? "null" : String(form.minPeriod)},`,
        `        .max_period = ${form.maxPeriod === null ? "null" : String(form.maxPeriod)},`,
        "        .source_path = null,",
        "        .roles = &.{},",
        "        .profile_roles = &.{},",
        "        .consumed_taxpayer_year_settings = &.{},",
        "        .tax_form_profile = .{",
        "            .mode = .calendar_only,",
        "            .spec_revision = null,",
        "            .spec_hash = null,",
        `            .source_evidence = ${zigString(form.taxFormProfile.sourceEvidence)},`,
        "            .values = &.{},",
        "        },",
        "        .fields = &.{},",
        "    },",
      );
      continue;
    }

    const name = zigIdentifier(`${form.code}_${form.revision}`);
    const consumedTaxpayerYearSettings =
      form.consumedTaxpayerYearSettings.length === 0
        ? "&.{}"
        : `&.{ ${form.consumedTaxpayerYearSettings.map((key) => `.${key}`).join(", ")} }`;
    sections.push(
      "    .{",
      `        .code = ${zigString(form.code)},`,
      `        .display_title = ${zigString(form.displayTitle)},`,
      `        .tax_category = .${form.taxCategory},`,
      `        .revision = ${zigString(form.revision ?? "")},`,
      "        .status = .static_layout,",
      `        .cadence = .${form.cadence},`,
      `        .min_period = ${form.minPeriod === null ? "null" : String(form.minPeriod)},`,
      `        .max_period = ${form.maxPeriod === null ? "null" : String(form.maxPeriod)},`,
      `        .source_path = ${zigString(form.sourcePath ?? "")},`,
      `        .roles = &roles_${name},`,
      `        .profile_roles = &profile_roles_${name},`,
      `        .consumed_taxpayer_year_settings = ${consumedTaxpayerYearSettings},`,
      `        .tax_form_profile = tax_form_profile_spec_${name},`,
      `        .fields = &fields_${name},`,
      "    },",
    );
  }
  sections.push(
    "};",
    "",
    `pub const registry_count: usize = ${expectedRegistryCount};`,
    `pub const editor_count: usize = ${expectedEditorCount};`,
    `pub const calendar_only_count: usize = ${expectedCalendarOnlyCount};`,
    `pub const native_input_count: usize = ${expectedInputCount};`,
    `pub const table_field_count: usize = ${tableFieldCount};`,
    `pub const profile_target_count: usize = ${profileTargetCount};`,
    `pub const optional_profile_target_count: usize = ${optionalProfileTargetCount};`,
    `pub const taxpayer_year_target_count: usize = ${taxpayerYearTargetCount};`,
    `pub const taxpayer_year_consumer_form_count: usize = ${taxpayerYearConsumerFormCount};`,
    `pub const taxpayer_year_consumption_count: usize = ${taxpayerYearConsumptionCount};`,
    `pub const form_policy_target_count: usize = ${formPolicyTargetCount};`,
    `pub const tax_form_profile_setup_count: usize = ${setupContracts.length};`,
    `pub const tax_form_profile_no_setup_count: usize = ${noSetupContracts.length};`,
    `pub const tax_form_profile_value_count: usize = ${setupValues.length};`,
    `pub const tax_form_profile_evidence_required_value_count: usize = ${evidenceRequiredSetupValues.length};`,
    "",
    "pub fn findForm(code: []const u8) ?*const FormDefinition {",
    "    for (&forms) |*form| {",
    "        if (std.mem.eql(u8, form.code, code)) return form;",
    "    }",
    "    return null;",
    "}",
    "",
    "pub fn consumesTaxpayerYearSetting(",
    "    form: *const FormDefinition,",
    "    key: TaxpayerYearSettingKey,",
    ") bool {",
    "    for (form.consumed_taxpayer_year_settings) |consumed| {",
    "        if (consumed == key) return true;",
    "    }",
    "    return false;",
    "}",
    "",
    "pub fn findTaxFormProfileValue(",
    "    spec: *const TaxFormProfileSpec,",
    "    key: TaxFormProfileSemanticKey,",
    ") ?*const TaxFormProfileValueDefinition {",
    "    for (spec.values) |*value| {",
    "        if (value.semantic_key == key) return value;",
    "    }",
    "    return null;",
    "}",
    "",
  );
  return `${sections.join("\n").replace(/\n+$/u, "")}\n`;
}

function markdownCell(value: string): string {
  return value.replaceAll("|", "\\|").replace(/\s+/gu, " ").trim();
}

function generateMarkdown(forms: readonly FormDefinition[]): string {
  const inputCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.control === "input").length;
  const tableCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.control === "table").length;
  const profileTargets = forms
    .flatMap((form) =>
      form.fields.map((field) => ({ form, field })),
    )
    .filter(({ field }) => field.provenance === "profile");
  const taxpayerYearTargets = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "taxpayer_year");
  const taxpayerYearConsumerForms = forms.filter(
    (form) => form.consumedTaxpayerYearSettings.length !== 0,
  );
  const taxpayerYearConsumptionCount = taxpayerYearConsumerForms.reduce(
    (count, form) => count + form.consumedTaxpayerYearSettings.length,
    0,
  );
  const formPolicyTargets = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "form_policy");
  const editorDefinitions = forms.filter(
    (form) => form.status === "static_layout",
  );
  const setupContracts = editorDefinitions.filter(
    (form) => form.taxFormProfile.mode === "setup",
  );
  const noSetupContracts = editorDefinitions.filter(
    (form) => form.taxFormProfile.mode === "no_setup",
  );
  const setupValues = setupContracts.flatMap(
    (form) => form.taxFormProfile.values,
  );
  const evidenceRequiredSetupValues = setupValues.filter(
    (value) => value.availability === "evidence_required",
  );
  const lines = [
    "# Form field catalog",
    "",
    "<!-- GENERATED FILE - DO NOT EDIT. Run `npm run generate:tax-catalog`. -->",
    "",
    "This catalog is the checked boundary between the 51-code calendar registry,",
    "the 10 exact Native editor revisions currently present, and future profile",
    "projection/domain work. `calendar_only` means that no editor field contract",
    "exists yet; it does not imply filing support.",
    "",
    "## Coverage",
    "",
    `- Registry codes: ${forms.length}`,
    `- Native editor revisions: ${forms.filter((form) => form.status === "static_layout").length}`,
    `- Calendar-only codes: ${forms.filter((form) => form.status === "calendar_only").length}`,
    `- Native input controls inventoried: ${inputCount}`,
    `- Meaningful static-table fields inventoried: ${tableCount}`,
    `- Direct profile projection targets: ${profileTargets.length}`,
    `- Optional profile projection targets: ${profileTargets.filter(({ field }) => field.profilePresence === "optional").length}`,
    `- Visible taxpayer-year setting targets: ${taxpayerYearTargets.length}`,
    `- Taxpayer-year consumer forms: ${taxpayerYearConsumerForms.length}`,
    `- Declared taxpayer-year setting consumptions: ${taxpayerYearConsumptionCount}`,
    `- Fixed form-policy targets: ${formPolicyTargets.length}`,
    `- Nonempty Tax Form Profile setup contracts: ${setupContracts.length}`,
    `- Explicit \`no_setup\` editor contracts: ${noSetupContracts.length}`,
    `- Tax Form Profile semantic values: ${setupValues.length}`,
    `- Evidence-required (unsupported) setup values: ${evidenceRequiredSetupValues.length}`,
    "",
    "| Code | Title | Tax category | Revision | Status | Tax Form Profile | Taxpayer-year settings | Cadence | Periods | Inputs | Table fields | Source |",
    "|---|---|---|---|---|---|---|---|---|---:|---:|---|",
  ];

  for (const form of forms) {
    const inputs = form.fields.filter((field) => field.control === "input").length;
    const tables = form.fields.filter((field) => field.control === "table").length;
    const periods = form.minPeriod === null
      ? "—"
      : `${form.minPeriod}-${form.maxPeriod}`;
    lines.push(
      `| ${form.code} | ${markdownCell(form.displayTitle)} | ${form.taxCategory} | ${form.revision ?? "—"} | ${form.status} | ${form.taxFormProfile.mode} | ${form.consumedTaxpayerYearSettings.map((key) => `\`${key}\``).join(", ") || "—"} | ${form.cadence} | ${periods} | ${inputs} | ${tables} | ${form.sourcePath ?? "—"} |`,
    );
  }

  lines.push(
    "",
    "## Taxpayer-year consumer contracts",
    "",
    "A form declares every shared taxpayer/year setting it consumes, including",
    "settings with no visible control in the current Native editor. This contract",
    "is separate from visible-field provenance and from Tax Form Profile setup.",
    "Every form not listed below has an explicit empty consumer slice.",
    "",
    "| Form revision | Consumed settings | Visible taxpayer-year targets |",
    "|---|---|---:|",
  );
  for (const form of taxpayerYearConsumerForms) {
    const visibleTargets = form.fields.filter(
      (field) => field.provenance === "taxpayer_year",
    ).length;
    lines.push(
      `| ${form.code} ${form.revision ?? "—"} | ${form.consumedTaxpayerYearSettings.map((key) => `\`${key}\``).join(", ")} | ${visibleTargets} |`,
    );
  }

  lines.push(
    "",
    "## Tax Form Profile setup contracts",
    "",
    "Every Native editor has either a nonempty typed `setup` contract or an",
    "explicit `no_setup` contract. The 41 `calendar_only` entries are explicitly",
    "non-editable and have no setup values. `evidence_required` means the key is",
    "known but unsupported: it cannot be edited or persisted until its gate is",
    "resolved. Base profile facts, taxpayer-year settings, filing transactions,",
    "schedules, amounts, payments, rates, elections, and calculated values are",
    "not Tax Form Profile values.",
    "",
    "The ownership vocabulary supports `binding_selection`, `yearly_value`, and",
    "`transaction_default`. The current approved contracts contain only stable",
    "binding selections. There are no approved form-specific yearly values or",
    "transaction defaults; this is intentional rather than an inferred omission.",
    "",
    "| Form revision | Mode | Spec revision | SHA-256 | Values | Supported | Evidence required | Contract evidence |",
    "|---|---|---:|---|---:|---:|---:|---|",
  );
  for (const form of editorDefinitions) {
    const supported = form.taxFormProfile.values.filter(
      (value) => value.availability === "supported",
    ).length;
    const evidenceRequired = form.taxFormProfile.values.filter(
      (value) => value.availability === "evidence_required",
    ).length;
    lines.push(
      `| ${form.code} ${form.revision} | ${form.taxFormProfile.mode} | ${form.taxFormProfile.specRevision ?? "—"} | \`${form.taxFormProfile.specHash ?? "—"}\` | ${form.taxFormProfile.values.length} | ${supported} | ${evidenceRequired} | ${markdownCell(form.taxFormProfile.sourceEvidence)} |`,
    );
  }

  lines.push(
    "",
    "| Form revision | Semantic key | Value type | Role | Presence | Validation | Ownership | Source kind | Availability | Source evidence | Blocking evidence gate |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
  );
  for (const form of setupContracts) {
    for (const value of form.taxFormProfile.values) {
      lines.push(
        `| ${form.code} ${form.revision} | \`${value.semanticKey}\` | ${value.valueType} | ${value.role} | ${value.presence} | ${value.validationRule} | ${value.ownership} | ${value.sourceKind} | ${value.availability} | ${markdownCell(value.sourceEvidence)} | ${value.evidenceGate === null ? "—" : markdownCell(value.evidenceGate)} |`,
      );
    }
  }

  lines.push(
    "",
    "## Classification",
    "",
    "Every Native input is joined to exact stable-ID metadata declared in",
    "`scripts/tax-catalog/catalog.ts`; labels and placeholders are not used to",
    "infer ownership, role, value type, or profile projection.",
    "",
    "- `profile`: reusable taxpayer facts projected through a named `filer` or `spouse` role.",
    "- `taxpayer_year`: a shared taxpayer/year setting consumed read-only by a filing.",
    "- `form_policy`: a locked constant for the exact form revision, never editable profile data.",
    "- `transaction`: values belonging to one return or filing decision.",
    "- `derived`: calculated values; an input-shaped current control is still recorded as unbound.",
    "- `filing_context`: period, revision intent, or other draft identity.",
    "- `external`: evidence, payment references, certificates, attachments, or policy-sourced facts.",
    "- Profile-role cardinality controls whether a named binding is required; target presence separately controls whether a missing capability is an error.",
    "",
    "## Reusable profile projection matrix",
    "",
    "Only direct profile-sourced form targets appear here. Repeated schedule rows",
    "(including 2551Q Schedule 1 ATC rows) remain filing data and are deliberately",
    "excluded even when a selected registration may help compose a row.",
    "",
    "| Form revision | Named role | Cardinality | Allowed subjects | Presence | Canonical profile key | Stable target field |",
    "|---|---|---|---|---|---|---|",
  );

  for (const { form, field } of profileTargets) {
    const role = form.profileRoles.find(
      (candidate) => candidate.role === field.role,
    );
    if (!role || !field.profilePresence) {
      fail(`${field.id} lacks complete profile projection policy`);
    }
    lines.push(
      `| ${form.code} ${form.revision} | ${field.role} | ${role.cardinality} | ${role.allowedSubjectKinds.join(", ")} | ${field.profilePresence} | \`${field.profileField}\` | \`${field.id}\` |`,
    );
  }
  lines.push("");

  for (const form of forms.filter((item) => item.status === "static_layout")) {
    lines.push(
      `## ${form.code} — ${form.revision}`,
      "",
      `Source: \`${form.sourcePath}\``,
      "",
      `Tax Form Profile: \`${form.taxFormProfile.mode}\`, spec revision ${form.taxFormProfile.specRevision}, SHA-256 \`${form.taxFormProfile.specHash}\``,
      "",
      `Consumed taxpayer-year settings: ${form.consumedTaxpayerYearSettings.map((key) => `\`${key}\``).join(", ") || "none"}`,
      "",
      `Named roles: ${form.roles.map((role) => `\`${role}\``).join(", ")}`,
      "",
      "Profile binding policy:",
      "",
      "| Profile role | Cardinality | Allowed subject kinds |",
      "|---|---|---|",
    );
    for (const role of form.profileRoles) {
      lines.push(
        `| ${role.role} | ${role.cardinality} | ${role.allowedSubjectKinds.join(", ")} |`,
      );
    }
    lines.push(
      "",
      "| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |",
      "|---|---|---|---|---|---|---|---|---|---|---|",
    );

    for (const field of form.fields) {
      const location =
        field.sourceLine === null
          ? `${field.sourcePath} (table schema)`
          : `${field.sourcePath}:${field.sourceLine}`;
      lines.push(
        `| \`${field.id}\` | ${markdownCell(field.label)} | ${field.provenance} | ${field.profileField ?? "—"} | ${field.profilePresence ?? "—"} | ${field.sourceKey ?? "—"} | ${field.fixedValue ?? "—"} | ${field.role} | ${field.valueType} | ${field.status} | \`${location}\` |`,
      );
    }
    lines.push("");
  }

  return `${lines.join("\n").replace(/\n+$/u, "")}\n`;
}

async function emit(
  relativePath: string,
  expected: string,
  checkOnly: boolean,
): Promise<boolean> {
  const absolutePath = path.join(projectRoot, relativePath);
  let current: string | null = null;
  try {
    current = await readFile(absolutePath, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }

  if (current === expected) return false;
  if (checkOnly) {
    fail(
      `${relativePath} is missing or stale; run npm run generate:tax-catalog`,
    );
  }

  await mkdir(path.dirname(absolutePath), { recursive: true });
  await writeFile(absolutePath, expected, "utf8");
  return true;
}

async function main(): Promise<void> {
  const checkOnly = process.argv.slice(2).includes("--check");
  const forms = await buildCatalog();
  const changed = [
    await emit(generatedZigPath, generateZig(forms), checkOnly),
    await emit(generatedMarkdownPath, generateMarkdown(forms), checkOnly),
  ].filter(Boolean).length;

  if (checkOnly) {
    const profileTargetCount = forms
      .flatMap((form) => form.fields)
      .filter((field) => field.provenance === "profile").length;
    const optionalProfileTargetCount = forms
      .flatMap((form) => form.fields)
      .filter(
        (field) =>
          field.provenance === "profile" && field.profilePresence === "optional",
      ).length;
    const taxpayerYearTargetCount = forms
      .flatMap((form) => form.fields)
      .filter((field) => field.provenance === "taxpayer_year").length;
    const taxpayerYearConsumerForms = forms.filter(
      (form) => form.consumedTaxpayerYearSettings.length !== 0,
    );
    const taxpayerYearConsumptionCount = taxpayerYearConsumerForms.reduce(
      (count, form) => count + form.consumedTaxpayerYearSettings.length,
      0,
    );
    const formPolicyTargetCount = forms
      .flatMap((form) => form.fields)
      .filter((field) => field.provenance === "form_policy").length;
    const setupContracts = forms.filter(
      (form) => form.taxFormProfile.mode === "setup",
    );
    const noSetupContracts = forms.filter(
      (form) => form.taxFormProfile.mode === "no_setup",
    );
    const setupValues = setupContracts.flatMap(
      (form) => form.taxFormProfile.values,
    );
    const evidenceRequiredSetupValues = setupValues.filter(
      (value) => value.availability === "evidence_required",
    );
    process.stdout.write(
      `tax-catalog: verified ${forms.length} codes, ${forms.filter((form) => form.status === "static_layout").length} editors, ${forms.filter((form) => form.status === "calendar_only").length} calendar-only forms, ${forms.flatMap((form) => form.fields).length} explicitly owned Native inputs, ${profileTargetCount} profile targets (${optionalProfileTargetCount} optional), ${taxpayerYearTargetCount} visible taxpayer-year targets, ${taxpayerYearConsumerForms.length} taxpayer-year consumer forms (${taxpayerYearConsumptionCount} setting consumptions), ${formPolicyTargetCount} form-policy targets, ${setupContracts.length} setup contracts, ${noSetupContracts.length} no_setup contracts, and ${setupValues.length} setup values (${evidenceRequiredSetupValues.length} evidence-required).\n`,
    );
  } else if (changed === 0) {
    process.stdout.write("tax-catalog: generated outputs are already up to date.\n");
  } else {
    process.stdout.write(`tax-catalog: updated ${changed} generated outputs.\n`);
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`tax-catalog: ${message}\n`);
  process.exitCode = 1;
});
