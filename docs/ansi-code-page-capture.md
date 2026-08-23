# Windows capture: ANSI code-page behaviour of `CreateTextFile`

## Why this exists

Two readiness flags are false across **every** exact form package, for one shared
reason:

- `editable_serializer_exact`
- `final_plaintext_serializer_exact`

`src/form_engine/forms/form_1701q_2018/document.zig:14` states it:

> `Scripting.FileSystemObject.CreateTextFile` still uses the machine ANSI code page.
> That code page is not an invariant of the form package, so this module deliberately
> accepts only the code-page-independent ASCII byte subset. The public readiness fact
> remains false until **paired official captures** qualify the complete encoding
> behaviour.

So the serializers reject any byte above `0x7F` (`validateAscii`, line 400) rather than
guess how it is written. That is the correct conservative choice, and it is the only
thing standing between roughly 6,200 lines of already-written 1701Q codec work — plus
1601C's `document.zig`, `editable_codec.zig` and `final_copy_codec.zig` — and those two
flags.

This capture answers exactly one question: **what bytes does `CreateTextFile` write for
non-ASCII input, under a known code page?**

## What is already established (do not re-derive)

- The separator is `\t\r\n` + twelve spaces. `innerHTML` normalizes the source LF to
  CRLF; a controlled MSHTML observation established this and it is inherited by 1601C.
- `TextStream.Write` adds no newline of its own.
- Envelope, tails and occurrence delimiters are pinned and identical between 1701Q and
  1601C.

None of that needs re-checking. This is only about bytes above `0x7F`.

## Where a non-ASCII byte can actually reach the file

In 1601C, `escape()` is applied to exactly four controls — taxpayer name, line of
business, and both address lines — which percent-encode to ASCII on the wire. **Every
other text control is written raw**, so those are the ones that can carry a high byte
into `CreateTextFile`.

Good capture targets, all raw and all plausibly non-ASCII in real use:

| control | why |
|---|---|
| `txtEmail` | unprefixed id, written raw |
| `frm1601c:txtTelNum` | raw |
| `frm1601c:txtZipCode` | raw |

The escaped four are still worth one capture each, to confirm `escape()` really does
keep them ASCII rather than merely usually doing so.

## Procedure

Run on a Windows machine with eBIRForms 7.9.6 installed. Record the code page first —
everything below is meaningless without it.

1. **Record the environment.**
   ```
   chcp
   reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage" /v ACP
   ```
   Capture both verbatim. The ACP value is the one that matters.

2. **For each case below**: open 1601C, enter the value in the named control, fill the
   minimum needed to save (month, year, all four TIN parts — see
   `workflow.saveButtonEnabled`), save an editable copy, then capture the file as
   **raw bytes**, not as text:
   ```
   certutil -encodehex "<saved>.xml" out.hex
   ```

3. **Cases.** Each is one save and one hex dump.

   | # | control | value to enter | establishes |
   |---|---|---|---|
   | 1 | `txtEmail` | `josé@example.ph` | single Latin-1 char, raw path |
   | 2 | `txtEmail` | `Ω@example.ph` | char outside Latin-1 |
   | 3 | `txtTelNum` | `02‑8888` (U+2011 non-breaking hyphen) | punctuation substitution |
   | 4 | `txtTaxpayerName` | `JOSÉ DELA CRUZ` | confirms `escape()` yields ASCII |
   | 5 | `txtAddress` | `PEÑAFRANCIA ST` | escaped path, and the address fusion |
   | 6 | `txtEmail` | `a` then `é` appended | isolates the single changed byte |

4. **Pair each capture** with the exact string entered, as UTF-8, so the mapping is
   unambiguous. That pairing is what "paired official captures" means — an input and its
   resulting bytes, not a file alone.

## What a good result looks like

For each case, one of:

- **round-trips**: the high byte appears as a single ANSI byte in the named code page
- **substituted**: it appears as `?` or another replacement — lossy, and that is itself
  the finding
- **expanded**: it appears as multiple bytes

Any of those is a usable answer. The current position is that we do not know which.

## What to do with the result

Bring back the hex dumps and the `chcp` / ACP values. From those I can:

1. Pin the observed mapping in `document.zig` beside the existing MSHTML note, scoped to
   the captured code page and **not** generalised beyond it.
2. Widen `validateAscii` to the qualified range, or keep it and record precisely why the
   full range still cannot be claimed.
3. Flip `editable_serializer_exact` and `final_plaintext_serializer_exact` if — and only
   if — the captures support it, for 1701Q and 1601C together.

If the result is "substituted", the flags likely **stay false** and we record that the
format is lossy for non-ASCII input. That is a legitimate outcome, not a failed trip.

## What this does not cover

Submit and transport. `transport_enabled` is barred separately by
`EvidenceReadiness.validateOfflineBoundary` (`src/form_engine/evidence.zig:80`) and is
not affected by anything here.
