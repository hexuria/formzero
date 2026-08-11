// Client for the public BIR CMS API — the same endpoint bir.gov.ph's own
// Next.js bundle calls. There is no auth beyond two headers; omitting either
// one returns `403 {"error":"forbidden"}` (see fixtures/2026-08-11/CAPTURES.md).
//
// Everything network-facing here is deliberately thin and side-effect free
// apart from the request itself, so the offline path (`loadFixtureDataset`)
// can substitute committed captures without touching the network.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

import type { ArchiveKind } from "./types.ts";

export const CMS_BASE_URL = "https://bir-cms-ws.bir.gov.ph";
export const SITE_BASE_URL = "https://www.bir.gov.ph";

/** Template 9 = homepage "What's New → New Issuances" widget. */
export const WIDGET_TEMPLATE_ID = 9;

/**
 * Every issuance kind with its own yearly archive, in fetch order. The widget
 * carries no dates, so an issuance whose kind is missing here can only ever be
 * dated by its PDF header or by first sighting.
 */
export const ARCHIVE_KINDS: readonly ArchiveKind[] = ["RMC", "RMO", "RR"];

/**
 * The `{year}-<slug>` page that embeds each kind's yearly template id. Derived
 * from the kind alone, so a new year needs no new entry here.
 */
const ARCHIVE_PAGE_SLUGS: Readonly<Record<ArchiveKind, string>> = Object.freeze({
  RMC: "Revenue-Memorandum-Circulars",
  RMO: "Revenue-Memorandum-Orders",
  RR: "Revenue-Regulations",
});

/** `"RMC:2026"` — the composite key of `KNOWN_YEAR_TEMPLATE_IDS`. */
export function yearTemplateKey(kind: ArchiveKind, year: number): string {
  return `${kind}:${year}`;
}

/**
 * Yearly-archive template ids resolved by hand from the served HTML on
 * 2026-08-11, keyed by `<kind>:<year>`. `discoverYearTemplateId` re-derives
 * these at run time and only falls back here when the discovery request or
 * regex fails.
 */
export const KNOWN_YEAR_TEMPLATE_IDS: ReadonlyMap<string, number> = new Map([
  ["RMC:2026", 3752],
  ["RMO:2026", 3753],
  ["RR:2026", 3754],
]);

/** Verified header contract. All three are sent verbatim on every CMS request. */
export const CMS_REQUEST_HEADERS: Readonly<Record<string, string>> = Object.freeze({
  "client-website-id": "2",
  origin: SITE_BASE_URL,
  "user-agent": "buwiz-news-sync/1.0",
});

export const REQUEST_TIMEOUT_MS = 20_000;
export const RETRY_DELAY_MS = 30_000;

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));

export const FIXTURE_DIR = path.join(scriptDirectory, "fixtures", "2026-08-11");
export const WIDGET_FIXTURE = "cms-template-9-new-issuances.json";

/** One committed archive capture per kind; `--offline` reads exactly these. */
export const ARCHIVE_FIXTURES: Readonly<Record<ArchiveKind, string>> = Object.freeze({
  RMC: "cms-template-3752-rmc-archive-2026-excerpt.json",
  RMO: "cms-template-3753-rmo-archive-2026-excerpt.json",
  RR: "cms-template-3754-rr-archive-2026-excerpt.json",
});

/**
 * A verbatim excerpt of the served 2026 RMO archive page, so the template-id
 * extractor is covered offline against the real HTML escaping.
 */
export const ARCHIVE_PAGE_FIXTURE = "page-2026-revenue-memorandum-orders-excerpt.html";

const CAPTURES_HINT =
  "scripts/news-sync/fixtures/2026-08-11/CAPTURES.md documents the verified contract.";

export type FetchOptions = {
  signal?: AbortSignal;
};

export function templateDatasetsUrl(templateId: number): string {
  return `${CMS_BASE_URL}/api/pub/templates/${templateId}/datasets?per_page=3000`;
}

export function yearArchivePageUrl(kind: ArchiveKind, year: number): string {
  return `${SITE_BASE_URL}/${year}-${ARCHIVE_PAGE_SLUGS[kind]}`;
}

/**
 * Pulls the `data` array out of a CMS response body. Exported so the fixture
 * loader and the live client share one shape check.
 */
export function datasetsFromPayload(payload: unknown, sourceLabel: string): unknown[] {
  if (typeof payload !== "object" || payload === null) {
    throw new Error(`${sourceLabel}: response body is not a JSON object`);
  }
  const data = (payload as { data?: unknown }).data;
  if (!Array.isArray(data)) {
    throw new Error(`${sourceLabel}: response body has no "data" array`);
  }
  return data;
}

async function requestOnce(url: string, signal: AbortSignal | undefined): Promise<Response> {
  const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  const combined = signal === undefined ? timeout : AbortSignal.any([signal, timeout]);
  return await fetch(url, {
    headers: { ...CMS_REQUEST_HEADERS },
    redirect: "follow",
    signal: combined,
  });
}

function isRetriable(response: Response): boolean {
  return response.status >= 500;
}

