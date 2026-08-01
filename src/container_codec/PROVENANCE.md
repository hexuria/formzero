# Legacy container codec provenance

Status: clean-room decrypt-only candidate; private-corpus qualification absent.

This directory was authored on 2026-07-30 from the project’s value-free
behavioral requirements:

- `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md`, section 7;
- the separately frozen payload-research artifact-stage, container-algorithm,
  safety, and known-answer findings; and
- Zig 0.16 standard-library cryptography, hashing, compression, and UTF-8 APIs.

No rebuilt/FSL implementation source was copied into this module. The module
does not contain an outbound encryption operation. It also contains no protocol
secret, raw or decrypted evidence, taxpayer value, original artifact filename,
endpoint, credential, or logging path.

The checked test vectors are synthetic and use fixture-only key material. They
were generated independently with Node 24.14.0 standard APIs: SHA-256,
AES-256-ECB with padding disabled for the documented block primitive, and
`zlib.deflateSync` at level 9. The vectors cover full cipher blocks, partial
tails, UTF-8 rejection, checksum damage, and trailing compressed data. They do
not count toward the protected 67-vector qualification gate.

`qualificationSummary()` must remain fail-closed until a separately authorized
Windows ARM64 run binds all 67 decrypt answers and all 67 exact ciphertext
answers to the production sources, build inputs, and shipping binary. Missing,
skipped, reconstructed, or synthetic fixtures are zero verified vectors.
