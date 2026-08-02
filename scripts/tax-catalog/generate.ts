#!/usr/bin/env node

import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  editorForms,
  filingCadenceValues,
  filingPeriodPolicy,
  formDisplayMetadata,
  formDisplayMetadataByCode,
  inferProfileField,
  inferProvenance,
  inferRole,
  inferValueType,
  profileCardinalityValues,
  provenanceValues,
  profileFieldKeyValues,
  profilePresenceValues,
  profileRoleValues,
  profileSubjectKindValues,
  registryCodes,
  roleValues,
  taxCategoryValues,
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
  readonly sourcePath: string;
  readonly sourceLine: number | null;
  readonly control: "input" | "table";
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
  readonly fields: readonly FieldDefinition[];
}

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "../..");
const generatedZigPath = "src/forms/generated/catalog.zig";
const generatedMarkdownPath = "docs/tax-profile/FORM_FIELD_CATALOG.md";
const expectedRegistryCount = 51;
const expectedEditorCount = 10;
const expectedCalendarOnlyCount = 41;
const expectedInputCount = 299;
const expectedProfileTargetCount = 72;
const expectedOptionalProfileTargetCount = 9;

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
  const tokenPattern =
    /<text\b[^>]*>([^<]*)<\/text>|<input\b([^>]*)\/?>/gu;
  const duplicateIds = new Map<string, number>();
  const fields: FieldDefinition[] = [];
  let lastLabel = "";

  for (const match of source.matchAll(tokenPattern)) {
    if (match[1] !== undefined) {
      const candidate = decodeText(match[1]);
      if (candidate) lastLabel = candidate;
      continue;
    }

    if (match[2] === undefined) continue;
    if (!lastLabel) {
      fail(`${spec.sourcePath}:${sourceLineAt(source, match.index)} input has no label`);
    }

    const placeholderMatch = /\bplaceholder="([^"]*)"/u.exec(match[2]);
    const placeholder = decodeText(placeholderMatch?.[1] ?? "");
    const baseId = slug(lastLabel);
    const occurrence = (duplicateIds.get(baseId) ?? 0) + 1;
    duplicateIds.set(baseId, occurrence);
    const localId = occurrence === 1 ? baseId : `${baseId}_${occurrence}`;
    const id = `${spec.code}.${spec.revision}.input.${localId}`;
    const provenance = inferProvenance(lastLabel);

    fields.push({
      id,
      label: lastLabel,
      provenance,
      role: inferRole(lastLabel, provenance),
      valueType: inferValueType(lastLabel, placeholder),
      status: "unbound_input",
      profileField:
        provenance === "profile" ? inferProfileField(lastLabel) : null,
      profilePresence:
        provenance === "profile"
          ? spec.profileTargetPresence?.[id] ?? "required"
          : null,
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

  validateUnique(
    forms.flatMap((form) => form.fields.map((field) => field.id)),
    "field ids",
  );

  for (const form of forms) {
    validateUnique(form.roles, `${form.code} roles`);
    validateUnique(
      form.profileRoles.map((role) => role.role),
      `${form.code} profile roles`,
    );
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
  const tableFieldCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.control === "table").length;
  const profileTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.provenance === "profile").length;
  const optionalProfileTargetCount = forms
    .flatMap((form) => form.fields)
    .filter((field) => field.profilePresence === "optional").length;
  const sections: string[] = [
    "// GENERATED FILE - DO NOT EDIT.",
    "// Generated by scripts/tax-catalog/generate.ts from the TypeScript catalog",
    "// and the exact Native form sources.",
    "",
    'const std = @import("std");',
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
        "        .fields = &.{},",
        "    },",
      );
      continue;
    }

    const name = zigIdentifier(`${form.code}_${form.revision}`);
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
    "",
    "pub fn findForm(code: []const u8) ?*const FormDefinition {",
    "    for (&forms) |*form| {",
    "        if (std.mem.eql(u8, form.code, code)) return form;",
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
    "",
    "| Code | Title | Tax category | Revision | Status | Cadence | Periods | Inputs | Table fields | Source |",
    "|---|---|---|---|---|---|---|---:|---:|---|",
  ];

  for (const form of forms) {
    const inputs = form.fields.filter((field) => field.control === "input").length;
    const tables = form.fields.filter((field) => field.control === "table").length;
    const periods = form.minPeriod === null
      ? "—"
      : `${form.minPeriod}-${form.maxPeriod}`;
    lines.push(
      `| ${form.code} | ${markdownCell(form.displayTitle)} | ${form.taxCategory} | ${form.revision ?? "—"} | ${form.status} | ${form.cadence} | ${periods} | ${inputs} | ${tables} | ${form.sourcePath ?? "—"} |`,
    );
  }

  lines.push(
    "",
    "## Classification",
    "",
    "- `profile`: reusable taxpayer facts projected through a named `filer` or `spouse` role.",
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
      "| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |",
      "|---|---|---|---|---|---|---|---|---|",
    );

    for (const field of form.fields) {
      const location =
        field.sourceLine === null
          ? `${field.sourcePath} (table schema)`
          : `${field.sourcePath}:${field.sourceLine}`;
      lines.push(
        `| \`${field.id}\` | ${markdownCell(field.label)} | ${field.provenance} | ${field.profileField ?? "—"} | ${field.profilePresence ?? "—"} | ${field.role} | ${field.valueType} | ${field.status} | \`${location}\` |`,
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
    process.stdout.write(
      `tax-catalog: verified ${forms.length} codes, 10 editors, 41 calendar-only forms, 299 Native inputs, and 72 profile targets (9 optional).\n`,
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
