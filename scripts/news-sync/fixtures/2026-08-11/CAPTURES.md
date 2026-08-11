# Live-source captures — 2026-08-11 (Asia/Manila)

Point-in-time captures of the public BIR sources that the news-sync pipeline
consumes. All content here is public government data. Captured with plain
`curl` from a residential macOS host; no session cookies were required.

## Required request headers (verified working)

Every `bir-cms-ws.bir.gov.ph` request MUST send both headers below or the API
returns `403 {"error":"forbidden"}`. No other auth exists. A normal browser
User-Agent is recommended but was not required:

```
client-website-id: 2
origin: https://www.bir.gov.ph
```

These values come from the site's own JS bundle
(`/_next/static/chunks/247-f0dc8044ae52499b.js`, webpack module `5886`), which
builds `{"client-website-id":"2", origin:"https://www.bir.gov.ph"}` and
resolves every path against `https://bir-cms-ws.bir.gov.ph`.

## Files

| File | Source URL | Notes |
| --- | --- | --- |
| `cms-template-9-new-issuances.json` | `https://bir-cms-ws.bir.gov.ph/api/pub/templates/9/datasets?per_page=3000&sort%5Bkeyword_field_1%5D=asc` | Full response. One dataset, `content.Issuance` = HTML blob of the homepage "What's New → New Issuances" tab (RMC 89-2026 … RMO 17-2026, `more` anchors → bir-cdn PDF URLs). No dates in this blob. |
| `cms-template-3752-rmc-archive-2026-excerpt.json` | `https://bir-cms-ws.bir.gov.ph/api/pub/templates/3752/datasets?per_page=3000` | Trimmed: `content.Content` table cut to header + first 6 rows (live capture was 112,942 bytes, 90 `<tr>` rows). Columns: NO. OF ISSUANCE / SUBJECT (with `Full Text` anchor) / DATE OF ISSUE. |
| `cms-template-3753-rmo-archive-2026-excerpt.json` | `https://bir-cms-ws.bir.gov.ph/api/pub/templates/3753/datasets?per_page=3000` | 2026 Revenue Memorandum Orders. Trimmed the same way: header + first 6 of 20 live rows. Same three columns; note its header row uses `<td>`, not `<th>`. Dates RMO 19/18-2026 = July 23, 2026 and RMO 17-2026 = July 8, 2026. |
| `cms-template-3754-rr-archive-2026-excerpt.json` | `https://bir-cms-ws.bir.gov.ph/api/pub/templates/3754/datasets?per_page=3000` | 2026 Revenue Regulations. Trimmed the same way; the live table had 5 rows. Numbers print single-digit (`RR No. 4-2026`) and zero-pad into `bir:rr:2026:004`. |
| `page-2026-revenue-memorandum-orders-excerpt.html` | `https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders` | 313-byte verbatim excerpt of the served HTML: the one `<script>self.__next_f.push(...)` element carrying the template-id marker, kept **with its backslash escaping intact** so `extractYearTemplateId` has offline coverage against the real page (see the discovery trail below). |
| `rmc-89-2026-pdftotext-layout.txt` | `pdftotext -layout` of the PDF below | The PDF ships a machine-OCR text layer. OCR noise is real and must be handled (see samples below). |

## RMC No. 89-2026 PDF (not committed — 1.9 MB binary)

- URL: `https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf`
  (the archive/widget HTML carries the unencoded form `.../RMC No. 89-2026_redacted.pdf`)
- Size: 1,970,851 bytes; PDF 1.7; SHA-256
  `59bba7e9a114cbf7714903fa06513d00fb8113083ecba96dfa01f138cc5134e9`
- 6 pages: p1–2 affected-areas/RDO table, p3–5 deadline table
  (`BIR Forms/Returns | Due Date | Extended Due Date`), p5–6 closing + signature.
- Contains DCTDecode page scans PLUS an embedded OCR text layer, so
  `pdftotext` works without tesseract on this document.

## Observed OCR-noise samples (from the committed layout text)

| OCR output | Actual value |
| --- | --- |
| `A]ugttst 17,2026` | August 17, 2026 |
| `Aueust 17. 2026` | August 17, 2026 (body paragraph) |
| `RDO No. 4l - Mandaluyong City` | RDO No. 41 |
| `RDONo.T- Abra` | RDO No. 7 |
| `RDONo. l0- Mountain Province` | RDO No. 10 |
| `RDO No. l7A - South Tarlac` | RDO No. 17A |
| `RDO No. 2lB - South Pampansa` | RDO No. 21B — South Pampanga |
| `RDO No. I 16 - Regular LT Audit Division I` | RDO No. 116 |
| `06 1 9-F` | 0619-F (spaces injected inside form code) |
| `e-FlLlNG & PAYMENT (Online,Manual)` | e-FILING & PAYMENT (Online/Manual) |

## Template-ID discovery trail (how these IDs were found)

- `https://www.bir.gov.ph/home` is a Next.js app; the What's New widget
  fetches template `9` client-side. Homepage also fetches `1135`
  ("BIR Tax Calendar" — 169 dated deadline entries, potential future
  cross-check source) and `3405` ("Quick Links").
- `https://www.bir.gov.ph/revenue-issuances-details` (template `3628`)
  links year pages such as `2026-Revenue-Memorandum-Circulars`.
- Each yearly archive page embeds its own dataset template id in the served
  HTML, so every kind/year pair is discoverable with one HTML GET + regex, no
  browser needed. Verified 2026-08-11:

  | Page | Template |
  | --- | --- |
  | `https://www.bir.gov.ph/2026-Revenue-Memorandum-Circulars` | `3752` |
  | `https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders` | `3753` |
  | `https://www.bir.gov.ph/2026-Revenue-Regulations` | `3754` |

- **The marker is backslash-escaped in the served bytes.** It lives inside a JS
  string literal in the RSC payload, so what is actually on the wire is:

  ```
  \"code\":\"3753\",\"dataMapper\":{\"content\":\"Content\"}
  ```

  not the bare `"code":"3753","dataMapper":{"content":"Content"}`. A regex that
  matches only the unescaped form never matches a real page, and the discovery
  step then falls back to the checked-in map without failing — silently
  disabling the year-rollover safety net. `cms.ts` therefore accepts both forms
  (`\\?"` at every quote), and
  `page-2026-revenue-memorandum-orders-excerpt.html` pins that offline.

  ```
  # grep it out of a live page (note the escaped quotes)
  curl -s https://www.bir.gov.ph/2026-Revenue-Memorandum-Orders \
    | grep -o '\\"code\\":\\"[0-9]*\\",\\"dataMapper\\"'
  ```
