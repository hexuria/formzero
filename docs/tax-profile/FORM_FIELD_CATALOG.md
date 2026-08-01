# Form field catalog

<!-- GENERATED FILE - DO NOT EDIT. Run `npm run generate:tax-catalog`. -->

This catalog is the checked boundary between the 51-code calendar registry,
the 10 exact Native editor revisions currently present, and future profile
projection/domain work. `calendar_only` means that no editor field contract
exists yet; it does not imply filing support.

## Coverage

- Registry codes: 51
- Native editor revisions: 10
- Calendar-only codes: 41
- Native input controls inventoried: 299
- Meaningful static-table fields inventoried: 63
- Direct profile projection targets: 72
- Optional profile projection targets: 9

| Code | Revision | Status | Inputs | Table fields | Source |
|---|---|---|---:|---:|---|
| 0605 | 1999-07-ENCS | static_layout | 17 | 4 | src/pages/forms/0605.native |
| 1905 | — | calendar_only | 0 | 0 | — |
| 1600 | — | calendar_only | 0 | 0 | — |
| 1600PT | — | calendar_only | 0 | 0 | — |
| 1600VT | — | calendar_only | 0 | 0 | — |
| 1600WP | — | calendar_only | 0 | 0 | — |
| 1601C | 2018-01-ENCS | static_layout | 28 | 7 | src/pages/forms/1601-c.native |
| 1601E | — | calendar_only | 0 | 0 | — |
| 1601F | — | calendar_only | 0 | 0 | — |
| 0619F | 2018-01-ENCS | static_layout | 20 | 4 | src/pages/forms/0619-f.native |
| 1601FQ | — | calendar_only | 0 | 0 | — |
| 1602 | — | calendar_only | 0 | 0 | — |
| 1602Q | — | calendar_only | 0 | 0 | — |
| 1603 | — | calendar_only | 0 | 0 | — |
| 1603Q | — | calendar_only | 0 | 0 | — |
| 1604CF | — | calendar_only | 0 | 0 | — |
| 1604E | — | calendar_only | 0 | 0 | — |
| 0620 | — | calendar_only | 0 | 0 | — |
| 2316 | — | calendar_only | 0 | 0 | — |
| 1700 | — | calendar_only | 0 | 0 | — |
| 1701Q | 2018-01-ENCS | static_layout | 37 | 4 | src/pages/forms/1701q.native |
| 1701 | 2018-01-ENCS | static_layout | 49 | 15 | src/pages/forms/1701.native |
| 1701A | — | calendar_only | 0 | 0 | — |
| 1702Q | — | calendar_only | 0 | 0 | — |
| 1702 | — | calendar_only | 0 | 0 | — |
| 1702RT | 2018-01-ENCS | static_layout | 33 | 3 | src/pages/forms/1702-rt.native |
| 1702EX | — | calendar_only | 0 | 0 | — |
| 1702MX | 2018-01-ENCS | static_layout | 29 | 5 | src/pages/forms/1702-mx.native |
| 1704 | — | calendar_only | 0 | 0 | — |
| 2550M | — | calendar_only | 0 | 0 | — |
| 2550Q | 2024-04-ENCS | static_layout | 33 | 13 | src/pages/forms/2550q.native |
| 2551Q | 2018-01-ENCS | static_layout | 35 | 4 | src/pages/forms/2551q.native |
| 2551M | — | calendar_only | 0 | 0 | — |
| 2552 | — | calendar_only | 0 | 0 | — |
| 2553 | — | calendar_only | 0 | 0 | — |
| 2000 | — | calendar_only | 0 | 0 | — |
| 2000OT | — | calendar_only | 0 | 0 | — |
| 2200A | — | calendar_only | 0 | 0 | — |
| 2200AN | — | calendar_only | 0 | 0 | — |
| 2200M | — | calendar_only | 0 | 0 | — |
| 2200P | — | calendar_only | 0 | 0 | — |
| 2200T | — | calendar_only | 0 | 0 | — |
| 2200C | — | calendar_only | 0 | 0 | — |
| 2200S | — | calendar_only | 0 | 0 | — |
| 0619E | 2018-01-ENCS | static_layout | 18 | 4 | src/pages/forms/0619-e.native |
| 1601EQ | — | calendar_only | 0 | 0 | — |
| 1701MS | — | calendar_only | 0 | 0 | — |
| 1706 | — | calendar_only | 0 | 0 | — |
| 1707A | — | calendar_only | 0 | 0 | — |
| 1800 | — | calendar_only | 0 | 0 | — |
| 1801 | — | calendar_only | 0 | 0 | — |

## Classification

- `profile`: reusable taxpayer facts projected through a named `filer` or `spouse` role.
- `transaction`: values belonging to one return or filing decision.
- `derived`: calculated values; an input-shaped current control is still recorded as unbound.
- `filing_context`: period, revision intent, or other draft identity.
- `external`: evidence, payment references, certificates, attachments, or policy-sourced facts.
- Profile-role cardinality controls whether a named binding is required; target presence separately controls whether a missing capability is an error.

## Reusable profile projection matrix

Only direct profile-sourced form targets appear here. Repeated schedule rows
(including 2551Q Schedule 1 ATC rows) remain filing data and are deliberately
excluded even when a selected registration may help compose a row.

