# Submit path findings, offline eBIRForms 7.9.6

Recorded from the verified package while pinning 1601C's transaction surface. Nothing
here is enabled in this repository: `transport_enabled` is false for every form and
`EvidenceReadiness.validateOfflineBoundary` rejects it at nine call sites.

Literal credential values are **not** reproduced. Line numbers are given so anyone with
the package can read them directly.

## 1. Hardcoded credentials in the upload login

`forms/BIR-Form1601Cv2018.hta:4534` builds a login URL with a `loginName` and `password`
embedded as **query parameters**, then issues it as a `GET` against the live host
`ebirforms.bir.gov.ph:443`.

The developer's own comment sits immediately above it:

> username/password should not be hard-coded here. It should verify first if there's an
> IAF session.

**77 of the shipped form HTAs contain the same construction.** It is a package-wide
pattern, not a single form's slip.

Credentials in a query string are logged by servers, proxies and browser history as a
matter of course, so they are exposed to anything on that path regardless of TLS.

## 2. Return content travels in the URI

`uploadXMLFile` (line 4623) chunks the saved return into 1,000-character pieces and
places each chunk in the query string of a `rest/api/create2?...&content=<chunk>`
request.

The request is `POST`, but the payload is in the URI rather than the body, so the same
logging exposure applies — and the payload is the taxpayer's return, including the TIN.

A commented-out `GET` variant sits directly above the live `POST`, so the transport was
changed without moving the payload out of the URI.

## 3. `uploadMe` is defined twice

Lines 4528 and 4532 both define `uploadMe`. The later declaration wins, so the version
that runs is the one performing the hardcoded login. The earlier one, which simply saves
and opens the admin screen, is unreachable.

## 4. Saved files are plaintext under an encrypted-sounding name

Pinned separately in `final_copy_codec_crypto.zig`. `encrypt` is complete and functional
— `js/aes.js` and `aesPW` both resolve — but every call site is commented out, so
returns are written as plaintext into `IAF_RDO_Copy/` under a filename that embeds the
TIN.

## Bearing on this repository

These are reasons the offline boundary is worth keeping, not a to-do list.

Enabling `transport_enabled` would make the path in items 1 and 2 live. That is a
system-wide change — the guard is enforced in `tax_profile/store.zig`,
`form_engine/draft.zig` and every `EvidenceManifest.validate()` — and would need its own
design, including what to do about the credentials and the URI-borne payload.

If these are ever reported upstream to BIR, this file is the summary; the package itself
is the evidence.
