# Tax-profile documentation

This directory contains three different kinds of material: current implementation
contracts, the proposed TIN/branch target architecture, and historical design or
audit evidence. A document being present here does not mean its behavior is
implemented or legally authoritative.

## Start here

1. Read the [canonical domain context](../../CONTEXT.md) for shared terminology.
2. Read the [TIN, branch-code, and multi-branch filing guide](TIN_BRANCH_PROFILE_AND_FILING_GUIDE_2026-08-07.md)
   for regulatory findings, source quality, and unresolved evidence gaps.
3. Read the [revised implementation plan](TIN_BRANCH_IMPLEMENTATION_PLAN_2026-08-07.md)
   for the proposed target model, migration order, stop conditions, and acceptance
   gates.
4. Read the [current tax-profile architecture](ARCHITECTURE.md) and
   [field-ownership matrix](FORM_PROFILE_OWNERSHIP_MATRIX_2026-08-04.md) when
   checking what the Native/Zig application currently implements.

## Authority and status

| Document group | Status | Use it for |
| --- | --- | --- |
| `CONTEXT.md`, TIN/branch guide, revised TIN/branch plan | Proposed target and research authority as of 2026-08-07 | Taxpayer versus Registration Unit terminology, Branch Code evidence, Filing Unit and Return Coverage, migration design, and unresolved policy work |
| `ARCHITECTURE.md`, ownership matrix, `IMPLEMENTATION_PLAN.md` | Current implementation contract or implementation history | Existing profile projection, Forms Set persistence, editor bindings, snapshots, and verification gates |
| Tax Form Library/COR architecture | Mixed: implemented Forms Set baseline plus follow-up design | Current library behavior and still-proposed COR-assisted setup, subject to the TIN/branch clarification below |
| Dated audit, UX specification, Fable prompt, and superseded execution plan | Historical evidence | Reconstructing earlier decisions, screenshots, defects, and rejected or superseded models |

When documents conflict:

1. Current official BIR registration evidence, issuance, exact form revision, and
   filing period control the tax decision.
2. The 2026-08-07 guide controls regulatory conclusions and evidence gaps; the
   revised plan controls the proposed TIN/branch implementation direction.
3. Current architecture documents remain the source for what the application
   actually does until a plan milestone is implemented and verified.
4. Historical documents never override a current document merely because they
   contain more implementation detail.

## Critical distinctions

- One Taxpayer owns one nine-digit TIN Root. Head office and branches are
  Registration Units under that taxpayer, not independent taxpayer profiles.
- `00000` is the normalized head-office candidate, but a new unit remains
  pending evidence and cannot file until registration evidence confirms it.
- The UI may suggest `00001` or another unused code; it does not assign the BIR
  Branch Code.
- Forms Set is a user workspace preference. It is not Tax-Type Registration
  evidence and cannot create, suppress, or prove a Filing Obligation.
- Form catalog presence, an enabled editor, preview fidelity, and legal
  fileability are separate states.
- Source Unit, Filing Unit, Return Coverage, filing venue, deadline rules, and
  artifact representation are separate policy dimensions.

## Change boundary

The 2026-08-07 documents are documentation only. They do not change the current
schema, migrate existing profiles, enable a form, or authorize a filing. Any
implementation must follow the revised plan's evidence inventory, migration
decision ledger, write-frozen cutover, rollback, and verification gates.
