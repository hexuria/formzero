# Form field catalog

<!-- GENERATED FILE - DO NOT EDIT. Run `npm run generate:tax-catalog`. -->

This catalog is the checked boundary between the 51-code calendar registry,
the 10 exact Native editor revisions currently present, and future profile
projection/domain work. `calendar_only` means that no editor field contract
exists yet; it does not imply filing support.

## Coverage

- Registry codes: 51
- Native editor revisions: 11
- Calendar-only codes: 40
- Native input controls inventoried: 399
- Meaningful static-table fields inventoried: 63
- Direct profile projection targets: 99
- Optional profile projection targets: 35
- Visible taxpayer-year setting targets: 1
- Taxpayer-year consumer forms: 2
- Declared taxpayer-year setting consumptions: 4
- Fixed form-policy targets: 4
- Nonempty Tax Form Profile setup contracts: 4
- Explicit `no_setup` editor contracts: 7
- Tax Form Profile semantic values: 4
- Evidence-required (unsupported) setup values: 0

| Code | Title | Tax category | Revision | Status | Tax Form Profile | Taxpayer-year settings | Cadence | Periods | Inputs | Table fields | Source |
|---|---|---|---|---|---|---|---|---|---:|---:|---|
| 0605 | Payment Form | payment | 1999-07-ENCS | static_layout | no_setup | — | on_demand | — | 20 | 4 | src/pages/forms/0605.native |
| 1905 | Application for Registration Information Update / Correction / Cancellation | registration | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 1600 | Monthly Remittance Return of VAT and Other Percentage Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1600PT | Monthly Remittance Return of Other Percentage Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1600VT | Monthly Remittance Return of Value-Added Tax Withheld | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1600WP | Remittance Return of Percentage Tax on Winnings and Prizes | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1601C | Monthly Remittance Return of Income Taxes Withheld on Compensation | withholding_tax | 2018-01-ENCS | static_layout | no_setup | — | monthly | 1-12 | 30 | 7 | src/pages/forms/1601-c.native |
| 1601E | Monthly Remittance Return of Creditable Income Taxes Withheld (Expanded) | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1601F | Monthly Remittance Return of Final Income Tax Withheld | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 0619F | Monthly Remittance Form for Final Income Taxes Withheld | withholding_tax | 2018-01-ENCS | static_layout | no_setup | — | monthly | 1-12 | 25 | 4 | src/pages/forms/0619-f.native |
| 1601FQ | Quarterly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | quarterly | 1-4 | 0 | 0 | — |
| 1602 | Monthly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 1602Q | Quarterly Remittance Return of Final Taxes Withheld on Interest Paid on Deposits and Yield on Deposit Substitutes / Trusts / Etc. | withholding_tax | — | calendar_only | calendar_only | — | quarterly | 1-4 | 0 | 0 | — |
| 1603 | Quarterly Remittance Return of Final Income Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | quarterly | 1-4 | 0 | 0 | — |
| 1603Q | Quarterly Remittance Return of Final Income Taxes Withheld on Fringe Benefits Paid to Employees Other Than Rank and File | withholding_tax | — | calendar_only | calendar_only | — | quarterly | 1-4 | 0 | 0 | — |
| 1604CF | Annual Information Return of Income Taxes Withheld on Compensation | withholding_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1604E | Annual Information Return of Creditable Income Taxes Withheld | withholding_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 0620 | Monthly Remittance Form of Tax Withheld on the Amount Withdrawn from the Decedent's Deposit Account | withholding_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2316 | Certificate of Compensation Payment / Tax Withheld | withholding_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1700 | Annual Income Tax Return (Purely Compensation) | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1701Q | Quarterly Income Tax Return for Individuals, Estates and Trusts | income_tax | 2018-01-ENCS | static_layout | setup | `income_tax_rate_election`, `deduction_method` | quarterly | 1-3 | 37 | 4 | src/pages/forms/1701q.native |
| 1701 | Annual Income Tax Return for Individuals, Estates and Trusts | income_tax | 2018-01-ENCS | static_layout | setup | `income_tax_rate_election`, `deduction_method` | annual | — | 49 | 15 | src/pages/forms/1701.native |
| 1701A | Annual Income Tax Return (8% / OSD) | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1702Q | Quarterly Income Tax Return for Corporations, Partnerships and Cooperatives | income_tax | — | calendar_only | calendar_only | — | quarterly | 1-4 | 0 | 0 | — |
| 1702 | Annual Income Tax Return for Corporations, Partnerships and Cooperatives | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1702RT | Annual Income Tax Return — Regular Taxable | income_tax | 2018-01-ENCS | static_layout | no_setup | — | annual | — | 36 | 3 | src/pages/forms/1702-rt.native |
| 1702EX | Annual Income Tax Return — Tax-Exempt | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1702MX | Annual Income Tax Return — Mixed Income | income_tax | 2018-01-ENCS | static_layout | setup | — | annual | — | 32 | 5 | src/pages/forms/1702-mx.native |
| 1704 | Improperly Accumulated Earnings Tax Return | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 2550M | Monthly Value-Added Tax Declaration | value_added_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2550Q | Quarterly Value-Added Tax Return | value_added_tax | 2024-04-ENCS | static_layout | no_setup | — | quarterly | 1-4 | 38 | 13 | src/pages/forms/2550q.native |
| 2551Q | Quarterly Percentage Tax Return | percentage_tax | 2018-01-ENCS | static_layout | setup | — | quarterly | 1-4 | 35 | 4 | src/pages/forms/2551q.native |
| 2551M | Monthly Percentage Tax Return | percentage_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2552 | Percentage Tax Return on Transactions Involving Shares of Stock | percentage_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 2553 | Percentage Tax Payable Under Special Laws | percentage_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 2000 | Documentary Stamp Tax Declaration/Return | documentary_stamp_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 2000OT | Documentary Stamp Tax Declaration/Return (One-Time Transactions) | documentary_stamp_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 2200A | Excise Tax Return for Alcohol Products | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200AN | Excise Tax Return for Automobiles and Non-Essential Goods | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200M | Excise Tax Return for Mineral Products | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200P | Excise Tax Return for Petroleum Products | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200T | Excise Tax Return for Tobacco Products | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200C | Excise Tax Return for Coal and Coke | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 2200S | Excise Tax Return for Sweetened Beverages | excise_tax | — | calendar_only | calendar_only | — | monthly | 1-12 | 0 | 0 | — |
| 0619E | Monthly Remittance Form for Creditable Income Taxes Withheld (Expanded) | withholding_tax | 2018-01-ENCS | static_layout | no_setup | — | monthly | 1-12 | 24 | 4 | src/pages/forms/0619-e.native |
| 1601EQ | Quarterly Remittance Return of Creditable Income Taxes Withheld (Expanded) | withholding_tax | 2018-01-ENCS | static_layout | no_setup | — | quarterly | 1-4 | 73 | 0 | src/pages/forms/1601-eq.native |
| 1701MS | Annual Income Tax Return for Micro and Small Taxpayers | income_tax | — | calendar_only | calendar_only | — | annual | — | 0 | 0 | — |
| 1706 | Capital Gains Tax Return (Real Properties) | capital_gains_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 1707A | Annual Capital Gains Tax Return (Shares of Stock Not Traded) | capital_gains_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 1800 | Donor's Tax Return | estate_and_donors_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |
| 1801 | Estate Tax Return | estate_and_donors_tax | — | calendar_only | calendar_only | — | on_demand | — | 0 | 0 | — |

## Taxpayer-year consumer contracts

A form declares every shared taxpayer/year setting it consumes, including
settings with no visible control in the current Native editor. This contract
is separate from visible-field provenance and from Tax Form Profile setup.
Every form not listed below has an explicit empty consumer slice.

| Form revision | Consumed settings | Visible taxpayer-year targets |
|---|---|---:|
| 1701Q 2018-01-ENCS | `income_tax_rate_election`, `deduction_method` | 1 |
| 1701 2018-01-ENCS | `income_tax_rate_election`, `deduction_method` | 0 |

## Tax Form Profile setup contracts

Every Native editor has either a nonempty typed `setup` contract or an
explicit `no_setup` contract. The 41 `calendar_only` entries are explicitly
non-editable and have no setup values. `evidence_required` means the key is
known but unsupported: it cannot be edited or persisted until its gate is
resolved. Base profile facts, taxpayer-year settings, filing transactions,
schedules, amounts, payments, rates, elections, and calculated values are
not Tax Form Profile values.

The ownership vocabulary supports `binding_selection`, `yearly_value`, and
`transaction_default`. The current approved contracts contain only stable
binding selections. There are no approved form-specific yearly values or
transaction defaults; this is intentional rather than an inferred omission.