| Form revision | Named role | Cardinality | Allowed subjects | Presence | Canonical profile key | Stable target field |
|---|---|---|---|---|---|---|
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `atc` | `0605.1999-07-ENCS.input.atc_only_source_proven_pairs` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tax_type` | `0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `0605.1999-07-ENCS.input.tin` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `0605.1999-07-ENCS.input.rdo_code` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `line_of_business` | `0605.1999-07-ENCS.input.line_of_business_occupation` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `taxpayer_name` | `0605.1999-07-ENCS.input.taxpayer_name` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `registered_address` | `0605.1999-07-ENCS.input.registered_address` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `1601C.2018-01-ENCS.input.tin` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `1601C.2018-01-ENCS.input.rdo_code` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `taxpayer_name` | `1601C.2018-01-ENCS.input.taxpayer_name` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `registered_address` | `1601C.2018-01-ENCS.input.registered_address` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `line_of_business` | `1601C.2018-01-ENCS.input.line_of_business` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `contact_number` | `1601C.2018-01-ENCS.input.contact_number` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `atc` | `1601C.2018-01-ENCS.input.atc` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tax_type` | `0619F.2018-01-ENCS.input.tax_type_code` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `government_withholding_agent` | `0619F.2018-01-ENCS.input.government_withholding_agent` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `0619F.2018-01-ENCS.input.tin` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `0619F.2018-01-ENCS.input.rdo_code` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `taxpayer_name` | `0619F.2018-01-ENCS.input.registered_taxpayer_name` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `tin` | `1701Q.2018-01-ENCS.input.tin` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `rdo_code` | `1701Q.2018-01-ENCS.input.rdo_code` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `taxpayer_name` | `1701Q.2018-01-ENCS.input.taxpayer_filer_name` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `registered_address` | `1701Q.2018-01-ENCS.input.registered_address` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `zip_code` | `1701Q.2018-01-ENCS.input.zip_code` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `date_of_birth` | `1701Q.2018-01-ENCS.input.date_of_birth` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `email_address` | `1701Q.2018-01-ENCS.input.email_address` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `citizenship` | `1701Q.2018-01-ENCS.input.citizenship` |
| 1701Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `foreign_tax_number` | `1701Q.2018-01-ENCS.input.foreign_tax_number` |
| 1701Q 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `tin` | `1701Q.2018-01-ENCS.input.spouse_tin` |
| 1701Q 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `rdo_code` | `1701Q.2018-01-ENCS.input.spouse_rdo_code` |
| 1701Q 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `taxpayer_name` | `1701Q.2018-01-ENCS.input.spouse_name` |
| 1701Q 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | optional | `citizenship` | `1701Q.2018-01-ENCS.input.spouse_citizenship` |
| 1701Q 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | optional | `foreign_tax_number` | `1701Q.2018-01-ENCS.input.spouse_foreign_tax_number` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `tin` | `1701.2018-01-ENCS.input.tin` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `rdo_code` | `1701.2018-01-ENCS.input.rdo_code` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `taxpayer_name` | `1701.2018-01-ENCS.input.taxpayer_name` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `registered_address` | `1701.2018-01-ENCS.input.registered_address` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `zip_code` | `1701.2018-01-ENCS.input.zip_code` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `date_of_birth` | `1701.2018-01-ENCS.input.date_of_birth` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `email_address` | `1701.2018-01-ENCS.input.email_address` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `citizenship` | `1701.2018-01-ENCS.input.citizenship` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | optional | `foreign_tax_number` | `1701.2018-01-ENCS.input.foreign_tax_number` |
| 1701 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, estate, trust | required | `contact_number` | `1701.2018-01-ENCS.input.contact_number` |
| 1701 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `tin` | `1701.2018-01-ENCS.input.spouse_tin` |
| 1701 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `rdo_code` | `1701.2018-01-ENCS.input.spouse_rdo_code` |
| 1701 2018-01-ENCS | spouse | zero_or_one | individual, sole_proprietor | required | `taxpayer_name` | `1701.2018-01-ENCS.input.spouse_name` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `tin` | `1702RT.2018-01-ENCS.input.tin` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `rdo_code` | `1702RT.2018-01-ENCS.input.rdo_code` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `registered_name` | `1702RT.2018-01-ENCS.input.registered_name` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `registered_address` | `1702RT.2018-01-ENCS.input.registered_address` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `line_of_business` | `1702RT.2018-01-ENCS.input.line_of_business` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `tin` | `1702MX.2018-01-ENCS.input.tin` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `rdo_code` | `1702MX.2018-01-ENCS.input.rdo_code` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `registered_name` | `1702MX.2018-01-ENCS.input.registered_name` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `registered_address` | `1702MX.2018-01-ENCS.input.registered_address` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | required | `line_of_business` | `1702MX.2018-01-ENCS.input.line_of_business` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, other_legal_entity | optional | `special_rate_basis` | `1702MX.2018-01-ENCS.input.special_preferential_rate_basis` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `2550Q.2024-04-ENCS.input.tin` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `2550Q.2024-04-ENCS.input.rdo_code` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `taxpayer_name` | `2550Q.2024-04-ENCS.input.taxpayer_name` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `2551Q.2018-01-ENCS.input.tin` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `2551Q.2018-01-ENCS.input.rdo_code` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `taxpayer_name` | `2551Q.2018-01-ENCS.input.taxpayers_name` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `registered_address` | `2551Q.2018-01-ENCS.input.registered_address` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `zip_code` | `2551Q.2018-01-ENCS.input.zip_code` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `contact_number` | `2551Q.2018-01-ENCS.input.contact_number` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `email_address` | `2551Q.2018-01-ENCS.input.email_address` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `atc` | `0619E.2018-01-ENCS.input.atc` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tax_type` | `0619E.2018-01-ENCS.input.tax_type_code` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `tin` | `0619E.2018-01-ENCS.input.tin` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `rdo_code` | `0619E.2018-01-ENCS.input.rdo_code` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity | required | `government_withholding_agent` | `0619E.2018-01-ENCS.input.government_withholding_agent` |

## 0605 — 1999-07-ENCS

