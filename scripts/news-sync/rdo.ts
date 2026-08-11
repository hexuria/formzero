// Canonical Revenue District Office vocabulary for the news-sync extractor.
//
// data/rdo-reference.json is generated from src/tax_profile/rdo_reference.zig
// (npm run generate:news-sync-data), so a code that survives `findRdoByCode`
// here is guaranteed to be a code the app can scope an override to.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { normalizeDigits } from "./ocr-normalize.ts";

export type RdoReferenceEntry = {
  code: string;
  name: string;
};

const referencePath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "data",
  "rdo-reference.json",
);

let cachedEntries: readonly RdoReferenceEntry[] | null = null;

export function rdoEntries(): readonly RdoReferenceEntry[] {
  if (cachedEntries !== null) return cachedEntries;

  const parsed: unknown = JSON.parse(readFileSync(referencePath, "utf8"));
  if (!Array.isArray(parsed)) {
    throw new Error(`${referencePath} is not a JSON array; run npm run generate:news-sync-data`);
  }

  const entries = parsed.map((row: unknown, index: number): RdoReferenceEntry => {
    if (typeof row !== "object" || row === null) {
      throw new Error(`${referencePath} entry ${index} is not an object`);
    }
    const { code, name } = row as { code?: unknown; name?: unknown };
    if (typeof code !== "string" || typeof name !== "string") {
      throw new Error(`${referencePath} entry ${index} lacks a string code/name`);
    }
    return Object.freeze({ code, name });
  });

  cachedEntries = Object.freeze(entries);
  return cachedEntries;
}

export function findRdoByCode(code: string): RdoReferenceEntry | null {
  const needle = code.trim().toUpperCase();
  if (!needle) return null;
  return rdoEntries().find((entry) => entry.code.toUpperCase() === needle) ?? null;
}

/**
 * Canonicalizes an RDO code token lifted from OCR text.
 *
 * Numeric-only tokens pad to three digits (`"7"` -> `"007"`, `"24"` -> `"024"`);
 * a trailing A/B/C branch suffix pads its digits to two (`"l7A"` -> `"17A"`).
 * Digit lookalikes are resolved in the numeric part only, so `"T"` alone reads
 * as `7` while the `B` of `"53B"` stays a branch letter. Returns null when the
 * token cannot be read as a code shape at all; membership in the reference list
 * is a separate check (`findRdoByCode`).
 */
export function normalizeRdoCode(raw: string): string | null {
  const compact = raw.replace(/\s+/gu, "").replace(/^[^0-9A-Za-z|]+|[^0-9A-Za-z|]+$/gu, "");
  if (!compact) return null;

  const suffix = compact.slice(-1);
  if (compact.length >= 2 && /^[A-Ca-c]$/u.test(suffix)) {
    const digits = normalizeDigits(compact.slice(0, -1));
    if (/^[0-9]+$/u.test(digits)) {
      const trimmed = digits.replace(/^0+/u, "");
      if (trimmed.length >= 1 && trimmed.length <= 2) {
        return `${trimmed.padStart(2, "0")}${suffix.toUpperCase()}`;
      }
      return null;
    }
  }

  const digits = normalizeDigits(compact);
  if (!/^[0-9]+$/u.test(digits)) return null;
  const trimmed = digits.replace(/^0+/u, "");
  if (trimmed.length < 1 || trimmed.length > 3) return null;
  return trimmed.padStart(3, "0");
}

/**
 * Lettered branch codes for a plain numeric code, e.g. `"043"` -> `["43A","43B"]`.
 * Profiles may be registered under either spelling, so an override scoped to the
 * parent office must also list its branches. Returns [] for codes with no
 * branches and for codes that already carry a branch letter.
 */
export function letteredVariants(code: string): string[] {
  const normalized = normalizeRdoCode(code);
  if (normalized === null || /[A-Z]$/u.test(normalized)) return [];

  const base = normalized.replace(/^0+/u, "");
  if (!base) return [];

  return rdoEntries()
    .map((entry) => entry.code)
    .filter(
      (candidate) =>
        /^[0-9]+[A-Z]$/u.test(candidate) &&
        candidate.slice(0, -1).replace(/^0+/u, "") === base,
    )
    .toSorted();
}
