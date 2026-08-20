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
  "tax_form_profile",
  "taxpayer_year",
  "form_policy",
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
  "cooperative",
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

/** Filing cadence is independent from editor capability. */
export const filingCadenceValues = [
  "monthly",
  "quarterly",
  "annual",
  "on_demand",
] as const;
export type FilingCadence = (typeof filingCadenceValues)[number];

/** Closed, UI-facing tax category vocabulary for catalog filtering. */
export const taxCategoryValues = [
  "payment",
  "registration",
  "withholding_tax",
  "income_tax",
  "value_added_tax",
  "percentage_tax",
  "documentary_stamp_tax",
  "excise_tax",
  "capital_gains_tax",
  "estate_and_donors_tax",
] as const;
export type TaxCategory = (typeof taxCategoryValues)[number];

export interface FormDisplayMetadata {
  readonly displayTitle: string;
  readonly taxCategory: TaxCategory;
}

export interface FilingPeriodPolicy {
  readonly cadence: FilingCadence;
  /** Inclusive 1-based period bounds for monthly/quarterly forms. */
  readonly minPeriod: number | null;
  readonly maxPeriod: number | null;
}

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
  "accounting_period_basis",
  "line_of_business",
  "eopt_tier",
  "atc",
  "tax_type",
  "government_withholding_agent",
  "special_rate_basis",
] as const;
export type ProfileFieldKey = (typeof profileFieldKeyValues)[number];

/**
 * Shared taxpayer/year facts that a form contract may consume even when the
 * exact Native editor has no visible control for the value yet.
 */
export const taxpayerYearSettingKeyValues = [
  "income_tax_rate_election",
  "deduction_method",
] as const;
export type TaxpayerYearSettingKey =
  (typeof taxpayerYearSettingKeyValues)[number];

/**
 * Tax Form Profile metadata is deliberately separate from reusable taxpayer
 * facts. A setup contract may select a stable source, own a genuinely
 * form-specific annual value, or provide a safe draft seed. It may never copy
 * a base profile fact, taxpayer-year setting, or filing transaction into a
 * second source of truth.
 */
export const taxFormProfileSetupModeValues = [
  "calendar_only",
  "no_setup",
  "setup",
] as const;
export type TaxFormProfileSetupMode =
  (typeof taxFormProfileSetupModeValues)[number];

export const taxFormProfileOwnershipValues = [
  "binding_selection",
  "yearly_value",
  "transaction_default",
] as const;
export type TaxFormProfileOwnership =
  (typeof taxFormProfileOwnershipValues)[number];

export const taxFormProfileAvailabilityValues = [
  "supported",
  "evidence_required",
] as const;
export type TaxFormProfileAvailability =
  (typeof taxFormProfileAvailabilityValues)[number];

export const taxFormProfilePresenceValues = [
  "required",
  "optional",
  "conditional",
] as const;
export type TaxFormProfilePresence =
  (typeof taxFormProfilePresenceValues)[number];

export const taxFormProfileValueTypeValues = [
  "profile_id",
  "text",
  "boolean",
  "integer",
  "date",
  "year",
  "choice",
] as const;
export type TaxFormProfileValueType =
  (typeof taxFormProfileValueTypeValues)[number];

/**
 * These are references or setup-authoring sources only. Direct profile scalar
 * facts and filing transactions are intentionally absent from this vocabulary.
 */
export const taxFormProfileSourceKindValues = [
  "named_profile_role",
  "user_entry",
  "catalog_default",
] as const;
export type TaxFormProfileSourceKind =
  (typeof taxFormProfileSourceKindValues)[number];

export const taxFormProfileValidationRuleValues = [
  "distinct_profile_role",
  "nonempty_text",
  "catalog_choice",
] as const;
export type TaxFormProfileValidationRule =
  (typeof taxFormProfileValidationRuleValues)[number];

export const taxFormProfileSemanticKeyValues = [
  "spouse_profile_id",
  "income_tax_rate_election",
  "special_rate_basis",
] as const;
export type TaxFormProfileSemanticKey =
  (typeof taxFormProfileSemanticKeyValues)[number];

export interface TaxFormProfileSemanticDefinition {
  readonly valueType: TaxFormProfileValueType;
  readonly role: ProfileRole;
  readonly presence: TaxFormProfilePresence;
  readonly validationRule: TaxFormProfileValidationRule;
  readonly ownership: TaxFormProfileOwnership;
  readonly sourceKind: TaxFormProfileSourceKind;
}

/**
 * One definition per approved semantic key. Editor contracts reference these
 * keys; they cannot redefine ownership or alias the selected source value.
 */
export const taxFormProfileSemanticDefinitions = {
  spouse_profile_id: {
    valueType: "profile_id",
    role: "spouse",
    presence: "optional",
    validationRule: "distinct_profile_role",
    ownership: "binding_selection",
    sourceKind: "named_profile_role",
  },
  income_tax_rate_election: {
    valueType: "choice",
    role: "filer",
    presence: "required",
    validationRule: "catalog_choice",
    ownership: "yearly_value",
    sourceKind: "user_entry",
  },
  special_rate_basis: {
    valueType: "text",
    role: "filer",
    presence: "conditional",
    validationRule: "nonempty_text",
    ownership: "yearly_value",
    sourceKind: "user_entry",
  },
} as const satisfies Readonly<
  Record<TaxFormProfileSemanticKey, TaxFormProfileSemanticDefinition>
>;

interface TaxFormProfileSupportedValueSpec {
  readonly semanticKey: TaxFormProfileSemanticKey;
  readonly availability: "supported";
  readonly sourceEvidence: string;
  readonly evidenceGate?: never;
}

interface TaxFormProfileEvidenceRequiredValueSpec {
  readonly semanticKey: TaxFormProfileSemanticKey;
  readonly availability: "evidence_required";
  readonly sourceEvidence: string;
  /** A blocking question; this value is not editable or persistable yet. */
  readonly evidenceGate: string;
}

export type TaxFormProfileValueSpec =
  | TaxFormProfileSupportedValueSpec
  | TaxFormProfileEvidenceRequiredValueSpec;

export type TaxFormProfileEditorContract =
  | {
      readonly mode: "no_setup";
      readonly specRevision: number;
      readonly sourceEvidence: string;
      readonly values: readonly [];
    }
  | {
      readonly mode: "setup";
      readonly specRevision: number;
      readonly sourceEvidence: string;
      readonly values: readonly [
        TaxFormProfileValueSpec,
        ...TaxFormProfileValueSpec[],
      ];
    };

export interface TableFieldSpec {
  readonly id: string;
  readonly label: string;
  readonly provenance: Provenance;
  readonly role: Role;
  readonly valueType: ValueType;
  readonly status?: Exclude<FieldStatus, "unbound_input">;
  readonly profileField?: ProfileFieldKey;
}

/**
 * Reviewed metadata for one exact Native input control.
 *
 * Labels and placeholders remain useful display/source evidence, but they are
 * deliberately not ownership authority. Every discovered input must match one
 * exact stable ID in this contract before generation can proceed.
 */
export interface InputFieldSpec {
  readonly provenance: Provenance;
  readonly role: Role;
  readonly valueType: ValueType;
  readonly profileField?: ProfileFieldKey;
  /** Typed source identity consumed by projection/composition code. */
  readonly sourceKey?: string;
  /** Locked value when the source is exact-revision form policy. */
  readonly fixedValue?: string;
}