Source: `src/pages/forms/0605.native`

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `0605.1999-07-ENCS.input.year_ended_month_independent` | 2 Year Ended month (independent) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0605.native:5` |
| `0605.1999-07-ENCS.input.due_date_mm_dd_yyyy` | 4 Due Date (MM/DD/YYYY) | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0605.native:9` |
| `0605.1999-07-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/0605.native:13` |
| `0605.1999-07-ENCS.input.atc_only_source_proven_pairs` | 6 ATC - only source-proven pairs | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/0605.native:17` |
| `0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs` | 8 Tax Type - only source-proven pairs | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0605.native:21` |
| `0605.1999-07-ENCS.input.manner_of_payment` | 17 Manner of Payment | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:25` |
| `0605.1999-07-ENCS.input.tin` | 9 TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0605.native:34` |
| `0605.1999-07-ENCS.input.rdo_code` | 10 RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0605.native:38` |
| `0605.1999-07-ENCS.input.line_of_business_occupation` | 12 Line of Business / Occupation | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/0605.native:42` |
| `0605.1999-07-ENCS.input.taxpayer_name` | 13 Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/0605.native:46` |
| `0605.1999-07-ENCS.input.registered_address` | 15 Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/0605.native:50` |
| `0605.1999-07-ENCS.input.type_of_payment` | 18 Type of Payment | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:54` |
| `0605.1999-07-ENCS.input.basic_tax_deposit_advance_payment` | 19 Basic Tax / Deposit / Advance Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:63` |
| `0605.1999-07-ENCS.input.surcharge_manual` | 20A Surcharge (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:67` |
| `0605.1999-07-ENCS.input.interest_manual` | 20B Interest (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:71` |
| `0605.1999-07-ENCS.input.compromise_manual` | 20C Compromise (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:75` |
| `0605.1999-07-ENCS.input.taxpayer_authorized_representative` | 22A Taxpayer / Authorized Representative | transaction | — | — | preparer | text | unbound_input | `src/pages/forms/0605.native:298` |
| `0605.1999-07-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | payment | text | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/0605.native (table schema)` |

## 1601C — 2018-01-ENCS

Source: `src/pages/forms/1601-c.native`

Named roles: `filer`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `1601C.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1601-c.native:5` |
| `1601C.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1601-c.native:9` |
| `1601C.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:13` |
| `1601C.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:17` |
| `1601C.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:21` |
| `1601C.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/1601-c.native:25` |
| `1601C.2018-01-ENCS.input.for_the_month_of` | For the Month of | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/1601-c.native:34` |
| `1601C.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:38` |
| `1601C.2018-01-ENCS.input.any_taxes_withheld` | Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:42` |
| `1601C.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1601-c.native:46` |
| `1601C.2018-01-ENCS.input.atc` | ATC | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/1601-c.native:50` |
| `1601C.2018-01-ENCS.input.tax_relief` | 13 Tax Relief | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1601-c.native:54` |
| `1601C.2018-01-ENCS.input.total_amount_of_compensation` | 14 Total Amount of Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:63` |
| `1601C.2018-01-ENCS.input.statutory_minimum_wage` | 15 Statutory Minimum Wage | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:67` |
| `1601C.2018-01-ENCS.input.holiday_overtime_and_night_shift_pay` | 16 Holiday, Overtime and Night Shift Pay | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:71` |
| `1601C.2018-01-ENCS.input.13th_month_pay_and_other_benefits` | 17 13th Month Pay and Other Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:75` |
| `1601C.2018-01-ENCS.input.de_minimis_benefits` | 18 De Minimis Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:79` |
| `1601C.2018-01-ENCS.input.sss_gsis_phic_and_pag_ibig_contributions` | 19 SSS, GSIS, PHIC and Pag-IBIG Contributions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:83` |
| `1601C.2018-01-ENCS.input.other_non_taxable_compensation` | 20 Other Non-Taxable Compensation | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:87` |
| `1601C.2018-01-ENCS.input.total_non_taxable_exempt_compensation` | 21 Total Non-Taxable / Exempt Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:91` |
| `1601C.2018-01-ENCS.input.total_taxable_compensation` | 22 Total Taxable Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:95` |
| `1601C.2018-01-ENCS.input.tax_required_to_be_withheld` | 25 Tax Required to be Withheld | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:99` |
| `1601C.2018-01-ENCS.input.schedule_adjustment` | 26 Schedule Adjustment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:103` |
| `1601C.2018-01-ENCS.input.tax_still_due` | 31 Tax Still Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:107` |
| `1601C.2018-01-ENCS.input.surcharge` | 32 Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:116` |
| `1601C.2018-01-ENCS.input.interest` | 33 Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:120` |
| `1601C.2018-01-ENCS.input.compromise` | 34 Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:124` |
| `1601C.2018-01-ENCS.input.total_penalties` | 35 Total Penalties | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:128` |
| `1601C.2018-01-ENCS.table.prior_payment.period` | Previous-month period | external | — | — | evidence | tax_period | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.date_paid` | Previous payment date | external | — | — | payment | date | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.agency` | Previous payment agency | external | — | — | payment | text | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.reference_number` | Previous payment reference | external | — | — | payment | text | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.tax_paid` | Previous tax paid | external | — | — | evidence | money | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.tax_due` | Previous tax due | external | — | — | evidence | money | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.adjustment` | Previous-payment adjustment | derived | — | — | system | money | derived_display | `src/pages/forms/1601-c.native (table schema)` |

## 0619F — 2018-01-ENCS

Source: `src/pages/forms/0619-f.native`

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `0619F.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-f.native:5` |
| `0619F.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:9` |
| `0619F.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:13` |
| `0619F.2018-01-ENCS.input.tax_type_code` | Tax Type Code | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0619-f.native:17` |
| `0619F.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0619-f.native:21` |
| `0619F.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | profile | government_withholding_agent | required | filer | boolean | unbound_input | `src/pages/forms/0619-f.native:25` |
| `0619F.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0619-f.native:29` |
| `0619F.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0619-f.native:33` |
| `0619F.2018-01-ENCS.input.registered_taxpayer_name` | Registered Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/0619-f.native:37` |
| `0619F.2018-01-ENCS.input.final_tax_withheld_on_interest_deposits_and_trusts` | 13 Final tax withheld on interest, deposits and trusts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:46` |
| `0619F.2018-01-ENCS.input.other_final_income_taxes_withheld` | 14 Other final income taxes withheld | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:50` |
| `0619F.2018-01-ENCS.input.total_final_income_taxes_withheld` | 15 Total final income taxes withheld | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:54` |
| `0619F.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 16 Less: Amount Remitted from Previously Filed Form | external | — | — | evidence | money | unbound_input | `src/pages/forms/0619-f.native:58` |
| `0619F.2018-01-ENCS.input.net_amount_of_remittance` | 17 Net Amount of Remittance | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:62` |
| `0619F.2018-01-ENCS.input.surcharge` | 18A Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:66` |
| `0619F.2018-01-ENCS.input.interest` | 18B Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:70` |
| `0619F.2018-01-ENCS.input.compromise` | 18C Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:74` |
| `0619F.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | preparer | text | unbound_input | `src/pages/forms/0619-f.native:83` |
| `0619F.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:87` |
| `0619F.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:91` |
| `0619F.2018-01-ENCS.table.payment.item_reference` | Payment item reference | filing_context | — | — | filing | text | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/0619-f.native (table schema)` |

## 1701Q — 2018-01-ENCS

Source: `src/pages/forms/1701q.native`

Named roles: `filer`, `spouse`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, estate, trust |
| spouse | zero_or_one | individual, sole_proprietor |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `1701Q.2018-01-ENCS.input.taxable_year` | 1 Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1701q.native:5` |
| `1701Q.2018-01-ENCS.input.quarter` | 2 Quarter | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/1701q.native:9` |
| `1701Q.2018-01-ENCS.input.amended_return` | 3 Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1701q.native:36` |
| `1701Q.2018-01-ENCS.input.number_of_sheets_attached` | 4 Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1701q.native:40` |
| `1701Q.2018-01-ENCS.input.tin` | 5 TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1701q.native:53` |
| `1701Q.2018-01-ENCS.input.rdo_code` | 6 RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1701q.native:57` |
| `1701Q.2018-01-ENCS.input.taxpayer_filer_name` | 7 Taxpayer / Filer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/1701q.native:61` |
| `1701Q.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1701q.native:65` |
| `1701Q.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | filer | postal_code | unbound_input | `src/pages/forms/1701q.native:68` |
| `1701Q.2018-01-ENCS.input.date_of_birth` | Date of Birth | profile | date_of_birth | optional | filer | date | unbound_input | `src/pages/forms/1701q.native:72` |
| `1701Q.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | filer | email | unbound_input | `src/pages/forms/1701q.native:76` |
| `1701Q.2018-01-ENCS.input.citizenship` | Citizenship | profile | citizenship | optional | filer | text | unbound_input | `src/pages/forms/1701q.native:80` |
| `1701Q.2018-01-ENCS.input.foreign_tax_number` | Foreign Tax Number | profile | foreign_tax_number | optional | filer | tax_identifier | unbound_input | `src/pages/forms/1701q.native:84` |
| `1701Q.2018-01-ENCS.input.income_tax_rate_election` | Income-tax-rate election | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/1701q.native:88` |
| `1701Q.2018-01-ENCS.input.spouse_tin` | Spouse TIN | profile | tin | required | spouse | tin | unbound_input | `src/pages/forms/1701q.native:113` |
| `1701Q.2018-01-ENCS.input.spouse_rdo_code` | Spouse RDO Code | profile | rdo_code | required | spouse | rdo_code | unbound_input | `src/pages/forms/1701q.native:117` |
| `1701Q.2018-01-ENCS.input.spouse_name` | Spouse Name | profile | taxpayer_name | required | spouse | text | unbound_input | `src/pages/forms/1701q.native:121` |
| `1701Q.2018-01-ENCS.input.spouse_citizenship` | Spouse Citizenship | profile | citizenship | optional | spouse | text | unbound_input | `src/pages/forms/1701q.native:124` |
| `1701Q.2018-01-ENCS.input.spouse_foreign_tax_number` | Spouse Foreign Tax Number | profile | foreign_tax_number | optional | spouse | tax_identifier | unbound_input | `src/pages/forms/1701q.native:127` |
| `1701Q.2018-01-ENCS.input.sales_revenues_receipts` | Sales / Revenues / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:136` |
| `1701Q.2018-01-ENCS.input.cost_of_sales_services` | Cost of Sales / Services | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:144` |
| `1701Q.2018-01-ENCS.input.allowable_deductions` | Allowable Deductions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:152` |
| `1701Q.2018-01-ENCS.input.taxable_income_external_policy_result` | Taxable Income (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:160` |
| `1701Q.2018-01-ENCS.input.income_tax_due_external_policy_result` | Income Tax Due (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:168` |
| `1701Q.2018-01-ENCS.input.gross_sales_receipts` | Gross Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:181` |
| `1701Q.2018-01-ENCS.input.less_non_operating_income` | Less: Non-Operating Income | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:189` |
| `1701Q.2018-01-ENCS.input.tax_due_at_8_percent_external_policy_result` | Tax Due at 8 percent (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:197` |
| `1701Q.2018-01-ENCS.input.prior_quarter_income_tax_payments` | Prior-quarter income tax payments | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701q.native:210` |
| `1701Q.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307` | Creditable tax withheld (BIR Form 2307) | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701q.native:218` |
| `1701Q.2018-01-ENCS.input.other_tax_credits_payments` | Other Tax Credits / Payments | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:226` |
| `1701Q.2018-01-ENCS.input.tax_payable_overpayment_external_policy_result` | 63 Tax Payable / (Overpayment) (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:239` |
| `1701Q.2018-01-ENCS.input.surcharge_external_policy_result` | 64 Surcharge (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:247` |
| `1701Q.2018-01-ENCS.input.interest_external_policy_result` | 65 Interest (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:255` |
| `1701Q.2018-01-ENCS.input.compromise_external_policy_result` | 66 Compromise (external policy result) | derived | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:263` |
| `1701Q.2018-01-ENCS.input.bank_agency` | Bank / Agency | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701q.native:367` |
| `1701Q.2018-01-ENCS.input.reference` | Reference | external | — | — | evidence | text | unbound_input | `src/pages/forms/1701q.native:375` |
| `1701Q.2018-01-ENCS.input.amount` | Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:383` |
| `1701Q.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | payment | text | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/1701q.native (table schema)` |

## 1701 — 2018-01-ENCS

Source: `src/pages/forms/1701.native`

Named roles: `filer`, `spouse`, `filing`, `payment`, `employer`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, estate, trust |
| spouse | zero_or_one | individual, sole_proprietor |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `1701.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1701.native:5` |
| `1701.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1701.native:9` |
| `1701.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1701.native:13` |
| `1701.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1701.native:17` |
| `1701.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1701.native:21` |
| `1701.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/1701.native:25` |
| `1701.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1701.native:29` |
| `1701.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | filer | postal_code | unbound_input | `src/pages/forms/1701.native:33` |
| `1701.2018-01-ENCS.input.date_of_birth` | Date of Birth | profile | date_of_birth | optional | filer | date | unbound_input | `src/pages/forms/1701.native:37` |
| `1701.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | filer | email | unbound_input | `src/pages/forms/1701.native:41` |
| `1701.2018-01-ENCS.input.citizenship` | Citizenship | profile | citizenship | optional | filer | text | unbound_input | `src/pages/forms/1701.native:45` |
| `1701.2018-01-ENCS.input.foreign_tax_number` | Foreign Tax Number | profile | foreign_tax_number | optional | filer | tax_identifier | unbound_input | `src/pages/forms/1701.native:49` |
| `1701.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/1701.native:53` |
| `1701.2018-01-ENCS.input.spouse_tin` | Spouse TIN | profile | tin | required | spouse | tin | unbound_input | `src/pages/forms/1701.native:62` |
| `1701.2018-01-ENCS.input.spouse_rdo_code` | Spouse RDO Code | profile | rdo_code | required | spouse | rdo_code | unbound_input | `src/pages/forms/1701.native:66` |
| `1701.2018-01-ENCS.input.spouse_name` | Spouse Name | profile | taxpayer_name | required | spouse | text | unbound_input | `src/pages/forms/1701.native:70` |
| `1701.2018-01-ENCS.input.taxable_compensation_income` | Taxable Compensation Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:79` |
| `1701.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:83` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation` | Tax Withheld on Compensation | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:87` |
| `1701.2018-01-ENCS.input.sales_revenues_receipts_fees` | Sales / Revenues / Receipts / Fees | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:96` |
| `1701.2018-01-ENCS.input.returns_allowances_and_discounts` | Returns, Allowances and Discounts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:100` |
| `1701.2018-01-ENCS.input.cost_of_sales_services` | Cost of Sales / Services | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:104` |
| `1701.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:108` |
| `1701.2018-01-ENCS.input.allowable_deductions` | Allowable Deductions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:112` |
| `1701.2018-01-ENCS.input.net_taxable_income` | Net Taxable Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:116` |
| `1701.2018-01-ENCS.input.other_taxable_income_description` | Other Taxable Income Description | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:125` |
| `1701.2018-01-ENCS.input.other_taxable_income_amount` | Other Taxable Income Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:129` |
| `1701.2018-01-ENCS.input.salaries_wages_and_benefits` | Salaries, Wages and Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:138` |
| `1701.2018-01-ENCS.input.rent_repairs_and_utilities` | Rent, Repairs and Utilities | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:142` |
| `1701.2018-01-ENCS.input.other_ordinary_deductions` | Other Ordinary Deductions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:146` |
| `1701.2018-01-ENCS.input.tax_on_compensation_income` | Tax on Compensation Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:155` |
| `1701.2018-01-ENCS.input.tax_on_business_profession_income` | Tax on Business / Profession Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:159` |
| `1701.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:163` |
| `1701.2018-01-ENCS.input.quarterly_income_tax_payments` | Quarterly Income Tax Payments | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:172` |
| `1701.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307` | Creditable Tax Withheld (BIR Form 2307) | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:176` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation_2` | Tax Withheld on Compensation | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:180` |
| `1701.2018-01-ENCS.input.other_tax_credit_description` | Other Tax Credit Description | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:189` |
| `1701.2018-01-ENCS.input.other_tax_credit_amount` | Other Tax Credit Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:193` |
| `1701.2018-01-ENCS.input.tax_relief_special_rate` | Tax Relief / Special Rate | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:202` |
| `1701.2018-01-ENCS.input.tax_relief_amount` | Tax Relief Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:206` |
| `1701.2018-01-ENCS.input.net_income_per_books` | Net Income per Books | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:215` |
| `1701.2018-01-ENCS.input.add_non_deductible_expenses` | Add: Non-Deductible Expenses | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:219` |
| `1701.2018-01-ENCS.input.less_non_taxable_income` | Less: Non-Taxable Income | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:223` |
| `1701.2018-01-ENCS.input.taxable_net_income` | Taxable Net Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:227` |
| `1701.2018-01-ENCS.input.tax_due` | Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:236` |
| `1701.2018-01-ENCS.input.less_total_tax_credits_payments` | Less: Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:240` |
| `1701.2018-01-ENCS.input.penalties` | Penalties | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:244` |
| `1701.2018-01-ENCS.input.overpayment_disposition` | 32 Overpayment Disposition | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/1701.native:253` |
| `1701.2018-01-ENCS.input.required_attachments` | 33 Required Attachments | external | — | — | attachment | text | unbound_input | `src/pages/forms/1701.native:257` |
| `1701.2018-01-ENCS.table.compensation.employer_name` | Employer name | external | — | — | employer | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.employer_tin` | Employer TIN | external | — | — | employer | tin | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.gross` | Gross compensation | external | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.non_taxable` | Non-taxable compensation | external | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.taxable` | Taxable compensation | derived | — | — | system | money | derived_display | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.tax_withheld` | Compensation tax withheld | external | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.year_incurred` | NOLCO year incurred | external | — | — | evidence | year | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.original_amount` | Original NOLCO | external | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.applied_previously` | NOLCO applied previously | external | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.applied_this_year` | NOLCO applied this year | transaction | — | — | filing | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.balance` | NOLCO balance | derived | — | — | system | money | derived_display | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | payment | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/1701.native (table schema)` |

## 1702RT — 2018-01-ENCS

Source: `src/pages/forms/1702-rt.native`

Named roles: `filer`, `filing`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | corporation, partnership, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `1702RT.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1702-rt.native:5` |
| `1702RT.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-rt.native:9` |
| `1702RT.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1702-rt.native:13` |
| `1702RT.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1702-rt.native:17` |
| `1702RT.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1702-rt.native:21` |
| `1702RT.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:25` |
| `1702RT.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:29` |
| `1702RT.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:33` |
| `1702RT.2018-01-ENCS.input.tax_relief_special_law` | Tax Relief / Special Law | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1702-rt.native:37` |
| `1702RT.2018-01-ENCS.input.sales_receipts_revenues_fees` | 27 Sales / Receipts / Revenues / Fees | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:46` |
| `1702RT.2018-01-ENCS.input.returns_allowances_discounts` | 28 Returns / Allowances / Discounts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:50` |
| `1702RT.2018-01-ENCS.input.cost_of_sales_services` | 30 Cost of Sales / Services | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:54` |
| `1702RT.2018-01-ENCS.input.other_taxable_income` | 32 Other Taxable Income | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:58` |
| `1702RT.2018-01-ENCS.input.itemized_optional_standard_deduction` | Itemized / Optional Standard Deduction | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/1702-rt.native:62` |
| `1702RT.2018-01-ENCS.input.regular_income_tax_rate` | 40 Regular Income Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-rt.native:66` |
| `1702RT.2018-01-ENCS.input.net_sales_receipts` | Net Sales / Receipts | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:75` |
| `1702RT.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:79` |
| `1702RT.2018-01-ENCS.input.total_taxable_income` | Total Taxable Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:83` |
| `1702RT.2018-01-ENCS.input.normal_income_tax` | Normal Income Tax | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:87` |
| `1702RT.2018-01-ENCS.input.minimum_corporate_income_tax` | Minimum Corporate Income Tax | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:91` |
| `1702RT.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:95` |
| `1702RT.2018-01-ENCS.input.prior_year_excess_credits` | 44 Prior-Year Excess Credits | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:104` |
| `1702RT.2018-01-ENCS.input.quarterly_income_tax_payments` | 45 Quarterly Income Tax Payments | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:108` |
| `1702RT.2018-01-ENCS.input.creditable_tax_withheld` | 46 Creditable Tax Withheld | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:112` |
| `1702RT.2018-01-ENCS.input.foreign_tax_credits` | 47 Foreign Tax Credits | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:116` |
| `1702RT.2018-01-ENCS.input.48_53_other_credits_payments` | 48-53 Other Credits / Payments | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:120` |
| `1702RT.2018-01-ENCS.input.total_tax_credits_payments` | 54 Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:124` |
| `1702RT.2018-01-ENCS.input.tax_payable_overpayment` | Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:133` |
| `1702RT.2018-01-ENCS.input.add_surcharge_interest_and_compromise` | Add: Surcharge, Interest and Compromise | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:137` |
| `1702RT.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:141` |
| `1702RT.2018-01-ENCS.input.refund` | Refund | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:150` |
| `1702RT.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:154` |
| `1702RT.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:158` |
| `1702RT.2018-01-ENCS.table.official_schedule.name` | Official schedule name | filing_context | — | — | attachment | text | static_table | `src/pages/forms/1702-rt.native (table schema)` |
| `1702RT.2018-01-ENCS.table.official_schedule.rows` | Official schedule rows | external | — | — | attachment | text | static_table | `src/pages/forms/1702-rt.native (table schema)` |
| `1702RT.2018-01-ENCS.table.official_schedule.attachment_status` | Official schedule attachment status | filing_context | — | — | attachment | choice | static_table | `src/pages/forms/1702-rt.native (table schema)` |

## 1702MX — 2018-01-ENCS

Source: `src/pages/forms/1702-mx.native`

Named roles: `filer`, `filing`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | corporation, partnership, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `1702MX.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1702-mx.native:5` |
| `1702MX.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-mx.native:9` |
| `1702MX.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1702-mx.native:13` |
| `1702MX.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1702-mx.native:17` |
| `1702MX.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1702-mx.native:21` |
| `1702MX.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:25` |
| `1702MX.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:29` |
| `1702MX.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:33` |
| `1702MX.2018-01-ENCS.input.special_preferential_rate_basis` | Special / Preferential Rate Basis | profile | special_rate_basis | optional | filer | text | unbound_input | `src/pages/forms/1702-mx.native:37` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_regular_rate` | Gross Income Subject to Regular Rate | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:46` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_special_rate` | Gross Income Subject to Special Rate | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:50` |
| `1702MX.2018-01-ENCS.input.special_preferential_tax_rate` | Special / Preferential Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-mx.native:54` |
| `1702MX.2018-01-ENCS.input.schedule_2_regular_rate_tax_due` | Schedule 2 Regular-Rate Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:58` |
| `1702MX.2018-01-ENCS.input.schedule_2_special_rate_tax_due` | Schedule 2 Special-Rate Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:62` |
| `1702MX.2018-01-ENCS.input.schedule_3_total_tax_credits` | Schedule 3 Total Tax Credits | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:66` |
| `1702MX.2018-01-ENCS.input.income_tax_at_regular_rate` | Income Tax at Regular Rate | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:75` |
| `1702MX.2018-01-ENCS.input.income_tax_at_special_rate` | Income Tax at Special Rate | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:79` |
| `1702MX.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:83` |
| `1702MX.2018-01-ENCS.input.total_tax_credits_payments` | Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:87` |
| `1702MX.2018-01-ENCS.input.net_tax_payable_overpayment` | Net Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:91` |
| `1702MX.2018-01-ENCS.input.surcharge` | Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:100` |
| `1702MX.2018-01-ENCS.input.interest` | Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:104` |
| `1702MX.2018-01-ENCS.input.compromise` | Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:108` |
| `1702MX.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:112` |
| `1702MX.2018-01-ENCS.input.refund` | Refund | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:121` |
| `1702MX.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-mx.native:125` |
| `1702MX.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:129` |
| `1702MX.2018-01-ENCS.input.attachment_description` | Attachment Description | external | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:138` |
| `1702MX.2018-01-ENCS.input.attachment_reference` | Attachment Reference | external | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:142` |
| `1702MX.2018-01-ENCS.table.rate_schedule.schedule_id` | Rate-schedule identity | filing_context | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.description` | Special-rate income description | transaction | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.legal_basis` | Special-rate legal basis | transaction | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.regular_rate` | Regular income-tax rate | external | — | — | evidence | percent | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.special_rate` | Special income-tax rate | external | — | — | evidence | percent | static_table | `src/pages/forms/1702-mx.native (table schema)` |

## 2550Q — 2024-04-ENCS

Source: `src/pages/forms/2550q.native`

Named roles: `filer`, `filing`, `payment`, `preparer`, `withholding_agent`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `2550Q.2024-04-ENCS.input.year_end_month` | Year-end month | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/2550q.native:5` |
| `2550Q.2024-04-ENCS.input.taxable_year_raw` | Taxable year (raw) | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/2550q.native:9` |
| `2550Q.2024-04-ENCS.input.return_period_from` | Return Period From | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:13` |
| `2550Q.2024-04-ENCS.input.return_period_to` | Return Period To | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:17` |
| `2550Q.2024-04-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:21` |
| `2550Q.2024-04-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:25` |
| `2550Q.2024-04-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/2550q.native:29` |
| `2550Q.2024-04-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/2550q.native:33` |
| `2550Q.2024-04-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/2550q.native:37` |
| `2550Q.2024-04-ENCS.input.vatable_sales_receipts` | 31A Vatable Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:46` |
| `2550Q.2024-04-ENCS.input.output_tax_due` | 31B Output Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:50` |
| `2550Q.2024-04-ENCS.input.zero_rated_sales_receipts` | 32A Zero-Rated Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:54` |
| `2550Q.2024-04-ENCS.input.exempt_sales_receipts` | 33A Exempt Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:58` |
| `2550Q.2024-04-ENCS.input.output_vat_adjustments` | Output VAT Adjustments | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:62` |
| `2550Q.2024-04-ENCS.input.total_output_tax_due` | Total Output Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:66` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_input_tax` | 44 Domestic Purchases / Input Tax | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:75` |
| `2550Q.2024-04-ENCS.input.services_rendered_by_non_residents` | 45 Services Rendered by Non-Residents | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:79` |
| `2550Q.2024-04-ENCS.input.importation_of_goods` | 46 Importation of Goods | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:83` |
| `2550Q.2024-04-ENCS.input.other_purchases` | 47 Other Purchases | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:87` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_without_input_tax` | 48 Domestic Purchases Without Input Tax | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:91` |
| `2550Q.2024-04-ENCS.input.exempt_importations` | 49 Exempt Importations | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:95` |
| `2550Q.2024-04-ENCS.input.input_tax_directly_attributable_to_exempt_sales` | Input Tax Directly Attributable to Exempt Sales | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:104` |
| `2550Q.2024-04-ENCS.input.input_tax_not_directly_attributable` | Input Tax Not Directly Attributable | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:108` |
| `2550Q.2024-04-ENCS.input.ratable_input_tax_to_exempt_sales` | Ratable Input Tax to Exempt Sales | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:112` |
| `2550Q.2024-04-ENCS.input.prior_return_payment` | Prior Return Payment | external | — | — | evidence | money | unbound_input | `src/pages/forms/2550q.native:121` |
| `2550Q.2024-04-ENCS.input.other_tax_credit_payment` | Other Tax Credit / Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:125` |
| `2550Q.2024-04-ENCS.input.net_vat_payable_overpayment` | Net VAT Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:129` |
| `2550Q.2024-04-ENCS.input.surcharge` | Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:133` |
| `2550Q.2024-04-ENCS.input.interest` | Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:137` |
| `2550Q.2024-04-ENCS.input.compromise` | Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:141` |
| `2550Q.2024-04-ENCS.input.taxpayer_authorized_representative` | Taxpayer / Authorized Representative | transaction | — | — | preparer | text | unbound_input | `src/pages/forms/2550q.native:150` |
| `2550Q.2024-04-ENCS.input.payment_method` | Payment Method | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/2550q.native:154` |
| `2550Q.2024-04-ENCS.input.payment_reference` | Payment Reference | external | — | — | payment | text | unbound_input | `src/pages/forms/2550q.native:158` |
| `2550Q.2024-04-ENCS.table.capital_good.description` | Capital-good description | external | — | — | evidence | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.date_acquired` | Capital-good acquisition date | external | — | — | evidence | date | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.useful_life` | Capital-good useful life | external | — | — | evidence | integer | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.acquisition_cost` | Capital-good acquisition cost | external | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.allowable_input_tax` | Allowable capital-good input tax | derived | — | — | system | money | derived_display | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.agent` | VAT withholding agent | external | — | — | withholding_agent | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.agent_tin` | VAT withholding-agent TIN | external | — | — | withholding_agent | tin | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.period` | VAT withholding period | external | — | — | evidence | tax_period | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.credit` | Creditable VAT withheld | external | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.payment_date` | Advance VAT payment date | external | — | — | payment | date | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.reference_number` | Advance VAT reference number | external | — | — | payment | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.taxable_base` | Advance VAT taxable base | external | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.paid` | Advance VAT paid | external | — | — | payment | money | static_table | `src/pages/forms/2550q.native (table schema)` |

## 2551Q — 2018-01-ENCS

Source: `src/pages/forms/2551q.native`

Named roles: `filer`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `2551Q.2018-01-ENCS.input.taxable_period_basis` | 1 Taxable-period basis | filing_context | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:5` |
| `2551Q.2018-01-ENCS.input.year_end_month` | 2 Year-end month | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/2551q.native:25` |
| `2551Q.2018-01-ENCS.input.taxable_quarter` | Taxable Quarter | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/2551q.native:33` |
| `2551Q.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/2551q.native:37` |
| `2551Q.2018-01-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/2551q.native:41` |
| `2551Q.2018-01-ENCS.input.return_options` | Return Options | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:49` |
| `2551Q.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:53` |
| `2551Q.2018-01-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:57` |
| `2551Q.2018-01-ENCS.input.tax_relief_specification` | 12A Tax Relief Specification | transaction | — | — | filing | text | unbound_input | `src/pages/forms/2551q.native:77` |
| `2551Q.2018-01-ENCS.input.income_tax_rate_election` | 13 Income-tax-rate election | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:85` |
| `2551Q.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/2551q.native:110` |
| `2551Q.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/2551q.native:114` |
| `2551Q.2018-01-ENCS.input.taxpayers_name` | Taxpayer's Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/2551q.native:118` |
| `2551Q.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/2551q.native:122` |
| `2551Q.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | filer | postal_code | unbound_input | `src/pages/forms/2551q.native:126` |
| `2551Q.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/2551q.native:130` |
| `2551Q.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | filer | email | unbound_input | `src/pages/forms/2551q.native:134` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_code` | Schedule 1 Line 1 Percentage-tax Code | transaction | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:147` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_tax_base_taxable_amount` | Schedule 1 Line 1 Tax Base / Taxable Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:155` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_policy_supplied_tax_rate` | Schedule 1 Line 1 Policy-supplied Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:163` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_due` | Schedule 1 Line 1 Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:171` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_code` | Schedule 1 Line 2 Percentage-tax Code | transaction | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:175` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_tax_base_taxable_amount` | Schedule 1 Line 2 Tax Base / Taxable Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:183` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_policy_supplied_tax_rate` | Schedule 1 Line 2 Policy-supplied Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:191` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_due` | Schedule 1 Line 2 Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:199` |
| `2551Q.2018-01-ENCS.input.total_percentage_tax_due` | 14 Total Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:209` |
| `2551Q.2018-01-ENCS.input.creditable_percentage_tax_withheld` | 15 Creditable Percentage Tax Withheld | external | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:213` |
| `2551Q.2018-01-ENCS.input.tax_paid_in_previous_return` | 16 Tax Paid in Previous Return | external | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:221` |
| `2551Q.2018-01-ENCS.input.other_tax_credit_payment` | 17 Other Tax Credit / Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:229` |
| `2551Q.2018-01-ENCS.input.total_tax_credits_payments` | 18 Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:237` |
| `2551Q.2018-01-ENCS.input.tax_payable_overpayment` | 19 Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:241` |
| `2551Q.2018-01-ENCS.input.surcharge_manual` | 20 Surcharge (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:245` |
| `2551Q.2018-01-ENCS.input.interest_manual` | 21 Interest (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:253` |
| `2551Q.2018-01-ENCS.input.compromise_manual` | 22 Compromise (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:261` |
| `2551Q.2018-01-ENCS.input.overpayment_disposition` | 24 Overpayment Disposition | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:269` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.atc` | Percentage-tax ATC | transaction | — | — | filing | atc_code | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.tax_base` | Percentage-tax base | transaction | — | — | filing | money | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.rate` | Percentage-tax rate | external | — | — | evidence | percent | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.tax_due` | Percentage tax due | derived | — | — | system | money | derived_display | `src/pages/forms/2551q.native (table schema)` |

## 0619E — 2018-01-ENCS

Source: `src/pages/forms/0619-e.native`

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|
| `0619E.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-e.native:5` |
| `0619E.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:9` |
| `0619E.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:13` |
| `0619E.2018-01-ENCS.input.atc` | 5 ATC | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/0619-e.native:17` |
| `0619E.2018-01-ENCS.input.tax_type_code` | 6 Tax Type Code | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0619-e.native:21` |
| `0619E.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0619-e.native:25` |
| `0619E.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0619-e.native:29` |
| `0619E.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0619-e.native:33` |
| `0619E.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | profile | government_withholding_agent | required | filer | boolean | unbound_input | `src/pages/forms/0619-e.native:37` |
| `0619E.2018-01-ENCS.input.amount_of_remittance` | 14 Amount of Remittance | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-e.native:46` |
| `0619E.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 15 Less: Amount Remitted from Previously Filed Form | external | — | — | evidence | money | unbound_input | `src/pages/forms/0619-e.native:50` |
| `0619E.2018-01-ENCS.input.net_amount_of_remittance_14_15` | 16 Net Amount of Remittance (14 - 15) | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:54` |
| `0619E.2018-01-ENCS.input.surcharge` | 17A Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:58` |
| `0619E.2018-01-ENCS.input.interest` | 17B Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:62` |
| `0619E.2018-01-ENCS.input.compromise` | 17C Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:66` |
| `0619E.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | preparer | text | unbound_input | `src/pages/forms/0619-e.native:75` |
| `0619E.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:79` |
| `0619E.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:83` |
| `0619E.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/0619-e.native (table schema)` |
