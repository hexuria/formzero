/**
 * Authoritative build-time inventory for the form surfaces currently present
 * in this repository.
 *
 * Input controls are discovered from the exact Native source revision and are
 * classified by the rules below. Static tables are declared explicitly because
 * they do not contain controls that can be discovered mechanically. The
 * generator validates both sources and emits reviewable Zig and Markdown.
 */

export const provenanceValues = [
  "profile",
  "transaction",
  "derived",
  "filing_context",
  "external",
] as const;
export type Provenance = (typeof provenanceValues)[number];

export const roleValues = [
  "filer",
  "spouse",
  "filing",
  "payment",
  "preparer",
  "employer",
  "withholding_agent",
  "attachment",
  "evidence",
  "system",
] as const;
export type Role = (typeof roleValues)[number];

export const profileRoleValues = ["filer", "spouse"] as const;
export type ProfileRole = (typeof profileRoleValues)[number];

export const profileCardinalityValues = [
  "exactly_one",
  "zero_or_one",
] as const;
export type ProfileCardinality = (typeof profileCardinalityValues)[number];

export const profilePresenceValues = ["required", "optional"] as const;
export type ProfilePresence = (typeof profilePresenceValues)[number];

export const profileSubjectKindValues = [
  "individual",
  "sole_proprietor",
  "corporation",
  "partnership",
  "estate",
  "trust",
  "other_legal_entity",
] as const;
export type ProfileSubjectKind = (typeof profileSubjectKindValues)[number];

export const valueTypeValues = [
  "text",
  "boolean",
  "integer",
  "money",
  "percent",
  "date",
  "year",
  "tax_period",
  "tin",
  "rdo_code",
  "postal_code",
  "email",
  "phone",
  "atc_code",
  "tax_identifier",
  "choice",
] as const;
export type ValueType = (typeof valueTypeValues)[number];

export type FieldStatus =
  | "unbound_input"
  | "static_table"
  | "derived_display";

export type FormStatus = "calendar_only" | "static_layout";

export const profileFieldKeyValues = [
  "tin",
  "rdo_code",
  "taxpayer_name",
  "registered_name",
  "registered_address",
  "zip_code",
  "contact_number",
  "email_address",
  "date_of_birth",
  "citizenship",
  "foreign_tax_number",
  "line_of_business",
  "atc",
  "tax_type",
  "government_withholding_agent",
  "special_rate_basis",
] as const;
export type ProfileFieldKey = (typeof profileFieldKeyValues)[number];

export interface TableFieldSpec {
  readonly id: string;
  readonly label: string;
  readonly provenance: Provenance;
  readonly role: Role;
  readonly valueType: ValueType;
  readonly status?: Exclude<FieldStatus, "unbound_input">;
  readonly profileField?: ProfileFieldKey;
}

export interface ProfileRoleSpec {
  readonly role: ProfileRole;
  readonly cardinality: ProfileCardinality;
  readonly allowedSubjectKinds: readonly ProfileSubjectKind[];
  /**
   * Named profile roles that must resolve to a different stable profile.
   *
   * The relation is authored once and interpreted symmetrically. It belongs
   * to the form contract, not to a particular screen adapter.
   */
  readonly distinctFrom?: readonly ProfileRole[];
}

export interface EditorFormSpec {
  readonly code: string;
  readonly revision: string;
  readonly revisionLabel: string;
  readonly sourcePath: string;
  readonly expectedInputCount: number;
  readonly roles: readonly Role[];
  readonly profileRoles: readonly ProfileRoleSpec[];
  /**
   * Exact generated target IDs with an explicit presence policy.
   * Every undeclared profile target defaults to required.
   */
  readonly profileTargetPresence?: Readonly<Record<string, ProfilePresence>>;
  readonly tableFields: readonly TableFieldSpec[];
  readonly expectedTableCount: number;
  readonly expectedTableHeaders: readonly string[];
}

