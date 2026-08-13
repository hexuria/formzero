import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import test from "node:test";

import {
  generate,
  generatedPath,
  parseGeoNamesPostalData,
  validatePhlpostBaseline,
} from "./generate.ts";

test("parser accepts a complete GeoNames postal row", () => {
  const rows = parseGeoNamesPostalData(
    "PH\t2600\tBaguio City\tCordillera\t15\tProvince of Benguet\t10\t\t\t16.4\t120.5\t4\n",
  );
  assert.deepEqual(rows, [
    {
      code: "2600",
      locality: "Baguio City",
      region: "Cordillera",
      province: "Province of Benguet",
    },
  ]);
});

test("parser preserves institution codes without administrative names", () => {
  const rows = parseGeoNamesPostalData(
    "PH\t0401\tAsian Development Bank\t\t\t\t\t\t\t14.5\t121.0\t\n",
  );
  assert.deepEqual(rows[0], {
    code: "0401",
    locality: "Asian Development Bank",
    region: "",
    province: "",
  });
});

test("parser fails malformed postal records", () => {
  assert.throws(
    () => parseGeoNamesPostalData("PH\t260\tBaguio City\tCordillera\n"),
    /columns; expected 12/u,
  );
  assert.throws(
    () =>
      parseGeoNamesPostalData(
        "PH\t26A0\tBaguio City\tCordillera\t15\tBenguet\t10\t\t\t0\t0\t4\n",
      ),
    /invalid postal code/u,
  );
  assert.throws(
    () =>
      parseGeoNamesPostalData(
        "PH\t2600\tBaguio City\tCordillera\t15\tBenguet\t10\t\t\t0\t0\t4\n" +
          "PH\t2600\tBaguio City\tCordillera\t15\tBenguet\t10\t\t\t0\t0\t4\n",
      ),
    /duplicates an earlier postal identity/u,
  );
});

test("generated Zig is byte-identical to the committed reference", async () => {
  const [generated, committed] = await Promise.all([
    generate(),
    readFile(generatedPath, "utf8"),
  ]);
  assert.equal(generated, committed);
});

test("PHLPost reconciliation baseline rejects malformed and missing codes", () => {
  const entries = [
    { code: "2600", locality: "Baguio City", province: "Benguet", region: "CAR" },
    { code: "8000", locality: "Davao City", province: "Davao del Sur", region: "Davao" },
  ];
  const baseline = {
    expected_phlpost_baseline_code_count: 2,
    phlpost_baseline_codes: ["2600", "8000"],
  } as const;
  assert.doesNotThrow(() => validatePhlpostBaseline(entries, baseline));
  assert.throws(
    () => validatePhlpostBaseline(entries.slice(0, 1), baseline),
    /missing codes from the pinned PHLPost baseline: 8000/u,
  );
  assert.throws(
    () =>
      validatePhlpostBaseline(entries, {
        expected_phlpost_baseline_code_count: 2,
        phlpost_baseline_codes: ["2600", "2600"],
      }),
    /unique and strictly sorted/u,
  );
});