| Form revision | Mode | Spec revision | SHA-256 | Values | Supported | Evidence required | Contract evidence |
|---|---|---:|---|---:|---:|---:|---|
| 0605 1999-07-ENCS | no_setup | 1 | `5cd3dcbfa7e9acfc43abb2f03a86248c25a199eaa22c11ad734b6a831f36bfe6` | 0 | 0 | 0 | Ownership matrix § 0605; legacy form_0605.rs:480-507 leaves ATC/tax type filing-owned |
| 1601C 2018-01-ENCS | no_setup | 1 | `e48344b54c5296b7cbfde0570ccbf1a668177e1cabeb8e887c2f5d1fee9ac4f4` | 0 | 0 | 0 | Line of business is inherited from the Base Tax Profile; 1601C has no form-specific yearly setup |
| 0619F 2018-01-ENCS | no_setup | 1 | `4a7e25ef886f788600c5c19ba5aab37b05129c234b87a39967523e09bc2a95ba` | 0 | 0 | 0 | Line of business is inherited from the Base Tax Profile; 0619F has no form-specific yearly setup |
| 1701Q 2018-01-ENCS | setup | 2 | `f91af79d1e9978084a1ec98e6a249f70a88439ac36de409f5ec926c64fe16440` | 1 | 1 | 0 | Ownership matrix § 1701Q |
| 1701 2018-01-ENCS | setup | 2 | `18e080aab881f659587a3e50d34723ca4b8571d33593e529ccb0661cda6e3095` | 1 | 1 | 0 | Ownership matrix § 1701 |
| 1702RT 2018-01-ENCS | no_setup | 1 | `7dc726162bab90d4909f876daaa6f93d02bb3fe64b22f78a86b9aebc26ba66f2` | 0 | 0 | 0 | Line of business is inherited from the Base Tax Profile; 1702RT has no form-specific yearly setup |
| 1702MX 2018-01-ENCS | setup | 1 | `61478774c6335ea70c77bada3537cc9bafe1963d7805d38a58f7ce49ed3f46e7` | 1 | 1 | 0 | Ownership matrix § 1702MX |
| 2550Q 2024-04-ENCS | no_setup | 1 | `49363b23a0fd60148850df5a6f3b162b907e95840efc80af3c7a60700e3ab7f6` | 0 | 0 | 0 | Ownership matrix § 2550Q finds no genuine form-specific annual setup value |
| 2551Q 2018-01-ENCS | setup | 2 | `7f3df1b82f7d72e8e9b29ff01e10b086e0a6b1a1d4702861cd9f8d175f62cef4` | 1 | 1 | 0 | 2551Q January 2018 ENCS Item 13 is a form-specific yearly choice projected only on the initial applicable quarter |
| 0619E 2018-01-ENCS | no_setup | 1 | `0bbca08d13a26690fb24c819c36c4c83aafe1e150ee6b4aef10fd4bce16d3579` | 0 | 0 | 0 | Line of business is inherited from the Base Tax Profile; 0619E has no form-specific yearly setup |
| 1601EQ 2018-01-ENCS | no_setup | 1 | `00da4f31d7e8646a51315909b4eadf20feaf1bd8b7d8127158bf0475bed3be1a` | 0 | 0 | 0 | Identity, filing choices, unbound ATC rows, remittance totals including items 22-24 and over-remittance marks, payment rows, and tax-agent fields; save stays disabled until an exact 1601EQ path exists |

| Form revision | Semantic key | Value type | Role | Presence | Validation | Ownership | Source kind | Availability | Source evidence | Blocking evidence gate |
|---|---|---|---|---|---|---|---|---|---|---|
| 1701Q 2018-01-ENCS | `spouse_profile_id` | profile_id | spouse | optional | distinct_profile_role | binding_selection | named_profile_role | supported | src/pages/forms/1701q.native:113-127 declares the optional distinct spouse role | — |
| 1701 2018-01-ENCS | `spouse_profile_id` | profile_id | spouse | optional | distinct_profile_role | binding_selection | named_profile_role | supported | src/pages/forms/1701.native:21-23 declares the optional distinct spouse role | — |
| 1702MX 2018-01-ENCS | `special_rate_basis` | text | filer | conditional | nonempty_text | yearly_value | user_entry | supported | src/pages/forms/1702-mx.native:11 records an optional form-specific special/preferential-rate basis | — |
| 2551Q 2018-01-ENCS | `income_tax_rate_election` | choice | filer | required | catalog_choice | yearly_value | user_entry | supported | 2551Q January 2018 ENCS Item 13 asks the taxpayer to select graduated or 8% income tax rates | — |

## Classification

Every Native input is joined to exact stable-ID metadata declared in
`scripts/tax-catalog/catalog.ts`; labels and placeholders are not used to
infer ownership, role, value type, or profile projection.

- `profile`: reusable taxpayer facts projected through a named `filer` or `spouse` role.
- `taxpayer_year`: a shared taxpayer/year setting consumed read-only by a filing.
- `form_policy`: a locked constant for the exact form revision, never editable profile data.
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
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `0605.1999-07-ENCS.input.tin` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `0605.1999-07-ENCS.input.rdo_code` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `line_of_business` | `0605.1999-07-ENCS.input.line_of_business_occupation` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `0605.1999-07-ENCS.input.taxpayer_name` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `registered_address` | `0605.1999-07-ENCS.input.registered_address` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `0605.1999-07-ENCS.input.zip_code` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `contact_number` | `0605.1999-07-ENCS.input.contact_number` |
| 0605 1999-07-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `0605.1999-07-ENCS.input.email_address` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `1601C.2018-01-ENCS.input.tin` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `1601C.2018-01-ENCS.input.rdo_code` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `1601C.2018-01-ENCS.input.taxpayer_name` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `registered_address` | `1601C.2018-01-ENCS.input.registered_address` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `1601C.2018-01-ENCS.input.zip_code` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `line_of_business` | `1601C.2018-01-ENCS.input.line_of_business` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `contact_number` | `1601C.2018-01-ENCS.input.contact_number` |
| 1601C 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `1601C.2018-01-ENCS.input.email_address` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `0619F.2018-01-ENCS.input.tin` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `0619F.2018-01-ENCS.input.rdo_code` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `0619F.2018-01-ENCS.input.registered_taxpayer_name` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `line_of_business` | `0619F.2018-01-ENCS.input.line_of_business` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `registered_address` | `0619F.2018-01-ENCS.input.registered_address` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `0619F.2018-01-ENCS.input.zip_code` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `contact_number` | `0619F.2018-01-ENCS.input.contact_number` |
| 0619F 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `0619F.2018-01-ENCS.input.email_address` |
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
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `tin` | `1702RT.2018-01-ENCS.input.tin` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `rdo_code` | `1702RT.2018-01-ENCS.input.rdo_code` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `registered_name` | `1702RT.2018-01-ENCS.input.registered_name` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `registered_address` | `1702RT.2018-01-ENCS.input.registered_address` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `zip_code` | `1702RT.2018-01-ENCS.input.zip_code` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `contact_number` | `1702RT.2018-01-ENCS.input.contact_number` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `email_address` | `1702RT.2018-01-ENCS.input.email_address` |
| 1702RT 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `line_of_business` | `1702RT.2018-01-ENCS.input.line_of_business` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `tin` | `1702MX.2018-01-ENCS.input.tin` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `rdo_code` | `1702MX.2018-01-ENCS.input.rdo_code` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `registered_name` | `1702MX.2018-01-ENCS.input.registered_name` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `registered_address` | `1702MX.2018-01-ENCS.input.registered_address` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `zip_code` | `1702MX.2018-01-ENCS.input.zip_code` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `contact_number` | `1702MX.2018-01-ENCS.input.contact_number` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | optional | `email_address` | `1702MX.2018-01-ENCS.input.email_address` |
| 1702MX 2018-01-ENCS | filer | exactly_one | corporation, partnership, cooperative, other_legal_entity | required | `line_of_business` | `1702MX.2018-01-ENCS.input.line_of_business` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `2550Q.2024-04-ENCS.input.tin` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `2550Q.2024-04-ENCS.input.rdo_code` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `2550Q.2024-04-ENCS.input.taxpayer_name` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `registered_address` | `2550Q.2024-04-ENCS.input.registered_address` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `2550Q.2024-04-ENCS.input.zip_code` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `contact_number` | `2550Q.2024-04-ENCS.input.contact_number` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `2550Q.2024-04-ENCS.input.email_address` |
| 2550Q 2024-04-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `eopt_tier` | `2550Q.2024-04-ENCS.input.eopt_taxpayer_classification` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `accounting_period_basis` | `2551Q.2018-01-ENCS.input.taxable_period_basis` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `2551Q.2018-01-ENCS.input.tin` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `2551Q.2018-01-ENCS.input.rdo_code` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `2551Q.2018-01-ENCS.input.taxpayers_name` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `registered_address` | `2551Q.2018-01-ENCS.input.registered_address` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `zip_code` | `2551Q.2018-01-ENCS.input.zip_code` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `contact_number` | `2551Q.2018-01-ENCS.input.contact_number` |
| 2551Q 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `email_address` | `2551Q.2018-01-ENCS.input.email_address` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `0619E.2018-01-ENCS.input.tin` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `0619E.2018-01-ENCS.input.rdo_code` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `0619E.2018-01-ENCS.input.registered_taxpayer_name` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `line_of_business` | `0619E.2018-01-ENCS.input.line_of_business` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `registered_address` | `0619E.2018-01-ENCS.input.registered_address` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `0619E.2018-01-ENCS.input.zip_code` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `contact_number` | `0619E.2018-01-ENCS.input.contact_number` |
| 0619E 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `0619E.2018-01-ENCS.input.email_address` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `tin` | `1601EQ.2018-01-ENCS.input.tin` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `rdo_code` | `1601EQ.2018-01-ENCS.input.rdo_code` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `taxpayer_name` | `1601EQ.2018-01-ENCS.input.taxpayer_name` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `registered_address` | `1601EQ.2018-01-ENCS.input.registered_address` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `zip_code` | `1601EQ.2018-01-ENCS.input.zip_code` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `line_of_business` | `1601EQ.2018-01-ENCS.input.line_of_business` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | required | `contact_number` | `1601EQ.2018-01-ENCS.input.contact_number` |
| 1601EQ 2018-01-ENCS | filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity | optional | `email_address` | `1601EQ.2018-01-ENCS.input.email_address` |

