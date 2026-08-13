#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

export type SourceManifest = {
  readonly source_name: string;
  readonly source_url: string;
  readonly source_archive_member: string;
  readonly source_retrieved_at: string;
  readonly source_last_modified: string;
  readonly retrieved_archive_sha256: string;
  readonly source_data_sha256: string;
  readonly source_data_byte_length: number;
  readonly expected_row_count: number;
  readonly expected_unique_code_count: number;
  readonly expected_empty_region_count: number;
  readonly expected_empty_province_count: number;
  readonly phlpost_baseline_retrieved_at: string;
  readonly phlpost_baseline_source_sha256: string;
  readonly expected_phlpost_baseline_code_count: number;
  readonly phlpost_baseline_codes: readonly string[];
  readonly license: string;
  readonly license_url: string;
  readonly attribution: string;
  readonly publisher_url: string;
  readonly format_reference_url: string;
};

export type PostalEntry = {
  readonly code: string;
  readonly locality: string;
  readonly region: string;
  readonly province: string;
};

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "../..");
const manifestPath = path.join(scriptDirectory, "source-manifest.json");
const sourceDataPath = path.join(scriptDirectory, "data/PH.txt");
export const generatedPath = path.join(
  projectRoot,
  "src/tax_profile/philippine_postal_reference.zig",
);

