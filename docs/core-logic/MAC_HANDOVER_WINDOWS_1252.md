# Mac handover: 1701Q Windows-1252 serializers

Windows VM work for the ANSI/`CreateTextFile` question is done.
Continue on macOS. Do not reopen the encoding decision.

## Pull this work

The pin lives on branch `exact/1701q-windows-1252`, not on `main` until
the PR merges.

```bash
git fetch origin
git checkout exact/1701q-windows-1252
git pull
```

Throwaway capture scripts and XML under `%TEMP%\ansi-capture-1601c` are
not in git. Leave them on the VM.

## Decision (closed)

Philippine offline eBIRForms 7.9.6.1 `CreateTextFile` uses the machine
ACP. On the capture VM that was **Windows-1252**
(`HKLM\SYSTEM\CurrentControlSet\Control\Nls\CodePage\ACP = 1252`).
OEM `chcp` 437 is unrelated.

Exact serializers therefore:

- keep live control values as UTF-8
- encode **raw** on-disk values as Windows-1252 (`é` → `0xE9`, `É` → `0xC9`,
  `Ñ` → `0xD1`)
- keep JS `escape()` fields as ASCII (`JOS%C9`, `PE%D1…`)
- **fail closed** on scalars outside 1252 (`Ω`, U+2011, peso U+20B1)
- do **not** clone Windows best-fit (`Ω` → `O`, U+2011 → `-`)

The 1601C Save of `é` that landed as `0xC9` is the form/COM storing `É`,
not a mapping of U+00E9 to `0xC9`. Encode U+00E9 as `0xE9`.

`codec_version` stays `null`. Calculation, validation, encrypt, decrypt,
persistence, UI, transport stay false. Artifacts stay **candidate**.

## What landed

| Path | Change |
| --- | --- |
| `src/form_engine/windows_1252.zig` | 1252 encode/decode, fail-closed unmapped |
| `…/form_1701q_2018/document.zig` | raw values may be `0x80–0xFF`; `encodeRawUtf8Alloc` |
| `…/editable_codec.zig` | raw emission through 1252 |
| `…/final_copy_codec.zig` | same for Final Copy plaintext |
| `…/transaction.zig` | accept 1252 UTF-8; `maxlength` is codepoints |
| `…/profile_mapping.zig` | same; address split by codepoints |
| `…/evidence.zig` | `editable_serializer_exact` and `final_plaintext_serializer_exact` true |
| `src/tax_profile/store.zig` | stored exact values may be `0x80–0xFF` |

Keys stay ASCII. `<`, C0, and DEL still fail.

## What to do on Mac

1. Run the normal macOS quality gate (`zig build test` / CI). GitHub CI
   is already macOS. Treat Windows `dirSetPermissionsWindows` /
   registration-fixture crashes as host bugs, not this pin.
2. Next 1701Q work is **`calculation_reconciled`**, then
   **`validation_reconciled`**. Do that from the already-extracted HTA/JS
   in-repo. You do not need live eBIRForms for that.
3. Leave serializer flags true. Do not flip calc/validation/encrypt
   without their own gates.
4. Do not re-run the ACP capture and do not “fix” `é` to `0xC9`.

`plaintextCodecsReady()` stays false until calc **and** validation are
also true. `expectedExactness` still returns `.candidate` while
`codec_version` is null.

## When Windows is needed again

Not for this pin. Bring the VM back only for:

- a new live eBIRForms XML/GUI capture (next form, or a new official Save
  / Final Copy pair)
- the private 67-vector encrypt KAT / pinned Windows zlib 1.2.12
- a Windows ARM64 package smoke
