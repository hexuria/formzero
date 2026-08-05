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

- `base`: effective-dated taxpayer identity, contact, accounting, EOPT, and
  primary Line of Business facts
- `form-specific`: a genuine form/revision/year profile value
- `filing-context`: filing route and period identity
- `transaction`: one return's declarations, schedules, payments, evidence, and
  values calculated from that return's owned source values

## Pilot decisions

- 2551Q January 2018 ENCS Item 13 is `form-specific`, stored once per taxpayer,
  exact form revision, and tax year. It is projected onto the official return
  only for the initial applicable quarter; later quarters display it read-only.
- 2550Q April 2024 ENCS Item 13 is the Base Tax Profile EOPT tier.
- 2550Q April 2024 ENCS contains no Line of Business field on either page. The
  manifest therefore forbids projecting Base Tax Profile Line of Business into
  that exact revision.
