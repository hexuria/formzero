# Exact-PDF field ownership manifests

These files are the checked-in, human-approved boundary between an official BIR
PDF revision and the application's canonical data owners. They are evidence and
review artifacts. They are **not** an ownership inference engine.

## Required workflow

1. Pin one exact PDF revision by filename, revision key, page count, and SHA-256.
2. Inspect every page visually and with layout-preserving text extraction.
3. Record every relevant official item id and label, canonical semantic key,
   persistence owner, applicability rule, and exact page/region evidence.
4. Record material absences explicitly. An absent field must not be projected
   merely because another revision or the Base Tax Profile contains it.
5. Obtain human approval and set `approval.status` to `human_approved`.
6. Run `npm run check:field-ownership-manifests`.
7. Publish a mapping into the runtime catalog only through a separate, explicit
   human-reviewed source change.

The checker validates schema, pinned local hashes when the source PDFs are
available, exact pilot invariants, and the manual-publication guardrail. It does
not write generated files or mutate `catalog.ts`.

## Owner vocabulary

- `base`: effective-dated taxpayer identity and contact facts
- `registration`: registration facts and bindings, including EOPT tier
- `annual`: taxpayer-and-tax-year values shared by forms
- `form-specific`: a genuine form/revision/year profile value
- `filing-context`: filing route and period identity
- `transaction`: one return's declarations, schedules, payments, or evidence
- `derived`: values calculated from owned source values

## Pilot decisions

- 2551Q January 2018 ENCS Item 13 is `annual`, stored once per taxpayer and tax
  year, and projected onto the official return only for the initial applicable
  quarter. Later quarters may display the inherited selection read-only.
- 2550Q April 2024 ENCS Item 13 is the registration-owned EOPT tier.
- 2550Q April 2024 ENCS contains no Line of Business field on either page. The
  manifest therefore forbids projecting Base Tax Profile Line of Business into
  that exact revision.
