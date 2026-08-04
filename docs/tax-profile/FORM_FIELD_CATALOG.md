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

| Code | Title | Tax category | Revision | Status | Cadence | Periods | Inputs | Table fields | Source |
|---|---|---|---|---|---|---|---:|---:|---|
| 0605 | Payment Form | payment | 1999-07-ENCS | static_layout | on_demand | — | 17 | 4 | src/pages/forms/0605.native |
| 1905 | Application for Registration Information Update / Correction / Cancellation | registration | — | calendar_only | on_demand | — | 0 | 0 | — |
| 1600 | Monthly Remittance Return of VAT and Other Percentage Taxes Withheld | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1600PT | Monthly Remittance Return of Other Percentage Taxes Withheld | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1600VT | Monthly Remittance Return of Value-Added Tax Withheld | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1600WP | Remittance Return of Percentage Tax on Winnings and Prizes | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1601C | Monthly Remittance Return of Income Taxes Withheld on Compensation | withholding_tax | 2018-01-ENCS | static_layout | monthly | 1-12 | 28 | 7 | src/pages/forms/1601-c.native |
| 1601E | Monthly Remittance Return of Creditable Income Taxes Withheld (Expanded) | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1601F | Monthly Remittance Return of Final Income Tax Withheld | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 0619F | Monthly Remittance Form for Final Income Taxes Withheld | withholding_tax | 2018-01-ENCS | static_layout | monthly | 1-12 | 20 | 4 | src/pages/forms/0619-f.native |
| 1601FQ | Quarterly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1602 | Monthly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 1602Q | Quarterly Remittance Return of Final Taxes Withheld on Interest Paid on Deposits and Yield on Deposit Substitutes / Trusts / Etc. | withholding_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1603 | Quarterly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1603Q | Quarterly Remittance Return of Final Income Taxes Withheld on Fringe Benefits Paid to Employees Other Than Rank and File | withholding_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1604CF | Annual Information Return of Income Taxes Withheld on Compensation | withholding_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1604E | Annual Information Return of Creditable Income Taxes Withheld | withholding_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 0620 | Monthly Remittance Form of Tax Withheld on the Amount Withdrawn from the Decedent's Deposit Account | withholding_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2316 | Certificate of Compensation Payment / Tax Withheld | withholding_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1700 | Annual Income Tax Return (Purely Compensation) | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1701Q | Quarterly Income Tax Return for Individuals, Estates and Trusts | income_tax | 2018-01-ENCS | static_layout | quarterly | 1-3 | 37 | 4 | src/pages/forms/1701q.native |
| 1701 | Annual Income Tax Return for Individuals, Estates and Trusts | income_tax | 2018-01-ENCS | static_layout | annual | — | 49 | 15 | src/pages/forms/1701.native |
| 1701A | Annual Income Tax Return (8% / OSD) | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1702Q | Quarterly Income Tax Return for Corporations, Partnerships and Cooperatives | income_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1702 | Annual Income Tax Return for Corporations, Partnerships and Cooperatives | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1702RT | Annual Income Tax Return — Regular Taxable | income_tax | 2018-01-ENCS | static_layout | annual | — | 33 | 3 | src/pages/forms/1702-rt.native |
| 1702EX | Annual Income Tax Return — Tax-Exempt | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1702MX | Annual Income Tax Return — Mixed Income | income_tax | 2018-01-ENCS | static_layout | annual | — | 29 | 5 | src/pages/forms/1702-mx.native |
| 1704 | Improperly Accumulated Earnings Tax Return | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 2550M | Monthly Value-Added Tax Declaration | value_added_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2550Q | Quarterly Value-Added Tax Return | value_added_tax | 2024-04-ENCS | static_layout | quarterly | 1-4 | 33 | 13 | src/pages/forms/2550q.native |
| 2551Q | Quarterly Percentage Tax Return | percentage_tax | 2018-01-ENCS | static_layout | quarterly | 1-4 | 35 | 4 | src/pages/forms/2551q.native |
| 2551M | Monthly Percentage Tax Return | percentage_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2552 | Percentage Tax Return on Transactions Involving Shares of Stock | percentage_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 2553 | Percentage Tax Payable Under Special Laws | percentage_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 2000 | Documentary Stamp Tax Declaration/Return | documentary_stamp_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 2000OT | Documentary Stamp Tax Declaration/Return (One-Time Transactions) | documentary_stamp_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 2200A | Excise Tax Return for Alcohol Products | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200AN | Excise Tax Return for Automobiles and Non-Essential Goods | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200M | Excise Tax Return for Mineral Products | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200P | Excise Tax Return for Petroleum Products | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200T | Excise Tax Return for Tobacco Products | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200C | Excise Tax Return for Coal and Coke | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 2200S | Excise Tax Return for Sweetened Beverages | excise_tax | — | calendar_only | monthly | 1-12 | 0 | 0 | — |
| 0619E | Monthly Remittance Form for Creditable Income Taxes Withheld (Expanded) | withholding_tax | 2018-01-ENCS | static_layout | monthly | 1-12 | 18 | 4 | src/pages/forms/0619-e.native |
| 1601EQ | Quarterly Remittance Return of Creditable Income Taxes Withheld (Expanded) | withholding_tax | — | calendar_only | quarterly | 1-4 | 0 | 0 | — |
| 1701MS | Annual Income Tax Return for Micro and Small Taxpayers | income_tax | — | calendar_only | annual | — | 0 | 0 | — |
| 1706 | Capital Gains Tax Return (Real Properties) | capital_gains_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 1707A | Annual Capital Gains Tax Return (Shares of Stock Not Traded) | capital_gains_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 1800 | Donor's Tax Return | estate_and_donors_tax | — | calendar_only | on_demand | — | 0 | 0 | — |
| 1801 | Estate Tax Return | estate_and_donors_tax | — | calendar_only | on_demand | — | 0 | 0 | — |

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
| `0605.1999-07-ENCS.input.year_ended_month_independent` | 2 Year Ended month (independent) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0605.native:3` |
| `0605.1999-07-ENCS.input.due_date_mm_dd_yyyy` | 4 Due Date (MM/DD/YYYY) | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0605.native:4` |
| `0605.1999-07-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/0605.native:5` |
| `0605.1999-07-ENCS.input.atc_only_source_proven_pairs` | 6 ATC - only source-proven pairs | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/0605.native:6` |
| `0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs` | 8 Tax Type - only source-proven pairs | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0605.native:7` |
| `0605.1999-07-ENCS.input.manner_of_payment` | 17 Manner of Payment | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:8` |
| `0605.1999-07-ENCS.input.tin` | 9 TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0605.native:14` |
| `0605.1999-07-ENCS.input.rdo_code` | 10 RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0605.native:15` |
| `0605.1999-07-ENCS.input.line_of_business_occupation` | 12 Line of Business / Occupation | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/0605.native:16` |
| `0605.1999-07-ENCS.input.taxpayer_name` | 13 Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/0605.native:17` |
| `0605.1999-07-ENCS.input.registered_address` | 15 Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/0605.native:18` |
| `0605.1999-07-ENCS.input.type_of_payment` | 18 Type of Payment | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:19` |
| `0605.1999-07-ENCS.input.basic_tax_deposit_advance_payment` | 19 Basic Tax / Deposit / Advance Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:25` |
| `0605.1999-07-ENCS.input.surcharge_manual` | 20A Surcharge (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:26` |
| `0605.1999-07-ENCS.input.interest_manual` | 20B Interest (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:27` |
| `0605.1999-07-ENCS.input.compromise_manual` | 20C Compromise (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:28` |
| `0605.1999-07-ENCS.input.taxpayer_authorized_representative` | 22A Taxpayer / Authorized Representative | transaction | — | — | preparer | text | unbound_input | `src/pages/forms/0605.native:248` |
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
| `1601C.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1601-c.native:3` |
| `1601C.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1601-c.native:4` |
| `1601C.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:5` |
| `1601C.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:6` |
| `1601C.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1601-c.native:7` |
| `1601C.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/1601-c.native:8` |
| `1601C.2018-01-ENCS.input.for_the_month_of` | For the Month of | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/1601-c.native:14` |
| `1601C.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:15` |
| `1601C.2018-01-ENCS.input.any_taxes_withheld` | Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:16` |
| `1601C.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1601-c.native:17` |
| `1601C.2018-01-ENCS.input.atc` | ATC | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/1601-c.native:18` |
| `1601C.2018-01-ENCS.input.tax_relief` | 13 Tax Relief | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1601-c.native:19` |
| `1601C.2018-01-ENCS.input.total_amount_of_compensation` | 14 Total Amount of Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:25` |
| `1601C.2018-01-ENCS.input.statutory_minimum_wage` | 15 Statutory Minimum Wage | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:26` |
| `1601C.2018-01-ENCS.input.holiday_overtime_and_night_shift_pay` | 16 Holiday, Overtime and Night Shift Pay | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:27` |
| `1601C.2018-01-ENCS.input.13th_month_pay_and_other_benefits` | 17 13th Month Pay and Other Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:28` |
| `1601C.2018-01-ENCS.input.de_minimis_benefits` | 18 De Minimis Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:29` |
| `1601C.2018-01-ENCS.input.sss_gsis_phic_and_pag_ibig_contributions` | 19 SSS, GSIS, PHIC and Pag-IBIG Contributions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:30` |
| `1601C.2018-01-ENCS.input.other_non_taxable_compensation` | 20 Other Non-Taxable Compensation | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:31` |
| `1601C.2018-01-ENCS.input.total_non_taxable_exempt_compensation` | 21 Total Non-Taxable / Exempt Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:32` |
| `1601C.2018-01-ENCS.input.total_taxable_compensation` | 22 Total Taxable Compensation | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:33` |
| `1601C.2018-01-ENCS.input.tax_required_to_be_withheld` | 25 Tax Required to be Withheld | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:34` |
| `1601C.2018-01-ENCS.input.schedule_adjustment` | 26 Schedule Adjustment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:35` |
| `1601C.2018-01-ENCS.input.tax_still_due` | 31 Tax Still Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:36` |
| `1601C.2018-01-ENCS.input.surcharge` | 32 Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:42` |
| `1601C.2018-01-ENCS.input.interest` | 33 Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:43` |
| `1601C.2018-01-ENCS.input.compromise` | 34 Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:44` |
| `1601C.2018-01-ENCS.input.total_penalties` | 35 Total Penalties | derived | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:45` |
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
| `0619F.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-f.native:3` |
| `0619F.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:4` |
| `0619F.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:5` |
| `0619F.2018-01-ENCS.input.tax_type_code` | Tax Type Code | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0619-f.native:6` |
| `0619F.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0619-f.native:7` |
| `0619F.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | profile | government_withholding_agent | required | filer | boolean | unbound_input | `src/pages/forms/0619-f.native:8` |
| `0619F.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0619-f.native:9` |
| `0619F.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0619-f.native:10` |
| `0619F.2018-01-ENCS.input.registered_taxpayer_name` | Registered Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/0619-f.native:11` |
| `0619F.2018-01-ENCS.input.final_tax_withheld_on_interest_deposits_and_trusts` | 13 Final tax withheld on interest, deposits and trusts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:17` |
| `0619F.2018-01-ENCS.input.other_final_income_taxes_withheld` | 14 Other final income taxes withheld | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:18` |
| `0619F.2018-01-ENCS.input.total_final_income_taxes_withheld` | 15 Total final income taxes withheld | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:19` |
| `0619F.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 16 Less: Amount Remitted from Previously Filed Form | external | — | — | evidence | money | unbound_input | `src/pages/forms/0619-f.native:20` |
| `0619F.2018-01-ENCS.input.net_amount_of_remittance` | 17 Net Amount of Remittance | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:21` |
| `0619F.2018-01-ENCS.input.surcharge` | 18A Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:22` |
| `0619F.2018-01-ENCS.input.interest` | 18B Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:23` |
| `0619F.2018-01-ENCS.input.compromise` | 18C Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:24` |
| `0619F.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | preparer | text | unbound_input | `src/pages/forms/0619-f.native:30` |
| `0619F.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:31` |
| `0619F.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:32` |
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
| `1701.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1701.native:3` |
| `1701.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1701.native:4` |
| `1701.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1701.native:5` |
| `1701.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1701.native:6` |
| `1701.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1701.native:7` |
| `1701.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/1701.native:8` |
| `1701.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1701.native:9` |
| `1701.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | filer | postal_code | unbound_input | `src/pages/forms/1701.native:10` |
| `1701.2018-01-ENCS.input.date_of_birth` | Date of Birth | profile | date_of_birth | optional | filer | date | unbound_input | `src/pages/forms/1701.native:11` |
| `1701.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | filer | email | unbound_input | `src/pages/forms/1701.native:12` |
| `1701.2018-01-ENCS.input.citizenship` | Citizenship | profile | citizenship | optional | filer | text | unbound_input | `src/pages/forms/1701.native:13` |
| `1701.2018-01-ENCS.input.foreign_tax_number` | Foreign Tax Number | profile | foreign_tax_number | optional | filer | tax_identifier | unbound_input | `src/pages/forms/1701.native:14` |
| `1701.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/1701.native:15` |
| `1701.2018-01-ENCS.input.spouse_tin` | Spouse TIN | profile | tin | required | spouse | tin | unbound_input | `src/pages/forms/1701.native:21` |
| `1701.2018-01-ENCS.input.spouse_rdo_code` | Spouse RDO Code | profile | rdo_code | required | spouse | rdo_code | unbound_input | `src/pages/forms/1701.native:22` |
| `1701.2018-01-ENCS.input.spouse_name` | Spouse Name | profile | taxpayer_name | required | spouse | text | unbound_input | `src/pages/forms/1701.native:23` |
| `1701.2018-01-ENCS.input.taxable_compensation_income` | Taxable Compensation Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:29` |
| `1701.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:30` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation` | Tax Withheld on Compensation | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:31` |
| `1701.2018-01-ENCS.input.sales_revenues_receipts_fees` | Sales / Revenues / Receipts / Fees | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:37` |
| `1701.2018-01-ENCS.input.returns_allowances_and_discounts` | Returns, Allowances and Discounts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:38` |
| `1701.2018-01-ENCS.input.cost_of_sales_services` | Cost of Sales / Services | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:39` |
| `1701.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:40` |
| `1701.2018-01-ENCS.input.allowable_deductions` | Allowable Deductions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:41` |
| `1701.2018-01-ENCS.input.net_taxable_income` | Net Taxable Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:42` |
| `1701.2018-01-ENCS.input.other_taxable_income_description` | Other Taxable Income Description | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:48` |
| `1701.2018-01-ENCS.input.other_taxable_income_amount` | Other Taxable Income Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:49` |
| `1701.2018-01-ENCS.input.salaries_wages_and_benefits` | Salaries, Wages and Benefits | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:55` |
| `1701.2018-01-ENCS.input.rent_repairs_and_utilities` | Rent, Repairs and Utilities | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:56` |
| `1701.2018-01-ENCS.input.other_ordinary_deductions` | Other Ordinary Deductions | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:57` |
| `1701.2018-01-ENCS.input.tax_on_compensation_income` | Tax on Compensation Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:63` |
| `1701.2018-01-ENCS.input.tax_on_business_profession_income` | Tax on Business / Profession Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:64` |
| `1701.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:65` |
| `1701.2018-01-ENCS.input.quarterly_income_tax_payments` | Quarterly Income Tax Payments | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:71` |
| `1701.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307` | Creditable Tax Withheld (BIR Form 2307) | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:72` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation_2` | Tax Withheld on Compensation | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:73` |
| `1701.2018-01-ENCS.input.other_tax_credit_description` | Other Tax Credit Description | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:79` |
| `1701.2018-01-ENCS.input.other_tax_credit_amount` | Other Tax Credit Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:80` |
| `1701.2018-01-ENCS.input.tax_relief_special_rate` | Tax Relief / Special Rate | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:86` |
| `1701.2018-01-ENCS.input.tax_relief_amount` | Tax Relief Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:87` |
| `1701.2018-01-ENCS.input.net_income_per_books` | Net Income per Books | external | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:93` |
| `1701.2018-01-ENCS.input.add_non_deductible_expenses` | Add: Non-Deductible Expenses | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:94` |
| `1701.2018-01-ENCS.input.less_non_taxable_income` | Less: Non-Taxable Income | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:95` |
| `1701.2018-01-ENCS.input.taxable_net_income` | Taxable Net Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:96` |
| `1701.2018-01-ENCS.input.tax_due` | Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:102` |
| `1701.2018-01-ENCS.input.less_total_tax_credits_payments` | Less: Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:103` |
| `1701.2018-01-ENCS.input.penalties` | Penalties | derived | — | — | system | money | unbound_input | `src/pages/forms/1701.native:104` |
| `1701.2018-01-ENCS.input.overpayment_disposition` | 32 Overpayment Disposition | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/1701.native:110` |
| `1701.2018-01-ENCS.input.required_attachments` | 33 Required Attachments | external | — | — | attachment | text | unbound_input | `src/pages/forms/1701.native:111` |
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
| `1702RT.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1702-rt.native:3` |
| `1702RT.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-rt.native:4` |
| `1702RT.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1702-rt.native:5` |
| `1702RT.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1702-rt.native:6` |
| `1702RT.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1702-rt.native:7` |
| `1702RT.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:8` |
| `1702RT.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:9` |
| `1702RT.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1702-rt.native:10` |
| `1702RT.2018-01-ENCS.input.tax_relief_special_law` | Tax Relief / Special Law | transaction | — | — | filing | text | unbound_input | `src/pages/forms/1702-rt.native:11` |
| `1702RT.2018-01-ENCS.input.sales_receipts_revenues_fees` | 27 Sales / Receipts / Revenues / Fees | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:17` |
| `1702RT.2018-01-ENCS.input.returns_allowances_discounts` | 28 Returns / Allowances / Discounts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:18` |
| `1702RT.2018-01-ENCS.input.cost_of_sales_services` | 30 Cost of Sales / Services | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:19` |
| `1702RT.2018-01-ENCS.input.other_taxable_income` | 32 Other Taxable Income | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:20` |
| `1702RT.2018-01-ENCS.input.itemized_optional_standard_deduction` | Itemized / Optional Standard Deduction | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/1702-rt.native:21` |
| `1702RT.2018-01-ENCS.input.regular_income_tax_rate` | 40 Regular Income Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-rt.native:22` |
| `1702RT.2018-01-ENCS.input.net_sales_receipts` | Net Sales / Receipts | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:28` |
| `1702RT.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:29` |
| `1702RT.2018-01-ENCS.input.total_taxable_income` | Total Taxable Income | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:30` |
| `1702RT.2018-01-ENCS.input.normal_income_tax` | Normal Income Tax | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:31` |
| `1702RT.2018-01-ENCS.input.minimum_corporate_income_tax` | Minimum Corporate Income Tax | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:32` |
| `1702RT.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:33` |
| `1702RT.2018-01-ENCS.input.prior_year_excess_credits` | 44 Prior-Year Excess Credits | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:39` |
| `1702RT.2018-01-ENCS.input.quarterly_income_tax_payments` | 45 Quarterly Income Tax Payments | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:40` |
| `1702RT.2018-01-ENCS.input.creditable_tax_withheld` | 46 Creditable Tax Withheld | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:41` |
| `1702RT.2018-01-ENCS.input.foreign_tax_credits` | 47 Foreign Tax Credits | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:42` |
| `1702RT.2018-01-ENCS.input.48_53_other_credits_payments` | 48-53 Other Credits / Payments | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:43` |
| `1702RT.2018-01-ENCS.input.total_tax_credits_payments` | 54 Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:44` |
| `1702RT.2018-01-ENCS.input.tax_payable_overpayment` | Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:50` |
| `1702RT.2018-01-ENCS.input.add_surcharge_interest_and_compromise` | Add: Surcharge, Interest and Compromise | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:51` |
| `1702RT.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:52` |
| `1702RT.2018-01-ENCS.input.refund` | Refund | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:58` |
| `1702RT.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:59` |
| `1702RT.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:60` |
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
| `1702MX.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/1702-mx.native:3` |
| `1702MX.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-mx.native:4` |
| `1702MX.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/1702-mx.native:5` |
| `1702MX.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/1702-mx.native:6` |
| `1702MX.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/1702-mx.native:7` |
| `1702MX.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:8` |
| `1702MX.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:9` |
| `1702MX.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | filer | text | unbound_input | `src/pages/forms/1702-mx.native:10` |
| `1702MX.2018-01-ENCS.input.special_preferential_rate_basis` | Special / Preferential Rate Basis | profile | special_rate_basis | optional | filer | text | unbound_input | `src/pages/forms/1702-mx.native:11` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_regular_rate` | Gross Income Subject to Regular Rate | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:17` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_special_rate` | Gross Income Subject to Special Rate | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:18` |
| `1702MX.2018-01-ENCS.input.special_preferential_tax_rate` | Special / Preferential Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-mx.native:19` |
| `1702MX.2018-01-ENCS.input.schedule_2_regular_rate_tax_due` | Schedule 2 Regular-Rate Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:20` |
| `1702MX.2018-01-ENCS.input.schedule_2_special_rate_tax_due` | Schedule 2 Special-Rate Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:21` |
| `1702MX.2018-01-ENCS.input.schedule_3_total_tax_credits` | Schedule 3 Total Tax Credits | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:22` |
| `1702MX.2018-01-ENCS.input.income_tax_at_regular_rate` | Income Tax at Regular Rate | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:28` |
| `1702MX.2018-01-ENCS.input.income_tax_at_special_rate` | Income Tax at Special Rate | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:29` |
| `1702MX.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:30` |
| `1702MX.2018-01-ENCS.input.total_tax_credits_payments` | Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:31` |
| `1702MX.2018-01-ENCS.input.net_tax_payable_overpayment` | Net Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:32` |
| `1702MX.2018-01-ENCS.input.surcharge` | Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:38` |
| `1702MX.2018-01-ENCS.input.interest` | Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:39` |
| `1702MX.2018-01-ENCS.input.compromise` | Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:40` |
| `1702MX.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:41` |
| `1702MX.2018-01-ENCS.input.refund` | Refund | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:47` |
| `1702MX.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | evidence | money | unbound_input | `src/pages/forms/1702-mx.native:48` |
| `1702MX.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:49` |
| `1702MX.2018-01-ENCS.input.attachment_description` | Attachment Description | external | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:55` |
| `1702MX.2018-01-ENCS.input.attachment_reference` | Attachment Reference | external | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:56` |
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
| `2550Q.2024-04-ENCS.input.year_end_month` | Year-end month | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/2550q.native:3` |
| `2550Q.2024-04-ENCS.input.taxable_year_raw` | Taxable year (raw) | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/2550q.native:4` |
| `2550Q.2024-04-ENCS.input.return_period_from` | Return Period From | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:5` |
| `2550Q.2024-04-ENCS.input.return_period_to` | Return Period To | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:6` |
| `2550Q.2024-04-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:7` |
| `2550Q.2024-04-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:8` |
| `2550Q.2024-04-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/2550q.native:9` |
| `2550Q.2024-04-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/2550q.native:10` |
| `2550Q.2024-04-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/2550q.native:11` |
| `2550Q.2024-04-ENCS.input.vatable_sales_receipts` | 31A Vatable Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:17` |
| `2550Q.2024-04-ENCS.input.output_tax_due` | 31B Output Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:18` |
| `2550Q.2024-04-ENCS.input.zero_rated_sales_receipts` | 32A Zero-Rated Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:19` |
| `2550Q.2024-04-ENCS.input.exempt_sales_receipts` | 33A Exempt Sales / Receipts | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:20` |
| `2550Q.2024-04-ENCS.input.output_vat_adjustments` | Output VAT Adjustments | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:21` |
| `2550Q.2024-04-ENCS.input.total_output_tax_due` | Total Output Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:22` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_input_tax` | 44 Domestic Purchases / Input Tax | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:28` |
| `2550Q.2024-04-ENCS.input.services_rendered_by_non_residents` | 45 Services Rendered by Non-Residents | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:29` |
| `2550Q.2024-04-ENCS.input.importation_of_goods` | 46 Importation of Goods | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:30` |
| `2550Q.2024-04-ENCS.input.other_purchases` | 47 Other Purchases | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:31` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_without_input_tax` | 48 Domestic Purchases Without Input Tax | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:32` |
| `2550Q.2024-04-ENCS.input.exempt_importations` | 49 Exempt Importations | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:33` |
| `2550Q.2024-04-ENCS.input.input_tax_directly_attributable_to_exempt_sales` | Input Tax Directly Attributable to Exempt Sales | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:39` |
| `2550Q.2024-04-ENCS.input.input_tax_not_directly_attributable` | Input Tax Not Directly Attributable | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:40` |
| `2550Q.2024-04-ENCS.input.ratable_input_tax_to_exempt_sales` | Ratable Input Tax to Exempt Sales | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:41` |
| `2550Q.2024-04-ENCS.input.prior_return_payment` | Prior Return Payment | external | — | — | evidence | money | unbound_input | `src/pages/forms/2550q.native:47` |
| `2550Q.2024-04-ENCS.input.other_tax_credit_payment` | Other Tax Credit / Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:48` |
| `2550Q.2024-04-ENCS.input.net_vat_payable_overpayment` | Net VAT Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:49` |
| `2550Q.2024-04-ENCS.input.surcharge` | Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:50` |
| `2550Q.2024-04-ENCS.input.interest` | Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:51` |
| `2550Q.2024-04-ENCS.input.compromise` | Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:52` |
| `2550Q.2024-04-ENCS.input.taxpayer_authorized_representative` | Taxpayer / Authorized Representative | transaction | — | — | preparer | text | unbound_input | `src/pages/forms/2550q.native:58` |
| `2550Q.2024-04-ENCS.input.payment_method` | Payment Method | transaction | — | — | payment | choice | unbound_input | `src/pages/forms/2550q.native:59` |
| `2550Q.2024-04-ENCS.input.payment_reference` | Payment Reference | external | — | — | payment | text | unbound_input | `src/pages/forms/2550q.native:60` |
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
| `2551Q.2018-01-ENCS.input.taxable_quarter` | Taxable Quarter | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/2551q.native:31` |
| `2551Q.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | filing | year | unbound_input | `src/pages/forms/2551q.native:32` |
| `2551Q.2018-01-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | filing | integer | unbound_input | `src/pages/forms/2551q.native:35` |
| `2551Q.2018-01-ENCS.input.return_options` | Return Options | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:41` |
| `2551Q.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:42` |
| `2551Q.2018-01-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:45` |
| `2551Q.2018-01-ENCS.input.tax_relief_specification` | 12A Tax Relief Specification | transaction | — | — | filing | text | unbound_input | `src/pages/forms/2551q.native:65` |
| `2551Q.2018-01-ENCS.input.income_tax_rate_election` | 13 Income-tax-rate election | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:73` |
| `2551Q.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/2551q.native:96` |
| `2551Q.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/2551q.native:97` |
| `2551Q.2018-01-ENCS.input.taxpayers_name` | Taxpayer's Name | profile | taxpayer_name | required | filer | text | unbound_input | `src/pages/forms/2551q.native:98` |
| `2551Q.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | filer | text | unbound_input | `src/pages/forms/2551q.native:101` |
| `2551Q.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | filer | postal_code | unbound_input | `src/pages/forms/2551q.native:105` |
| `2551Q.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | filer | phone | unbound_input | `src/pages/forms/2551q.native:109` |
| `2551Q.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | filer | email | unbound_input | `src/pages/forms/2551q.native:113` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_code` | Schedule 1 Line 1 Percentage-tax Code | transaction | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:134` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_tax_base_taxable_amount` | Schedule 1 Line 1 Tax Base / Taxable Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:142` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_policy_supplied_tax_rate` | Schedule 1 Line 1 Policy-supplied Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:150` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_due` | Schedule 1 Line 1 Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:156` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_code` | Schedule 1 Line 2 Percentage-tax Code | transaction | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:159` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_tax_base_taxable_amount` | Schedule 1 Line 2 Tax Base / Taxable Amount | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:167` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_policy_supplied_tax_rate` | Schedule 1 Line 2 Policy-supplied Tax Rate | external | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:175` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_due` | Schedule 1 Line 2 Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:181` |
| `2551Q.2018-01-ENCS.input.total_percentage_tax_due` | 14 Total Percentage Tax Due | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:188` |
| `2551Q.2018-01-ENCS.input.creditable_percentage_tax_withheld` | 15 Creditable Percentage Tax Withheld | external | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:191` |
| `2551Q.2018-01-ENCS.input.tax_paid_in_previous_return` | 16 Tax Paid in Previous Return | external | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:199` |
| `2551Q.2018-01-ENCS.input.other_tax_credit_payment` | 17 Other Tax Credit / Payment | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:207` |
| `2551Q.2018-01-ENCS.input.total_tax_credits_payments` | 18 Total Tax Credits / Payments | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:213` |
| `2551Q.2018-01-ENCS.input.tax_payable_overpayment` | 19 Tax Payable / (Overpayment) | derived | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:214` |
| `2551Q.2018-01-ENCS.input.surcharge_manual` | 20 Surcharge (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:217` |
| `2551Q.2018-01-ENCS.input.interest_manual` | 21 Interest (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:225` |
| `2551Q.2018-01-ENCS.input.compromise_manual` | 22 Compromise (manual) | transaction | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:233` |
| `2551Q.2018-01-ENCS.input.overpayment_disposition` | 24 Overpayment Disposition | transaction | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:241` |
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
| `0619E.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-e.native:3` |
| `0619E.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:4` |
| `0619E.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:5` |
| `0619E.2018-01-ENCS.input.atc` | 5 ATC | profile | atc | required | filer | atc_code | unbound_input | `src/pages/forms/0619-e.native:6` |
| `0619E.2018-01-ENCS.input.tax_type_code` | 6 Tax Type Code | profile | tax_type | required | filer | choice | unbound_input | `src/pages/forms/0619-e.native:7` |
| `0619E.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | filing | date | unbound_input | `src/pages/forms/0619-e.native:8` |
| `0619E.2018-01-ENCS.input.tin` | TIN | profile | tin | required | filer | tin | unbound_input | `src/pages/forms/0619-e.native:9` |
| `0619E.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | filer | rdo_code | unbound_input | `src/pages/forms/0619-e.native:10` |
| `0619E.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | profile | government_withholding_agent | required | filer | boolean | unbound_input | `src/pages/forms/0619-e.native:11` |
| `0619E.2018-01-ENCS.input.amount_of_remittance` | 14 Amount of Remittance | transaction | — | — | filing | money | unbound_input | `src/pages/forms/0619-e.native:17` |
| `0619E.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 15 Less: Amount Remitted from Previously Filed Form | external | — | — | evidence | money | unbound_input | `src/pages/forms/0619-e.native:18` |
| `0619E.2018-01-ENCS.input.net_amount_of_remittance_14_15` | 16 Net Amount of Remittance (14 - 15) | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:19` |
| `0619E.2018-01-ENCS.input.surcharge` | 17A Surcharge | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:20` |
| `0619E.2018-01-ENCS.input.interest` | 17B Interest | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:21` |
| `0619E.2018-01-ENCS.input.compromise` | 17C Compromise | derived | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:22` |
| `0619E.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | preparer | text | unbound_input | `src/pages/forms/0619-e.native:28` |
| `0619E.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:29` |
| `0619E.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:30` |
| `0619E.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | payment | choice | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | payment | money | static_table | `src/pages/forms/0619-e.native (table schema)` |