/**
 * GETs one CMS template's datasets. Retries exactly once, 30 s later, on a
 * network error or an HTTP 5xx. A 403 is never retried: it means the header
 * contract drifted, and hammering the endpoint will not fix that.
 */
export async function fetchTemplateDatasets(
  templateId: number,
  opts?: FetchOptions,
): Promise<unknown[]> {
  const url = templateDatasetsUrl(templateId);
  const label = `CMS template ${templateId}`;

  let response: Response;
  try {
    response = await requestOnce(url, opts?.signal);
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    await delay(RETRY_DELAY_MS, undefined, { signal: opts?.signal });
    response = await requestOnce(url, opts?.signal).catch((retryError: unknown) => {
      const retryDetail =
        retryError instanceof Error ? retryError.message : String(retryError);
      throw new Error(
        `${label}: request failed twice (${detail}; retry: ${retryDetail}) — ${url}`,
      );
    });
  }

  if (response.status === 403) {
    throw new Error(
      `${label}: HTTP 403 forbidden. The CMS requires exactly ` +
        `"client-website-id: 2" and "origin: ${SITE_BASE_URL}" on every request; ` +
        `a 403 means that header contract changed. ${CAPTURES_HINT}`,
    );
  }

  if (isRetriable(response)) {
    await delay(RETRY_DELAY_MS, undefined, { signal: opts?.signal });
    response = await requestOnce(url, opts?.signal);
  }

  if (!response.ok) {
    throw new Error(`${label}: HTTP ${response.status} ${response.statusText} — ${url}`);
  }

  const payload: unknown = await response.json();
  return datasetsFromPayload(payload, label);
}

/**
 * The marker sits inside a JS string literal in the Next.js RSC payload, so the
 * served HTML carries it with every quote backslash-escaped:
 *
 *   \"code\":\"3753\",\"dataMapper\":{\"content\":\"Content\"}
 *
 * Both forms are accepted. Matching only the unescaped one made
 * `discoverYearTemplateId` miss on every real page and silently fall back to
 * the checked-in map — see fixtures/2026-08-11/CAPTURES.md.
 */
const TEMPLATE_ID_PATTERN =
  /\\?"code\\?":\\?"(\d{1,6})\\?",\\?"dataMapper\\?":\{\\?"content\\?":\\?"Content\\?"\}/u;

/**
 * Regexes the yearly archive template id out of the server-rendered HTML.
 * Pure, so the selector itself is unit-testable without a network call.
 */
export function extractYearTemplateId(html: string): number | null {
  const match = TEMPLATE_ID_PATTERN.exec(html);
  if (match === null) return null;
  const templateId = Number.parseInt(match[1], 10);
  return Number.isSafeInteger(templateId) && templateId > 0 ? templateId : null;
}

function fallbackYearTemplateId(kind: ArchiveKind, year: number, reason: string): number {
  const key = yearTemplateKey(kind, year);
  const known = KNOWN_YEAR_TEMPLATE_IDS.get(key);
  if (known === undefined) {
    throw new Error(
      `news-sync: cannot resolve the ${year} ${kind} archive template id (${reason}) ` +
        `and no fallback is checked in. Add ${JSON.stringify(key)} to ` +
        `KNOWN_YEAR_TEMPLATE_IDS in cms.ts. ` +
        CAPTURES_HINT,
    );
  }
  process.stderr.write(
    `news-sync: template-id discovery for ${year} ${kind} failed (${reason}); ` +
      `falling back to the checked-in id ${known}.\n`,
  );
  return known;
}

/**
 * Resolves one kind's yearly archive template id from the live site, falling
 * back to `KNOWN_YEAR_TEMPLATE_IDS` (with a stderr warning) on any failure.
 */
export async function discoverYearTemplateId(
  kind: ArchiveKind,
  year: number,
  opts?: FetchOptions,
): Promise<number> {
  const url = yearArchivePageUrl(kind, year);
  let html: string;
  try {
    const response = await requestOnce(url, opts?.signal);
    if (!response.ok) {
      return fallbackYearTemplateId(kind, year, `HTTP ${response.status} from ${url}`);
    }
    html = await response.text();
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    return fallbackYearTemplateId(kind, year, detail);
  }

  const templateId = extractYearTemplateId(html);
  if (templateId === null) {
    return fallbackYearTemplateId(kind, year, `no dataMapper template id in ${url}`);
  }
  return templateId;
}

/**
 * Offline source of truth: reads one committed capture and returns its `data`
 * array, so `--offline` runs and the whole test suite never hit the network.
 * `fixtureFile` is a bare filename inside `fixtures/2026-08-11/` or an
 * absolute path.
 */
export async function loadFixtureDataset(fixtureFile: string): Promise<unknown[]> {
  const absolutePath = path.isAbsolute(fixtureFile)
    ? fixtureFile
    : path.join(FIXTURE_DIR, fixtureFile);
  const raw = await readFile(absolutePath, "utf8");
  let payload: unknown;
  try {
    payload = JSON.parse(raw);
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`fixture ${absolutePath}: invalid JSON (${detail})`);
  }
  return datasetsFromPayload(payload, `fixture ${path.basename(absolutePath)}`);
}
