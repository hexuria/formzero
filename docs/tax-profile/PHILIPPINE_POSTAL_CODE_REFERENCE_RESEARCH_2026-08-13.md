# Philippine Postal-Code Reference Research — 2026-08-13

> Superseded implementation decision: the initial PHLPost-only snapshot below
> was replaced after the library/dataset audit in
> [PHILIPPINE_POSTAL_LIBRARY_AUDIT_2026-08-13.md](./PHILIPPINE_POSTAL_LIBRARY_AUDIT_2026-08-13.md).
> The app now uses the 2026-08-12 GeoNames `PH.zip` export (2,317 rows,
> 2,190 unique four-digit codes, CC BY 4.0) as its offline suggestion
> catalogue. PHLPost remains the postal-authority reconciliation baseline.

## Decision

Use the Philippine Postal Corporation (PHLPost) **Zip Code Locator** as the
authoritative upstream source for a checked-in, offline-searchable Philippine
postal-code reference. It is the national postal operator's own published
locator and exposes the exact four columns needed by the Tax Profile UI:
`Region`, `Provinces`, `City/Municipality`, and `Zip Code`.

Source: <https://phlpost.gov.ph/zip-code-locator/> (retrieved 2026-08-13,
Asia/Manila).

## What was verified

- The page title is **“Zip Code Locator | PHLPost”** and its footer identifies
  the publisher as **Philippine Postal Corporation**.
- The rendered locator contains one nationwide HTML table (`#offices`) with
  the four columns above. It is client-side DataTables presentation, not a
  five-row or paginated server query. A raw-HTML parse on retrieval found
  1,401 `<tr>` tags: one header plus 1,400 data rows. Of those data rows, 959
  had four non-empty cells and a four-digit ZIP; 440 were four-cell empty
  placeholders; one non-empty row repeated `Cajidiocan` in its ZIP column and
  was rejected as malformed.
- The published rows include geographically separated checks: Batanes
  municipalities (Basco `3900`, Itbayat `3905`) and Davao City (`8000`). This
  supports nationwide municipal-level coverage, but does **not** prove that
  every barangay, PO box, or special delivery code is enumerated.

## Completeness boundary

The appropriate product claim is: “PHLPost's published region/province/
city-or-municipality ZIP locator snapshot.” Do not describe it as a complete
barangay or delivery-point directory. Several localities can legitimately
share one four-digit ZIP, so an application entry must retain a stable row ID;
the ZIP alone is not a unique catalog key.

## Import and checked-in data shape

1. Fetch the locator over HTTPS during an explicit, reviewable refresh—not at
   application runtime. Save the raw HTML outside the shipped app data only if
   repository policy permits it; otherwise retain its source URL, retrieval
   date, byte count, and SHA-256 in the generated Zig module/refresh record.
2. Parse only rows with exactly four non-empty cells; strip markup and
   normalize whitespace. Validate `Zip Code` as exactly four ASCII digits.
   Reject the known malformed Cajidiocan row and all empty placeholder rows;
   fail the import if the valid-row count changes unexpectedly.
3. Generate a checked-in `src/tax_profile/philippine_postal_reference.zig`
   table shaped as:

   ```zig
   Entry{ .region, .province, .locality, .code }
   ```

   Give the UI row its array index as ID. Persist only `.code`, preserving the
   existing `ZipCode` storage contract.
4. Search case-insensitively over code, locality, province, and region; cap
   visible results at five. Empty search returns the first five normalized
   rows. Suppress only exact repeated source rows in suggestions; do not merge
   distinct localities that share a code. `hasCode(code)` is an optional
   snapshot lookup helper, not a validator: do not reject a well-formed typed
   or persisted four-digit code merely because this snapshot omits it.
5. Test source-row integrity, duplicate-code tolerance, exact-suggestion
   deduplication, numeric and location matching, result cap, and
   suggestion-only behavior for unknown codes. Record the snapshot hash so a
   future refresh is auditable and intentional.

## Reuse and licensing caveat

PHLPost's locator page publishes a copyright notice—“Copyright © 2026
Philippine Postal Corporation”—and I found no explicit open-data licence or
bulk-download redistribution grant on the locator page. Government ownership
does not by itself establish a software-data licence. Before shipping the raw
table in a public or commercial distribution, obtain written confirmation from
PHLPost (its footer links to the agency's FOI channel) or an explicit licence
from the agency. Until then, treat the checked-in derived reference as
attributed operational data, preserve the source/provenance record, and do not
represent it as open-licensed.

## Reproducibility evidence

On the corrected raw-response retrieval, the locator response was 964,045
bytes with SHA-256:

```
50f7682b55c7ae0550a4a59387814077b6ad37b18cb8261952d0c08f9bedb2c8
```

Extraction method: stream the response without `rtk` output reduction, find
each raw `<tr>...</tr>`, then extract `<td>` cells, strip tags, normalize
whitespace, and accept only four non-empty cells whose fourth cell matches
`^[0-9]{4}$`. The earlier 456-row figure was erroneous: it came from
`rtk`-processed command output rather than this raw-response parse. The hash
identifies one exact source response observed on 2026-08-13; PHLPost content
can change between requests, so a future refresh must record its own hash.
