# Philippine Postal-Code Library and Dataset Audit — 2026-08-13

## Scope and baseline

This audit tests public libraries and downloadable datasets as candidates for
the Tax Profile ZIP-code suggestions. The comparison baseline is the existing
PHLPost Zip Code Locator snapshot retrieved on 2026-08-13:

- 959 valid locality rows;
- 958 unique four-digit codes; and
- source response SHA-256
  `50f7682b55c7ae0550a4a59387814077b6ad37b18cb8261952d0c08f9bedb2c8`.

The baseline is the Philippine postal operator's published city/municipality
locator, but it is not an openly licensed bulk dataset and does not claim to
list every delivery point. This audit uses primary sources only: package
registries and package archives, GitHub repositories, and the data publisher's
own download and licence pages.

## Recommendation

Use **GeoNames PH postal-code export** as the application suggestion catalogue,
with visible/source attribution to GeoNames and the required CC BY 4.0 attribution
in the shipped documentation. It is the only candidate inspected that is both
materially broader than the PHLPost snapshot and has explicit redistributable
data terms.

At the retrieved revision, it has **2,317 rows / 2,190 unique four-digit ZIP
codes**. It contains all **958** unique codes in the PHLPost snapshot and adds
**1,232** codes. Its HTTP `Last-Modified` value was `Wed, 12 Aug 2026
02:14:22 GMT`, one day before this audit.

This does not establish that GeoNames is error-free or that it supersedes
PHLPost as the postal authority. GeoNames itself says some postal-code
coordinates are algorithmically determined and makes no warranty for accuracy,
timeliness, or completeness. Therefore the UI should continue to treat the
catalogue as suggestions: accept a syntactically valid typed four-digit code
even when it is absent, and retain provenance/version/hash for a reviewable
refresh.

## Candidate ranking

| Rank | Candidate | Postal coverage observed | Freshness/provenance | Reuse terms | Decision |
| --- | --- | --- | --- | --- | --- |
| 1 | GeoNames `PH.zip` | 2,317 rows; 2,190 unique four-digit codes; every baseline code present | Download response last modified 2026-08-12; publisher documents the tab-delimited schema and caveats | CC BY 4.0 for postal files; attribution required | Adopt as the broader, legally reusable suggestion catalogue |
| 2 | PHLPost Zip Code Locator | 959 rows; 958 unique codes | Postal operator's published locator, retrieved 2026-08-13 | No explicit open-data redistribution licence found on the source page | Keep as an authoritative reconciliation input, not the vendored public dataset until permission is obtained |
| 3 | `philippines-regions-provinces-municipalities-barangays-zipcodes-api` 2.2.1 | 2,722 rows; 1,870 unique four-digit values after reading its `data/zipcodes.json` | npm publish 2026-08-09, but the archive supplies no source/provenance or dataset date for ZIP values | Manifest says MIT; source repository has no `LICENSE` file or ZIP source dataset to substantiate third-party data rights | Do not adopt: fewer codes than GeoNames and unproven provenance |
| 4 | `zipcodes-ph` 1.1.2 | 1,830 unique four-digit codes | Dataset-file commit is 2017-10-30; npm published 2017-10-31 | MIT package licence | Do not adopt: materially stale and less complete |
| 5 | `use-postal-ph` 1.1.14 | 2,139 rows; 1,990 distinct values after normalizing code text, but only 2,049 rows are four digits | npm published 2026-03-15; README explicitly says its geographic data is sourced from Wikipedia and says it may not be comprehensive | MIT package licence | Do not adopt: behind GeoNames and not sourced from a postal authority/open postal dataset |
| 6 | `zipcodes-ph2` 1.0.0 | No usable ZIP data in its published tarball | npm published 2021-09-07; manifest calls itself a fork but points to the original 2017 repository | MIT manifest | Reject: package archive contains only metadata/readme/licence, no `build` data it declares as its entry point |
| 7 | `ph-addresses-locations` 1.0.3 | 1,584 city rows; 1,045 include ZIP, only 642 unique four-digit ZIPs | npm published 2025-10-19; README calls its geographic hierarchy PSGC data but does not identify a postal-code source or dataset date | MIT package licence | Do not adopt: much less coverage and unproven postal provenance |
| Not a postal candidate | `@aivangogh/ph-address` 2026.2.2 | No ZIP/postal-code data; region/province/municipality/barangay PSGC data | README says PSGC as of 2026-06-30, and repository includes that PSGC publication file | MIT | Useful only for reconciling locality names; PSGC is not a postal-code directory |

## Primary-source evidence

### 1. GeoNames PH export

- Dataset: <https://download.geonames.org/export/zip/PH.zip>
- Postal-file directory and schema/licence statement:
  <https://www.geonames.org/export/zip/>
- Publisher-wide licence page: <https://www.geonames.org/about.html>

The exact downloaded `PH.txt` had 2,317 tab-delimited rows. Column two
(`postal code`) had 2,190 unique values, and every value was four decimal
digits. GeoNames' current postal-file readme explicitly licenses the postal
files under Creative Commons Attribution 4.0, requires credit/link attribution,
and states that its data is supplied without warranties. (Its following line
still links the older 3.0 deed; this implementation follows the readme's
explicit 4.0 grant.) It also explains that in
many countries coordinates can be derived through an algorithmic place-name
search; do not present its coordinates as postal-operator-confirmed delivery
points.

Code-set comparison was performed against the generated PHLPost catalogue:

```text
PHLPost snapshot:  958 unique codes
GeoNames PH.txt:  2,190 unique codes
intersection:       958 codes
GeoNames-only:    1,232 codes
PHLPost-only:         0 codes
```