const paymentTable = (prefix: string): readonly TableFieldSpec[] => [
  {
    id: `${prefix}.method`,
    label: "Payment method",
    provenance: "external",
    role: "payment",
    valueType: "choice",
  },
  {
    id: `${prefix}.bank_agency`,
    label: "Drawee bank or collecting agency",
    provenance: "external",
    role: "payment",
    valueType: "text",
  },
  {
    id: `${prefix}.reference_number`,
    label: "Payment reference number",
    provenance: "external",
    role: "payment",
    valueType: "text",
  },
  {
    id: `${prefix}.amount`,
    label: "Payment amount",
    provenance: "external",
    role: "payment",
    valueType: "money",
  },
];

const allProfileSubjectKinds = profileSubjectKindValues;
const individualReturnSubjectKinds = [
  "individual",
  "sole_proprietor",
  "estate",
  "trust",
] as const satisfies readonly ProfileSubjectKind[];
const spouseSubjectKinds = [
  "individual",
  "sole_proprietor",
] as const satisfies readonly ProfileSubjectKind[];
const corporateReturnSubjectKinds = [
  "corporation",
  "partnership",
  "other_legal_entity",
] as const satisfies readonly ProfileSubjectKind[];

function exactlyOneFiler(
  allowedSubjectKinds: readonly ProfileSubjectKind[] =
    allProfileSubjectKinds,
): ProfileRoleSpec {
  return {
    role: "filer",
    cardinality: "exactly_one",
    allowedSubjectKinds,
  };
}