function fail(message: string): never {
  throw new Error(message);
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function zigString(value: string): string {
  return JSON.stringify(value)
    .replaceAll("\\u2028", "\\u{2028}")
    .replaceAll("\\u2029", "\\u{2029}");
}

export function parseGeoNamesPostalData(source: string): PostalEntry[] {
  if (!source.endsWith("\n")) fail("GeoNames PH.txt must end with a newline");

  const entries: PostalEntry[] = [];
  const identities = new Set<string>();
  const lines = source.slice(0, -1).split("\n");

  for (const [index, line] of lines.entries()) {
    const fields = line.split("\t");
    const row = index + 1;
    if (fields.length !== 12) {
      fail(`GeoNames row ${row} has ${fields.length} columns; expected 12`);
    }
    if (fields[0] !== "PH") fail(`GeoNames row ${row} is not a PH record`);

    const code = fields[1];
    const locality = fields[2].trim();
    const region = fields[3].trim();
    const province = fields[5].trim();
    if (!/^[0-9]{4}$/u.test(code)) {
      fail(`GeoNames row ${row} has invalid postal code ${JSON.stringify(code)}`);
    }
    if (!locality) fail(`GeoNames row ${row} has no place name`);

    const identity = `${code}\u0000${locality}\u0000${province}\u0000${region}`;
    if (identities.has(identity)) {
      fail(`GeoNames row ${row} duplicates an earlier postal identity`);
    }
    identities.add(identity);
    entries.push({ code, locality, region, province });
  }

  return entries;
}

export function validateSnapshot(
  source: string,
  entries: readonly PostalEntry[],
  manifest: SourceManifest,
): void {
  if (Buffer.byteLength(source, "utf8") !== manifest.source_data_byte_length) {
    fail("GeoNames PH.txt byte length does not match source manifest");
  }
  if (sha256(source) !== manifest.source_data_sha256) {
    fail("GeoNames PH.txt SHA-256 does not match source manifest");
  }
  if (entries.length !== manifest.expected_row_count) {
    fail(`GeoNames PH.txt yielded ${entries.length} rows; expected ${manifest.expected_row_count}`);
  }

  const uniqueCodeCount = new Set(entries.map((entry) => entry.code)).size;
  if (uniqueCodeCount !== manifest.expected_unique_code_count) {
    fail(
      `GeoNames PH.txt yielded ${uniqueCodeCount} unique codes; expected ` +
        `${manifest.expected_unique_code_count}`,
    );
  }

  const emptyRegionCount = entries.filter((entry) => !entry.region).length;
  if (emptyRegionCount !== manifest.expected_empty_region_count) {
    fail(
      `GeoNames PH.txt yielded ${emptyRegionCount} empty regions; expected ` +
        `${manifest.expected_empty_region_count}`,
    );
  }

  const emptyProvinceCount = entries.filter((entry) => !entry.province).length;
  if (emptyProvinceCount !== manifest.expected_empty_province_count) {
    fail(
      `GeoNames PH.txt yielded ${emptyProvinceCount} empty provinces; expected ` +
      `${manifest.expected_empty_province_count}`,
    );
  }

  validatePhlpostBaseline(entries, manifest);
}

export function validatePhlpostBaseline(
  entries: readonly PostalEntry[],
  manifest: Pick<
    SourceManifest,
    "expected_phlpost_baseline_code_count" | "phlpost_baseline_codes"
  >,
): void {
  if (
    manifest.phlpost_baseline_codes.length !==
    manifest.expected_phlpost_baseline_code_count
  ) {
    fail(
      `PHLPost baseline has ${manifest.phlpost_baseline_codes.length} codes; expected ` +
        `${manifest.expected_phlpost_baseline_code_count}`,
    );
  }

  for (const [index, code] of manifest.phlpost_baseline_codes.entries()) {
    if (!/^[0-9]{4}$/u.test(code)) {
      fail(`PHLPost baseline contains invalid code ${JSON.stringify(code)}`);
    }
    if (index > 0 && manifest.phlpost_baseline_codes[index - 1] >= code) {
      fail("PHLPost baseline codes must be unique and strictly sorted");
    }
  }

  const availableCodes = new Set(entries.map((entry) => entry.code));
  const missingPhlpostCodes = manifest.phlpost_baseline_codes.filter(
    (code) => !availableCodes.has(code),
  );
  if (missingPhlpostCodes.length > 0) {
    fail(
      "GeoNames PH.txt is missing codes from the pinned PHLPost baseline: " +
        missingPhlpostCodes.join(", "),
    );
  }
}

export function renderPostalReference(
  entries: readonly PostalEntry[],
  manifest: SourceManifest,
): string {
  const lines = [
    "//! GENERATED FILE - DO NOT EDIT.",
    "//! Generated by scripts/postal-reference/generate.ts.",
    `//! Source: ${manifest.source_url} (${manifest.source_archive_member})`,
    `//! Retrieved: ${manifest.source_retrieved_at}`,
    `//! Last-Modified: ${manifest.source_last_modified}`,
    `//! Source data SHA-256: ${manifest.source_data_sha256}`,
    `//! PHLPost reconciliation baseline: ${manifest.phlpost_baseline_retrieved_at}`,
    `//! PHLPost response SHA-256: ${manifest.phlpost_baseline_source_sha256}`,
    `//! License: ${manifest.license} (${manifest.license_url})`,
    `//! Attribution: ${manifest.attribution} (${manifest.publisher_url})`,
    "//!",
    "//! GeoNames is a broad, reusable suggestion reference, not the Philippine",
    "//! postal authority and not a claim of accuracy or completeness. Profiles",
    "//! persist only the selected four-digit code, and well-formed typed codes",
    "//! remain valid even when absent from this snapshot.",
    "",
    'const std = @import("std");',
    "",
    `pub const source_name = ${zigString(manifest.source_name)};`,
    `pub const source_url = ${zigString(manifest.source_url)};`,
    `pub const source_retrieved_at = ${zigString(manifest.source_retrieved_at)};`,
    `pub const source_last_modified = ${zigString(manifest.source_last_modified)};`,
    `pub const retrieved_archive_sha256 = ${zigString(manifest.retrieved_archive_sha256)};`,
    `pub const source_data_sha256 = ${zigString(manifest.source_data_sha256)};`,
    `pub const source_data_byte_length: usize = ${manifest.source_data_byte_length};`,
    `pub const valid_row_count: usize = ${entries.length};`,
    `pub const unique_code_count: usize = ${manifest.expected_unique_code_count};`,
    `pub const phlpost_baseline_code_count: usize = ${manifest.phlpost_baseline_codes.length};`,
    `pub const license_name = ${zigString(manifest.license)};`,
    `pub const license_url = ${zigString(manifest.license_url)};`,
    `pub const attribution = ${zigString(manifest.attribution)};`,
    `pub const publisher_url = ${zigString(manifest.publisher_url)};`,
    "",
    "pub const Entry = struct {",
    "    region: []const u8,",
    "    province: []const u8,",
    "    locality: []const u8,",
    "    code: []const u8,",
    "};",
    "",
    "pub const entries = [_]Entry{",
  ];

  for (const entry of entries) {
    lines.push(
      `    .{ .region = ${zigString(entry.region)}, .province = ` +
        `${zigString(entry.province)}, .locality = ${zigString(entry.locality)}, ` +
        `.code = ${zigString(entry.code)} },`,
    );
  }

  lines.push(
    "};",
    "",
    "pub fn SearchResult(comptime limit: usize) type {",
    "    return struct {",
    "        matches: [limit]*const Entry = undefined,",
    "        len: usize = 0,",
    "",
    "        pub fn items(self: *const @This()) []const *const Entry {",
    "            return self.matches[0..self.len];",
    "        }",
    "    };",
    "}",
    "",
    "/// Searches code, locality, province, and region case-insensitively.",
    "/// Numeric queries search postal-code values, not numbers embedded in labels.",
    "/// Results retain source order and distinct place identities sharing a code.",
    "pub fn search(comptime limit: usize, query: []const u8) SearchResult(limit) {",
    '    const needle = std.mem.trim(u8, query, " \\t\\r\\n");',
    "    var result = SearchResult(limit){};",
    "    if (needle.len == 0) {",
    "        for (&entries) |*entry| {",
    "            if (result.len == limit) break;",
    "            result.matches[result.len] = entry;",
    "            result.len += 1;",
    "        }",
    "        return result;",
    "    }",
    "    if (isAsciiDigits(needle)) {",
    "        for (&entries) |*entry| {",
    "            if (!std.mem.eql(u8, entry.code, needle)) continue;",
    "            if (result.len == limit) break;",
    "            result.matches[result.len] = entry;",
    "            result.len += 1;",
    "        }",
    "        if (result.len > 0) return result;",
    "        for (&entries) |*entry| {",
    "            if (!std.mem.startsWith(u8, entry.code, needle)) continue;",
    "            if (result.len == limit) break;",
    "            result.matches[result.len] = entry;",
    "            result.len += 1;",
    "        }",
    "        if (result.len == limit) return result;",
    "        for (&entries) |*entry| {",
    "            if (std.mem.startsWith(u8, entry.code, needle)) continue;",
    "            if (std.mem.indexOf(u8, entry.code, needle) == null) continue;",
    "            if (result.len == limit) break;",
    "            result.matches[result.len] = entry;",
    "            result.len += 1;",
    "        }",
    "        return result;",
    "    }",
    "    for (&entries) |*entry| {",
    "        if (!startsWithPostalInsensitive(entry.locality, needle) and",
    "            !startsWithPostalInsensitive(entry.province, needle) and",
    "            !startsWithPostalInsensitive(entry.region, needle)) continue;",
    "        if (result.len == limit) break;",
    "        result.matches[result.len] = entry;",
    "        result.len += 1;",
    "    }",
    "    if (result.len == limit) return result;",
    "    for (&entries) |*entry| {",
    "        if (startsWithPostalInsensitive(entry.locality, needle) or",
    "            startsWithPostalInsensitive(entry.province, needle) or",
    "            startsWithPostalInsensitive(entry.region, needle)) continue;",
    "        if (!containsPostalInsensitive(entry.locality, needle) and",
    "            !containsPostalInsensitive(entry.province, needle) and",
    "            !containsPostalInsensitive(entry.region, needle)) continue;",
    "        if (result.len == limit) break;",
    "        result.matches[result.len] = entry;",
    "        result.len += 1;",
    "    }",
    "    return result;",
    "}",
    "",
    "/// Snapshot membership is informational only; it is not ZIP validation.",
    "pub fn hasCode(code: []const u8) bool {",
    "    for (&entries) |*entry| {",
    "        if (std.mem.eql(u8, entry.code, code)) return true;",
    "    }",
    "    return false;",
    "}",
    "",
    "fn isAsciiDigits(value: []const u8) bool {",
    "    if (value.len == 0) return false;",
    "    for (value) |byte| if (!std.ascii.isDigit(byte)) return false;",
    "    return true;",
    "}",
    "",
    "fn startsWithPostalInsensitive(candidate: []const u8, query: []const u8) bool {",
    "    var candidate_index: usize = 0;",
    "    var query_index: usize = 0;",
    "    while (query_index < query.len) {",
    "        const candidate_codepoint = nextPostalCodepoint(candidate, &candidate_index) orelse return false;",
    "        const query_codepoint = nextPostalCodepoint(query, &query_index) orelse return false;",
    "        if (foldPostalCodepoint(candidate_codepoint) !=",
    "            foldPostalCodepoint(query_codepoint)) return false;",
    "    }",
    "    return true;",
    "}",
    "",
    "fn containsPostalInsensitive(candidate: []const u8, query: []const u8) bool {",
    "    var start: usize = 0;",
    "    while (start < candidate.len) {",
    "        var candidate_index = start;",
    "        var query_index: usize = 0;",
    "        var matches = true;",
    "        while (query_index < query.len) {",
    "            const candidate_codepoint = nextPostalCodepoint(candidate, &candidate_index) orelse {",
    "                matches = false;",
    "                break;",
    "            };",
    "            const query_codepoint = nextPostalCodepoint(query, &query_index) orelse return false;",
    "            if (foldPostalCodepoint(candidate_codepoint) !=",
    "                foldPostalCodepoint(query_codepoint)) {",
    "                matches = false;",
    "                break;",
    "            }",
    "        }",
    "        if (matches and query_index == query.len) return true;",
    "        _ = nextPostalCodepoint(candidate, &start) orelse return false;",
    "    }",
    "    return false;",
    "}",
    "",
    "fn nextPostalCodepoint(value: []const u8, index: *usize) ?u21 {",
    "    if (index.* >= value.len) return null;",
    "    const sequence_len = std.unicode.utf8ByteSequenceLength(value[index.*]) catch return null;",
    "    const end = index.* + sequence_len;",
    "    if (end > value.len) return null;",
    "    const codepoint = std.unicode.utf8Decode(value[index.*..end]) catch return null;",
    "    index.* = end;",
    "    return codepoint;",
    "}",
    "",
    "fn foldPostalCodepoint(codepoint: u21) u21 {",
    "    return switch (codepoint) {",
    "        'A'...'Z' => codepoint + ('a' - 'A'),",
    "        0x00C0...0x00C5, 0x00E0...0x00E5 => 'a',",
    "        0x00C7, 0x00E7 => 'c',",
    "        0x00C8...0x00CB, 0x00E8...0x00EB => 'e',",
    "        0x00CC...0x00CF, 0x00EC...0x00EF => 'i',",
    "        0x00D1, 0x00F1 => 'n',",
    "        0x00D2...0x00D6, 0x00F2...0x00F6 => 'o',",
    "        0x00D9...0x00DC, 0x00F9...0x00FC => 'u',",
    "        0x00DD, 0x00FD, 0x00FF => 'y',",
    "        0x2018, 0x2019 => '\\'',",
    "        0x2010...0x2015 => '-',",
    "        else => codepoint,",
    "    };",
    "}",
    "",
    'test "GeoNames postal snapshot has pinned shape and representative codes" {',
    "    try std.testing.expectEqual(valid_row_count, entries.len);",
    "    try std.testing.expectEqual(@as(usize, 2_317), entries.len);",
    "    try std.testing.expect(hasCode(\"2600\"));",
    "    try std.testing.expect(hasCode(\"8000\"));",
    "    try std.testing.expect(hasCode(\"0401\"));",
    "    try std.testing.expect(!hasCode(\"0000\"));",
    "}",
    "",
    'test "postal search supports code, locality, province, region, and special codes" {',
    "    const by_code = search(5, \"2600\");",
    "    try std.testing.expectEqual(@as(usize, 1), by_code.len);",
    "    try std.testing.expectEqualStrings(\"Baguio City\", by_code.items()[0].locality);",
    "",
    "    const by_location = search(5, \"Baguio\");",
    "    try std.testing.expect(by_location.len >= 1);",
    "    try std.testing.expectEqualStrings(\"2600\", by_location.items()[0].code);",
    "",
    "    const by_province = search(5, \"Benguet\");",
    "    try std.testing.expectEqual(@as(usize, 5), by_province.len);",
    "",
    "    const by_region = search(5, \"Cordillera\");",
    "    try std.testing.expectEqual(@as(usize, 5), by_region.len);",
    "",
    "    const special = search(5, \"Asian Development Bank\");",
    "    try std.testing.expectEqual(@as(usize, 2), special.len);",
    "    try std.testing.expectEqualStrings(\"0401\", special.items()[0].code);",
    "    try std.testing.expectEqualStrings(\"0980\", special.items()[1].code);",
    "",
    "    const uppercase_enye = search(5, \"PEÑABLANCA\");",
    "    try std.testing.expectEqualStrings(\"3502\", uppercase_enye.items()[0].code);",
    "    const unaccented_enye = search(5, \"PENABLANCA\");",
    "    try std.testing.expectEqualStrings(\"3502\", unaccented_enye.items()[0].code);",
    "    const uppercase_nino = search(5, \"SANTO NIÑO\");",
    "    try std.testing.expect(uppercase_nino.len >= 1);",
    "    try std.testing.expectEqualStrings(\"3525\", uppercase_nino.items()[0].code);",
    "}",
    "",
    'test "postal search returns five initial suggestions and honors caller cap" {',
    "    const initial = search(5, \"\");",
    "    try std.testing.expectEqual(@as(usize, 5), initial.len);",
    "    try std.testing.expectEqualStrings(\"2900\", initial.items()[0].code);",
    "",
    "    const capped = search(1, \"Province\");",
    "    try std.testing.expectEqual(@as(usize, 1), capped.len);",
    "",
    "    const numeric_prefix = search(5, \"26\");",
    "    try std.testing.expectEqualStrings(\"2600\", numeric_prefix.items()[0].code);",
    "}",
  );
  return `${lines.join("\n")}\n`;
}

async function readManifest(): Promise<SourceManifest> {
  return JSON.parse(await readFile(manifestPath, "utf8")) as SourceManifest;
}

export async function generate(): Promise<string> {
  const [manifest, source] = await Promise.all([
    readManifest(),
    readFile(sourceDataPath, "utf8"),
  ]);
  const entries = parseGeoNamesPostalData(source);
  validateSnapshot(source, entries, manifest);
  return renderPostalReference(entries, manifest);
}

async function main(): Promise<void> {
  const output = await generate();
  if (process.argv.includes("--check")) {
    const current = await readFile(generatedPath, "utf8");
    if (current !== output) fail("Philippine postal reference is stale; run npm run generate");
    return;
  }
  await writeFile(generatedPath, output);
}

if (path.resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  await main();
}