The GeoNames file fields are sufficient for the existing suggestions: country,
postal code, place name, first-level administrative name/code, second-level
administrative name/code, then latitude/longitude/accuracy. The importer should
use only code/place/admin text for this UI, not coordinates.

### 2. `zipcodes-ph` and `zipcodes-ph2`

- Registry metadata: <https://registry.npmjs.org/zipcodes-ph>
- Published `zipcodes-ph` archive:
  <https://registry.npmjs.org/zipcodes-ph/-/zipcodes-ph-1.1.2.tgz>
- Source repository: <https://github.com/arnellebalane/zipcodes-ph>
- Dataset-file commit history:
  <https://api.github.com/repos/arnellebalane/zipcodes-ph/commits?path=source/zipcodes.json&per_page=1>
- Fork registry metadata: <https://registry.npmjs.org/zipcodes-ph2>
- Published fork archive:
  <https://registry.npmjs.org/zipcodes-ph2/-/zipcodes-ph2-1.0.0.tgz>

The original package's shipped `build/zipcodes.json` is a code-to-name map with
1,830 unique four-digit keys. Its only postal-data file commit is
`b6dea43a5ed78c066b02e78ea80e13b7db1fa0f0` dated 2017-10-30. The package is
MIT-licensed, but the age alone rules it out as a latest reference.

`zipcodes-ph2` describes itself as an updated fork, yet the published tarball
contains no `build/` directory or ZIP data and its repository/homepage points
back to the original project. It cannot be used as a reproducible data source.

### 3. `use-postal-ph`

- Registry metadata: <https://registry.npmjs.org/use-postal-ph>
- Published archive:
  <https://registry.npmjs.org/use-postal-ph/-/use-postal-ph-1.1.14.tgz>
- Source repository: <https://github.com/blckclov3r/use-postal-ph>

The current version was published 2026-03-15. The packaged function returns
2,139 records, with 1,990 distinct normalized code values; only 2,049 records
are four digits. Crucially, its own README identifies Wikipedia as the source
for its geographic information and explicitly says the library may not be
comprehensive. The MIT software licence does not make that an authoritative or
more complete postal dataset. It ranks below GeoNames' 2,190 all-four-digit
codes.

### 4. `philippines-regions-provinces-municipalities-barangays-zipcodes-api`

- Registry metadata:
  <https://registry.npmjs.org/philippines-regions-provinces-municipalities-barangays-zipcodes-api>
- Published archive:
  <https://registry.npmjs.org/philippines-regions-provinces-municipalities-barangays-zipcodes-api/-/philippines-regions-provinces-municipalities-barangays-zipcodes-api-2.2.1.tgz>
- Linked source repository:
  <https://github.com/m4rkbello/philippine-address-selector>

The npm registry reports version 2.2.1 published 2026-08-09 and an MIT
manifest. Its published `data/zipcodes.json` contains 2,722 rows and 1,870
unique four-digit ZIP values (after filtering to `^[0-9]{4}$`). That is still
320 fewer codes than GeoNames. More importantly, neither its README nor its
repository identifies a ZIP source, source revision, collection date, or the
underlying data licence; the repository tree has no `LICENSE` file and no
checked-in ZIP data source. A current package publication date is not evidence
that the postal values were refreshed.

### 5. `ph-addresses-locations`

- Registry metadata: <https://registry.npmjs.org/ph-addresses-locations>
- Published archive:
  <https://registry.npmjs.org/ph-addresses-locations/-/ph-addresses-locations-1.0.3.tgz>
- Source repository: <https://github.com/KuramitZui/ph-addresses-locations>

This package's city data has 1,584 rows but only 1,045 ZIP-populated rows and
642 distinct four-digit ZIP values. Its README describes the primary hierarchy
as PSGC but does not identify a postal-code source, source date, or licence for
the ZIP fields. It is a useful example of why a current package release does
not equal a current postal reference.

### 6. `@aivangogh/ph-address`

- Registry metadata: <https://registry.npmjs.org/@aivangogh%2fph-address>
- Published archive:
  <https://registry.npmjs.org/@aivangogh/ph-address/-/ph-address-2026.2.2.tgz>
- Source repository: <https://github.com/aivangogh/ph-address>
- PSGC authority identified by its README:
  <https://psa.gov.ph/classification/psgc/>

Version 2026.2.2 was published 2026-08-11 and its README identifies PSGC data
as of 2026-06-30. It is a well-documented, MIT-licensed geographic hierarchy,
but its public API and packaged data have PSGC codes rather than postal codes.
It must not be represented as a ZIP-code source. It can be a separate optional
normalization aid for municipality/province names after postal data is chosen.

## Safe implementation path

1. During an explicit maintainer refresh, download `PH.zip`, update its pinned
   HTTP last-modified and SHA-256 values, and regenerate the checked-in Zig
   table. Do not download data at application startup.
2. Vendor all 2,317 rows offline; preserve multiple rows sharing a code and a
   stable generated row index for selection identity.
3. Add the GeoNames CC BY attribution to the in-app/source attribution and this
   research record. Preserve the `GeoNames` name and link required by its
   postal-file licence.
4. Keep the current PHLPost code set as a reconciliation guard: alert a
   maintainer when a PHLPost code disappears from a future GeoNames refresh;
   do not silently discard it. The pinned manifest and generator enforce this.
5. Keep validation syntax-only (`^[0-9]{4}$`) and catalogue matching
   suggestion-only until a postal authority publishes a licensed, complete
   delivery-point data feed.
