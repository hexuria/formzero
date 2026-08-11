// PDF stage of the news-sync pipeline (plan §5.4): fetch an issuance PDF into
// the gitignored work/ cache, run poppler's `pdftotext -layout` over it, and
// decide whether the resulting text layer is worth handing to the extractor.
//
// Everything that touches the network or the poppler binary lives here so the
// extractor modules stay pure and their tests stay offline: they consume the
// committed layout text via `loadFixtureLayoutText`.

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));

/** Absolute path of the news-sync script directory. */
export const newsSyncRoot = scriptDirectory;

/** Poppler binary the pipeline shells out to. */
export const pdftotextBinary = "pdftotext";

/** Exit code `sync.ts` uses when the runner dependency is missing (plan §5.4.4). */
export const missingDependencyExitCode = 2;

/** Minimum characters per page a text layer must carry to be usable (plan D3). */
export const minimumCharactersPerPage = 200;

/**
 * `pdftotext -layout` can emit a lot of whitespace on a scanned document; the
 * 6-page RMC 89-2026 fixture is ~16 KiB, so this ceiling is generous.
 */
const maxLayoutTextBytes = 8 * 1024 * 1024;

const installHint =
  "install poppler first: `brew install poppler` (macOS) or " +
  "`sudo apt-get install -y poppler-utils` (CI/Debian)";

/** Offline layout-text fixtures, keyed by issuance external id. */
const fixtureLayoutText: ReadonlyMap<string, string> = new Map([
  ["bir:rmc:2026:089", "fixtures/2026-08-11/rmc-89-2026-pdftotext-layout.txt"],
  ["bir:rmc:2026:062", "fixtures/2026-08-11/rmc-62-2026-pdftotext-layout.txt"],
]);

export type DownloadedPdf = {
  path: string;
  bytes: number;
  sha256: string;
  cached: boolean;
};

/**
 * Thrown when `pdftotext` cannot be executed. Carries the exit code `sync.ts`
 * should terminate with so the runner failure is distinguishable from a
 * parsing failure.
 */
export class PdftotextUnavailableError extends Error {
  readonly exitCode = missingDependencyExitCode;

  constructor(detail: string) {
    super(`${pdftotextBinary} is not usable (${detail}); ${installHint}`);
    this.name = "PdftotextUnavailableError";
  }
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function statOrNull(target: string): Promise<{ size: number } | null> {
  try {
    const info = await stat(target);
    return info.isFile() ? { size: info.size } : null;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

/**
 * Verifies the poppler dependency at startup. Resolves when `pdftotext -v`
 * runs; otherwise throws a `PdftotextUnavailableError` carrying the install
 * hint and exit code 2.
 */
export async function ensurePdftotext(): Promise<void> {
  try {
    // poppler prints its banner on stderr and exits 0.
    await execFileAsync(pdftotextBinary, ["-v"]);
  } catch (error) {
    throw new PdftotextUnavailableError(describe(error));
  }
}

/** Streaming SHA-256 of a file, lowercase hex. */
export async function sha256File(target: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(target)) {
    hash.update(chunk as Buffer);
  }
  return hash.digest("hex");
}

/**
 * The origin's `Content-Length` for a PDF, from one HEAD request, or null when
 * the answer cannot be trusted: HEAD unanswered or refused, the header absent,
 * or the value not a positive integer. Null always means "find out by
 * downloading" — never "unchanged".
 */
export async function remoteContentLength(url: string): Promise<number | null> {
  try {
    const response = await fetch(url, { method: "HEAD", redirect: "follow" });
    if (!response.ok) return null;
    const header = response.headers.get("content-length");
    if (header === null) return null;
    const bytes = Number.parseInt(header, 10);
    return Number.isSafeInteger(bytes) && bytes > 0 ? bytes : null;
  } catch {
    return null;
  }
}

/**
 * Downloads an issuance PDF to `destPath`, reusing the cached copy when the
 * origin reports the same `Content-Length` (plan §5.4.1). The URL must already
 * be percent-encoded — `issuances.ts` owns that, because the CMS HTML carries
 * the unencoded `.../RMC No. 89-2026_redacted.pdf` form.
 */
export async function downloadPdf(url: string, destPath: string): Promise<DownloadedPdf> {
  const existing = await statOrNull(destPath);
  if (existing !== null) {
    const remoteBytes = await remoteContentLength(url);
    if (remoteBytes !== null && remoteBytes === existing.size) {
      return {
        path: destPath,
        bytes: existing.size,
        sha256: await sha256File(destPath),
        cached: true,
      };
    }
  }

  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`GET ${url} failed with HTTP ${response.status} ${response.statusText}`);
  }
  const body = Buffer.from(await response.arrayBuffer());
  if (body.byteLength === 0) throw new Error(`GET ${url} returned an empty body`);

  await mkdir(path.dirname(destPath), { recursive: true });
  await writeFile(destPath, body);

  return {
    path: destPath,
    bytes: body.byteLength,
    sha256: createHash("sha256").update(body).digest("hex"),
    cached: false,
  };
}

/** Runs `pdftotext -layout <pdf> -` and returns the extracted text. */
export async function pdfToLayoutText(pdfPath: string): Promise<string> {
  try {
    const { stdout } = await execFileAsync(pdftotextBinary, ["-layout", pdfPath, "-"], {
      maxBuffer: maxLayoutTextBytes,
      encoding: "utf8",
    });
    return stdout;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT") throw new PdftotextUnavailableError(describe(error));
    throw new Error(`${pdftotextBinary} -layout ${pdfPath} failed: ${describe(error)}`);
  }
}

/**
 * Counts pages in `pdftotext` output. Poppler separates pages with a form feed
 * and emits a trailing one, so the count is simply the number of form feeds
 * (with a floor of 1 for text that carries none).
 */
export function countLayoutPages(text: string): number {
  let pages = 0;
  for (const character of text) {
    if (character === "\f") pages += 1;
  }
  return Math.max(pages, 1);
}

/**
 * Plan D3: a scan with no embedded text layer yields near-empty output. Below
 * 200 characters per page the circular is flagged `needs_manual_review` and no
 * override is emitted.
 */
export function hasUsableTextLayer(text: string, pageCount: number): boolean {
  const pages = Math.max(pageCount, 1);
  const meaningful = text.replace(/[\s\f]+/gu, " ").trim();
  return meaningful.length / pages >= minimumCharactersPerPage;
}

/**
 * Offline hook: returns the committed `pdftotext -layout` capture for an
 * issuance, or null when none is committed. Tests and `sync.ts --offline` read
 * PDF text through this instead of touching the network or poppler.
 */
export async function loadFixtureLayoutText(externalId: string): Promise<string | null> {
  const relativePath = fixtureLayoutText.get(externalId);
  if (relativePath === undefined) return null;
  try {
    return await readFile(path.join(newsSyncRoot, relativePath), "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}
