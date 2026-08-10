#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  renameSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const BASE_IDENTITY = Object.freeze({
  appName: "buwiz",
  displayName: "Buwiz App",
  bundleId: "dev.goldcoders.buwiz",
  shellRole: "Buwiz App application",
});

const MAX_SLUG_STEM_LENGTH = 32;
const HASH_LENGTH = 12;

function nonEmpty(value) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

export function canonicalRef(value) {
  let ref = nonEmpty(value);
  if (ref === null) return null;

  if (ref.startsWith("refs/heads/")) {
    return ref.slice("refs/heads/".length);
  }
  if (ref.startsWith("refs/remotes/")) {
    const remoteAndBranch = ref.slice("refs/remotes/".length);
    const separator = remoteAndBranch.indexOf("/");
    return separator === -1 ? remoteAndBranch : remoteAndBranch.slice(separator + 1);
  }
  return ref;
}

export function gitBranch(repositoryRoot) {
  try {
    return nonEmpty(
      execFileSync("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], {
        cwd: repositoryRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
  } catch {
    return null;
  }
}

export function resolveBuildRef({
  env = process.env,
  repositoryRoot,
  detectGitBranch = gitBranch,
} = {}) {
  const detectedRef = canonicalRef(detectGitBranch(repositoryRoot));
  const explicitRef = canonicalRef(env.BUWIZ_BUILD_REF);
  if (detectedRef !== null) {
    if (explicitRef !== null && explicitRef !== detectedRef) {
      throw new Error(
        `BUWIZ_BUILD_REF (${explicitRef}) does not match the checked-out branch (${detectedRef}).`,
      );
    }
    return detectedRef;
  }

  const candidates = [
    explicitRef,
    env.GITHUB_HEAD_REF,
    env.GITHUB_REF_TYPE === "branch" ? env.GITHUB_REF_NAME : null,
    env.CI_COMMIT_REF_NAME,
    env.BRANCH_NAME,
  ];

  for (const candidate of candidates) {
    const ref = canonicalRef(candidate);
    if (ref !== null) return ref;
  }

  throw new Error(
    "Cannot resolve a branch identity from detached HEAD. Set BUWIZ_BUILD_REF to the source branch name.",
  );
}

export function sanitizeRef(ref) {
  const canonical = canonicalRef(ref);
  if (canonical === null) throw new Error("Build ref must not be empty.");

  let stem = canonical
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-+/g, "-");

  if (stem.length === 0) stem = "branch";
  if (!/^[a-z]/.test(stem)) stem = `branch-${stem}`;
  stem = stem.slice(0, MAX_SLUG_STEM_LENGTH).replace(/-+$/g, "");
  if (stem.length === 0) stem = "branch";

  const hash = createHash("sha256")
    .update(canonical, "utf8")
    .digest("hex")
    .slice(0, HASH_LENGTH);
  return `${stem}-${hash}`;
}

export function resolveIdentity({
  ref,
  env = process.env,
  repositoryRoot,
  detectGitBranch = gitBranch,
} = {}) {
  const resolvedRef = canonicalRef(ref) ??
    resolveBuildRef({ env, repositoryRoot, detectGitBranch });
  const isMain = resolvedRef === "main";
  const slug = isMain ? "main" : sanitizeRef(resolvedRef);
  const displayName = isMain
    ? BASE_IDENTITY.displayName
    : `${BASE_IDENTITY.displayName} — ${slug}`;

  return Object.freeze({
    ref: resolvedRef,
    slug,
    isMain,
    appName: isMain ? BASE_IDENTITY.appName : `${BASE_IDENTITY.appName}-${slug}`,
    displayName,
    bundleId: isMain
      ? BASE_IDENTITY.bundleId
      : `${BASE_IDENTITY.bundleId}.${slug}`,
    shellRole: BASE_IDENTITY.shellRole,
  });
}

function replaceOne(source, pattern, replacement, label) {
  const matches = source.match(new RegExp(pattern.source, `${pattern.flags}g`));
  if (matches?.length !== 1) {
    throw new Error(
      `Expected exactly one ${label} in app.zon; found ${matches?.length ?? 0}.`,
    );
  }
  return source.replace(pattern, replacement);
}

export function renderManifest(source, identity) {
  let rendered = source;
  rendered = replaceOne(
    rendered,
    /^([ \t]*)\.id = "[^"]+",/m,
    `$1.id = ${JSON.stringify(identity.bundleId)},`,
    "top-level app id",
  );
  rendered = replaceOne(
    rendered,
    /^([ \t]*)\.name = "[^"]+",/m,
    `$1.name = ${JSON.stringify(identity.appName)},`,
    "top-level app name",
  );
  rendered = replaceOne(
    rendered,
    /^([ \t]*)\.display_name = "[^"]+",/m,
    `$1.display_name = ${JSON.stringify(identity.displayName)},`,
    "top-level display name",
  );
  rendered = replaceOne(
    rendered,
    /^([ \t]*)\.title = "[^"]+",/m,
    `$1.title = ${JSON.stringify(identity.displayName)},`,
    "main window title",
  );
  rendered = replaceOne(
    rendered,
    /\.role = "[^"]+",/,
    `.role = ${JSON.stringify(identity.shellRole)},`,
    "main canvas role",
  );
  rendered = replaceOne(
    rendered,
    /\.accessibility_label = "[^"]+",/,
    `.accessibility_label = ${JSON.stringify(identity.displayName)},`,
    "main canvas accessibility label",
  );
  return rendered;
}