## 0605 — 1999-07-ENCS

Source: `src/pages/forms/0605.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `5cd3dcbfa7e9acfc43abb2f03a86248c25a199eaa22c11ad734b6a831f36bfe6`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `0605.1999-07-ENCS.input.year_ended_month_independent` | 2 Year Ended month (independent) | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/0605.native:3` |
| `0605.1999-07-ENCS.input.due_date_mm_dd_yyyy` | 4 Due Date (MM/DD/YYYY) | filing_context | — | — | — | — | filing | date | unbound_input | `src/pages/forms/0605.native:4` |
| `0605.1999-07-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/0605.native:5` |
| `0605.1999-07-ENCS.input.atc_only_source_proven_pairs` | 6 ATC - only source-proven pairs | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/0605.native:6` |
| `0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs` | 8 Tax Type - only source-proven pairs | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/0605.native:7` |
| `0605.1999-07-ENCS.input.manner_of_payment` | 17 Manner of Payment | transaction | — | — | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:8` |
| `0605.1999-07-ENCS.input.tin` | 9 TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/0605.native:14` |
| `0605.1999-07-ENCS.input.rdo_code` | 10 RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/0605.native:15` |
| `0605.1999-07-ENCS.input.line_of_business_occupation` | 12 Line of Business / Occupation | profile | line_of_business | required | — | — | filer | text | unbound_input | `src/pages/forms/0605.native:16` |
| `0605.1999-07-ENCS.input.taxpayer_name` | 13 Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/0605.native:17` |
| `0605.1999-07-ENCS.input.registered_address` | 15 Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/0605.native:18` |
| `0605.1999-07-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/0605.native:19` |
| `0605.1999-07-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/0605.native:20` |
| `0605.1999-07-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/0605.native:21` |
| `0605.1999-07-ENCS.input.type_of_payment` | 18 Type of Payment | transaction | — | — | — | — | payment | choice | unbound_input | `src/pages/forms/0605.native:22` |
| `0605.1999-07-ENCS.input.basic_tax_deposit_advance_payment` | 19 Basic Tax / Deposit / Advance Payment | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:28` |
| `0605.1999-07-ENCS.input.surcharge_manual` | 20A Surcharge (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:29` |
| `0605.1999-07-ENCS.input.interest_manual` | 20B Interest (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:30` |
| `0605.1999-07-ENCS.input.compromise_manual` | 20C Compromise (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0605.native:31` |
| `0605.1999-07-ENCS.input.taxpayer_authorized_representative` | 22A Taxpayer / Authorized Representative | transaction | — | — | — | — | preparer | text | unbound_input | `src/pages/forms/0605.native:251` |
| `0605.1999-07-ENCS.table.payment.method` | Payment method | external | — | — | — | — | payment | choice | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | — | — | payment | text | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/0605.native (table schema)` |
| `0605.1999-07-ENCS.table.payment.amount` | Payment amount | external | — | — | — | — | payment | money | static_table | `src/pages/forms/0605.native (table schema)` |

## 1601C — 2018-01-ENCS

Source: `src/pages/forms/1601-c.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `e48344b54c5296b7cbfde0570ccbf1a668177e1cabeb8e887c2f5d1fee9ac4f4`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1601C.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1601-c.native:3` |
| `1601C.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1601-c.native:4` |
| `1601C.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-c.native:5` |
| `1601C.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-c.native:6` |
| `1601C.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/1601-c.native:7` |
| `1601C.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-c.native:8` |
| `1601C.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | — | — | filer | phone | unbound_input | `src/pages/forms/1601-c.native:9` |
| `1601C.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/1601-c.native:10` |
| `1601C.2018-01-ENCS.input.for_the_month_of` | For the Month of | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/1601-c.native:16` |
| `1601C.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:17` |
| `1601C.2018-01-ENCS.input.any_taxes_withheld` | Any Taxes Withheld? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-c.native:18` |
| `1601C.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1601-c.native:19` |
| `1601C.2018-01-ENCS.input.atc` | ATC | form_policy | — | — | form_policy.atc | WW010 | system | atc_code | unbound_input | `src/pages/forms/1601-c.native:20` |
| `1601C.2018-01-ENCS.input.tax_relief` | 13 Tax Relief | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1601-c.native:21` |
| `1601C.2018-01-ENCS.input.total_amount_of_compensation` | 14 Total Amount of Compensation | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:27` |
| `1601C.2018-01-ENCS.input.statutory_minimum_wage` | 15 Statutory Minimum Wage | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:28` |
| `1601C.2018-01-ENCS.input.holiday_overtime_and_night_shift_pay` | 16 Holiday, Overtime and Night Shift Pay | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:29` |
| `1601C.2018-01-ENCS.input.13th_month_pay_and_other_benefits` | 17 13th Month Pay and Other Benefits | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:30` |
| `1601C.2018-01-ENCS.input.de_minimis_benefits` | 18 De Minimis Benefits | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:31` |
| `1601C.2018-01-ENCS.input.sss_gsis_phic_and_pag_ibig_contributions` | 19 SSS, GSIS, PHIC and Pag-IBIG Contributions | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:32` |
| `1601C.2018-01-ENCS.input.other_non_taxable_compensation` | 20 Other Non-Taxable Compensation | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:33` |
| `1601C.2018-01-ENCS.input.total_non_taxable_exempt_compensation` | 21 Total Non-Taxable / Exempt Compensation | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:34` |
| `1601C.2018-01-ENCS.input.total_taxable_compensation` | 22 Total Taxable Compensation | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:35` |
| `1601C.2018-01-ENCS.input.tax_required_to_be_withheld` | 25 Tax Required to be Withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:36` |
| `1601C.2018-01-ENCS.input.schedule_adjustment` | 26 Schedule Adjustment | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-c.native:37` |
| `1601C.2018-01-ENCS.input.tax_still_due` | 31 Tax Still Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:38` |
| `1601C.2018-01-ENCS.input.surcharge` | 32 Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:44` |
| `1601C.2018-01-ENCS.input.interest` | 33 Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:45` |
| `1601C.2018-01-ENCS.input.compromise` | 34 Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:46` |
| `1601C.2018-01-ENCS.input.total_penalties` | 35 Total Penalties | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-c.native:47` |
| `1601C.2018-01-ENCS.table.prior_payment.period` | Previous-month period | external | — | — | — | — | evidence | tax_period | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.date_paid` | Previous payment date | external | — | — | — | — | payment | date | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.agency` | Previous payment agency | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.reference_number` | Previous payment reference | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.tax_paid` | Previous tax paid | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.tax_due` | Previous tax due | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1601-c.native (table schema)` |
| `1601C.2018-01-ENCS.table.prior_payment.adjustment` | Previous-payment adjustment | derived | — | — | — | — | system | money | derived_display | `src/pages/forms/1601-c.native (table schema)` |

## 0619F — 2018-01-ENCS

Source: `src/pages/forms/0619-f.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `4a7e25ef886f788600c5c19ba5aab37b05129c234b87a39967523e09bc2a95ba`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `0619F.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-f.native:3` |
| `0619F.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:4` |
| `0619F.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:5` |
| `0619F.2018-01-ENCS.input.tax_type_code` | Tax Type Code | form_policy | — | — | form_policy.tax_type | WB | system | choice | unbound_input | `src/pages/forms/0619-f.native:6` |
| `0619F.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | — | — | filing | date | unbound_input | `src/pages/forms/0619-f.native:7` |
| `0619F.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-f.native:8` |
| `0619F.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/0619-f.native:9` |
| `0619F.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/0619-f.native:10` |
| `0619F.2018-01-ENCS.input.registered_taxpayer_name` | Registered Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/0619-f.native:11` |
| `0619F.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | optional | — | — | filer | text | unbound_input | `src/pages/forms/0619-f.native:12` |
| `0619F.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | optional | — | — | filer | text | unbound_input | `src/pages/forms/0619-f.native:13` |
| `0619F.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/0619-f.native:14` |
| `0619F.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/0619-f.native:15` |
| `0619F.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/0619-f.native:16` |
| `0619F.2018-01-ENCS.input.final_tax_withheld_on_interest_deposits_and_trusts` | 13 Final tax withheld on interest, deposits and trusts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:22` |
| `0619F.2018-01-ENCS.input.other_final_income_taxes_withheld` | 14 Other final income taxes withheld | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0619-f.native:23` |
| `0619F.2018-01-ENCS.input.total_final_income_taxes_withheld` | 15 Total final income taxes withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:24` |
| `0619F.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 16 Less: Amount Remitted from Previously Filed Form | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/0619-f.native:25` |
| `0619F.2018-01-ENCS.input.net_amount_of_remittance` | 17 Net Amount of Remittance | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:26` |
| `0619F.2018-01-ENCS.input.surcharge` | 18A Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:27` |
| `0619F.2018-01-ENCS.input.interest` | 18B Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:28` |
| `0619F.2018-01-ENCS.input.compromise` | 18C Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-f.native:29` |
| `0619F.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | — | — | preparer | text | unbound_input | `src/pages/forms/0619-f.native:35` |
| `0619F.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:36` |
| `0619F.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/0619-f.native:37` |
| `0619F.2018-01-ENCS.table.payment.item_reference` | Payment item reference | filing_context | — | — | — | — | filing | text | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | — | — | payment | choice | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/0619-f.native (table schema)` |
| `0619F.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | — | — | payment | money | static_table | `src/pages/forms/0619-f.native (table schema)` |

## 1701Q — 2018-01-ENCS

Source: `src/pages/forms/1701q.native`

Tax Form Profile: `setup`, spec revision 2, SHA-256 `f91af79d1e9978084a1ec98e6a249f70a88439ac36de409f5ec926c64fe16440`

Consumed taxpayer-year settings: `income_tax_rate_election`, `deduction_method`

Named roles: `filer`, `spouse`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, estate, trust |
| spouse | zero_or_one | individual, sole_proprietor |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1701Q.2018-01-ENCS.input.taxable_year` | 1 Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/1701q.native:5` |
| `1701Q.2018-01-ENCS.input.quarter` | 2 Quarter | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/1701q.native:9` |
| `1701Q.2018-01-ENCS.input.amended_return` | 3 Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1701q.native:36` |
| `1701Q.2018-01-ENCS.input.number_of_sheets_attached` | 4 Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1701q.native:40` |
| `1701Q.2018-01-ENCS.input.tin` | 5 TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1701q.native:53` |
| `1701Q.2018-01-ENCS.input.rdo_code` | 6 RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1701q.native:57` |
| `1701Q.2018-01-ENCS.input.taxpayer_filer_name` | 7 Taxpayer / Filer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1701q.native:61` |
| `1701Q.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1701q.native:65` |
| `1701Q.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | — | — | filer | postal_code | unbound_input | `src/pages/forms/1701q.native:68` |
| `1701Q.2018-01-ENCS.input.date_of_birth` | Date of Birth | profile | date_of_birth | optional | — | — | filer | date | unbound_input | `src/pages/forms/1701q.native:72` |
| `1701Q.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | — | — | filer | email | unbound_input | `src/pages/forms/1701q.native:76` |
| `1701Q.2018-01-ENCS.input.citizenship` | Citizenship | profile | citizenship | optional | — | — | filer | text | unbound_input | `src/pages/forms/1701q.native:80` |
| `1701Q.2018-01-ENCS.input.foreign_tax_number` | Foreign Tax Number | profile | foreign_tax_number | optional | — | — | filer | tax_identifier | unbound_input | `src/pages/forms/1701q.native:84` |
| `1701Q.2018-01-ENCS.input.income_tax_rate_election` | Income-tax-rate election | taxpayer_year | — | — | income_tax_rate_election | — | filing | choice | unbound_input | `src/pages/forms/1701q.native:88` |
| `1701Q.2018-01-ENCS.input.spouse_tin` | Spouse TIN | profile | tin | required | — | — | spouse | tin | unbound_input | `src/pages/forms/1701q.native:113` |
| `1701Q.2018-01-ENCS.input.spouse_rdo_code` | Spouse RDO Code | profile | rdo_code | required | — | — | spouse | rdo_code | unbound_input | `src/pages/forms/1701q.native:117` |
| `1701Q.2018-01-ENCS.input.spouse_name` | Spouse Name | profile | taxpayer_name | required | — | — | spouse | text | unbound_input | `src/pages/forms/1701q.native:121` |
| `1701Q.2018-01-ENCS.input.spouse_citizenship` | Spouse Citizenship | profile | citizenship | optional | — | — | spouse | text | unbound_input | `src/pages/forms/1701q.native:124` |
| `1701Q.2018-01-ENCS.input.spouse_foreign_tax_number` | Spouse Foreign Tax Number | profile | foreign_tax_number | optional | — | — | spouse | tax_identifier | unbound_input | `src/pages/forms/1701q.native:127` |
| `1701Q.2018-01-ENCS.input.sales_revenues_receipts` | Sales / Revenues / Receipts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:136` |
| `1701Q.2018-01-ENCS.input.cost_of_sales_services` | Cost of Sales / Services | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:144` |
| `1701Q.2018-01-ENCS.input.allowable_deductions` | Allowable Deductions | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:152` |
| `1701Q.2018-01-ENCS.input.taxable_income_external_policy_result` | Taxable Income (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:160` |
| `1701Q.2018-01-ENCS.input.income_tax_due_external_policy_result` | Income Tax Due (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:168` |
| `1701Q.2018-01-ENCS.input.gross_sales_receipts` | Gross Sales / Receipts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:181` |
| `1701Q.2018-01-ENCS.input.less_non_operating_income` | Less: Non-Operating Income | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:189` |
| `1701Q.2018-01-ENCS.input.tax_due_at_8_percent_external_policy_result` | Tax Due at 8 percent (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:197` |
| `1701Q.2018-01-ENCS.input.prior_quarter_income_tax_payments` | Prior-quarter income tax payments | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701q.native:210` |
| `1701Q.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307` | Creditable tax withheld (BIR Form 2307) | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701q.native:218` |
| `1701Q.2018-01-ENCS.input.other_tax_credits_payments` | Other Tax Credits / Payments | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:226` |
| `1701Q.2018-01-ENCS.input.tax_payable_overpayment_external_policy_result` | 63 Tax Payable / (Overpayment) (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:239` |
| `1701Q.2018-01-ENCS.input.surcharge_external_policy_result` | 64 Surcharge (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:247` |
| `1701Q.2018-01-ENCS.input.interest_external_policy_result` | 65 Interest (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:255` |
| `1701Q.2018-01-ENCS.input.compromise_external_policy_result` | 66 Compromise (external policy result) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701q.native:263` |
| `1701Q.2018-01-ENCS.input.bank_agency` | Bank / Agency | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1701q.native:367` |
| `1701Q.2018-01-ENCS.input.reference` | Reference | external | — | — | — | — | evidence | text | unbound_input | `src/pages/forms/1701q.native:375` |
| `1701Q.2018-01-ENCS.input.amount` | Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701q.native:383` |
| `1701Q.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | — | — | payment | choice | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1701q.native (table schema)` |
| `1701Q.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | — | — | payment | money | static_table | `src/pages/forms/1701q.native (table schema)` |

## 1701 — 2018-01-ENCS

Source: `src/pages/forms/1701.native`

Tax Form Profile: `setup`, spec revision 2, SHA-256 `18e080aab881f659587a3e50d34723ca4b8571d33593e529ccb0661cda6e3095`

Consumed taxpayer-year settings: `income_tax_rate_election`, `deduction_method`

Named roles: `filer`, `spouse`, `filing`, `payment`, `employer`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, estate, trust |
| spouse | zero_or_one | individual, sole_proprietor |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1701.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/1701.native:3` |
| `1701.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1701.native:4` |
| `1701.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1701.native:5` |
| `1701.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1701.native:6` |
| `1701.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1701.native:7` |
| `1701.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1701.native:8` |
| `1701.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1701.native:9` |
| `1701.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | — | — | filer | postal_code | unbound_input | `src/pages/forms/1701.native:10` |
| `1701.2018-01-ENCS.input.date_of_birth` | Date of Birth | profile | date_of_birth | optional | — | — | filer | date | unbound_input | `src/pages/forms/1701.native:11` |
| `1701.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | — | — | filer | email | unbound_input | `src/pages/forms/1701.native:12` |
| `1701.2018-01-ENCS.input.citizenship` | Citizenship | profile | citizenship | optional | — | — | filer | text | unbound_input | `src/pages/forms/1701.native:13` |
| `1701.2018-01-ENCS.input.foreign_tax_number` | Foreign Tax Number | profile | foreign_tax_number | optional | — | — | filer | tax_identifier | unbound_input | `src/pages/forms/1701.native:14` |
| `1701.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | — | — | filer | phone | unbound_input | `src/pages/forms/1701.native:15` |
| `1701.2018-01-ENCS.input.spouse_tin` | Spouse TIN | profile | tin | required | — | — | spouse | tin | unbound_input | `src/pages/forms/1701.native:21` |
| `1701.2018-01-ENCS.input.spouse_rdo_code` | Spouse RDO Code | profile | rdo_code | required | — | — | spouse | rdo_code | unbound_input | `src/pages/forms/1701.native:22` |
| `1701.2018-01-ENCS.input.spouse_name` | Spouse Name | profile | taxpayer_name | required | — | — | spouse | text | unbound_input | `src/pages/forms/1701.native:23` |
| `1701.2018-01-ENCS.input.taxable_compensation_income` | Taxable Compensation Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:29` |
| `1701.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:30` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation` | Tax Withheld on Compensation | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:31` |
| `1701.2018-01-ENCS.input.sales_revenues_receipts_fees` | Sales / Revenues / Receipts / Fees | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:37` |
| `1701.2018-01-ENCS.input.returns_allowances_and_discounts` | Returns, Allowances and Discounts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:38` |
| `1701.2018-01-ENCS.input.cost_of_sales_services` | Cost of Sales / Services | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:39` |
| `1701.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:40` |
| `1701.2018-01-ENCS.input.allowable_deductions` | Allowable Deductions | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:41` |
| `1701.2018-01-ENCS.input.net_taxable_income` | Net Taxable Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:42` |
| `1701.2018-01-ENCS.input.other_taxable_income_description` | Other Taxable Income Description | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:48` |
| `1701.2018-01-ENCS.input.other_taxable_income_amount` | Other Taxable Income Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:49` |
| `1701.2018-01-ENCS.input.salaries_wages_and_benefits` | Salaries, Wages and Benefits | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:55` |
| `1701.2018-01-ENCS.input.rent_repairs_and_utilities` | Rent, Repairs and Utilities | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:56` |
| `1701.2018-01-ENCS.input.other_ordinary_deductions` | Other Ordinary Deductions | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:57` |
| `1701.2018-01-ENCS.input.tax_on_compensation_income` | Tax on Compensation Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:63` |
| `1701.2018-01-ENCS.input.tax_on_business_profession_income` | Tax on Business / Profession Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:64` |
| `1701.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:65` |
| `1701.2018-01-ENCS.input.quarterly_income_tax_payments` | Quarterly Income Tax Payments | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:71` |
| `1701.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307` | Creditable Tax Withheld (BIR Form 2307) | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:72` |
| `1701.2018-01-ENCS.input.tax_withheld_on_compensation_2` | Tax Withheld on Compensation | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:73` |
| `1701.2018-01-ENCS.input.other_tax_credit_description` | Other Tax Credit Description | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:79` |
| `1701.2018-01-ENCS.input.other_tax_credit_amount` | Other Tax Credit Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:80` |
| `1701.2018-01-ENCS.input.tax_relief_special_rate` | Tax Relief / Special Rate | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1701.native:86` |
| `1701.2018-01-ENCS.input.tax_relief_amount` | Tax Relief Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:87` |
| `1701.2018-01-ENCS.input.net_income_per_books` | Net Income per Books | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1701.native:93` |
| `1701.2018-01-ENCS.input.add_non_deductible_expenses` | Add: Non-Deductible Expenses | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:94` |
| `1701.2018-01-ENCS.input.less_non_taxable_income` | Less: Non-Taxable Income | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1701.native:95` |
| `1701.2018-01-ENCS.input.taxable_net_income` | Taxable Net Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:96` |
| `1701.2018-01-ENCS.input.tax_due` | Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:102` |
| `1701.2018-01-ENCS.input.less_total_tax_credits_payments` | Less: Total Tax Credits / Payments | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:103` |
| `1701.2018-01-ENCS.input.penalties` | Penalties | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1701.native:104` |
| `1701.2018-01-ENCS.input.overpayment_disposition` | 32 Overpayment Disposition | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/1701.native:110` |
| `1701.2018-01-ENCS.input.required_attachments` | 33 Required Attachments | external | — | — | — | — | attachment | text | unbound_input | `src/pages/forms/1701.native:111` |
| `1701.2018-01-ENCS.table.compensation.employer_name` | Employer name | external | — | — | — | — | employer | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.employer_tin` | Employer TIN | external | — | — | — | — | employer | tin | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.gross` | Gross compensation | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.non_taxable` | Non-taxable compensation | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.taxable` | Taxable compensation | derived | — | — | — | — | system | money | derived_display | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.compensation.tax_withheld` | Compensation tax withheld | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.year_incurred` | NOLCO year incurred | external | — | — | — | — | evidence | year | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.original_amount` | Original NOLCO | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.applied_previously` | NOLCO applied previously | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.applied_this_year` | NOLCO applied this year | transaction | — | — | — | — | filing | money | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.nolco.balance` | NOLCO balance | derived | — | — | — | — | system | money | derived_display | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | — | — | payment | choice | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/1701.native (table schema)` |
| `1701.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | — | — | payment | money | static_table | `src/pages/forms/1701.native (table schema)` |

## 1702RT — 2018-01-ENCS

Source: `src/pages/forms/1702-rt.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `7dc726162bab90d4909f876daaa6f93d02bb3fe64b22f78a86b9aebc26ba66f2`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | corporation, partnership, cooperative, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1702RT.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/1702-rt.native:3` |
| `1702RT.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-rt.native:4` |
| `1702RT.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1702-rt.native:5` |
| `1702RT.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1702-rt.native:6` |
| `1702RT.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1702-rt.native:7` |
| `1702RT.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-rt.native:8` |
| `1702RT.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-rt.native:9` |
| `1702RT.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/1702-rt.native:10` |
| `1702RT.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/1702-rt.native:11` |
| `1702RT.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/1702-rt.native:12` |
| `1702RT.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-rt.native:13` |
| `1702RT.2018-01-ENCS.input.tax_relief_special_law` | Tax Relief / Special Law | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/1702-rt.native:14` |
| `1702RT.2018-01-ENCS.input.sales_receipts_revenues_fees` | 27 Sales / Receipts / Revenues / Fees | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:20` |
| `1702RT.2018-01-ENCS.input.returns_allowances_discounts` | 28 Returns / Allowances / Discounts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:21` |
| `1702RT.2018-01-ENCS.input.cost_of_sales_services` | 30 Cost of Sales / Services | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:22` |
| `1702RT.2018-01-ENCS.input.other_taxable_income` | 32 Other Taxable Income | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:23` |
| `1702RT.2018-01-ENCS.input.itemized_optional_standard_deduction` | Itemized / Optional Standard Deduction | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/1702-rt.native:24` |
| `1702RT.2018-01-ENCS.input.regular_income_tax_rate` | 40 Regular Income Tax Rate | external | — | — | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-rt.native:25` |
| `1702RT.2018-01-ENCS.input.net_sales_receipts` | Net Sales / Receipts | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:31` |
| `1702RT.2018-01-ENCS.input.gross_income` | Gross Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:32` |
| `1702RT.2018-01-ENCS.input.total_taxable_income` | Total Taxable Income | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:33` |
| `1702RT.2018-01-ENCS.input.normal_income_tax` | Normal Income Tax | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:34` |
| `1702RT.2018-01-ENCS.input.minimum_corporate_income_tax` | Minimum Corporate Income Tax | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:35` |
| `1702RT.2018-01-ENCS.input.income_tax_due` | Income Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:36` |
| `1702RT.2018-01-ENCS.input.prior_year_excess_credits` | 44 Prior-Year Excess Credits | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:42` |
| `1702RT.2018-01-ENCS.input.quarterly_income_tax_payments` | 45 Quarterly Income Tax Payments | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:43` |
| `1702RT.2018-01-ENCS.input.creditable_tax_withheld` | 46 Creditable Tax Withheld | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:44` |
| `1702RT.2018-01-ENCS.input.foreign_tax_credits` | 47 Foreign Tax Credits | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:45` |
| `1702RT.2018-01-ENCS.input.48_53_other_credits_payments` | 48-53 Other Credits / Payments | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:46` |
| `1702RT.2018-01-ENCS.input.total_tax_credits_payments` | 54 Total Tax Credits / Payments | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:47` |
| `1702RT.2018-01-ENCS.input.tax_payable_overpayment` | Tax Payable / (Overpayment) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:53` |
| `1702RT.2018-01-ENCS.input.add_surcharge_interest_and_compromise` | Add: Surcharge, Interest and Compromise | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:54` |
| `1702RT.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-rt.native:55` |
| `1702RT.2018-01-ENCS.input.refund` | Refund | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:61` |
| `1702RT.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-rt.native:62` |
| `1702RT.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-rt.native:63` |
| `1702RT.2018-01-ENCS.table.official_schedule.name` | Official schedule name | filing_context | — | — | — | — | attachment | text | static_table | `src/pages/forms/1702-rt.native (table schema)` |
| `1702RT.2018-01-ENCS.table.official_schedule.rows` | Official schedule rows | external | — | — | — | — | attachment | text | static_table | `src/pages/forms/1702-rt.native (table schema)` |
| `1702RT.2018-01-ENCS.table.official_schedule.attachment_status` | Official schedule attachment status | filing_context | — | — | — | — | attachment | choice | static_table | `src/pages/forms/1702-rt.native (table schema)` |

## 1702MX — 2018-01-ENCS

Source: `src/pages/forms/1702-mx.native`

Tax Form Profile: `setup`, spec revision 1, SHA-256 `61478774c6335ea70c77bada3537cc9bafe1963d7805d38a58f7ce49ed3f46e7`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `attachment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | corporation, partnership, cooperative, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1702MX.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/1702-mx.native:3` |
| `1702MX.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1702-mx.native:4` |
| `1702MX.2018-01-ENCS.input.number_of_sheets_attached` | Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1702-mx.native:5` |
| `1702MX.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1702-mx.native:6` |
| `1702MX.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1702-mx.native:7` |
| `1702MX.2018-01-ENCS.input.registered_name` | Registered Name | profile | registered_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-mx.native:8` |
| `1702MX.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-mx.native:9` |
| `1702MX.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/1702-mx.native:10` |
| `1702MX.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/1702-mx.native:11` |
| `1702MX.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/1702-mx.native:12` |
| `1702MX.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | — | — | filer | text | unbound_input | `src/pages/forms/1702-mx.native:13` |
| `1702MX.2018-01-ENCS.input.special_preferential_rate_basis` | Special / Preferential Rate Basis | tax_form_profile | — | — | special_rate_basis | — | filer | text | unbound_input | `src/pages/forms/1702-mx.native:14` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_regular_rate` | Gross Income Subject to Regular Rate | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:20` |
| `1702MX.2018-01-ENCS.input.gross_income_subject_to_special_rate` | Gross Income Subject to Special Rate | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:21` |
| `1702MX.2018-01-ENCS.input.special_preferential_tax_rate` | Special / Preferential Tax Rate | external | — | — | — | — | evidence | percent | unbound_input | `src/pages/forms/1702-mx.native:22` |
| `1702MX.2018-01-ENCS.input.schedule_2_regular_rate_tax_due` | Schedule 2 Regular-Rate Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:23` |
| `1702MX.2018-01-ENCS.input.schedule_2_special_rate_tax_due` | Schedule 2 Special-Rate Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:24` |
| `1702MX.2018-01-ENCS.input.schedule_3_total_tax_credits` | Schedule 3 Total Tax Credits | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:25` |
| `1702MX.2018-01-ENCS.input.income_tax_at_regular_rate` | Income Tax at Regular Rate | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:31` |
| `1702MX.2018-01-ENCS.input.income_tax_at_special_rate` | Income Tax at Special Rate | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:32` |
| `1702MX.2018-01-ENCS.input.total_income_tax_due` | Total Income Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:33` |
| `1702MX.2018-01-ENCS.input.total_tax_credits_payments` | Total Tax Credits / Payments | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:34` |
| `1702MX.2018-01-ENCS.input.net_tax_payable_overpayment` | Net Tax Payable / (Overpayment) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:35` |
| `1702MX.2018-01-ENCS.input.surcharge` | Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:41` |
| `1702MX.2018-01-ENCS.input.interest` | Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:42` |
| `1702MX.2018-01-ENCS.input.compromise` | Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:43` |
| `1702MX.2018-01-ENCS.input.total_amount_payable` | Total Amount Payable | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1702-mx.native:44` |
| `1702MX.2018-01-ENCS.input.refund` | Refund | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:50` |
| `1702MX.2018-01-ENCS.input.tax_credit_certificate` | Tax Credit Certificate | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1702-mx.native:51` |
| `1702MX.2018-01-ENCS.input.carry_over_to_next_period` | Carry Over to Next Period | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1702-mx.native:52` |
| `1702MX.2018-01-ENCS.input.attachment_description` | Attachment Description | external | — | — | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:58` |
| `1702MX.2018-01-ENCS.input.attachment_reference` | Attachment Reference | external | — | — | — | — | attachment | text | unbound_input | `src/pages/forms/1702-mx.native:59` |
| `1702MX.2018-01-ENCS.table.rate_schedule.schedule_id` | Rate-schedule identity | filing_context | — | — | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.description` | Special-rate income description | transaction | — | — | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.legal_basis` | Special-rate legal basis | transaction | — | — | — | — | filing | text | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.regular_rate` | Regular income-tax rate | external | — | — | — | — | evidence | percent | static_table | `src/pages/forms/1702-mx.native (table schema)` |
| `1702MX.2018-01-ENCS.table.rate_schedule.special_rate` | Special income-tax rate | external | — | — | — | — | evidence | percent | static_table | `src/pages/forms/1702-mx.native (table schema)` |

## 2550Q — 2024-04-ENCS

Source: `src/pages/forms/2550q.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `49363b23a0fd60148850df5a6f3b162b907e95840efc80af3c7a60700e3ab7f6`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `preparer`, `withholding_agent`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `2550Q.2024-04-ENCS.input.year_end_month` | Year-end month | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/2550q.native:3` |
| `2550Q.2024-04-ENCS.input.taxable_year_raw` | Taxable year (raw) | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/2550q.native:4` |
| `2550Q.2024-04-ENCS.input.return_period_from` | Return Period From | filing_context | — | — | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:5` |
| `2550Q.2024-04-ENCS.input.return_period_to` | Return Period To | filing_context | — | — | — | — | filing | date | unbound_input | `src/pages/forms/2550q.native:6` |
| `2550Q.2024-04-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:7` |
| `2550Q.2024-04-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/2550q.native:8` |
| `2550Q.2024-04-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/2550q.native:9` |
| `2550Q.2024-04-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/2550q.native:10` |
| `2550Q.2024-04-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/2550q.native:11` |
| `2550Q.2024-04-ENCS.input.registered_address` | Registered Address | profile | registered_address | optional | — | — | filer | text | unbound_input | `src/pages/forms/2550q.native:12` |
| `2550Q.2024-04-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/2550q.native:13` |
| `2550Q.2024-04-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/2550q.native:14` |
| `2550Q.2024-04-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/2550q.native:15` |
| `2550Q.2024-04-ENCS.input.eopt_taxpayer_classification` | EOPT Taxpayer Classification | profile | eopt_tier | required | — | — | filer | choice | unbound_input | `src/pages/forms/2550q.native:16` |
| `2550Q.2024-04-ENCS.input.vatable_sales_receipts` | 31A Vatable Sales / Receipts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:22` |
| `2550Q.2024-04-ENCS.input.output_tax_due` | 31B Output Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:23` |
| `2550Q.2024-04-ENCS.input.zero_rated_sales_receipts` | 32A Zero-Rated Sales / Receipts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:24` |
| `2550Q.2024-04-ENCS.input.exempt_sales_receipts` | 33A Exempt Sales / Receipts | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:25` |
| `2550Q.2024-04-ENCS.input.output_vat_adjustments` | Output VAT Adjustments | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:26` |
| `2550Q.2024-04-ENCS.input.total_output_tax_due` | Total Output Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:27` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_input_tax` | 44 Domestic Purchases / Input Tax | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:33` |
| `2550Q.2024-04-ENCS.input.services_rendered_by_non_residents` | 45 Services Rendered by Non-Residents | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:34` |
| `2550Q.2024-04-ENCS.input.importation_of_goods` | 46 Importation of Goods | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:35` |
| `2550Q.2024-04-ENCS.input.other_purchases` | 47 Other Purchases | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:36` |
| `2550Q.2024-04-ENCS.input.domestic_purchases_without_input_tax` | 48 Domestic Purchases Without Input Tax | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:37` |
| `2550Q.2024-04-ENCS.input.exempt_importations` | 49 Exempt Importations | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:38` |
| `2550Q.2024-04-ENCS.input.input_tax_directly_attributable_to_exempt_sales` | Input Tax Directly Attributable to Exempt Sales | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:44` |
| `2550Q.2024-04-ENCS.input.input_tax_not_directly_attributable` | Input Tax Not Directly Attributable | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:45` |
| `2550Q.2024-04-ENCS.input.ratable_input_tax_to_exempt_sales` | Ratable Input Tax to Exempt Sales | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:46` |
| `2550Q.2024-04-ENCS.input.prior_return_payment` | Prior Return Payment | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/2550q.native:52` |
| `2550Q.2024-04-ENCS.input.other_tax_credit_payment` | Other Tax Credit / Payment | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2550q.native:53` |
| `2550Q.2024-04-ENCS.input.net_vat_payable_overpayment` | Net VAT Payable / (Overpayment) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:54` |
| `2550Q.2024-04-ENCS.input.surcharge` | Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:55` |
| `2550Q.2024-04-ENCS.input.interest` | Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:56` |
| `2550Q.2024-04-ENCS.input.compromise` | Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2550q.native:57` |
| `2550Q.2024-04-ENCS.input.taxpayer_authorized_representative` | Taxpayer / Authorized Representative | transaction | — | — | — | — | preparer | text | unbound_input | `src/pages/forms/2550q.native:63` |
| `2550Q.2024-04-ENCS.input.payment_method` | Payment Method | transaction | — | — | — | — | payment | choice | unbound_input | `src/pages/forms/2550q.native:64` |
| `2550Q.2024-04-ENCS.input.payment_reference` | Payment Reference | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/2550q.native:65` |
| `2550Q.2024-04-ENCS.table.capital_good.description` | Capital-good description | external | — | — | — | — | evidence | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.date_acquired` | Capital-good acquisition date | external | — | — | — | — | evidence | date | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.useful_life` | Capital-good useful life | external | — | — | — | — | evidence | integer | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.acquisition_cost` | Capital-good acquisition cost | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.capital_good.allowable_input_tax` | Allowable capital-good input tax | derived | — | — | — | — | system | money | derived_display | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.agent` | VAT withholding agent | external | — | — | — | — | withholding_agent | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.agent_tin` | VAT withholding-agent TIN | external | — | — | — | — | withholding_agent | tin | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.period` | VAT withholding period | external | — | — | — | — | evidence | tax_period | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.vat_withholding.credit` | Creditable VAT withheld | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.payment_date` | Advance VAT payment date | external | — | — | — | — | payment | date | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.reference_number` | Advance VAT reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.taxable_base` | Advance VAT taxable base | external | — | — | — | — | evidence | money | static_table | `src/pages/forms/2550q.native (table schema)` |
| `2550Q.2024-04-ENCS.table.advance_vat.paid` | Advance VAT paid | external | — | — | — | — | payment | money | static_table | `src/pages/forms/2550q.native (table schema)` |

## 2551Q — 2018-01-ENCS

Source: `src/pages/forms/2551q.native`

Tax Form Profile: `setup`, spec revision 2, SHA-256 `7f3df1b82f7d72e8e9b29ff01e10b086e0a6b1a1d4702861cd9f8d175f62cef4`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `2551Q.2018-01-ENCS.input.taxable_period_basis` | 1 Taxable-period basis | profile | accounting_period_basis | required | — | — | filer | choice | unbound_input | `src/pages/forms/2551q.native:5` |
| `2551Q.2018-01-ENCS.input.year_end_month` | 2 Year-end month | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/2551q.native:10` |
| `2551Q.2018-01-ENCS.input.taxable_quarter` | Taxable Quarter | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/2551q.native:16` |
| `2551Q.2018-01-ENCS.input.taxable_year` | Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/2551q.native:17` |
| `2551Q.2018-01-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/2551q.native:20` |
| `2551Q.2018-01-ENCS.input.return_options` | Return Options | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:26` |
| `2551Q.2018-01-ENCS.input.amended_return` | Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:27` |
| `2551Q.2018-01-ENCS.input.tax_relief` | Tax Relief? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/2551q.native:30` |
| `2551Q.2018-01-ENCS.input.tax_relief_specification` | 12A Tax Relief Specification | transaction | — | — | — | — | filing | text | unbound_input | `src/pages/forms/2551q.native:50` |
| `2551Q.2018-01-ENCS.input.what_income_tax_rates_are_you_availing` | 13 What income tax rates are you availing? | tax_form_profile | — | — | income_tax_rate_election | — | filer | choice | unbound_input | `src/pages/forms/2551q.native:59` |
| `2551Q.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/2551q.native:68` |
| `2551Q.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/2551q.native:69` |
| `2551Q.2018-01-ENCS.input.taxpayers_name` | Taxpayer's Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/2551q.native:70` |
| `2551Q.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/2551q.native:73` |
| `2551Q.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | required | — | — | filer | postal_code | unbound_input | `src/pages/forms/2551q.native:77` |
| `2551Q.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | — | — | filer | phone | unbound_input | `src/pages/forms/2551q.native:81` |
| `2551Q.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | required | — | — | filer | email | unbound_input | `src/pages/forms/2551q.native:85` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_code` | Schedule 1 Line 1 Percentage-tax Code | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:106` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_tax_base_taxable_amount` | Schedule 1 Line 1 Tax Base / Taxable Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:114` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_policy_supplied_tax_rate` | Schedule 1 Line 1 Policy-supplied Tax Rate | external | — | — | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:122` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_due` | Schedule 1 Line 1 Percentage Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:128` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_code` | Schedule 1 Line 2 Percentage-tax Code | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/2551q.native:131` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_tax_base_taxable_amount` | Schedule 1 Line 2 Tax Base / Taxable Amount | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:139` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_policy_supplied_tax_rate` | Schedule 1 Line 2 Policy-supplied Tax Rate | external | — | — | — | — | evidence | percent | unbound_input | `src/pages/forms/2551q.native:147` |
| `2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_due` | Schedule 1 Line 2 Percentage Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:153` |
| `2551Q.2018-01-ENCS.input.total_percentage_tax_due` | 14 Total Percentage Tax Due | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:160` |
| `2551Q.2018-01-ENCS.input.creditable_percentage_tax_withheld` | 15 Creditable Percentage Tax Withheld | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:163` |
| `2551Q.2018-01-ENCS.input.tax_paid_in_previous_return` | 16 Tax Paid in Previous Return | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/2551q.native:171` |
| `2551Q.2018-01-ENCS.input.other_tax_credit_payment` | 17 Other Tax Credit / Payment | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:179` |
| `2551Q.2018-01-ENCS.input.total_tax_credits_payments` | 18 Total Tax Credits / Payments | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:185` |
| `2551Q.2018-01-ENCS.input.tax_payable_overpayment` | 19 Tax Payable / (Overpayment) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/2551q.native:186` |
| `2551Q.2018-01-ENCS.input.surcharge_manual` | 20 Surcharge (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:189` |
| `2551Q.2018-01-ENCS.input.interest_manual` | 21 Interest (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:197` |
| `2551Q.2018-01-ENCS.input.compromise_manual` | 22 Compromise (manual) | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/2551q.native:205` |
| `2551Q.2018-01-ENCS.input.overpayment_disposition` | 24 Overpayment Disposition | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/2551q.native:213` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.atc` | Percentage-tax ATC | transaction | — | — | — | — | filing | atc_code | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.tax_base` | Percentage-tax base | transaction | — | — | — | — | filing | money | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.rate` | Percentage-tax rate | external | — | — | — | — | evidence | percent | static_table | `src/pages/forms/2551q.native (table schema)` |
| `2551Q.2018-01-ENCS.table.percentage_tax_line.tax_due` | Percentage tax due | derived | — | — | — | — | system | money | derived_display | `src/pages/forms/2551q.native (table schema)` |

## 0619E — 2018-01-ENCS

Source: `src/pages/forms/0619-e.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `0bbca08d13a26690fb24c819c36c4c83aafe1e150ee6b4aef10fd4bce16d3579`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `0619E.2018-01-ENCS.input.for_the_month_of_mm_yyyy` | 1 For the Month of (MM/YYYY) | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/0619-e.native:3` |
| `0619E.2018-01-ENCS.input.amended_form` | 3 Amended Form? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:4` |
| `0619E.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:5` |
| `0619E.2018-01-ENCS.input.atc` | 5 ATC | form_policy | — | — | form_policy.atc | WME10 | system | atc_code | unbound_input | `src/pages/forms/0619-e.native:6` |
| `0619E.2018-01-ENCS.input.tax_type_code` | 6 Tax Type Code | form_policy | — | — | form_policy.tax_type | WE | system | choice | unbound_input | `src/pages/forms/0619-e.native:7` |
| `0619E.2018-01-ENCS.input.due_date_day` | Due date day | filing_context | — | — | — | — | filing | date | unbound_input | `src/pages/forms/0619-e.native:8` |
| `0619E.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/0619-e.native:9` |
| `0619E.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/0619-e.native:10` |
| `0619E.2018-01-ENCS.input.registered_taxpayer_name` | Registered Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/0619-e.native:11` |
| `0619E.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | optional | — | — | filer | text | unbound_input | `src/pages/forms/0619-e.native:12` |
| `0619E.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | optional | — | — | filer | text | unbound_input | `src/pages/forms/0619-e.native:13` |
| `0619E.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/0619-e.native:14` |
| `0619E.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | optional | — | — | filer | phone | unbound_input | `src/pages/forms/0619-e.native:15` |
| `0619E.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/0619-e.native:16` |
| `0619E.2018-01-ENCS.input.government_withholding_agent` | 12 Government withholding agent? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/0619-e.native:17` |
| `0619E.2018-01-ENCS.input.amount_of_remittance` | 14 Amount of Remittance | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/0619-e.native:23` |
| `0619E.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form` | 15 Less: Amount Remitted from Previously Filed Form | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/0619-e.native:24` |
| `0619E.2018-01-ENCS.input.net_amount_of_remittance_14_15` | 16 Net Amount of Remittance (14 - 15) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:25` |
| `0619E.2018-01-ENCS.input.surcharge` | 17A Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:26` |
| `0619E.2018-01-ENCS.input.interest` | 17B Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:27` |
| `0619E.2018-01-ENCS.input.compromise` | 17C Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/0619-e.native:28` |
| `0619E.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | — | — | preparer | text | unbound_input | `src/pages/forms/0619-e.native:34` |
| `0619E.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:35` |
| `0619E.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/0619-e.native:36` |
| `0619E.2018-01-ENCS.table.payment.method` | Payment method | external | — | — | — | — | payment | choice | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.bank_agency` | Drawee bank or collecting agency | external | — | — | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.reference_number` | Payment reference number | external | — | — | — | — | payment | text | static_table | `src/pages/forms/0619-e.native (table schema)` |
| `0619E.2018-01-ENCS.table.payment.amount` | Payment amount | external | — | — | — | — | payment | money | static_table | `src/pages/forms/0619-e.native (table schema)` |

## 1601EQ — 2018-01-ENCS

Source: `src/pages/forms/1601-eq.native`

Tax Form Profile: `no_setup`, spec revision 1, SHA-256 `00da4f31d7e8646a51315909b4eadf20feaf1bd8b7d8127158bf0475bed3be1a`

Consumed taxpayer-year settings: none

Named roles: `filer`, `filing`, `payment`, `preparer`, `evidence`, `system`

Profile binding policy:

| Profile role | Cardinality | Allowed subject kinds |
|---|---|---|
| filer | exactly_one | individual, sole_proprietor, corporation, partnership, cooperative, estate, trust, other_legal_entity |

| Stable field ID | Label | Provenance | Profile key | Presence | Source key | Fixed value | Role | Type | Status | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| `1601EQ.2018-01-ENCS.input.tin` | TIN | profile | tin | required | — | — | filer | tin | unbound_input | `src/pages/forms/1601-eq.native:3` |
| `1601EQ.2018-01-ENCS.input.rdo_code` | RDO Code | profile | rdo_code | required | — | — | filer | rdo_code | unbound_input | `src/pages/forms/1601-eq.native:4` |
| `1601EQ.2018-01-ENCS.input.taxpayer_name` | Taxpayer Name | profile | taxpayer_name | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-eq.native:5` |
| `1601EQ.2018-01-ENCS.input.registered_address` | Registered Address | profile | registered_address | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-eq.native:6` |
| `1601EQ.2018-01-ENCS.input.zip_code` | ZIP Code | profile | zip_code | optional | — | — | filer | postal_code | unbound_input | `src/pages/forms/1601-eq.native:7` |
| `1601EQ.2018-01-ENCS.input.line_of_business` | Line of Business | profile | line_of_business | required | — | — | filer | text | unbound_input | `src/pages/forms/1601-eq.native:8` |
| `1601EQ.2018-01-ENCS.input.contact_number` | Contact Number | profile | contact_number | required | — | — | filer | phone | unbound_input | `src/pages/forms/1601-eq.native:9` |
| `1601EQ.2018-01-ENCS.input.email_address` | Email Address | profile | email_address | optional | — | — | filer | email | unbound_input | `src/pages/forms/1601-eq.native:10` |
| `1601EQ.2018-01-ENCS.input.taxable_year` | 1 Taxable Year | filing_context | — | — | — | — | filing | year | unbound_input | `src/pages/forms/1601-eq.native:16` |
| `1601EQ.2018-01-ENCS.input.quarter` | 2 Quarter | filing_context | — | — | — | — | filing | tax_period | unbound_input | `src/pages/forms/1601-eq.native:17` |
| `1601EQ.2018-01-ENCS.input.amended_return` | 3 Amended Return? | filing_context | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-eq.native:18` |
| `1601EQ.2018-01-ENCS.input.any_taxes_withheld` | 4 Any Taxes Withheld? | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-eq.native:19` |
| `1601EQ.2018-01-ENCS.input.number_of_sheets_attached` | 5 Number of Sheets Attached | filing_context | — | — | — | — | filing | integer | unbound_input | `src/pages/forms/1601-eq.native:20` |
| `1601EQ.2018-01-ENCS.input.withholding_agent_category` | Withholding Agent Category | transaction | — | — | — | — | filing | choice | unbound_input | `src/pages/forms/1601-eq.native:21` |
| `1601EQ.2018-01-ENCS.input.item_13_atc` | Item 13 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:27` |
| `1601EQ.2018-01-ENCS.input.item_13_tax_base` | Item 13 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:28` |
| `1601EQ.2018-01-ENCS.input.item_13_tax_rate` | Item 13 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:29` |
| `1601EQ.2018-01-ENCS.input.item_13_tax_withheld` | Item 13 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:30` |
| `1601EQ.2018-01-ENCS.input.item_14_atc` | Item 14 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:31` |
| `1601EQ.2018-01-ENCS.input.item_14_tax_base` | Item 14 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:32` |
| `1601EQ.2018-01-ENCS.input.item_14_tax_rate` | Item 14 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:33` |
| `1601EQ.2018-01-ENCS.input.item_14_tax_withheld` | Item 14 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:34` |
| `1601EQ.2018-01-ENCS.input.item_15_atc` | Item 15 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:35` |
| `1601EQ.2018-01-ENCS.input.item_15_tax_base` | Item 15 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:36` |
| `1601EQ.2018-01-ENCS.input.item_15_tax_rate` | Item 15 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:37` |
| `1601EQ.2018-01-ENCS.input.item_15_tax_withheld` | Item 15 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:38` |
| `1601EQ.2018-01-ENCS.input.item_16_atc` | Item 16 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:39` |
| `1601EQ.2018-01-ENCS.input.item_16_tax_base` | Item 16 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:40` |
| `1601EQ.2018-01-ENCS.input.item_16_tax_rate` | Item 16 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:41` |
| `1601EQ.2018-01-ENCS.input.item_16_tax_withheld` | Item 16 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:42` |
| `1601EQ.2018-01-ENCS.input.item_17_atc` | Item 17 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:43` |
| `1601EQ.2018-01-ENCS.input.item_17_tax_base` | Item 17 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:44` |
| `1601EQ.2018-01-ENCS.input.item_17_tax_rate` | Item 17 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:45` |
| `1601EQ.2018-01-ENCS.input.item_17_tax_withheld` | Item 17 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:46` |
| `1601EQ.2018-01-ENCS.input.item_18_atc` | Item 18 ATC | transaction | — | — | — | — | filing | atc_code | unbound_input | `src/pages/forms/1601-eq.native:47` |
| `1601EQ.2018-01-ENCS.input.item_18_tax_base` | Item 18 tax base | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:48` |
| `1601EQ.2018-01-ENCS.input.item_18_tax_rate` | Item 18 tax rate | transaction | — | — | — | — | filing | percent | unbound_input | `src/pages/forms/1601-eq.native:49` |
| `1601EQ.2018-01-ENCS.input.item_18_tax_withheld` | Item 18 tax withheld | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:50` |
| `1601EQ.2018-01-ENCS.input.total_tax_withheld_this_quarter` | 19 Total tax withheld this quarter | transaction | — | — | — | — | filing | money | unbound_input | `src/pages/forms/1601-eq.native:56` |
| `1601EQ.2018-01-ENCS.input.less_tax_remitted_first_month_0619e` | 20 Less: tax remitted first month (0619E) | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1601-eq.native:57` |
| `1601EQ.2018-01-ENCS.input.less_tax_remitted_second_month_0619e` | 21 Less: tax remitted second month (0619E) | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1601-eq.native:58` |
| `1601EQ.2018-01-ENCS.input.tax_remitted_in_return_previously_filed` | 22 Tax remitted in return previously filed | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1601-eq.native:59` |
| `1601EQ.2018-01-ENCS.input.over_remittance_from_previous_quarter` | 23 Over-remittance from previous quarter | external | — | — | — | — | evidence | money | unbound_input | `src/pages/forms/1601-eq.native:60` |
| `1601EQ.2018-01-ENCS.input.total_remittances_made` | 24 Total remittances made | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:61` |
| `1601EQ.2018-01-ENCS.input.tax_still_due_over_remittance` | 25 Tax still due/(Over-remittance) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:62` |
| `1601EQ.2018-01-ENCS.input.surcharge` | 26 Surcharge | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:63` |
| `1601EQ.2018-01-ENCS.input.interest` | 27 Interest | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:64` |
| `1601EQ.2018-01-ENCS.input.compromise` | 28 Compromise | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:65` |
| `1601EQ.2018-01-ENCS.input.total_penalties` | 29 Total penalties | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:66` |
| `1601EQ.2018-01-ENCS.input.total_amount_still_due_over_remittance` | 30 Total amount still due/(Over-remittance) | derived | — | — | — | — | system | money | unbound_input | `src/pages/forms/1601-eq.native:67` |
| `1601EQ.2018-01-ENCS.input.over_remittance_to_be_refunded` | Over-remittance to be refunded | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-eq.native:68` |
| `1601EQ.2018-01-ENCS.input.over_remittance_issued_tax_credit_certificate` | Over-remittance issued tax credit certificate | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-eq.native:69` |
| `1601EQ.2018-01-ENCS.input.over_remittance_carried_over` | Over-remittance carried over | transaction | — | — | — | — | filing | boolean | unbound_input | `src/pages/forms/1601-eq.native:70` |
| `1601EQ.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no` | Tax Agent Accreditation / Attorney Roll No. | external | — | — | — | — | preparer | text | unbound_input | `src/pages/forms/1601-eq.native:76` |
| `1601EQ.2018-01-ENCS.input.date_issued` | Date Issued | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/1601-eq.native:77` |
| `1601EQ.2018-01-ENCS.input.date_of_expiry` | Date of Expiry | external | — | — | — | — | evidence | date | unbound_input | `src/pages/forms/1601-eq.native:78` |
| `1601EQ.2018-01-ENCS.input.item_33_agency` | Item 33 agency | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:87` |
| `1601EQ.2018-01-ENCS.input.item_33_date_paid` | Item 33 date paid | external | — | — | — | — | payment | date | unbound_input | `src/pages/forms/1601-eq.native:88` |
| `1601EQ.2018-01-ENCS.input.item_33_number` | Item 33 number | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:89` |
| `1601EQ.2018-01-ENCS.input.item_33_amount` | Item 33 amount | external | — | — | — | — | payment | money | unbound_input | `src/pages/forms/1601-eq.native:90` |
| `1601EQ.2018-01-ENCS.input.item_34_agency` | Item 34 agency | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:96` |
| `1601EQ.2018-01-ENCS.input.item_34_date_paid` | Item 34 date paid | external | — | — | — | — | payment | date | unbound_input | `src/pages/forms/1601-eq.native:97` |
| `1601EQ.2018-01-ENCS.input.item_34_number` | Item 34 number | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:98` |
| `1601EQ.2018-01-ENCS.input.item_34_amount` | Item 34 amount | external | — | — | — | — | payment | money | unbound_input | `src/pages/forms/1601-eq.native:99` |
| `1601EQ.2018-01-ENCS.input.item_35_agency` | Item 35 agency | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:105` |
| `1601EQ.2018-01-ENCS.input.item_35_date_paid` | Item 35 date paid | external | — | — | — | — | payment | date | unbound_input | `src/pages/forms/1601-eq.native:106` |
| `1601EQ.2018-01-ENCS.input.item_35_number` | Item 35 number | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:107` |
| `1601EQ.2018-01-ENCS.input.item_35_amount` | Item 35 amount | external | — | — | — | — | payment | money | unbound_input | `src/pages/forms/1601-eq.native:108` |
| `1601EQ.2018-01-ENCS.input.item_36_agency` | Item 36 agency | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:114` |
| `1601EQ.2018-01-ENCS.input.item_36_date_paid` | Item 36 date paid | external | — | — | — | — | payment | date | unbound_input | `src/pages/forms/1601-eq.native:115` |
| `1601EQ.2018-01-ENCS.input.item_36_number` | Item 36 number | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:116` |
| `1601EQ.2018-01-ENCS.input.item_36_amount` | Item 36 amount | external | — | — | — | — | payment | money | unbound_input | `src/pages/forms/1601-eq.native:117` |
| `1601EQ.2018-01-ENCS.input.item_36_particular` | Item 36 particular | external | — | — | — | — | payment | text | unbound_input | `src/pages/forms/1601-eq.native:118` |