export const editorForms: readonly EditorFormSpec[] = [
  {
    code: "0605",
    revision: "1999-07-ENCS",
    revisionLabel: "July 1999 (ENCS)",
    sourcePath: "src/pages/forms/0605.native",
    expectedInputCount: 17,
    expectedTableCount: 1,
    expectedTableHeaders: [
      "Payment method",
      "Drawee bank / agency",
      "Reference number",
      "Amount",
    ],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    tableFields: paymentTable("payment"),
  },
  {
    code: "0619E",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/0619-e.native",
    expectedInputCount: 18,
    expectedTableCount: 1,
    expectedTableHeaders: ["Method", "Bank / Agency", "Reference", "Amount"],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    tableFields: paymentTable("payment"),
  },
  {
    code: "0619F",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/0619-f.native",
    expectedInputCount: 20,
    expectedTableCount: 1,
    expectedTableHeaders: ["Item", "Payment method", "Reference", "Amount"],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    tableFields: [
      {
        id: "payment.item_reference",
        label: "Payment item reference",
        provenance: "filing_context",
        role: "filing",
        valueType: "text",
      },
      {
        id: "payment.method",
        label: "Payment method",
        provenance: "external",
        role: "payment",
        valueType: "choice",
      },
      {
        id: "payment.reference_number",
        label: "Payment reference number",
        provenance: "external",
        role: "payment",
        valueType: "text",
      },
      {
        id: "payment.amount",
        label: "Payment amount",
        provenance: "external",
        role: "payment",
        valueType: "money",
      },
    ],
  },
  {
    code: "1601C",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1601-c.native",
    expectedInputCount: 28,
    expectedTableCount: 1,
    expectedTableHeaders: [
      "Previous month",
      "Date paid",
      "Agency",
      "Payment reference",
      "Tax paid",
      "Tax due",
      "Adjustment",
    ],
    roles: ["filer", "filing", "payment", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    tableFields: [
      {
        id: "prior_payment.period",
        label: "Previous-month period",
        provenance: "external",
        role: "evidence",
        valueType: "tax_period",
      },
      {
        id: "prior_payment.date_paid",
        label: "Previous payment date",
        provenance: "external",
        role: "payment",
        valueType: "date",
      },
      {
        id: "prior_payment.agency",
        label: "Previous payment agency",
        provenance: "external",
        role: "payment",
        valueType: "text",
      },
      {
        id: "prior_payment.reference_number",
        label: "Previous payment reference",
        provenance: "external",
        role: "payment",
        valueType: "text",
      },
      {
        id: "prior_payment.tax_paid",
        label: "Previous tax paid",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "prior_payment.tax_due",
        label: "Previous tax due",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "prior_payment.adjustment",
        label: "Previous-payment adjustment",
        provenance: "derived",
        role: "system",
        valueType: "money",
        status: "derived_display",
      },
    ],
  },
  {
    code: "1701",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1701.native",
    expectedInputCount: 49,
    expectedTableCount: 3,
    expectedTableHeaders: [
      "Employer Name",
      "Employer TIN",
      "Gross Compensation",
      "Non-Taxable",
      "Taxable",
      "Tax Withheld",
      "Year Incurred",
      "Original NOLCO",
      "Applied Previously",
      "Applied This Year",
      "Balance",
      "Method",
      "Bank / Agency",
      "Reference",
      "Amount",
    ],
    roles: [
      "filer",
      "spouse",
      "filing",
      "payment",
      "employer",
      "attachment",
      "evidence",
      "system",
    ],
    profileRoles: [
      exactlyOneFiler(individualReturnSubjectKinds),
      {
        role: "spouse",
        cardinality: "zero_or_one",
        allowedSubjectKinds: spouseSubjectKinds,
        distinctFrom: ["filer"],
      },
    ],
    profileTargetPresence: {
      "1701.2018-01-ENCS.input.date_of_birth": "optional",
      "1701.2018-01-ENCS.input.citizenship": "optional",
      "1701.2018-01-ENCS.input.foreign_tax_number": "optional",
    },
    tableFields: [
      {
        id: "compensation.employer_name",
        label: "Employer name",
        provenance: "external",
        role: "employer",
        valueType: "text",
      },
      {
        id: "compensation.employer_tin",
        label: "Employer TIN",
        provenance: "external",
        role: "employer",
        valueType: "tin",
      },
      {
        id: "compensation.gross",
        label: "Gross compensation",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "compensation.non_taxable",
        label: "Non-taxable compensation",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "compensation.taxable",
        label: "Taxable compensation",
        provenance: "derived",
        role: "system",
        valueType: "money",
        status: "derived_display",
      },
      {
        id: "compensation.tax_withheld",
        label: "Compensation tax withheld",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "nolco.year_incurred",
        label: "NOLCO year incurred",
        provenance: "external",
        role: "evidence",
        valueType: "year",
      },
      {
        id: "nolco.original_amount",
        label: "Original NOLCO",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "nolco.applied_previously",
        label: "NOLCO applied previously",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "nolco.applied_this_year",
        label: "NOLCO applied this year",
        provenance: "transaction",
        role: "filing",
        valueType: "money",
      },
      {
        id: "nolco.balance",
        label: "NOLCO balance",
        provenance: "derived",
        role: "system",
        valueType: "money",
        status: "derived_display",
      },
      ...paymentTable("payment"),
    ],
  },
  {
    code: "1701Q",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1701q.native",
    expectedInputCount: 37,
    expectedTableCount: 1,
    expectedTableHeaders: ["Method", "Bank / Agency", "Reference", "Amount"],
    roles: ["filer", "spouse", "filing", "payment", "evidence", "system"],
    profileRoles: [
      exactlyOneFiler(individualReturnSubjectKinds),
      {
        role: "spouse",
        cardinality: "zero_or_one",
        allowedSubjectKinds: spouseSubjectKinds,
        distinctFrom: ["filer"],
      },
    ],
    profileTargetPresence: {
      "1701Q.2018-01-ENCS.input.date_of_birth": "optional",
      "1701Q.2018-01-ENCS.input.citizenship": "optional",
      "1701Q.2018-01-ENCS.input.foreign_tax_number": "optional",
      "1701Q.2018-01-ENCS.input.spouse_citizenship": "optional",
      "1701Q.2018-01-ENCS.input.spouse_foreign_tax_number": "optional",
    },
    tableFields: paymentTable("payment"),
  },
  {
    code: "1702MX",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1702-mx.native",
    expectedInputCount: 29,
    expectedTableCount: 1,
    expectedTableHeaders: [
      "Schedule",
      "Description",
      "Legal Basis",
      "Regular Rate",
      "Special Rate",
    ],
    roles: ["filer", "filing", "attachment", "evidence", "system"],
    profileRoles: [exactlyOneFiler(corporateReturnSubjectKinds)],
    profileTargetPresence: {
      "1702MX.2018-01-ENCS.input.special_preferential_rate_basis": "optional",
    },
    tableFields: [
      {
        id: "rate_schedule.schedule_id",
        label: "Rate-schedule identity",
        provenance: "filing_context",
        role: "filing",
        valueType: "text",
      },
      {
        id: "rate_schedule.description",
        label: "Special-rate income description",
        provenance: "transaction",
        role: "filing",
        valueType: "text",
      },
      {
        id: "rate_schedule.legal_basis",
        label: "Special-rate legal basis",
        provenance: "transaction",
        role: "filing",
        valueType: "text",
      },
      {
        id: "rate_schedule.regular_rate",
        label: "Regular income-tax rate",
        provenance: "external",
        role: "evidence",
        valueType: "percent",
      },
      {
        id: "rate_schedule.special_rate",
        label: "Special income-tax rate",
        provenance: "external",
        role: "evidence",
        valueType: "percent",
      },
    ],
  },
  {
    code: "1702RT",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1702-rt.native",
    expectedInputCount: 33,
    expectedTableCount: 1,
    expectedTableHeaders: ["Schedule", "Official rows", "Attachment status"],
    roles: ["filer", "filing", "attachment", "evidence", "system"],
    profileRoles: [exactlyOneFiler(corporateReturnSubjectKinds)],
    tableFields: [
      {
        id: "official_schedule.name",
        label: "Official schedule name",
        provenance: "filing_context",
        role: "attachment",
        valueType: "text",
      },
      {
        id: "official_schedule.rows",
        label: "Official schedule rows",
        provenance: "external",
        role: "attachment",
        valueType: "text",
      },
      {
        id: "official_schedule.attachment_status",
        label: "Official schedule attachment status",
        provenance: "filing_context",
        role: "attachment",
        valueType: "choice",
      },
    ],
  },
  {
    code: "2550Q",
    revision: "2024-04-ENCS",
    revisionLabel: "April 2024 (ENCS)",
    sourcePath: "src/pages/forms/2550q.native",
    expectedInputCount: 33,
    expectedTableCount: 3,
    expectedTableHeaders: [
      "Description",
      "Date Acquired",
      "Useful Life",
      "Acquisition Cost",
      "Allowable Input Tax",
      "Withholding Agent",
      "TIN",
      "Period",
      "Creditable VAT Withheld",
      "Payment Date",
      "Reference Number",
      "Taxable Base",
      "Advance VAT Paid",
    ],
    roles: [
      "filer",
      "filing",
      "payment",
      "preparer",
      "withholding_agent",
      "evidence",
      "system",
    ],
    profileRoles: [exactlyOneFiler()],
    tableFields: [
      {
        id: "capital_good.description",
        label: "Capital-good description",
        provenance: "external",
        role: "evidence",
        valueType: "text",
      },
      {
        id: "capital_good.date_acquired",
        label: "Capital-good acquisition date",
        provenance: "external",
        role: "evidence",
        valueType: "date",
      },
      {
        id: "capital_good.useful_life",
        label: "Capital-good useful life",
        provenance: "external",
        role: "evidence",
        valueType: "integer",
      },
      {
        id: "capital_good.acquisition_cost",
        label: "Capital-good acquisition cost",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "capital_good.allowable_input_tax",
        label: "Allowable capital-good input tax",
        provenance: "derived",
        role: "system",
        valueType: "money",
        status: "derived_display",
      },
      {
        id: "vat_withholding.agent",
        label: "VAT withholding agent",
        provenance: "external",
        role: "withholding_agent",
        valueType: "text",
      },
      {
        id: "vat_withholding.agent_tin",
        label: "VAT withholding-agent TIN",
        provenance: "external",
        role: "withholding_agent",
        valueType: "tin",
      },
      {
        id: "vat_withholding.period",
        label: "VAT withholding period",
        provenance: "external",
        role: "evidence",
        valueType: "tax_period",
      },
      {
        id: "vat_withholding.credit",
        label: "Creditable VAT withheld",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "advance_vat.payment_date",
        label: "Advance VAT payment date",
        provenance: "external",
        role: "payment",
        valueType: "date",
      },
      {
        id: "advance_vat.reference_number",
        label: "Advance VAT reference number",
        provenance: "external",
        role: "payment",
        valueType: "text",
      },
      {
        id: "advance_vat.taxable_base",
        label: "Advance VAT taxable base",
        provenance: "external",
        role: "evidence",
        valueType: "money",
      },
      {
        id: "advance_vat.paid",
        label: "Advance VAT paid",
        provenance: "external",
        role: "payment",
        valueType: "money",
      },
    ],
  },
  {
    code: "2551Q",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/2551q.native",
    expectedInputCount: 35,
    expectedTableCount: 1,
    expectedTableHeaders: ["ATC", "Tax Base / Taxable Amount", "Tax Rate", "Percentage Tax Due"],
    roles: ["filer", "filing", "payment", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    tableFields: [
      {
        id: "percentage_tax_line.atc",
        label: "Percentage-tax ATC",
        provenance: "transaction",
        role: "filing",
        valueType: "atc_code",
      },
      {
        id: "percentage_tax_line.tax_base",
        label: "Percentage-tax base",
        provenance: "transaction",
        role: "filing",
        valueType: "money",
      },
      {
        id: "percentage_tax_line.rate",
        label: "Percentage-tax rate",
        provenance: "external",
        role: "evidence",
        valueType: "percent",
      },
      {
        id: "percentage_tax_line.tax_due",
        label: "Percentage tax due",
        provenance: "derived",
        role: "system",
        valueType: "money",
        status: "derived_display",
      },
    ],
  },
] as const;

/**
 * Exact 51-code registry from src/main.zig. The generator independently reads
 * the Zig source and requires an exact, order-preserving match.
 */
export const registryCodes = [
  "0605",
  "1905",
  "1600",
  "1600PT",
  "1600VT",
  "1600WP",
  "1601C",
  "1601E",
  "1601F",
  "0619F",
  "1601FQ",
  "1602",
  "1602Q",
  "1603",
  "1603Q",
  "1604CF",
  "1604E",
  "0620",
  "2316",
  "1700",
  "1701Q",
  "1701",
  "1701A",
  "1702Q",
  "1702",
  "1702RT",
  "1702EX",
  "1702MX",
  "1704",
  "2550M",
  "2550Q",
  "2551Q",
  "2551M",
  "2552",
  "2553",
  "2000",
  "2000OT",
  "2200A",
  "2200AN",
  "2200M",
  "2200P",
  "2200T",
  "2200C",
  "2200S",
  "0619E",
  "1601EQ",
  "1701MS",
  "1706",
  "1707A",
  "1800",
  "1801",
] as const;

const profilePatterns = [
  /\btin\b/i,
  /\brdo\b/i,
  /\btaxpayer(?:'s)? (?:\/ filer )?name\b/i,
  /\bregistered name\b/i,
  /\bspouse name\b/i,
  /\bregistered address\b/i,
  /\bzip code\b/i,
  /\bdate of birth\b/i,
  /\bemail address\b/i,
  /\bcitizenship\b/i,
  /\bforeign tax number\b/i,
  /\bcontact number\b/i,
  /\bline of business\b/i,
  /\bbusiness activity\b/i,
  /\boccupation\b/i,
  /\batc\b/i,
  /\btax type(?: code)?\b/i,
  /\bgovernment withholding agent\b/i,
  /\bspecial (?:\/ preferential )?rate basis\b/i,
] as const;

const filingContextPatterns = [
  /\btaxable year\b/i,
  /\byear ended month\b/i,
  /\byear-end month\b/i,
  /\bfor the month\b/i,
  /\breturn period\b/i,
  /\btaxable quarter\b/i,
  /^(?:\d+\s+)?quarter\b/i,
  /\bdue date\b/i,
  /\bdue date day\b/i,
  /\bamended (?:form|return)\b/i,
  /\breturn options\b/i,
  /\bnumber of sheets attached\b/i,
  /\btaxable-period basis\b/i,
] as const;

const externalPatterns = [
  /\bprevious(?:ly)? (?:filed|return|payment|remitted)\b/i,
  /\bprior[- ](?:quarter|year|return)\b/i,
  /\bquarterly income tax payments\b/i,
  /\bcreditable\b/i,
  /\bwithheld on compensation\b/i,
  /\bforeign tax credits?\b/i,
  /\btax credit certificate\b/i,
  /\bnet income per books\b/i,
  /\battachments?\b/i,
  /\baccreditation\b/i,
  /\battorney roll\b/i,
  /\bdate issued\b/i,
  /\bdate of expiry\b/i,
  /\breference\b/i,
] as const;

const derivedPatterns = [
  /\btotal\b/i,
  /\bnet\b/i,
  /\btax due\b/i,
  /\btax payable\b/i,
  /\boverpayment\b/i,
  /\btax still due\b/i,
  /\bincome tax due\b/i,
  /\boutput tax due\b/i,
  /\bratable input tax\b/i,
  /\btax required to be withheld\b/i,
  /^(?:\d+[A-Z]?\s+)?surcharge\b/i,
  /^(?:\d+[A-Z]?\s+)?interest\b/i,
  /^(?:\d+[A-Z]?\s+)?compromise\b/i,
  /\bpenalt/i,
  /\btax on\b/i,
  /\bincome tax at\b/i,
  /\bnormal income tax\b/i,
  /\bminimum corporate income tax\b/i,
  /\btaxable income\b/i,
  /\bgross income\b/i,
  /\btaxable compensation\b/i,
] as const;

function matchesAny(label: string, patterns: readonly RegExp[]): boolean {
  return patterns.some((pattern) => pattern.test(label));
}

export function inferProvenance(label: string): Provenance {
  if (/\(manual\)/i.test(label)) return "transaction";
  if (/\bpolicy-supplied (?:percentage )?tax rate\b/i.test(label)) {
    return "external";
  }
  if (/\bdisposition\b|\belection\b|\bmethod\b|\bmanner\b|\breturn options\b/i.test(label)) {
    return "transaction";
  }
  if (
    /\bother (?:non-)?taxable (?:income|compensation)\b|\bgross income subject to\b|\bfinal tax withheld\b|\bless:\s*non-taxable income\b/i.test(
      label,
    )
  ) {
    return "transaction";
  }
  if (matchesAny(label, profilePatterns)) return "profile";
  if (matchesAny(label, filingContextPatterns)) return "filing_context";
  if (/\b(?:regular|special|preferential) (?:income )?tax rate\b/i.test(label)) {
    return "external";
  }
  if (matchesAny(label, externalPatterns)) return "external";
  if (matchesAny(label, derivedPatterns)) return "derived";
  return "transaction";
}

export function inferRole(label: string, provenance: Provenance): Role {
  if (/\bspouse\b/i.test(label)) return "spouse";
  if (/\bemployer\b/i.test(label)) return "employer";
  if (/\bgovernment withholding agent\b/i.test(label)) return "filer";
  if (/\bwithholding agent\b/i.test(label)) return "withholding_agent";
  if (/\btax agent\b|\battorney roll\b|\bauthorized representative\b/i.test(label)) {
    return "preparer";
  }
  if (/\bpayment method\b|\bmanner of payment\b|\btype of payment\b/i.test(label)) {
    return "payment";
  }
  if (/\bpayment reference\b/i.test(label)) return "payment";
  if (/\battachments?\b/i.test(label)) return "attachment";
  if (provenance === "profile") return "filer";
  if (provenance === "derived") return "system";
  if (provenance === "external") return "evidence";
  return "filing";
}

export function inferProfileField(label: string): ProfileFieldKey {
  if (/\btin\b/i.test(label)) return "tin";
  if (/\brdo\b/i.test(label)) return "rdo_code";
  if (/\bregistered address\b/i.test(label)) return "registered_address";
  if (/\bzip code\b/i.test(label)) return "zip_code";
  if (/\bcontact number\b/i.test(label)) return "contact_number";
  if (/\bemail address\b/i.test(label)) return "email_address";
  if (/\bdate of birth\b/i.test(label)) return "date_of_birth";
  if (/\bcitizenship\b/i.test(label)) return "citizenship";
  if (/\bforeign tax number\b/i.test(label)) return "foreign_tax_number";
  if (/\bline of business\b|\bbusiness activity\b|\boccupation\b/i.test(label)) {
    return "line_of_business";
  }
  if (/\batc\b/i.test(label)) return "atc";
  if (/\btax type(?: code)?\b/i.test(label)) return "tax_type";
  if (/\bgovernment withholding agent\b/i.test(label)) {
    return "government_withholding_agent";
  }
  if (/\bspecial[- /]*(?:preferential )?(?:rate )?(?:basis|legal basis)\b/i.test(label)) {
    return "special_rate_basis";
  }
  if (/\bspouse name\b|\btaxpayer(?:'s)? (?:\/ filer )?name\b/i.test(label)) {
    return "taxpayer_name";
  }
  if (/\bregistered taxpayer name\b/i.test(label)) return "taxpayer_name";
  if (/\bregistered name\b/i.test(label)) return "registered_name";
  throw new Error(`Profile field has no canonical profile key: ${label}`);
}

export function inferValueType(label: string, placeholder: string): ValueType {
  const text = `${label} ${placeholder}`;
  if (/\btin\b/i.test(text)) return "tin";
  if (/\brdo\b/i.test(text)) return "rdo_code";
  if (/\batc\b/i.test(text)) return "atc_code";
  if (/\bemail\b|@example\.com/i.test(text)) return "email";
  if (/\bcontact number\b|\bphone\b/i.test(text)) return "phone";
  if (/\bzip\b|\bpostal\b/i.test(text)) return "postal_code";
  if (/\bforeign tax number\b/i.test(text)) return "tax_identifier";
  if (/\breference\b/i.test(label)) return "text";
  if (/^Enter amount$/i.test(placeholder.trim())) return "money";
  if (/^Rate$/i.test(placeholder.trim())) return "percent";
  if (
    /^(?:No|Yes\s*\/\s*No|No\s*\/\s*Specify)$/i.test(placeholder.trim())
  ) {
    return "boolean";
  }
  if (
    /\bselect\b|\btax type\b|\bmethod\b|\bmanner\b|\bdisposition\b|\belection\b|\brefund\s*\/|\boriginal\s*\/|\bcalendar\s*\/|\bdeduction method\b/i.test(
      text,
    )
  ) {
    return "choice";
  }
  if (
    /\b(?:description|source|credit|code|basis|details|supporting|filename|name and capacity)\b/i.test(
      placeholder,
    )
  ) {
    return "text";
  }
  if (/\bMM\s*\/\s*DD\s*\/\s*YYYY\b/i.test(text) || /\bdate\b/i.test(label)) {
    return "date";
  }
  if (
    /\bfor the month\b|\bquarter\b|\bperiod\b|\byear[- ]end month\b/i.test(label) ||
    /\bMM\s*\/\s*YYYY\b/i.test(text)
  ) {
    return "tax_period";
  }
  if (/\btaxable year\b|\bYYYY\b/i.test(text)) return "year";
  if (/\bspecial (?:\/ preferential )?rate basis\b/i.test(label)) return "text";
  if (/\brate\b|%/i.test(text)) return "percent";
  if (
    /\bamount\b|\bincome\b|\bsales\b|\breceipts\b|\brevenues\b|\bcompensation\b|\bdeductions?\b|\bcredits?\b|\bpayments?\b|\bpenalt|\bsurcharge\b|\binterest\b|\bcompromise\b|\btax (?:due|paid|payable|required|withheld)\b|\btaxable base\b/i.test(
      label,
    )
  ) {
    return "money";
  }
  if (/\bnumber of sheets\b|\buseful life\b|Enter number/i.test(text)) {
    return "integer";
  }
  if (/\bamended\b|\byes\s*\/\s*no\b/i.test(text)) return "boolean";
  return "text";
}