function ensureDirectoryLink(target, linkPath) {
  let stat = null;
  try {
    stat = lstatSync(linkPath);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  if (stat !== null) {
    if (!stat.isSymbolicLink()) {
      throw new Error(`Refusing to replace non-link identity path: ${linkPath}`);
    }
    const current = resolve(dirname(linkPath), readlinkSync(linkPath));
    if (realpathSync(current) === realpathSync(target)) return;
    unlinkSync(linkPath);
  }

  try {
    symlinkSync(
      resolve(target),
      linkPath,
      process.platform === "win32" ? "junction" : "dir",
    );
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    const current = resolve(dirname(linkPath), readlinkSync(linkPath));
    if (realpathSync(current) !== realpathSync(target)) throw error;
  }
}

function writeGeneratedFile(path, contents) {
  const temporary = `${path}.tmp-${process.pid}`;
  writeFileSync(temporary, contents);
  renameSync(temporary, path);
}

export function prepareIdentity({
  repositoryRoot,
  env = process.env,
} = {}) {
  if (!repositoryRoot) throw new Error("repositoryRoot is required.");
  const root = realpathSync(repositoryRoot);
  // Filesystem-writing callers must use the actual checkout identity. Keep
  // ref/detector injection confined to the pure resolver used by unit tests.
  const identity = resolveIdentity({ env, repositoryRoot: root });
  const appRoot = join(".native", "identities", identity.appName);
  const absoluteAppRoot = join(root, appRoot);
  const manifestPath = join(appRoot, "app.zon");

  mkdirSync(absoluteAppRoot, { recursive: true });
  ensureDirectoryLink(join(root, "src"), join(absoluteAppRoot, "src"));
  ensureDirectoryLink(join(root, "assets"), join(absoluteAppRoot, "assets"));

  const source = readFileSync(join(root, "app.zon"), "utf8");
  writeGeneratedFile(join(root, manifestPath), renderManifest(source, identity));
  writeGeneratedFile(
    join(absoluteAppRoot, "identity.json"),
    `${JSON.stringify({ ...identity, appRoot, manifestPath }, null, 2)}\n`,
  );

  return Object.freeze({ ...identity, appRoot, manifestPath });
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

export function formatIdentity(identity, format) {
  if (format === "json") return JSON.stringify(identity);
  if (format === "shell") {
    return [
      `BUWIZ_APP_NAME=${shellQuote(identity.appName)}`,
      `BUWIZ_DISPLAY_NAME=${shellQuote(identity.displayName)}`,
      `BUWIZ_BUNDLE_ID=${shellQuote(identity.bundleId)}`,
      `BUWIZ_APP_ROOT=${shellQuote(identity.appRoot)}`,
      `BUWIZ_MANIFEST=${shellQuote(identity.manifestPath)}`,
      `BUWIZ_BUILD_SLUG=${shellQuote(identity.slug)}`,
    ].join("\n");
  }
  if (format.startsWith("field:")) {
    const field = format.slice("field:".length);
    if (!(field in identity)) throw new Error(`Unknown identity field: ${field}`);
    return String(identity[field]);
  }
  throw new Error(`Unknown output format: ${format}`);
}

function parseArgs(argv) {
  let command = "prepare";
  let format = "json";
  const args = [...argv];
  if (args[0] && !args[0].startsWith("--")) command = args.shift();
  while (args.length > 0) {
    const argument = args.shift();
    if (argument === "--format") format = args.shift() ?? "";
    else if (argument?.startsWith("--format=")) format = argument.slice(9);
    else throw new Error(`Unknown argument: ${argument}`);
  }
  return { command, format };
}

function main() {
  const scriptPath = fileURLToPath(import.meta.url);
  const repositoryRoot = resolve(dirname(scriptPath), "..");
  const { command, format } = parseArgs(process.argv.slice(2));
  const identity = command === "prepare"
    ? prepareIdentity({ repositoryRoot })
    : command === "resolve"
      ? resolveIdentity({ repositoryRoot })
      : (() => { throw new Error(`Unknown command: ${command}`); })();
  process.stdout.write(`${formatIdentity(identity, format)}\n`);
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`app identity error: ${error.message}\n`);
    process.exitCode = 1;
  }
}