interface InputFieldGroupSpec extends InputFieldSpec {
  readonly ids: readonly string[];
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
  readonly consumedTaxpayerYearSettings: readonly TaxpayerYearSettingKey[];
  readonly taxFormProfile: TaxFormProfileEditorContract;
  /** Exact, exhaustively reviewed metadata for every discovered input. */
  readonly inputFields: Readonly<Record<string, InputFieldSpec>>;
  /**
   * Exact generated target IDs with an explicit presence policy.
   * Every undeclared profile target defaults to required.
   */
  readonly profileTargetPresence?: Readonly<Record<string, ProfilePresence>>;
  readonly tableFields: readonly TableFieldSpec[];
  readonly expectedTableCount: number;
  readonly expectedTableHeaders: readonly string[];
}

function defineInputFields(
  groups: readonly InputFieldGroupSpec[],
): Readonly<Record<string, InputFieldSpec>> {
  const result: Record<string, InputFieldSpec> = {};
  for (const group of groups) {
    const metadata: InputFieldSpec = {
      provenance: group.provenance,
      role: group.role,
      valueType: group.valueType,
      ...(group.profileField === undefined
        ? {}
        : { profileField: group.profileField }),
      ...(group.sourceKey === undefined ? {} : { sourceKey: group.sourceKey }),
      ...(group.fixedValue === undefined ? {} : { fixedValue: group.fixedValue }),
    };
    for (const id of group.ids) {
      if (result[id]) throw new Error(`Duplicate explicit input field ${id}`);
      result[id] = metadata;
    }
  }
  return result;
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
  "cooperative",
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

function supportedSetupValue(
  semanticKey: TaxFormProfileSemanticKey,
  sourceEvidence: string,
): TaxFormProfileValueSpec {
  return {
    semanticKey,
    availability: "supported",
    sourceEvidence,
  };
}

/**
 * Exhaustive ownership/type review of the 372 Native input controls.
 *
 * Grouping keeps the source reviewable without weakening exact-ID coverage:
 * the generator rejects a discovered control missing from this table and an
 * entry that no longer resolves to a discovered control. The seven corrected
 * ownership defects are intentionally visible in the `form_policy` and 0605
 * transaction groups below. Shared annual elections use `taxpayer_year`.
 */
const explicitInputFields = defineInputFields([
  {
    provenance: "derived", role: "system", valueType: "money",
    ids: [
      "1601C.2018-01-ENCS.input.total_amount_of_compensation",
      "1601C.2018-01-ENCS.input.total_non_taxable_exempt_compensation",
      "1601C.2018-01-ENCS.input.total_taxable_compensation",
      "1601C.2018-01-ENCS.input.tax_required_to_be_withheld",
      "1601C.2018-01-ENCS.input.tax_still_due",
      "1601C.2018-01-ENCS.input.surcharge",
      "1601C.2018-01-ENCS.input.interest",
      "1601C.2018-01-ENCS.input.compromise",
      "1601C.2018-01-ENCS.input.total_penalties",
      "0619F.2018-01-ENCS.input.total_final_income_taxes_withheld",
      "0619F.2018-01-ENCS.input.net_amount_of_remittance",
      "0619F.2018-01-ENCS.input.surcharge",
      "0619F.2018-01-ENCS.input.interest",
      "0619F.2018-01-ENCS.input.compromise",
      "1701Q.2018-01-ENCS.input.taxable_income_external_policy_result",
      "1701Q.2018-01-ENCS.input.income_tax_due_external_policy_result",
      "1701Q.2018-01-ENCS.input.tax_due_at_8_percent_external_policy_result",
      "1701Q.2018-01-ENCS.input.tax_payable_overpayment_external_policy_result",
      "1701Q.2018-01-ENCS.input.surcharge_external_policy_result",
      "1701Q.2018-01-ENCS.input.interest_external_policy_result",
      "1701Q.2018-01-ENCS.input.compromise_external_policy_result",
      "1701.2018-01-ENCS.input.taxable_compensation_income",
      "1701.2018-01-ENCS.input.income_tax_due",
      "1701.2018-01-ENCS.input.gross_income",
      "1701.2018-01-ENCS.input.net_taxable_income",
      "1701.2018-01-ENCS.input.tax_on_compensation_income",
      "1701.2018-01-ENCS.input.tax_on_business_profession_income",
      "1701.2018-01-ENCS.input.total_income_tax_due",
      "1701.2018-01-ENCS.input.taxable_net_income",
      "1701.2018-01-ENCS.input.tax_due",
      "1701.2018-01-ENCS.input.less_total_tax_credits_payments",
      "1701.2018-01-ENCS.input.penalties",
      "1702RT.2018-01-ENCS.input.net_sales_receipts",
      "1702RT.2018-01-ENCS.input.gross_income",
      "1702RT.2018-01-ENCS.input.total_taxable_income",
      "1702RT.2018-01-ENCS.input.normal_income_tax",
      "1702RT.2018-01-ENCS.input.minimum_corporate_income_tax",
      "1702RT.2018-01-ENCS.input.income_tax_due",
      "1702RT.2018-01-ENCS.input.total_tax_credits_payments",
      "1702RT.2018-01-ENCS.input.tax_payable_overpayment",
      "1702RT.2018-01-ENCS.input.total_amount_payable",
      "1702MX.2018-01-ENCS.input.schedule_2_regular_rate_tax_due",
      "1702MX.2018-01-ENCS.input.schedule_2_special_rate_tax_due",
      "1702MX.2018-01-ENCS.input.schedule_3_total_tax_credits",
      "1702MX.2018-01-ENCS.input.income_tax_at_regular_rate",
      "1702MX.2018-01-ENCS.input.income_tax_at_special_rate",
      "1702MX.2018-01-ENCS.input.total_income_tax_due",
      "1702MX.2018-01-ENCS.input.total_tax_credits_payments",
      "1702MX.2018-01-ENCS.input.net_tax_payable_overpayment",
      "1702MX.2018-01-ENCS.input.surcharge",
      "1702MX.2018-01-ENCS.input.interest",
      "1702MX.2018-01-ENCS.input.compromise",
      "1702MX.2018-01-ENCS.input.total_amount_payable",
      "2550Q.2024-04-ENCS.input.output_tax_due",
      "2550Q.2024-04-ENCS.input.total_output_tax_due",
      "2550Q.2024-04-ENCS.input.ratable_input_tax_to_exempt_sales",
      "2550Q.2024-04-ENCS.input.net_vat_payable_overpayment",
      "2550Q.2024-04-ENCS.input.surcharge",
      "2550Q.2024-04-ENCS.input.interest",
      "2550Q.2024-04-ENCS.input.compromise",
      "2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_due",
      "2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_due",
      "2551Q.2018-01-ENCS.input.total_percentage_tax_due",
      "2551Q.2018-01-ENCS.input.total_tax_credits_payments",
      "2551Q.2018-01-ENCS.input.tax_payable_overpayment",
      "0619E.2018-01-ENCS.input.net_amount_of_remittance_14_15",
      "0619E.2018-01-ENCS.input.surcharge",
      "0619E.2018-01-ENCS.input.interest",
      "0619E.2018-01-ENCS.input.compromise",
      "1601EQ.2018-01-ENCS.input.tax_still_due",
      "1601EQ.2018-01-ENCS.input.surcharge",
      "1601EQ.2018-01-ENCS.input.interest",
      "1601EQ.2018-01-ENCS.input.compromise",
      "1601EQ.2018-01-ENCS.input.total_amount_payable",
      "1601EQ.2018-01-ENCS.input.item_13_tax_withheld",
      "1601EQ.2018-01-ENCS.input.item_14_tax_withheld",
      "1601EQ.2018-01-ENCS.input.item_15_tax_withheld",
      "1601EQ.2018-01-ENCS.input.item_16_tax_withheld",
      "1601EQ.2018-01-ENCS.input.item_17_tax_withheld",
      "1601EQ.2018-01-ENCS.input.item_18_tax_withheld",
    ],
  },
  {
    provenance: "external", role: "attachment", valueType: "text",
    ids: [
      "1701.2018-01-ENCS.input.required_attachments",
      "1702MX.2018-01-ENCS.input.attachment_description",
      "1702MX.2018-01-ENCS.input.attachment_reference",
    ],
  },
  {
    provenance: "external", role: "evidence", valueType: "date",
    ids: [
      "0619F.2018-01-ENCS.input.date_issued",
      "0619F.2018-01-ENCS.input.date_of_expiry",
      "0619E.2018-01-ENCS.input.date_issued",
      "0619E.2018-01-ENCS.input.date_of_expiry",
    ],
  },
  {
    provenance: "external", role: "evidence", valueType: "money",
    ids: [
      "0619F.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form",
      "1601EQ.2018-01-ENCS.input.less_tax_remitted_first_month_0619e",
      "1601EQ.2018-01-ENCS.input.less_tax_remitted_second_month_0619e",
      "1701Q.2018-01-ENCS.input.prior_quarter_income_tax_payments",
      "1701Q.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307",
      "1701.2018-01-ENCS.input.tax_withheld_on_compensation",
      "1701.2018-01-ENCS.input.quarterly_income_tax_payments",
      "1701.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307",
      "1701.2018-01-ENCS.input.tax_withheld_on_compensation_2",
      "1701.2018-01-ENCS.input.net_income_per_books",
      "1702RT.2018-01-ENCS.input.prior_year_excess_credits",
      "1702RT.2018-01-ENCS.input.quarterly_income_tax_payments",
      "1702RT.2018-01-ENCS.input.creditable_tax_withheld",
      "1702RT.2018-01-ENCS.input.foreign_tax_credits",
      "1702RT.2018-01-ENCS.input.tax_credit_certificate",
      "1702MX.2018-01-ENCS.input.tax_credit_certificate",
      "2550Q.2024-04-ENCS.input.prior_return_payment",
      "2551Q.2018-01-ENCS.input.creditable_percentage_tax_withheld",
      "2551Q.2018-01-ENCS.input.tax_paid_in_previous_return",
      "0619E.2018-01-ENCS.input.less_amount_remitted_from_previously_filed_form",
    ],
  },
  {
    provenance: "external", role: "evidence", valueType: "percent",
    ids: [
      "1702RT.2018-01-ENCS.input.regular_income_tax_rate",
      "1702MX.2018-01-ENCS.input.special_preferential_tax_rate",
      "2551Q.2018-01-ENCS.input.schedule_1_line_1_policy_supplied_tax_rate",
      "2551Q.2018-01-ENCS.input.schedule_1_line_2_policy_supplied_tax_rate",
    ],
  },
  {
    provenance: "transaction", role: "filing", valueType: "percent",
    ids: [
      "1601EQ.2018-01-ENCS.input.item_13_tax_rate",
      "1601EQ.2018-01-ENCS.input.item_14_tax_rate",
      "1601EQ.2018-01-ENCS.input.item_15_tax_rate",
      "1601EQ.2018-01-ENCS.input.item_16_tax_rate",
      "1601EQ.2018-01-ENCS.input.item_17_tax_rate",
      "1601EQ.2018-01-ENCS.input.item_18_tax_rate",
    ],
  },
  {
    provenance: "external", role: "evidence", valueType: "text",
    ids: ["1701Q.2018-01-ENCS.input.reference"],
  },
  {
    provenance: "external", role: "payment", valueType: "text",
    ids: ["2550Q.2024-04-ENCS.input.payment_reference"],
  },
  {
    provenance: "external", role: "preparer", valueType: "text",
    ids: [
      "0619F.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no",
      "0619E.2018-01-ENCS.input.tax_agent_accreditation_attorney_roll_no",
    ],
  },
  {
    provenance: "filing_context", role: "filing", valueType: "boolean",
    ids: [
      "1601C.2018-01-ENCS.input.amended_return",
      "1601EQ.2018-01-ENCS.input.amended_return",
      "0619F.2018-01-ENCS.input.amended_form",
      "1701Q.2018-01-ENCS.input.amended_return",
      "1701.2018-01-ENCS.input.amended_return",
      "1702RT.2018-01-ENCS.input.amended_return",
      "1702MX.2018-01-ENCS.input.amended_return",
      "2550Q.2024-04-ENCS.input.amended_return",
      "2551Q.2018-01-ENCS.input.amended_return",
      "0619E.2018-01-ENCS.input.amended_form",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "choice",
    profileField: "accounting_period_basis",
    ids: ["2551Q.2018-01-ENCS.input.taxable_period_basis"],
  },
  {
    provenance: "filing_context", role: "filing", valueType: "date",
    ids: [
      "0605.1999-07-ENCS.input.due_date_mm_dd_yyyy",
      "0619F.2018-01-ENCS.input.due_date_day",
      "2550Q.2024-04-ENCS.input.return_period_from",
      "2550Q.2024-04-ENCS.input.return_period_to",
      "0619E.2018-01-ENCS.input.due_date_day",
    ],
  },
  {
    provenance: "filing_context", role: "filing", valueType: "integer",
    ids: [
      "0605.1999-07-ENCS.input.number_of_sheets_attached",
      "1601C.2018-01-ENCS.input.number_of_sheets_attached",
      "1601EQ.2018-01-ENCS.input.number_of_sheets_attached",
      "1701Q.2018-01-ENCS.input.number_of_sheets_attached",
      "1701.2018-01-ENCS.input.number_of_sheets_attached",
      "1702RT.2018-01-ENCS.input.number_of_sheets_attached",
      "1702MX.2018-01-ENCS.input.number_of_sheets_attached",
      "2551Q.2018-01-ENCS.input.number_of_sheets_attached",
    ],
  },
  {
    provenance: "filing_context", role: "filing", valueType: "tax_period",
    ids: [
      "0605.1999-07-ENCS.input.year_ended_month_independent",
      "1601C.2018-01-ENCS.input.for_the_month_of",
      "1601EQ.2018-01-ENCS.input.quarter",
      "0619F.2018-01-ENCS.input.for_the_month_of_mm_yyyy",
      "1701Q.2018-01-ENCS.input.quarter",
      "2550Q.2024-04-ENCS.input.year_end_month",
      "2551Q.2018-01-ENCS.input.year_end_month",
      "2551Q.2018-01-ENCS.input.taxable_quarter",
      "0619E.2018-01-ENCS.input.for_the_month_of_mm_yyyy",
    ],
  },
  {
    provenance: "filing_context", role: "filing", valueType: "year",
    ids: [
      "1601EQ.2018-01-ENCS.input.taxable_year",
      "1701Q.2018-01-ENCS.input.taxable_year",
      "1701.2018-01-ENCS.input.taxable_year",
      "1702RT.2018-01-ENCS.input.taxable_year",
      "1702MX.2018-01-ENCS.input.taxable_year",
      "2550Q.2024-04-ENCS.input.taxable_year_raw",
      "2551Q.2018-01-ENCS.input.taxable_year",
    ],
  },
  {
    provenance: "form_policy", role: "system", valueType: "atc_code",
    sourceKey: "form_policy.atc", fixedValue: "WW010",
    ids: ["1601C.2018-01-ENCS.input.atc"],
  },
  {
    provenance: "form_policy", role: "system", valueType: "atc_code",
    sourceKey: "form_policy.atc", fixedValue: "WME10",
    ids: ["0619E.2018-01-ENCS.input.atc"],
  },
  {
    provenance: "form_policy", role: "system", valueType: "choice",
    sourceKey: "form_policy.tax_type", fixedValue: "WB",
    ids: ["0619F.2018-01-ENCS.input.tax_type_code"],
  },
  {
    provenance: "form_policy", role: "system", valueType: "choice",
    sourceKey: "form_policy.tax_type", fixedValue: "WE",
    ids: ["0619E.2018-01-ENCS.input.tax_type_code"],
  },
  {
    provenance: "profile", role: "filer", valueType: "date", profileField: "date_of_birth",
    ids: [
      "1701Q.2018-01-ENCS.input.date_of_birth",
      "1701.2018-01-ENCS.input.date_of_birth",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "email", profileField: "email_address",
    ids: [
      "0605.1999-07-ENCS.input.email_address",
      "1601C.2018-01-ENCS.input.email_address",
      "1601EQ.2018-01-ENCS.input.email_address",
      "0619E.2018-01-ENCS.input.email_address",
      "0619F.2018-01-ENCS.input.email_address",
      "1701Q.2018-01-ENCS.input.email_address",
      "1701.2018-01-ENCS.input.email_address",
      "1702RT.2018-01-ENCS.input.email_address",
      "1702MX.2018-01-ENCS.input.email_address",
      "2550Q.2024-04-ENCS.input.email_address",
      "2551Q.2018-01-ENCS.input.email_address",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "phone", profileField: "contact_number",
    ids: [
      "0605.1999-07-ENCS.input.contact_number",
      "1601C.2018-01-ENCS.input.contact_number",
      "1601EQ.2018-01-ENCS.input.contact_number",
      "0619E.2018-01-ENCS.input.contact_number",
      "0619F.2018-01-ENCS.input.contact_number",
      "1701.2018-01-ENCS.input.contact_number",
      "1702RT.2018-01-ENCS.input.contact_number",
      "1702MX.2018-01-ENCS.input.contact_number",
      "2550Q.2024-04-ENCS.input.contact_number",
      "2551Q.2018-01-ENCS.input.contact_number",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "postal_code", profileField: "zip_code",
    ids: [
      "0605.1999-07-ENCS.input.zip_code",
      "1601C.2018-01-ENCS.input.zip_code",
      "1601EQ.2018-01-ENCS.input.zip_code",
      "0619E.2018-01-ENCS.input.zip_code",
      "0619F.2018-01-ENCS.input.zip_code",
      "1701Q.2018-01-ENCS.input.zip_code",
      "1701.2018-01-ENCS.input.zip_code",
      "1702RT.2018-01-ENCS.input.zip_code",
      "1702MX.2018-01-ENCS.input.zip_code",
      "2550Q.2024-04-ENCS.input.zip_code",
      "2551Q.2018-01-ENCS.input.zip_code",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "rdo_code", profileField: "rdo_code",
    ids: [
      "0605.1999-07-ENCS.input.rdo_code",
      "1601C.2018-01-ENCS.input.rdo_code",
      "1601EQ.2018-01-ENCS.input.rdo_code",
      "0619F.2018-01-ENCS.input.rdo_code",
      "1701Q.2018-01-ENCS.input.rdo_code",
      "1701.2018-01-ENCS.input.rdo_code",
      "1702RT.2018-01-ENCS.input.rdo_code",
      "1702MX.2018-01-ENCS.input.rdo_code",
      "2550Q.2024-04-ENCS.input.rdo_code",
      "2551Q.2018-01-ENCS.input.rdo_code",
      "0619E.2018-01-ENCS.input.rdo_code",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "tax_identifier", profileField: "foreign_tax_number",
    ids: [
      "1701Q.2018-01-ENCS.input.foreign_tax_number",
      "1701.2018-01-ENCS.input.foreign_tax_number",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "text", profileField: "citizenship",
    ids: [
      "1701Q.2018-01-ENCS.input.citizenship",
      "1701.2018-01-ENCS.input.citizenship",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "text", profileField: "line_of_business",
    ids: [
      "1601C.2018-01-ENCS.input.line_of_business",
      "1601EQ.2018-01-ENCS.input.line_of_business",
      "0619E.2018-01-ENCS.input.line_of_business",
      "0619F.2018-01-ENCS.input.line_of_business",
      "1702RT.2018-01-ENCS.input.line_of_business",
      "1702MX.2018-01-ENCS.input.line_of_business",
      "0605.1999-07-ENCS.input.line_of_business_occupation",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "choice", profileField: "eopt_tier",
    ids: ["2550Q.2024-04-ENCS.input.eopt_taxpayer_classification"],
  },
  {
    provenance: "profile", role: "filer", valueType: "text", profileField: "registered_address",
    ids: [
      "0605.1999-07-ENCS.input.registered_address",
      "1601C.2018-01-ENCS.input.registered_address",
      "1601EQ.2018-01-ENCS.input.registered_address",
      "0619E.2018-01-ENCS.input.registered_address",
      "0619F.2018-01-ENCS.input.registered_address",
      "1701Q.2018-01-ENCS.input.registered_address",
      "1701.2018-01-ENCS.input.registered_address",
      "1702RT.2018-01-ENCS.input.registered_address",
      "1702MX.2018-01-ENCS.input.registered_address",
      "2550Q.2024-04-ENCS.input.registered_address",
      "2551Q.2018-01-ENCS.input.registered_address",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "text", profileField: "registered_name",
    ids: [
      "1702RT.2018-01-ENCS.input.registered_name",
      "1702MX.2018-01-ENCS.input.registered_name",
    ],
  },
  {
    provenance: "tax_form_profile", role: "filer", valueType: "text",
    sourceKey: "special_rate_basis",
    ids: ["1702MX.2018-01-ENCS.input.special_preferential_rate_basis"],
  },
  {
    provenance: "profile", role: "filer", valueType: "text", profileField: "taxpayer_name",
    ids: [
      "0605.1999-07-ENCS.input.taxpayer_name",
      "1601C.2018-01-ENCS.input.taxpayer_name",
      "1601EQ.2018-01-ENCS.input.taxpayer_name",
      "0619E.2018-01-ENCS.input.registered_taxpayer_name",
      "0619F.2018-01-ENCS.input.registered_taxpayer_name",
      "1701Q.2018-01-ENCS.input.taxpayer_filer_name",
      "1701.2018-01-ENCS.input.taxpayer_name",
      "2550Q.2024-04-ENCS.input.taxpayer_name",
      "2551Q.2018-01-ENCS.input.taxpayers_name",
    ],
  },
  {
    provenance: "profile", role: "filer", valueType: "tin", profileField: "tin",
    ids: [
      "0605.1999-07-ENCS.input.tin",
      "1601C.2018-01-ENCS.input.tin",
      "1601EQ.2018-01-ENCS.input.tin",
      "0619F.2018-01-ENCS.input.tin",
      "1701Q.2018-01-ENCS.input.tin",
      "1701.2018-01-ENCS.input.tin",
      "1702RT.2018-01-ENCS.input.tin",
      "1702MX.2018-01-ENCS.input.tin",
      "2550Q.2024-04-ENCS.input.tin",
      "2551Q.2018-01-ENCS.input.tin",
      "0619E.2018-01-ENCS.input.tin",
    ],
  },
  {
    provenance: "profile", role: "spouse", valueType: "rdo_code", profileField: "rdo_code",
    ids: [
      "1701Q.2018-01-ENCS.input.spouse_rdo_code",
      "1701.2018-01-ENCS.input.spouse_rdo_code",
    ],
  },
  {
    provenance: "profile", role: "spouse", valueType: "tax_identifier", profileField: "foreign_tax_number",
    ids: ["1701Q.2018-01-ENCS.input.spouse_foreign_tax_number"],
  },
  {
    provenance: "profile", role: "spouse", valueType: "text", profileField: "citizenship",
    ids: ["1701Q.2018-01-ENCS.input.spouse_citizenship"],
  },
  {
    provenance: "profile", role: "spouse", valueType: "text", profileField: "taxpayer_name",
    ids: [
      "1701Q.2018-01-ENCS.input.spouse_name",
      "1701.2018-01-ENCS.input.spouse_name",
    ],
  },
  {
    provenance: "profile", role: "spouse", valueType: "tin", profileField: "tin",
    ids: [
      "1701Q.2018-01-ENCS.input.spouse_tin",
      "1701.2018-01-ENCS.input.spouse_tin",
    ],
  },
  {
    provenance: "taxpayer_year", role: "filing", valueType: "choice",
    sourceKey: "income_tax_rate_election",
    ids: ["1701Q.2018-01-ENCS.input.income_tax_rate_election"],
  },
  {
    provenance: "tax_form_profile", role: "filer", valueType: "choice",
    sourceKey: "income_tax_rate_election",
    ids: ["2551Q.2018-01-ENCS.input.what_income_tax_rates_are_you_availing"],
  },
  {
    provenance: "transaction", role: "filing", valueType: "atc_code",
    ids: [
      "0605.1999-07-ENCS.input.atc_only_source_proven_pairs",
      "2551Q.2018-01-ENCS.input.schedule_1_line_1_percentage_tax_code",
      "2551Q.2018-01-ENCS.input.schedule_1_line_2_percentage_tax_code",
      "1601EQ.2018-01-ENCS.input.item_13_atc",
      "1601EQ.2018-01-ENCS.input.item_14_atc",
      "1601EQ.2018-01-ENCS.input.item_15_atc",
      "1601EQ.2018-01-ENCS.input.item_16_atc",
      "1601EQ.2018-01-ENCS.input.item_17_atc",
      "1601EQ.2018-01-ENCS.input.item_18_atc",
    ],
  },
  {
    provenance: "transaction", role: "filing", valueType: "boolean",
    ids: [
      "1601C.2018-01-ENCS.input.any_taxes_withheld",
      "1601EQ.2018-01-ENCS.input.any_taxes_withheld",
      "0619F.2018-01-ENCS.input.any_taxes_withheld",
      "0619F.2018-01-ENCS.input.government_withholding_agent",
      "2550Q.2024-04-ENCS.input.tax_relief",
      "2551Q.2018-01-ENCS.input.tax_relief",
      "0619E.2018-01-ENCS.input.any_taxes_withheld",
      "0619E.2018-01-ENCS.input.government_withholding_agent",
    ],
  },
  {
    provenance: "transaction", role: "filing", valueType: "choice",
    ids: [
      "0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs",
      "1701.2018-01-ENCS.input.overpayment_disposition",
      "1702RT.2018-01-ENCS.input.itemized_optional_standard_deduction",
      "2551Q.2018-01-ENCS.input.return_options",
      "2551Q.2018-01-ENCS.input.overpayment_disposition",
      "1601EQ.2018-01-ENCS.input.withholding_agent_category",
    ],
  },
  {
    provenance: "transaction", role: "filing", valueType: "money",
    ids: [
      "0605.1999-07-ENCS.input.basic_tax_deposit_advance_payment",
      "0605.1999-07-ENCS.input.surcharge_manual",
      "0605.1999-07-ENCS.input.interest_manual",
      "0605.1999-07-ENCS.input.compromise_manual",
      "1601C.2018-01-ENCS.input.statutory_minimum_wage",
      "1601C.2018-01-ENCS.input.holiday_overtime_and_night_shift_pay",
      "1601C.2018-01-ENCS.input.13th_month_pay_and_other_benefits",
      "1601C.2018-01-ENCS.input.de_minimis_benefits",
      "1601C.2018-01-ENCS.input.sss_gsis_phic_and_pag_ibig_contributions",
      "1601C.2018-01-ENCS.input.other_non_taxable_compensation",
      "1601C.2018-01-ENCS.input.schedule_adjustment",
      "0619F.2018-01-ENCS.input.final_tax_withheld_on_interest_deposits_and_trusts",
      "0619F.2018-01-ENCS.input.other_final_income_taxes_withheld",
      "1701Q.2018-01-ENCS.input.sales_revenues_receipts",
      "1701Q.2018-01-ENCS.input.cost_of_sales_services",
      "1701Q.2018-01-ENCS.input.allowable_deductions",
      "1701Q.2018-01-ENCS.input.gross_sales_receipts",
      "1701Q.2018-01-ENCS.input.less_non_operating_income",
      "1701Q.2018-01-ENCS.input.other_tax_credits_payments",
      "1701Q.2018-01-ENCS.input.amount",
      "1701.2018-01-ENCS.input.sales_revenues_receipts_fees",
      "1701.2018-01-ENCS.input.returns_allowances_and_discounts",
      "1701.2018-01-ENCS.input.cost_of_sales_services",
      "1701.2018-01-ENCS.input.allowable_deductions",
      "1701.2018-01-ENCS.input.other_taxable_income_amount",
      "1701.2018-01-ENCS.input.salaries_wages_and_benefits",
      "1701.2018-01-ENCS.input.rent_repairs_and_utilities",
      "1701.2018-01-ENCS.input.other_ordinary_deductions",
      "1701.2018-01-ENCS.input.other_tax_credit_amount",
      "1701.2018-01-ENCS.input.tax_relief_amount",
      "1701.2018-01-ENCS.input.add_non_deductible_expenses",
      "1701.2018-01-ENCS.input.less_non_taxable_income",
      "1702RT.2018-01-ENCS.input.sales_receipts_revenues_fees",
      "1702RT.2018-01-ENCS.input.returns_allowances_discounts",
      "1702RT.2018-01-ENCS.input.cost_of_sales_services",
      "1702RT.2018-01-ENCS.input.other_taxable_income",
      "1702RT.2018-01-ENCS.input.48_53_other_credits_payments",
      "1702RT.2018-01-ENCS.input.add_surcharge_interest_and_compromise",
      "1702RT.2018-01-ENCS.input.refund",
      "1702RT.2018-01-ENCS.input.carry_over_to_next_period",
      "1702MX.2018-01-ENCS.input.gross_income_subject_to_regular_rate",
      "1702MX.2018-01-ENCS.input.gross_income_subject_to_special_rate",
      "1702MX.2018-01-ENCS.input.refund",
      "1702MX.2018-01-ENCS.input.carry_over_to_next_period",
      "2550Q.2024-04-ENCS.input.vatable_sales_receipts",
      "2550Q.2024-04-ENCS.input.zero_rated_sales_receipts",
      "2550Q.2024-04-ENCS.input.exempt_sales_receipts",
      "2550Q.2024-04-ENCS.input.output_vat_adjustments",
      "2550Q.2024-04-ENCS.input.domestic_purchases_input_tax",
      "2550Q.2024-04-ENCS.input.services_rendered_by_non_residents",
      "2550Q.2024-04-ENCS.input.importation_of_goods",
      "2550Q.2024-04-ENCS.input.other_purchases",
      "2550Q.2024-04-ENCS.input.domestic_purchases_without_input_tax",
      "2550Q.2024-04-ENCS.input.exempt_importations",
      "2550Q.2024-04-ENCS.input.input_tax_directly_attributable_to_exempt_sales",
      "2550Q.2024-04-ENCS.input.input_tax_not_directly_attributable",
      "2550Q.2024-04-ENCS.input.other_tax_credit_payment",
      "2551Q.2018-01-ENCS.input.schedule_1_line_1_tax_base_taxable_amount",
      "2551Q.2018-01-ENCS.input.schedule_1_line_2_tax_base_taxable_amount",
      "2551Q.2018-01-ENCS.input.other_tax_credit_payment",
      "2551Q.2018-01-ENCS.input.surcharge_manual",
      "2551Q.2018-01-ENCS.input.interest_manual",
      "2551Q.2018-01-ENCS.input.compromise_manual",
      "0619E.2018-01-ENCS.input.amount_of_remittance",
      "1601EQ.2018-01-ENCS.input.total_tax_withheld_this_quarter",
      "1601EQ.2018-01-ENCS.input.item_13_tax_base",
      "1601EQ.2018-01-ENCS.input.item_14_tax_base",
      "1601EQ.2018-01-ENCS.input.item_15_tax_base",
      "1601EQ.2018-01-ENCS.input.item_16_tax_base",
      "1601EQ.2018-01-ENCS.input.item_17_tax_base",
      "1601EQ.2018-01-ENCS.input.item_18_tax_base",
    ],
  },
  {
    provenance: "transaction", role: "filing", valueType: "text",
    ids: [
      "1601C.2018-01-ENCS.input.tax_relief",
      "1701Q.2018-01-ENCS.input.bank_agency",
      "1701.2018-01-ENCS.input.other_taxable_income_description",
      "1701.2018-01-ENCS.input.other_tax_credit_description",
      "1701.2018-01-ENCS.input.tax_relief_special_rate",
      "1702RT.2018-01-ENCS.input.tax_relief_special_law",
      "2551Q.2018-01-ENCS.input.tax_relief_specification",
    ],
  },
  {
    provenance: "transaction", role: "payment", valueType: "choice",
    ids: [
      "0605.1999-07-ENCS.input.manner_of_payment",
      "0605.1999-07-ENCS.input.type_of_payment",
      "2550Q.2024-04-ENCS.input.payment_method",
    ],
  },
  {
    provenance: "transaction", role: "preparer", valueType: "text",
    ids: [
      "0605.1999-07-ENCS.input.taxpayer_authorized_representative",
      "2550Q.2024-04-ENCS.input.taxpayer_authorized_representative",
    ],
  },
]);

function inputFieldsFor(
  code: string,
  revision: string,
): Readonly<Record<string, InputFieldSpec>> {
  const prefix = `${code}.${revision}.input.`;
  return Object.fromEntries(
    Object.entries(explicitInputFields).filter(([id]) => id.startsWith(prefix)),
  );
}

export const editorForms: readonly EditorFormSpec[] = [
  {
    code: "0605",
    revision: "1999-07-ENCS",
    revisionLabel: "July 1999 (ENCS)",
    sourcePath: "src/pages/forms/0605.native",
    inputFields: inputFieldsFor("0605", "1999-07-ENCS"),
    expectedInputCount: 20,
    expectedTableCount: 1,
    expectedTableHeaders: [
      "Payment method",
      "Drawee bank / agency",
      "Reference number",
      "Amount",
    ],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Ownership matrix § 0605; legacy form_0605.rs:480-507 leaves ATC/tax type filing-owned",
      values: [],
    },
    profileTargetPresence: {
      "0605.1999-07-ENCS.input.zip_code": "optional",
      "0605.1999-07-ENCS.input.contact_number": "optional",
      "0605.1999-07-ENCS.input.email_address": "optional",
    },
    tableFields: paymentTable("payment"),
  },
  {
    code: "0619E",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/0619-e.native",
    inputFields: inputFieldsFor("0619E", "2018-01-ENCS"),
    expectedInputCount: 24,
    expectedTableCount: 1,
    expectedTableHeaders: ["Method", "Bank / Agency", "Reference", "Amount"],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Line of business is inherited from the Base Tax Profile; 0619E has no form-specific yearly setup",
      values: [],
    },
    profileTargetPresence: {
      "0619E.2018-01-ENCS.input.line_of_business": "optional",
      "0619E.2018-01-ENCS.input.registered_address": "optional",
      "0619E.2018-01-ENCS.input.zip_code": "optional",
      "0619E.2018-01-ENCS.input.contact_number": "optional",
      "0619E.2018-01-ENCS.input.email_address": "optional",
    },
    tableFields: paymentTable("payment"),
  },
  {
    code: "0619F",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/0619-f.native",
    inputFields: inputFieldsFor("0619F", "2018-01-ENCS"),
    expectedInputCount: 25,
    expectedTableCount: 1,
    expectedTableHeaders: ["Item", "Payment method", "Reference", "Amount"],
    roles: ["filer", "filing", "payment", "preparer", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Line of business is inherited from the Base Tax Profile; 0619F has no form-specific yearly setup",
      values: [],
    },
    profileTargetPresence: {
      "0619F.2018-01-ENCS.input.line_of_business": "optional",
      "0619F.2018-01-ENCS.input.registered_address": "optional",
      "0619F.2018-01-ENCS.input.zip_code": "optional",
      "0619F.2018-01-ENCS.input.contact_number": "optional",
      "0619F.2018-01-ENCS.input.email_address": "optional",
    },
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
    inputFields: inputFieldsFor("1601C", "2018-01-ENCS"),
    expectedInputCount: 30,
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
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Line of business is inherited from the Base Tax Profile; 1601C has no form-specific yearly setup",
      values: [],
    },
    profileTargetPresence: {
      "1601C.2018-01-ENCS.input.zip_code": "optional",
      "1601C.2018-01-ENCS.input.email_address": "optional",
    },
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
    code: "1601EQ",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1601-eq.native",
    inputFields: inputFieldsFor("1601EQ", "2018-01-ENCS"),
    expectedInputCount: 46,
    expectedTableCount: 0,
    expectedTableHeaders: [],
    roles: ["filer", "filing", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Identity, filing choices, unbound ATC rows 13-18, and remittance totals; save stays disabled until an exact 1601EQ path exists",
      values: [],
    },
    profileTargetPresence: {
      "1601EQ.2018-01-ENCS.input.zip_code": "optional",
      "1601EQ.2018-01-ENCS.input.email_address": "optional",
    },
    tableFields: [],
  },
  {
    code: "1701",
    revision: "2018-01-ENCS",
    revisionLabel: "January 2018 (ENCS)",
    sourcePath: "src/pages/forms/1701.native",
    inputFields: inputFieldsFor("1701", "2018-01-ENCS"),
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
    consumedTaxpayerYearSettings: [
      "income_tax_rate_election",
      "deduction_method",
    ],
    taxFormProfile: {
      mode: "setup",
      specRevision: 2,
      sourceEvidence: "Ownership matrix § 1701",
      values: [
        supportedSetupValue(
          "spouse_profile_id",
          "src/pages/forms/1701.native:21-23 declares the optional distinct spouse role",
        ),
      ],
    },
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
    inputFields: inputFieldsFor("1701Q", "2018-01-ENCS"),
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
    consumedTaxpayerYearSettings: [
      "income_tax_rate_election",
      "deduction_method",
    ],
    taxFormProfile: {
      mode: "setup",
      specRevision: 2,
      sourceEvidence: "Ownership matrix § 1701Q",
      values: [
        supportedSetupValue(
          "spouse_profile_id",
          "src/pages/forms/1701q.native:113-127 declares the optional distinct spouse role",
        ),
      ],
    },
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
    inputFields: inputFieldsFor("1702MX", "2018-01-ENCS"),
    expectedInputCount: 32,
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
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "setup",
      specRevision: 1,
      sourceEvidence: "Ownership matrix § 1702MX",
      values: [
        supportedSetupValue(
          "special_rate_basis",
          "src/pages/forms/1702-mx.native:11 records an optional form-specific special/preferential-rate basis",
        ),
      ],
    },
    profileTargetPresence: {
      "1702MX.2018-01-ENCS.input.zip_code": "optional",
      "1702MX.2018-01-ENCS.input.contact_number": "optional",
      "1702MX.2018-01-ENCS.input.email_address": "optional",
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
    inputFields: inputFieldsFor("1702RT", "2018-01-ENCS"),
    expectedInputCount: 36,
    expectedTableCount: 1,
    expectedTableHeaders: ["Schedule", "Official rows", "Attachment status"],
    roles: ["filer", "filing", "attachment", "evidence", "system"],
    profileRoles: [exactlyOneFiler(corporateReturnSubjectKinds)],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Line of business is inherited from the Base Tax Profile; 1702RT has no form-specific yearly setup",
      values: [],
    },
    profileTargetPresence: {
      "1702RT.2018-01-ENCS.input.zip_code": "optional",
      "1702RT.2018-01-ENCS.input.contact_number": "optional",
      "1702RT.2018-01-ENCS.input.email_address": "optional",
    },
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
    inputFields: inputFieldsFor("2550Q", "2024-04-ENCS"),
    expectedInputCount: 38,
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
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "no_setup",
      specRevision: 1,
      sourceEvidence:
        "Ownership matrix § 2550Q finds no genuine form-specific annual setup value",
      values: [],
    },
    profileTargetPresence: {
      "2550Q.2024-04-ENCS.input.registered_address": "optional",
      "2550Q.2024-04-ENCS.input.zip_code": "optional",
      "2550Q.2024-04-ENCS.input.contact_number": "optional",
      "2550Q.2024-04-ENCS.input.email_address": "optional",
    },
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
    inputFields: inputFieldsFor("2551Q", "2018-01-ENCS"),
    expectedInputCount: 35,
    expectedTableCount: 1,
    expectedTableHeaders: ["ATC", "Tax Base / Taxable Amount", "Tax Rate", "Percentage Tax Due"],
    roles: ["filer", "filing", "payment", "evidence", "system"],
    profileRoles: [exactlyOneFiler()],
    consumedTaxpayerYearSettings: [],
    taxFormProfile: {
      mode: "setup",
      specRevision: 2,
      sourceEvidence:
        "2551Q January 2018 ENCS Item 13 is a form-specific yearly choice projected only on the initial applicable quarter",
      values: [
        supportedSetupValue(
          "income_tax_rate_election",
          "2551Q January 2018 ENCS Item 13 asks the taxpayer to select graduated or 8% income tax rates",
        ),
      ],
    },
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

export type RegistryCode = (typeof registryCodes)[number];

/**
 * Build-time display authority for the 51-code catalog.
 *
 * Titles are form-specific rather than inherited from grouped calendar rules,
 * while categories use the closed vocabulary above so UI filters cannot drift
 * into spelling variants.
 */
export const formDisplayMetadataByCode = {
  "0605": {
    displayTitle: "Payment Form",
    taxCategory: "payment",
  },
  "1905": {
    displayTitle:
      "Application for Registration Information Update / Correction / Cancellation",
    taxCategory: "registration",
  },
  "1600": {
    displayTitle:
      "Monthly Remittance Return of VAT and Other Percentage Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1600PT": {
    displayTitle: "Monthly Remittance Return of Other Percentage Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1600VT": {
    displayTitle: "Monthly Remittance Return of Value-Added Tax Withheld",
    taxCategory: "withholding_tax",
  },
  "1600WP": {
    displayTitle: "Remittance Return of Percentage Tax on Winnings and Prizes",
    taxCategory: "withholding_tax",
  },
  "1601C": {
    displayTitle:
      "Monthly Remittance Return of Income Taxes Withheld on Compensation",
    taxCategory: "withholding_tax",
  },
  "1601E": {
    displayTitle:
      "Monthly Remittance Return of Creditable Income Taxes Withheld (Expanded)",
    taxCategory: "withholding_tax",
  },
  "1601F": {
    displayTitle: "Monthly Remittance Return of Final Income Tax Withheld",
    taxCategory: "withholding_tax",
  },
  "0619F": {
    displayTitle: "Monthly Remittance Form for Final Income Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1601FQ": {
    displayTitle: "Quarterly Remittance Return of Final Income Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1602": {
    displayTitle: "Monthly Remittance Return of Final Income Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1602Q": {
    displayTitle:
      "Quarterly Remittance Return of Final Taxes Withheld on Interest Paid on Deposits and Yield on Deposit Substitutes / Trusts / Etc.",
    taxCategory: "withholding_tax",
  },
  "1603": {
    displayTitle: "Quarterly Remittance Return of Final Income Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "1603Q": {
    displayTitle:
      "Quarterly Remittance Return of Final Income Taxes Withheld on Fringe Benefits Paid to Employees Other Than Rank and File",
    taxCategory: "withholding_tax",
  },
  "1604CF": {
    displayTitle: "Annual Information Return of Income Taxes Withheld on Compensation",
    taxCategory: "withholding_tax",
  },
  "1604E": {
    displayTitle: "Annual Information Return of Creditable Income Taxes Withheld",
    taxCategory: "withholding_tax",
  },
  "0620": {
    displayTitle:
      "Monthly Remittance Form of Tax Withheld on the Amount Withdrawn from the Decedent's Deposit Account",
    taxCategory: "withholding_tax",
  },
  "2316": {
    displayTitle: "Certificate of Compensation Payment / Tax Withheld",
    taxCategory: "withholding_tax",
  },
  "1700": {
    displayTitle: "Annual Income Tax Return (Purely Compensation)",
    taxCategory: "income_tax",
  },
  "1701Q": {
    displayTitle: "Quarterly Income Tax Return for Individuals, Estates and Trusts",
    taxCategory: "income_tax",
  },
  "1701": {
    displayTitle: "Annual Income Tax Return for Individuals, Estates and Trusts",
    taxCategory: "income_tax",
  },
  "1701A": {
    displayTitle: "Annual Income Tax Return (8% / OSD)",
    taxCategory: "income_tax",
  },
  "1702Q": {
    displayTitle:
      "Quarterly Income Tax Return for Corporations, Partnerships and Cooperatives",
    taxCategory: "income_tax",
  },
  "1702": {
    displayTitle:
      "Annual Income Tax Return for Corporations, Partnerships and Cooperatives",
    taxCategory: "income_tax",
  },
  "1702RT": {
    displayTitle: "Annual Income Tax Return — Regular Taxable",
    taxCategory: "income_tax",
  },
  "1702EX": {
    displayTitle: "Annual Income Tax Return — Tax-Exempt",
    taxCategory: "income_tax",
  },
  "1702MX": {
    displayTitle: "Annual Income Tax Return — Mixed Income",
    taxCategory: "income_tax",
  },
  "1704": {
    displayTitle: "Improperly Accumulated Earnings Tax Return",
    taxCategory: "income_tax",
  },
  "2550M": {
    displayTitle: "Monthly Value-Added Tax Declaration",
    taxCategory: "value_added_tax",
  },
  "2550Q": {
    displayTitle: "Quarterly Value-Added Tax Return",
    taxCategory: "value_added_tax",
  },
  "2551Q": {
    displayTitle: "Quarterly Percentage Tax Return",
    taxCategory: "percentage_tax",
  },
  "2551M": {
    displayTitle: "Monthly Percentage Tax Return",
    taxCategory: "percentage_tax",
  },
  "2552": {
    displayTitle: "Percentage Tax Return on Transactions Involving Shares of Stock",
    taxCategory: "percentage_tax",
  },
  "2553": {
    displayTitle: "Percentage Tax Payable Under Special Laws",
    taxCategory: "percentage_tax",
  },
  "2000": {
    displayTitle: "Documentary Stamp Tax Declaration/Return",
    taxCategory: "documentary_stamp_tax",
  },
  "2000OT": {
    displayTitle:
      "Documentary Stamp Tax Declaration/Return (One-Time Transactions)",
    taxCategory: "documentary_stamp_tax",
  },
  "2200A": {
    displayTitle: "Excise Tax Return for Alcohol Products",
    taxCategory: "excise_tax",
  },
  "2200AN": {
    displayTitle: "Excise Tax Return for Automobiles and Non-Essential Goods",
    taxCategory: "excise_tax",
  },
  "2200M": {
    displayTitle: "Excise Tax Return for Mineral Products",
    taxCategory: "excise_tax",
  },
  "2200P": {
    displayTitle: "Excise Tax Return for Petroleum Products",
    taxCategory: "excise_tax",
  },
  "2200T": {
    displayTitle: "Excise Tax Return for Tobacco Products",
    taxCategory: "excise_tax",
  },
  "2200C": {
    displayTitle: "Excise Tax Return for Coal and Coke",
    taxCategory: "excise_tax",
  },
  "2200S": {
    displayTitle: "Excise Tax Return for Sweetened Beverages",
    taxCategory: "excise_tax",
  },
  "0619E": {
    displayTitle:
      "Monthly Remittance Form for Creditable Income Taxes Withheld (Expanded)",
    taxCategory: "withholding_tax",
  },
  "1601EQ": {
    displayTitle:
      "Quarterly Remittance Return of Creditable Income Taxes Withheld (Expanded)",
    taxCategory: "withholding_tax",
  },
  "1701MS": {
    displayTitle: "Annual Income Tax Return for Micro and Small Taxpayers",
    taxCategory: "income_tax",
  },
  "1706": {
    displayTitle: "Capital Gains Tax Return (Real Properties)",
    taxCategory: "capital_gains_tax",
  },
  "1707A": {
    displayTitle: "Annual Capital Gains Tax Return (Shares of Stock Not Traded)",
    taxCategory: "capital_gains_tax",
  },
  "1800": {
    displayTitle: "Donor's Tax Return",
    taxCategory: "estate_and_donors_tax",
  },
  "1801": {
    displayTitle: "Estate Tax Return",
    taxCategory: "estate_and_donors_tax",
  },
} as const satisfies Readonly<Record<RegistryCode, FormDisplayMetadata>>;

export function formDisplayMetadata(code: string): FormDisplayMetadata {
  const metadata = (
    formDisplayMetadataByCode as Readonly<
      Record<string, FormDisplayMetadata | undefined>
    >
  )[code];
  if (!metadata) throw new Error(`Missing display metadata for ${code}`);
  return metadata;
}

/** Build-time filing cadence authority for the 51-code catalog. */
export const filingCadenceByCode: Readonly<Record<string, FilingCadence>> = {
  "0605": "on_demand",
  "1905": "on_demand",
  "1600": "monthly",
  "1600PT": "monthly",
  "1600VT": "monthly",
  "1600WP": "monthly",
  "1601C": "monthly",
  "1601E": "monthly",
  "1601F": "monthly",
  "0619F": "monthly",
  "1601FQ": "quarterly",
  "1602": "monthly",
  "1602Q": "quarterly",
  "1603": "quarterly",
  "1603Q": "quarterly",
  "1604CF": "annual",
  "1604E": "annual",
  "0620": "monthly",
  "2316": "annual",
  "1700": "annual",
  "1701Q": "quarterly",
  "1701": "annual",
  "1701A": "annual",
  "1702Q": "quarterly",
  "1702": "annual",
  "1702RT": "annual",
  "1702EX": "annual",
  "1702MX": "annual",
  "1704": "annual",
  "2550M": "monthly",
  "2550Q": "quarterly",
  "2551Q": "quarterly",
  "2551M": "monthly",
  "2552": "on_demand",
  "2553": "on_demand",
  "2000": "on_demand",
  "2000OT": "on_demand",
  "2200A": "monthly",
  "2200AN": "monthly",
  "2200M": "monthly",
  "2200P": "monthly",
  "2200T": "monthly",
  "2200C": "monthly",
  "2200S": "monthly",
  "0619E": "monthly",
  "1601EQ": "quarterly",
  "1701MS": "annual",
  "1706": "on_demand",
  "1707A": "on_demand",
  "1800": "on_demand",
  "1801": "on_demand",
};

export function filingPeriodPolicy(code: string): FilingPeriodPolicy {
  const cadence = filingCadenceByCode[code];
  if (!cadence) throw new Error(`Missing filing cadence for ${code}`);
  switch (cadence) {
    case "monthly":
      return { cadence, minPeriod: 1, maxPeriod: 12 };
    case "quarterly":
      return {
        cadence,
        minPeriod: 1,
        maxPeriod: code === "1701Q" ? 3 : 4,
      };
    case "annual":
    case "on_demand":
      return { cadence, minPeriod: null, maxPeriod: null };
  }
}
