#!/usr/bin/env node

import { createHash, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { hostname } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const EXIT = Object.freeze({ operational: 1, usage: 2, safety: 3 });
const TARGETS = Object.freeze({
  "zig-cache": [".zig-cache", "zig-cache"],
  "zig-packages": ["zig-pkg"],
  build: ["zig-out"],
  native: [".native"],
  deps: ["node_modules"],
  reports: ["coverage", "test-results"],
  "news-scratch": ["scripts/news-sync/work"],
});
const STANDARD = Object.freeze(["zig-cache", "zig-packages", "build", "reports", "news-scratch"]);
const ALL_TARGETS = Object.freeze(Object.keys(TARGETS));
const GIT_OPERATION_PATHS = Object.freeze([
  "MERGE_HEAD",
  "CHERRY_PICK_HEAD",
  "REVERT_HEAD",
  "BISECT_LOG",
  "index.lock",
  "rebase-apply",
  "rebase-merge",
  "sequencer",
]);
const VERSION = "2";

class MaintenanceError extends Error {
  constructor(message, exitCode = EXIT.operational) {
    super(message);
    this.exitCode = exitCode;
  }
}

function fail(message, exitCode = EXIT.operational) {
  throw new MaintenanceError(message, exitCode);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: options.encoding ?? "utf8",
    env: process.env,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) {
    fail(`${command} could not run: ${result.error.message}`);
  }
  if (result.status !== 0 && !options.allowFailure) {
    const detail = String(result.stderr || result.stdout || "").trim();
    fail(`${command} ${args.join(" ")} failed${detail ? `: ${detail}` : ""}`);
  }
  return result;
}

function git(cwd, args, options = {}) {
  return run("git", ["-C", cwd, ...args], options);
}

function gitText(cwd, args) {
  return git(cwd, args).stdout.trim();
}

function realpathExisting(path, label) {
  try {
    return realpathSync(path);
  } catch (error) {
    fail(`${label} does not resolve to an existing path: ${path}`, EXIT.safety);
  }
}

function isContained(parent, child) {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel));
}

function physicalStat(path, label, type) {
  let stat;
  try {
    stat = lstatSync(path);
  } catch {
    fail(`${label} does not exist: ${path}`, EXIT.safety);
  }
  if (stat.isSymbolicLink() || (type === "directory" ? !stat.isDirectory() : !stat.isFile())) {
    fail(`${label} must be a physical ${type}: ${path}`, EXIT.safety);
  }
  return stat;
}

function identity(path, label, type) {
  const stat = physicalStat(path, label, type);
  return { path, dev: stat.dev, ino: stat.ino, mode: stat.mode, mtimeMs: stat.mtimeMs, type };
}

function identityMatches(expected) {
  try {
    const actual = lstatSync(expected.path);
    return !actual.isSymbolicLink()
      && (expected.type === "directory" ? actual.isDirectory() : actual.isFile())
      && actual.dev === expected.dev
      && actual.ino === expected.ino
      && actual.mode === expected.mode
      && (expected.type === "directory" || actual.mtimeMs === expected.mtimeMs);
  } catch {
    return false;
  }
}

function readPhysicalText(path, label) {
  physicalStat(path, label, "file");
  const value = readFileSync(path, "utf8").trim();
  if (!value || value.includes("\0")) {
    fail(`${label} is empty or malformed: ${path}`, EXIT.safety);
  }
  return value;
}

function parseWorktreePorcelain(buffer) {
  const records = [];
  let current = null;
  for (const rawField of buffer.toString("utf8").split("\0")) {
    if (rawField === "") {
      if (current) {
        records.push(current);
        current = null;
      }
      continue;
    }
    const field = rawField;
    const space = field.indexOf(" ");
    const key = space < 0 ? field : field.slice(0, space);
    const value = space < 0 ? true : field.slice(space + 1);
    if (key === "worktree") {
      if (current) {
        records.push(current);
      }
      current = { path: value };
      continue;
    }
    if (!current) {
      fail("Git returned malformed worktree metadata");
    }
    if (!["HEAD", "branch", "detached", "bare", "locked", "prunable"].includes(key)) {
      fail(`Git returned unknown worktree metadata field: ${key}`);
    }
    if (Object.hasOwn(current, key)) {
      fail(`Git returned duplicate worktree metadata field: ${key}`);
    }
    current[key] = value;
  }
  if (current) {
    records.push(current);
  }
  if (records.length === 0 || records.some((record) => !record.path)) {
    fail("Git returned incomplete worktree metadata");
  }
  return records;
}

function repoContext(cwd = process.cwd()) {
  const top = realpathExisting(gitText(cwd, ["rev-parse", "--show-toplevel"]), "repository root");
  const commonRaw = gitText(top, ["rev-parse", "--git-common-dir"]);
  const commonDir = realpathExisting(resolve(top, commonRaw), "Git common directory");
  physicalStat(commonDir, "Git common directory", "directory");
  const linkedAdminRoot = join(commonDir, "worktrees");
  let linkedAdminRootReal = null;
  if (existsSync(linkedAdminRoot)) {
    physicalStat(linkedAdminRoot, "linked-worktree administration root", "directory");
    linkedAdminRootReal = realpathSync(linkedAdminRoot);
  }
  const list = git(top, ["worktree", "list", "--porcelain", "-z"], { encoding: "buffer" });
  const records = parseWorktreePorcelain(list.stdout).map((record) => {
    let pathReal = null;
    let missing = false;
    try {
      pathReal = realpathSync(record.path);
    } catch {
      missing = true;
    }
    let gitDirReal = null;
    let topologyIdentity = null;
    if (!missing) {
      const rootIdentity = identity(pathReal, "registered worktree root", "directory");
      const gitDirRaw = gitText(pathReal, ["rev-parse", "--git-dir"]);
      gitDirReal = realpathExisting(resolve(pathReal, gitDirRaw), "worktree Git directory");
      const recordCommonRaw = gitText(pathReal, ["rev-parse", "--git-common-dir"]);
      const recordCommonReal = realpathExisting(resolve(pathReal, recordCommonRaw), "worktree Git common directory");
      if (recordCommonReal !== commonDir) {
        fail(`registered worktree belongs to a different Git common directory: ${record.path}`, EXIT.safety);
      }
      const recordTop = realpathExisting(gitText(pathReal, ["rev-parse", "--show-toplevel"]), "worktree root");
      if (recordTop !== pathReal) {
        fail(`Git worktree topology is inconsistent at ${record.path}`, EXIT.safety);
      }
      if (gitDirReal === commonDir) {
      topologyIdentity = { root: rootIdentity, gitDir: identity(commonDir, "primary Git directory", "directory") };
      } else {
        if (!linkedAdminRootReal) {
          fail(`linked-worktree administration root is missing for ${record.path}`, EXIT.safety);
        }
        const dotGit = join(pathReal, ".git");
        const dotGitIdentity = identity(dotGit, "linked worktree .git file", "file");
        const adminIdentity = identity(gitDirReal, "linked worktree administration directory", "directory");
        if (dirname(gitDirReal) !== linkedAdminRootReal || basename(gitDirReal) === "") {
          fail(`linked worktree Git directory escapes ${linkedAdminRootReal}: ${gitDirReal}`, EXIT.safety);
        }
        const dotGitText = readPhysicalText(dotGit, "linked worktree .git file");
        if (!dotGitText.startsWith("gitdir: ")) {
          fail(`linked worktree .git file is malformed: ${dotGit}`, EXIT.safety);
        }
        const dotGitTarget = realpathExisting(resolve(pathReal, dotGitText.slice("gitdir: ".length)), "linked worktree .git target");
        if (dotGitTarget !== gitDirReal) {
          fail(`linked worktree .git target does not match its administration directory: ${record.path}`, EXIT.safety);
        }
        const gitdirFile = join(gitDirReal, "gitdir");
        const commondirFile = join(gitDirReal, "commondir");
        const gitdirIdentity = identity(gitdirFile, "administration gitdir linkback", "file");
        const commondirIdentity = identity(commondirFile, "administration commondir link", "file");
        const gitdirTarget = realpathExisting(resolve(gitDirReal, readPhysicalText(gitdirFile, "administration gitdir linkback")), "administration gitdir linkback target");
        const commondirTarget = realpathExisting(resolve(gitDirReal, readPhysicalText(commondirFile, "administration commondir link")), "administration commondir target");
        if (gitdirTarget !== dotGit) {
          fail(`linked worktree administration linkback does not resolve to ${dotGit}`, EXIT.safety);
        }
        if (commondirTarget !== commonDir) {
          fail(`linked worktree administration commondir does not resolve to ${commonDir}`, EXIT.safety);
        }
        topologyIdentity = {
          root: rootIdentity,
          adminRoot: identity(linkedAdminRootReal, "linked-worktree administration root", "directory"),
          dotGit: dotGitIdentity,
          admin: adminIdentity,
          gitdir: gitdirIdentity,
          commondir: commondirIdentity,
        };
      }
    }
    return { ...record, pathReal, gitDirReal, topologyIdentity, missing };
  });
  const primary = records.find((record) => record.gitDirReal === commonDir);
  if (!primary || records.filter((record) => record.gitDirReal === commonDir).length !== 1) {
    fail("Could not identify exactly one canonical primary worktree", EXIT.safety);
  }
  const cwdReal = realpathExisting(cwd, "current directory");
  const current = [...records]
    .filter((record) => record.pathReal && isContained(record.pathReal, cwdReal))
    .sort((a, b) => b.pathReal.length - a.pathReal.length)[0];
  if (!current) {
    fail("Current directory is not inside a registered worktree", EXIT.safety);
  }
  return { top, commonDir, records, primary, current };
}

function invocationCwd() {
  return process.env.WORKSPACE_MAINTENANCE_CWD || process.cwd();
}

function topologyMatches(record) {
  return record.topologyIdentity && Object.values(record.topologyIdentity).every(identityMatches);
}

function topologyIdentitiesEqual(left, right) {
  if (!left || !right) return false;
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  if (JSON.stringify(leftKeys) !== JSON.stringify(rightKeys)) return false;
  return leftKeys.every((key) => {
    const a = left[key];
    const b = right[key];
    return a.path === b.path && a.type === b.type && a.dev === b.dev && a.ino === b.ino
      && a.mode === b.mode && (a.type === "directory" || a.mtimeMs === b.mtimeMs);
  });
}

function contextTopologyEqual(planned, fresh) {
  if (planned.commonDir !== fresh.commonDir || planned.top !== fresh.top
    || planned.records.length !== fresh.records.length
    || !topologyIdentitiesEqual(planned.primary.topologyIdentity, fresh.primary.topologyIdentity)) {
    return false;
  }
  return planned.records.every((record) => {
    const replacement = fresh.records.find((candidate) => candidate.path === record.path);
    return replacement && replacement.missing === record.missing
      && replacement.gitDirReal === record.gitDirReal
      && topologyIdentitiesEqual(record.topologyIdentity, replacement.topologyIdentity);
  });
}

function parseOptions(args, supported) {
  const options = { dryRun: false, force: false, json: false, into: "origin/main", worktree: null, allWorktrees: false };
  const positionals = [];
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }
    if (!supported.has(arg)) {
      fail(`unknown option: ${arg}`, EXIT.usage);
    }
    if (["--dry-run", "--force", "--json", "--all-worktrees"].includes(arg)) {
      const key = arg === "--dry-run" ? "dryRun" : arg === "--all-worktrees" ? "allWorktrees" : arg.slice(2);
      if (options[key]) {
        fail(`duplicate option: ${arg}`, EXIT.usage);
      }
      options[key] = true;
      continue;
    }
    const value = args[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`${arg} requires a value`, EXIT.usage);
    }
    index += 1;
    const key = arg === "--worktree" ? "worktree" : "into";
    if (key === "into" && options.into !== "origin/main") {
      fail("--into may be specified only once", EXIT.usage);
    }
    if (key === "worktree" && options.worktree !== null) {
      fail("--worktree may be specified only once", EXIT.usage);
    }
    options[key] = value;
  }
  return { options, positionals };
}

function usageClean() {
  return [
    "error: choose a cleanup target; nothing was deleted",
    "",
    "Targets:",
    "  zig-cache     .zig-cache, zig-cache",
    "  zig-packages  zig-pkg",
    "  build         zig-out",
    "  native        .native",
    "  deps          node_modules",
    "  reports       coverage, test-results",
    "  news-scratch  scripts/news-sync/work",
    "  standard      caches, packages, build, reports, news scratch",
    "  all           every declared target; requires --force",
    "",
    "Read-only:",
    "  just clean list",
    "  just clean list --all-worktrees",
    "  just clean <target> --dry-run",
    "  just clean purge /exact/quarantine/receipt.json --dry-run",
    "  just clean purge /exact/quarantine/receipt.json --force",
  ].join("\n");
}

function requireMutationPlatform() {
  if (process.platform === "win32") {
    fail("destructive workspace maintenance is unavailable on Windows; inventory and dry-run remain supported", EXIT.safety);
  }
}

function parseReceipt(receiptPath, context) {
  if (!isAbsolute(receiptPath) || resolve(receiptPath) !== receiptPath || basename(receiptPath) !== "receipt.json") {
    fail(`purge requires an exact absolute receipt.json path: ${receiptPath}`, EXIT.safety);
  }
  const receiptReal = realpathExisting(receiptPath, "cleanup receipt");
  if (receiptReal !== receiptPath) {
    fail(`cleanup receipt must be canonical and not a symlink: ${receiptPath}`, EXIT.safety);
  }
  physicalStat(receiptReal, "cleanup receipt", "file");
  let receipt;
  try {
    receipt = JSON.parse(readFileSync(receiptReal, "utf8"));
  } catch {
    fail(`cleanup receipt is not valid JSON: ${receiptReal}`, EXIT.safety);
  }
  const transactionRoot = dirname(receiptReal);
  physicalStat(transactionRoot, "quarantine transaction", "directory");
  const quarantineRoot = dirname(transactionRoot);
  physicalStat(quarantineRoot, "quarantine root", "directory");
  if (basename(quarantineRoot) !== createHash("sha256").update(context.commonDir).digest("hex").slice(0, 16)
    || basename(dirname(quarantineRoot)) !== ".buwiz-workspace-maintenance") {
    fail(`receipt is outside this repository's quarantine: ${receiptReal}`, EXIT.safety);
  }
  if (context.records.some((record) => record.pathReal && (isContained(record.pathReal, transactionRoot) || isContained(transactionRoot, record.pathReal)))) {
    fail(`quarantine transaction overlaps a registered worktree: ${transactionRoot}`, EXIT.safety);
  }
  if (receipt.version !== VERSION || receipt.operation !== "clean" || receipt.transactionRoot !== transactionRoot
    || !Array.isArray(receipt.sourceWorktrees) || receipt.sourceWorktrees.length === 0
    || !Array.isArray(receipt.moves) || receipt.moves.length === 0) {
    fail(`cleanup receipt has an unsupported or incomplete schema: ${receiptReal}`, EXIT.safety);
  }
  const expectedQuarantineRoots = receipt.sourceWorktrees.map((sourceRoot) => {
    if (!isAbsolute(sourceRoot) || resolve(sourceRoot) !== sourceRoot) {
      fail(`cleanup receipt contains a non-canonical source worktree: ${sourceRoot}`, EXIT.safety);
    }
    const record = context.records.find((candidate) => candidate.path === sourceRoot && candidate.pathReal === sourceRoot && !candidate.missing);
    if (!record) {
      fail(`cleanup receipt source is no longer an exact registered worktree: ${sourceRoot}`, EXIT.safety);
    }
    return quarantineBase(context, record.pathReal, false);
  });
  const expectedBases = new Set(expectedQuarantineRoots);
  if (expectedBases.size !== 1 || !expectedBases.has(quarantineRoot)) {
    fail(`cleanup receipt is not under the canonical quarantine for its source worktree: ${receiptReal}`, EXIT.safety);
  }
  const expectedDigest = createHash("sha256").update(JSON.stringify(receipt.moves)).digest("hex");
  if (receipt.contentsDigest !== expectedDigest) {
    fail(`cleanup receipt digest is invalid: ${receiptReal}`, EXIT.safety);
  }
  const destinations = receipt.moves.map((move) => {
    if (!move || typeof move.source !== "string" || typeof move.destination !== "string"
      || typeof move.bytes !== "number" || typeof move.entries !== "number") {
      fail(`cleanup receipt contains an invalid move entry: ${receiptReal}`, EXIT.safety);
    }
    const destination = resolve(move.destination);
    if (destination !== move.destination || !isContained(transactionRoot, destination) || destination === receiptReal) {
      fail(`cleanup receipt destination escapes its transaction: ${move.destination}`, EXIT.safety);
    }
    physicalStat(destination, "quarantined artifact root", "directory");
    if (!isAbsolute(move.source) || resolve(move.source) !== move.source) {
      fail(`cleanup receipt source is not an exact absolute path: ${move.source}`, EXIT.safety);
    }
    const sourceRelative = receipt.sourceWorktrees
      ?.filter((root) => typeof root === "string" && isContained(root, move.source))
      .map((root) => relative(root, move.source))[0];
    if (!sourceRelative || !ALL_TARGETS.flatMap((name) => TARGETS[name]).includes(sourceRelative)) {
      fail(`cleanup receipt source is outside the literal artifact catalog: ${move.source}`, EXIT.safety);
    }
    return destination;
  });
  const actualChildren = readdirSync(transactionRoot).filter((name) => name !== "receipt.json");
  const allowedTop = new Set(destinations.map((path) => relative(transactionRoot, path).split(sep)[0]));
  if (actualChildren.some((name) => !allowedTop.has(name))) {
    fail(`quarantine transaction contains content not named by the receipt: ${transactionRoot}`, EXIT.safety);
  }
  const size = directorySize(transactionRoot);
  return {
    receipt,
    receiptPath: receiptReal,
    transactionRoot,
    quarantineRoot,
    transactionIdentity: identity(transactionRoot, "quarantine transaction", "directory"),
    quarantineIdentity: identity(quarantineRoot, "quarantine root", "directory"),
    size,
  };
}

function commandCleanPurge(positionals, options) {
  if (positionals.length !== 2) {
    fail("clean purge accepts exactly one receipt path", EXIT.usage);
  }
  if (options.json || options.worktree || options.allWorktrees) {
    fail("clean purge accepts only --dry-run and --force", EXIT.usage);
  }
  if (!options.dryRun && !options.force) {
    fail("clean purge requires --force (or use --dry-run)", EXIT.safety);
  }
  const context = repoContext(invocationCwd());
  const planned = parseReceipt(positionals[1], context);
  process.stdout.write(`${options.dryRun ? "Would permanently purge" : "Permanently purging"} ${planned.transactionRoot}\n`);
  process.stdout.write(`  ${planned.size.bytes} bytes, ${planned.size.entries} entries\n`);
  if (options.dryRun) return;
  requireMutationPlatform();
  const digest = createHash("sha256").update(readFileSync(planned.receiptPath)).digest("hex");
  const release = acquireLock(context.commonDir, digest);
  try {
    const fresh = repoContext(invocationCwd());
    if (!contextTopologyEqual(context, fresh)) {
      fail("repository worktree topology changed after planning; nothing was purged", EXIT.safety);
    }
    const verified = parseReceipt(planned.receiptPath, fresh);
    if (verified.transactionRoot !== planned.transactionRoot
      || !topologyIdentitiesEqual({ transaction: planned.transactionIdentity, quarantine: planned.quarantineIdentity },
        { transaction: verified.transactionIdentity, quarantine: verified.quarantineIdentity })
      || verified.size.bytes !== planned.size.bytes
      || verified.size.entries !== planned.size.entries) {
      fail("quarantine changed after planning; nothing was purged", EXIT.safety);
    }
    rmSync(verified.transactionRoot, { recursive: true, force: false });
    if (existsSync(verified.transactionRoot)) {
      fail(`quarantine purge did not complete: ${verified.transactionRoot}`);
    }
    process.stdout.write("Purge complete; the quarantined artifacts are no longer recoverable.\n");
  } finally {
    release();
  }
}

function expandTarget(target) {
  if (target === "standard") {
    return STANDARD.flatMap((name) => TARGETS[name]);
  }
  if (target === "all") {
    return ALL_TARGETS.flatMap((name) => TARGETS[name]);
  }
  if (!Object.hasOwn(TARGETS, target)) {
    fail(`unknown cleanup target: ${target}`, EXIT.usage);
  }
  return TARGETS[target];
}

function directorySize(path, rejectSymlinks = true) {
  const stack = [path];
  const rootDevice = lstatSync(path).dev;
  let bytes = 0;
  let entries = 0;
  while (stack.length) {
    const current = stack.pop();
    const stat = lstatSync(current);
    if (stat.dev !== rootDevice) {
      fail(`artifact crosses a filesystem boundary: ${current}`, EXIT.safety);
    }
    entries += 1;
    if (stat.isSymbolicLink()) {
      if (rejectSymlinks) {
        fail(`refusing nested symbolic link inside artifact root: ${current}`, EXIT.safety);
      }
      continue;
    }
    if (stat.isDirectory()) {
      for (const name of readdirSync(current)) {
        stack.push(join(current, name));
      }
    } else {
      bytes += stat.size;
    }
  }
  return { bytes, entries };
}

function snapshotEntry(root, relativePath, options = {}) {
  const absolute = join(root, relativePath);
  if (!existsSync(absolute)) {
    return { relativePath, absolute, exists: false };
  }
  const stat = lstatSync(absolute);
  if (stat.isSymbolicLink()) {
    if (options.inventoryOnly) {
      return { relativePath, absolute, exists: true, unsafe: "symbolic link artifact root", bytes: 0, entries: 1 };
    }
    fail(`refusing symbolic link artifact root: ${absolute}`, EXIT.safety);
  }
  if (!stat.isDirectory()) {
    fail(`artifact root must be a physical directory: ${absolute}`, EXIT.safety);
  }
  const expected = resolve(root, relativePath);
  if (!isContained(root, expected)) {
    fail(`artifact path escapes its registered worktree: ${relativePath}`, EXIT.safety);
  }
  const tracked = git(root, ["ls-files", "--error-unmatch", "--", relativePath], { allowFailure: true });
  if (tracked.status === 0) {
    fail(`refusing tracked artifact path: ${absolute}`, EXIT.safety);
  }
  const ignored = git(root, ["check-ignore", "--quiet", "--no-index", "--", relativePath], { allowFailure: true });
  if (ignored.status !== 0) {
    fail(`refusing artifact path that is not ignored: ${absolute}`, EXIT.safety);
  }
  const size = directorySize(absolute, !options.inventoryOnly);
  return {
    relativePath,
    absolute,
    exists: true,
    dev: stat.dev,
    ino: stat.ino,
    mode: stat.mode,
    mtimeMs: stat.mtimeMs,
    ...size,
  };
}

function snapshotMatches(entry) {
  if (!entry.exists) {
    return !existsSync(entry.absolute);
  }
  if (!existsSync(entry.absolute)) {
    return false;
  }
  const stat = lstatSync(entry.absolute);
  return !stat.isSymbolicLink()
    && stat.dev === entry.dev
    && stat.ino === entry.ino
    && stat.mode === entry.mode
    && stat.mtimeMs === entry.mtimeMs;
}

function selectExactWorktree(context, supplied) {
  if (!isAbsolute(supplied)) {
    fail(`worktree path must be absolute: ${supplied}`, EXIT.safety);
  }
  const normalized = resolve(supplied);
  if (normalized !== supplied) {
    fail(`worktree path must use its exact registered spelling: ${supplied}`, EXIT.safety);
  }
  const record = context.records.find((candidate) => candidate.path === supplied);
  if (!record) {
    fail(`path is not an exact registered worktree: ${supplied}`, EXIT.safety);
  }
  if (record.missing || record.prunable) {
    fail(`worktree is missing or prunable: ${supplied}`, EXIT.safety);
  }
  if (record.pathReal !== supplied) {
    fail(`worktree path must be canonical and not a symlink: ${supplied}`, EXIT.safety);
  }
  return record;
}

function resolveRequestedWorktree(context, supplied) {
  const record = selectExactWorktree(context, supplied);
  if (record === context.primary) {
    fail(`refusing the primary worktree: ${supplied}`, EXIT.safety);
  }
  if (record === context.current) {
    fail(`refusing the current worktree: ${supplied}`, EXIT.safety);
  }
  if (record.bare || record.locked || record.prunable || record.missing) {
    fail(`worktree is not an eligible linked worktree: ${supplied}`, EXIT.safety);
  }
  const descendants = context.records.filter((candidate) => candidate !== record && candidate.pathReal && isContained(record.pathReal, candidate.pathReal));
  if (descendants.length) {
    fail(`worktree contains registered descendant worktree: ${descendants.map((candidate) => candidate.path).join(", ")}`, EXIT.safety);
  }
  return record;
}

function processProof(root) {
  if (!existsSync("/usr/sbin/lsof") && !existsSync("/usr/bin/lsof")) {
    return { state: "unknown", detail: "lsof is unavailable" };
  }
  const lsof = existsSync("/usr/sbin/lsof") ? "/usr/sbin/lsof" : "/usr/bin/lsof";
  const marker = `WORKSPACE_MAINTENANCE_SCAN_${process.pid}_${Date.now()}`;
  const result = spawnSync(lsof, ["-nP", "-Fpcfn", "+D", root], {
    cwd: dirname(dirname(root)),
    encoding: "utf8",
    env: { ...process.env, [marker]: "1" },
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) {
    return { state: "unknown", detail: `lsof could not run: ${result.error.message}` };
  }
  const diagnostics = result.stderr.split("\n").filter((line) => line && !/^[pcfn]/u.test(line));
  if (result.status === 1 && !result.stdout && diagnostics.length === 0) {
    return { state: "clear", detail: "no open files" };
  }
  const fieldLines = [...result.stdout.split("\n"), ...result.stderr.split("\n")].filter((line) => /^[pcfn]/u.test(line));
  const noMatch = result.status === 1 && fieldLines.length === 0 && diagnostics.length === 0;
  if (noMatch) {
    return { state: "clear", detail: "no open files" };
  }
  if ((result.status !== 0 && fieldLines.length === 0) || diagnostics.length > 0) {
    return { state: "unknown", detail: diagnostics.join("\n") || String(result.stdout).trim() || `lsof exited ${result.status}` };
  }
  const processes = [];
  let current = null;
  for (const field of fieldLines) {
    const type = field[0];
    const value = field.slice(1);
    if (type === "p") {
      current = { pid: Number.parseInt(value, 10), command: "", paths: [] };
      processes.push(current);
    } else if (!current) {
      return { state: "unknown", detail: `unparseable lsof field: ${field}` };
    } else if (type === "c") {
      current.command = value;
    } else if (type === "n") {
      current.paths.push(value);
    }
  }
  if (processes.some((entry) => Number.isNaN(entry.pid))) {
    return { state: "unknown", detail: "lsof returned an invalid process id" };
  }
  const active = processes.filter((entry) => !processHasMarker(entry.pid, marker));
  return active.length > 0
    ? { state: "active", detail: active.slice(0, 8).map((entry) => `${entry.pid} ${entry.command} ${entry.paths.join(", ")}`).join("\n") }
    : { state: "clear", detail: "no open files" };
}

function processHasMarker(pid, marker) {
  if (pid === process.pid) return true;
  const result = spawnSync("ps", ["eww", "-p", String(pid)], { encoding: "utf8" });
  if (result.error || result.status !== 0) return false;
  return result.stdout.includes(`${marker}=1`);
}

function requireClearProcesses(root) {
  const proof = processProof(root);
  if (proof.state !== "clear") {
    fail(`process state for ${root} is ${proof.state}: ${proof.detail}`, EXIT.safety);
  }
  return proof;
}

function ensurePhysicalDirectory(path, label) {
  if (!existsSync(path)) {
    const parent = dirname(path);
    if (!existsSync(parent)) {
      mkdirSync(parent, { mode: 0o700 });
    }
    physicalStat(parent, `${label} parent`, "directory");
    mkdirSync(path, { mode: 0o700 });
  }
  physicalStat(path, label, "directory");
  return realpathSync(path);
}

function ensurePhysicalChild(parent, name, label) {
  const parentReal = realpathExisting(parent, `${label} parent`);
  physicalStat(parentReal, `${label} parent`, "directory");
  const child = join(parentReal, name);
  const childReal = ensurePhysicalDirectory(child, label);
  if (childReal !== child || dirname(childReal) !== parentReal) {
    fail(`${label} escapes its physical parent: ${child}`, EXIT.safety);
  }
  return childReal;
}

function metadataRoot(commonDir) {
  physicalStat(commonDir, "Git common directory", "directory");
  const candidate = join(commonDir, "buwiz-workspace-maintenance");
  const candidateReal = ensurePhysicalDirectory(candidate, "maintenance state directory");
  if (!isContained(commonDir, candidateReal)) {
    fail(`maintenance state directory escapes the Git common directory: ${candidateReal}`, EXIT.safety);
  }
  return candidateReal;
}

function quarantineBase(context, targetRoot, create = true) {
  const identity = createHash("sha256").update(context.commonDir).digest("hex").slice(0, 16);
  const targetDevice = lstatSync(targetRoot).dev;
  let parent = dirname(targetRoot);
  while (true) {
    const parentReal = realpathExisting(parent, "quarantine parent");
    physicalStat(parentReal, "quarantine parent", "directory");
    const maintenanceParent = join(parentReal, ".buwiz-workspace-maintenance");
    const candidate = join(maintenanceParent, identity);
    const overlaps = context.records.some((record) => record.pathReal && isContained(record.pathReal, candidate));
    if (!overlaps && lstatSync(parentReal).dev === targetDevice) {
      const maintenanceParentReal = create
        ? ensurePhysicalChild(parentReal, ".buwiz-workspace-maintenance", "quarantine namespace")
        : realpathExisting(maintenanceParent, "quarantine namespace");
      physicalStat(maintenanceParentReal, "quarantine namespace", "directory");
      if (maintenanceParentReal !== maintenanceParent) {
        fail(`quarantine namespace escapes its physical parent: ${maintenanceParent}`, EXIT.safety);
      }
      const candidateReal = create
        ? ensurePhysicalChild(maintenanceParentReal, identity, "quarantine base")
        : realpathExisting(candidate, "quarantine base");
      physicalStat(candidateReal, "quarantine base", "directory");
      if (candidateReal !== candidate) {
        fail(`quarantine base escapes its physical parent: ${candidate}`, EXIT.safety);
      }
      if (context.records.some((record) => record.pathReal && isContained(record.pathReal, candidateReal))) {
        fail(`quarantine base overlaps a registered worktree: ${candidateReal}`, EXIT.safety);
      }
      if (lstatSync(candidateReal).dev !== targetDevice) {
        fail(`quarantine base is on a different filesystem: ${candidateReal}`, EXIT.safety);
      }
      return candidateReal;
    }
    const next = dirname(parentReal);
    if (next === parentReal) {
      fail(`could not find a same-filesystem quarantine outside registered worktrees for ${targetRoot}`, EXIT.safety);
    }
    parent = next;
  }
}

function writeReceipt(path, receipt) {
  let fd;
  try {
    fd = openSync(path, "wx", 0o600);
    writeFileSync(fd, `${JSON.stringify(receipt, null, 2)}\n`);
    fsyncSync(fd);
  } catch (error) {
    fail(`could not create exclusive receipt ${path}: ${error.message}`, EXIT.safety);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function lockPath(commonDir) {
  return join(metadataRoot(commonDir), "lock.json");
}

function acquireLock(commonDir, snapshotDigest) {
  const path = lockPath(commonDir);
  const token = randomUUID();
  let fd;
  let lockIdentity;
  try {
    fd = openSync(path, "wx", 0o600);
    lockIdentity = fstatSync(fd);
    const owner = `${JSON.stringify({ version: VERSION, token, pid: process.pid, host: hostname(), startedAt: new Date().toISOString(), snapshotDigest }, null, 2)}\n`;
    writeFileSync(fd, owner);
    fsyncSync(fd);
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    if (lockIdentity) {
      try {
        const stat = lstatSync(path);
        if (stat.isFile() && !stat.isSymbolicLink() && stat.dev === lockIdentity.dev && stat.ino === lockIdentity.ino) {
          unlinkSync(path);
        }
      } catch {
        // Leave an uncertain lock in place rather than remove the wrong path.
      }
    }
    fail(`repository maintenance lock is already held: ${path}`, EXIT.safety);
  }
  closeSync(fd);
  return () => {
    try {
      const stat = lstatSync(path);
      const owner = JSON.parse(readFileSync(path, "utf8"));
      if (stat.isFile() && !stat.isSymbolicLink() && stat.dev === lockIdentity.dev && stat.ino === lockIdentity.ino && owner.token === token) {
        unlinkSync(path);
      } else {
        process.stderr.write(`warning: maintenance lock identity changed; refusing to remove ${path}\n`);
      }
    } catch (error) {
      process.stderr.write(`warning: could not safely release maintenance lock ${path}: ${error.message}\n`);
    }
  };
}

function cleanInventoryRecord(record) {
  if (!record.pathReal) {
    return { path: record.path, state: "missing" };
  }
  const artifacts = {};
  for (const [target, paths] of Object.entries(TARGETS)) {
    artifacts[target] = paths.map((path) => snapshotEntry(record.pathReal, path, { inventoryOnly: true })).filter((entry) => entry.exists);
  }
  return {
    path: record.path,
    head: record.HEAD,
    branch: typeof record.branch === "string" ? record.branch.replace("refs/heads/", "") : record.detached ? "detached" : null,
    flags: [record.locked && "locked", record.prunable && "prunable"].filter(Boolean),
    artifacts,
  };
}

function renderInventory(inventory, json, stream = process.stdout) {
  if (json) {
    stream.write(`${JSON.stringify(inventory, null, 2)}\n`);
    return;
  }
  for (const record of inventory) {
    stream.write(`${record.path}\n`);
    if (record.state) {
      stream.write(`  state: ${record.state}\n`);
      continue;
    }
    stream.write(`  branch: ${record.branch || "unknown"}\n`);
    for (const [target, entries] of Object.entries(record.artifacts)) {
      const bytes = entries.reduce((total, entry) => total + entry.bytes, 0);
      const unsafe = entries.filter((entry) => entry.unsafe).map((entry) => `${entry.relativePath}: ${entry.unsafe}`);
      stream.write(`  ${target}: ${entries.length} roots, ${bytes} bytes${unsafe.length ? `; blocked (${unsafe.join(", ")})` : ""}\n`);
    }
  }
}

function commandClean(args) {
  const { options, positionals } = parseOptions(args, new Set(["--dry-run", "--force", "--json", "--worktree", "--all-worktrees"]));
  if (positionals.length === 0) {
    const context = repoContext(invocationCwd());
    process.stderr.write(`${usageClean()}\n`);
    process.stderr.write("\nCurrent registered-worktree inventory:\n");
    renderInventory(context.records.map(cleanInventoryRecord), false, process.stderr);
    process.exitCode = EXIT.usage;
    return;
  }
  if (positionals[0] === "purge") {
    commandCleanPurge(positionals, options);
    return;
  }
  if (positionals.length !== 1) {
    fail("clean accepts exactly one target", EXIT.usage);
  }
  const target = positionals[0];
  const context = repoContext(invocationCwd());
  if (target === "list") {
    if (options.force || options.dryRun || options.worktree) {
      fail("clean list accepts only --all-worktrees and --json", EXIT.usage);
    }
    const selected = options.allWorktrees ? context.records : [context.current];
    renderInventory(selected.map(cleanInventoryRecord), options.json);
    return;
  }
  if (options.json) {
    fail("--json is available only with clean list", EXIT.usage);
  }
  if (options.worktree && options.allWorktrees) {
    fail("--worktree and --all-worktrees cannot be combined", EXIT.usage);
  }
  if (options.allWorktrees) {
    fail("--all-worktrees is read-only and available only with clean list", EXIT.safety);
  }
  if (target === "all" && !options.force) {
    fail("clean all requires --force", EXIT.safety);
  }
  const paths = expandTarget(target);
  let selected;
  if (options.worktree) {
    if (!options.force) {
      fail("cross-worktree cleanup requires --force", EXIT.safety);
    }
    selected = [resolveRequestedWorktree(context, options.worktree)];
  } else {
    selected = [context.current];
  }
  for (const record of selected) {
    if (record.locked || record.prunable || record.missing) {
      fail(`worktree cannot be cleaned in its current topology state: ${record.path}`, EXIT.safety);
    }
    const descendants = context.records.filter((candidate) => candidate !== record && candidate.pathReal && isContained(record.pathReal, candidate.pathReal));
    for (const relativePath of paths) {
      const root = resolve(record.pathReal, relativePath);
      if (descendants.some((descendant) => isContained(root, descendant.pathReal) || isContained(descendant.pathReal, root))) {
        fail(`artifact root overlaps registered descendant worktree: ${root}`, EXIT.safety);
      }
    }
  }
  const plan = selected.map((record) => ({
    record,
    entries: paths.map((path) => snapshotEntry(record.pathReal, path)).filter((entry) => entry.exists),
  }));
  for (const item of plan) {
    process.stdout.write(`${options.dryRun ? "Would clean" : "Cleaning"} ${item.record.path}\n`);
    for (const entry of item.entries) {
      process.stdout.write(`  ${entry.relativePath}: ${entry.bytes} bytes, ${entry.entries} entries\n`);
    }
    if (item.entries.length === 0) {
      process.stdout.write("  no matching artifacts\n");
    }
  }
  if (options.dryRun || plan.every((item) => item.entries.length === 0)) {
    return;
  }
  requireMutationPlatform();
  for (const item of plan) {
    requireClearProcesses(item.record.pathReal);
  }
  const digest = createHash("sha256").update(JSON.stringify(plan.map((item) => ({ path: item.record.path, head: item.record.HEAD, entries: item.entries })))).digest("hex");
  const moved = [];
  const transactionRoot = join(quarantineBase(context, plan[0].record.pathReal), `${digest.slice(0, 16)}-${randomUUID()}`);
  const quarantineRoot = dirname(transactionRoot);
  const quarantineIdentity = identity(quarantineRoot, "quarantine base", "directory");
  const quarantineNamespaceIdentity = identity(dirname(quarantineRoot), "quarantine namespace", "directory");
  const release = acquireLock(context.commonDir, digest);
  try {
    const fresh = repoContext(invocationCwd());
    if (!contextTopologyEqual(context, fresh)) {
      fail("repository worktree topology changed after planning; nothing was deleted", EXIT.safety);
    }
    for (const item of plan) {
      const freshRecord = fresh.records.find((record) => record.path === item.record.path);
      if (!freshRecord || freshRecord.HEAD !== item.record.HEAD || freshRecord.locked || freshRecord.prunable || freshRecord.missing) {
        fail("worktree state changed after planning; nothing was deleted", EXIT.safety);
      }
      requireClearProcesses(item.record.pathReal);
      if (!item.entries.every(snapshotMatches)) {
        fail("artifact state changed after planning; nothing was deleted", EXIT.safety);
      }
      for (const entry of item.entries) {
        const verified = snapshotEntry(item.record.pathReal, entry.relativePath);
        if (!verified.exists || !snapshotMatches(entry)) {
          fail(`artifact eligibility changed after planning: ${entry.absolute}`, EXIT.safety);
        }
      }
    }
    if (realpathExisting(quarantineRoot, "quarantine base") !== quarantineRoot
      || !identityMatches(quarantineIdentity) || !identityMatches(quarantineNamespaceIdentity)) {
      fail("quarantine base changed after planning; nothing was deleted", EXIT.safety);
    }
    const transactionReal = ensurePhysicalChild(quarantineRoot, basename(transactionRoot), "quarantine transaction");
    const transactionIdentity = identity(transactionReal, "quarantine transaction", "directory");
    for (const item of plan) {
      for (const entry of item.entries) {
        if (!identityMatches(quarantineIdentity) || !identityMatches(quarantineNamespaceIdentity) || !identityMatches(transactionIdentity)) {
          fail("quarantine topology changed immediately before moving artifacts", EXIT.safety);
        }
        if (!snapshotMatches(entry)) {
          fail(`artifact changed immediately before quarantine: ${entry.absolute}`, EXIT.safety);
        }
        const verified = snapshotEntry(item.record.pathReal, entry.relativePath);
        if (!verified.exists || !snapshotMatches(entry)) {
          fail(`artifact eligibility changed immediately before quarantine: ${entry.absolute}`, EXIT.safety);
        }
        const destination = join(transactionRoot, createHash("sha256").update(item.record.path).digest("hex").slice(0, 12), entry.relativePath);
        if (!isContained(transactionRoot, destination)) {
          fail(`quarantine destination escaped its transaction: ${destination}`, EXIT.safety);
        }
        mkdirSync(dirname(destination), { recursive: true });
        renameSync(entry.absolute, destination);
        moved.push({ source: entry.absolute, destination });
      }
    }
    const receipt = {
      version: VERSION,
      operation: "clean",
      createdAt: new Date().toISOString(),
      digest,
      transactionRoot,
      quarantineRoot,
      sourceWorktrees: plan.map((item) => item.record.path),
      moves: moved.map(({ source, destination }) => {
        const original = plan.flatMap((item) => item.entries).find((entry) => entry.absolute === source);
        return { source, destination, bytes: original.bytes, entries: original.entries };
      }),
    };
    receipt.contentsDigest = createHash("sha256").update(JSON.stringify(receipt.moves)).digest("hex");
    writeReceipt(join(transactionRoot, "receipt.json"), receipt);
    process.stdout.write(`Quarantined artifacts; nothing has been permanently deleted.\n  receipt: ${join(transactionRoot, "receipt.json")}\n`);
    process.stdout.write(`Review it, then reclaim disk with: just clean purge '${join(transactionRoot, "receipt.json")}' --force\n`);
  } catch (error) {
    let rollbackFailure = null;
    for (const entry of [...moved].reverse()) {
      if (!existsSync(entry.destination)) {
        continue;
      }
      try {
        mkdirSync(dirname(entry.source), { recursive: true });
        renameSync(entry.destination, entry.source);
      } catch (rollbackError) {
        rollbackFailure = rollbackError;
      }
    }
    if (existsSync(transactionRoot) && !rollbackFailure) {
      rmSync(transactionRoot, { recursive: true, force: true });
    }
    if (rollbackFailure) {
      fail(`artifact cleanup failed and rollback was incomplete; quarantine retained at ${transactionRoot}: ${rollbackFailure.message}`);
    }
    throw error;
  } finally {
    release();
  }
}

function worktreeStatus(root) {
  return git(root, ["status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=none"], { encoding: "buffer" }).stdout;
}

function operationBlocker(target) {
  for (const name of GIT_OPERATION_PATHS) {
    if (existsSync(join(target.gitDirReal, name))) {
      return name;
    }
  }
  return null;
}

function hasConflicts(root) {
  const result = git(root, ["ls-files", "-u", "-z"], { encoding: "buffer" });
  return result.stdout.length > 0;
}

function hasSubmodules(root) {
  if (existsSync(join(root, ".gitmodules"))) {
    return true;
  }
  const result = git(root, ["ls-files", "--stage", "-z"], { encoding: "buffer" });
  return result.stdout.toString("utf8").split("\0").some((entry) => entry.startsWith("160000 "));
}

function protectedIgnored(root) {
  const result = git(root, ["ls-files", "--others", "--ignored", "--exclude-standard", "-z"], { encoding: "buffer" });
  return result.stdout.toString("utf8").split("\0").filter(Boolean);
}

function resolveIntegrationRef(root, ref) {
  const result = git(root, ["rev-parse", "--verify", `${ref}^{commit}`], { allowFailure: true });
  return result.status === 0 ? result.stdout.trim() : null;
}

function isAncestor(root, head, refOid) {
  if (!refOid) {
    return false;
  }
  return git(root, ["merge-base", "--is-ancestor", head, refOid], { allowFailure: true }).status === 0;
}

function validateRemoval(context, target, options) {
  const blockers = [];
  if (!topologyMatches(target)) blockers.push("worktree topology identity changed");
  const operation = operationBlocker(target);
  if (operation) blockers.push(`Git operation is in progress (${operation})`);
  if (hasConflicts(target.pathReal)) blockers.push("working tree has unresolved conflicts");
  if (hasSubmodules(target.pathReal)) blockers.push("worktree contains submodules");
  const protectedPaths = protectedIgnored(target.pathReal);
  if (protectedPaths.length) blockers.push(`worktree contains ignored data; clean it explicitly first: ${protectedPaths.join(", ")}`);
  const process = processProof(target.pathReal);
  if (process.state !== "clear") blockers.push(`process state is ${process.state}: ${process.detail}`);
  const status = worktreeStatus(target.pathReal);
  const refOid = resolveIntegrationRef(target.pathReal, options.into);
  const merged = isAncestor(target.pathReal, target.HEAD, refOid);
  if (!options.force && status.length > 0) blockers.push("working tree is not clean");
  if (!options.force && !merged) blockers.push(`HEAD ${target.HEAD} is not an ancestor of ${options.into}${refOid ? ` (${refOid})` : " (unresolved)"}`);
  return { blockers, status, refOid, merged, process, protectedPaths };
}

function commandWorktreeRemove(args) {
  const { options, positionals } = parseOptions(args, new Set(["--dry-run", "--force", "--into"]));
  if (positionals.length !== 1) {
    const context = repoContext(invocationCwd());
    process.stderr.write("error: choose one exact absolute registered worktree path; nothing was removed\n\nRegistered worktrees:\n");
    for (const record of context.records) {
      process.stderr.write(`  ${record.path}\n`);
    }
    process.exitCode = EXIT.usage;
    return;
  }
  const context = repoContext(invocationCwd());
  const target = resolveRequestedWorktree(context, positionals[0]);
  const validation = validateRemoval(context, target, options);
  if (validation.blockers.length) {
    fail(`refusing to remove ${target.path}:\n  - ${validation.blockers.join("\n  - ")}`, EXIT.safety);
  }
  process.stdout.write(`${options.dryRun ? "Would remove" : "Removing"} worktree ${target.path}\n`);
  process.stdout.write(`  HEAD: ${target.HEAD}\n`);
  process.stdout.write(`  integration ref: ${options.into}${validation.refOid ? ` (${validation.refOid})` : " (unresolved; force override)"}\n`);
  process.stdout.write(`  clean: ${validation.status.length === 0 ? "yes" : "no (force override)"}\n`);
  if (options.dryRun) {
    return;
  }
  requireMutationPlatform();
  const digest = createHash("sha256").update(JSON.stringify({
    version: VERSION,
    target: target.path,
    head: target.HEAD,
    status: validation.status.toString("base64"),
    into: options.into,
    refOid: validation.refOid,
    force: options.force,
  })).digest("hex");
  const release = acquireLock(context.commonDir, digest);
  try {
    const fresh = repoContext(invocationCwd());
    if (!contextTopologyEqual(context, fresh)) {
      fail("repository worktree topology changed after planning; nothing was removed", EXIT.safety);
    }
    const freshTarget = resolveRequestedWorktree(fresh, target.path);
    if (freshTarget.HEAD !== target.HEAD || freshTarget.branch !== target.branch || Boolean(freshTarget.detached) !== Boolean(target.detached)) {
      fail("worktree HEAD or attachment state changed after planning; nothing was removed", EXIT.safety);
    }
    const freshValidation = validateRemoval(fresh, freshTarget, options);
    if (freshValidation.blockers.length
      || !freshValidation.status.equals(validation.status)
      || freshValidation.refOid !== validation.refOid) {
      fail("worktree state changed after planning; nothing was removed", EXIT.safety);
    }
    const immediateProcess = processProof(freshTarget.pathReal);
    if (immediateProcess.state !== "clear") {
      fail(`process state changed immediately before removal: ${immediateProcess.state}: ${immediateProcess.detail}`, EXIT.safety);
    }
    if (!worktreeStatus(freshTarget.pathReal).equals(validation.status)) {
      fail("worktree status changed immediately before removal; nothing was removed", EXIT.safety);
    }
    if (!topologyMatches(freshTarget)) {
      fail("worktree topology changed immediately before removal; nothing was removed", EXIT.safety);
    }
    let rescueRef = null;
    if (options.force && freshTarget.detached) {
      const timestamp = new Date().toISOString().replaceAll(/[-:.]/gu, "").replace("Z", "Z");
      rescueRef = `refs/buwiz/worktree-rescue/${timestamp}-${digest.slice(0, 16)}`;
      git(context.top, ["update-ref", "--create-reflog", rescueRef, freshTarget.HEAD, ""]);
      process.stdout.write(`  rescue ref: ${rescueRef}\n`);
    }
    const receipt = {
      version: VERSION,
      operation: "worktree-remove",
      createdAt: new Date().toISOString(),
      target: target.path,
      head: target.HEAD,
      branch: target.branch || null,
      integrationRef: options.into,
      integrationOid: validation.refOid,
      forced: options.force,
      rescueRef,
      snapshotDigest: digest,
    };
    const receiptDir = ensurePhysicalChild(metadataRoot(context.commonDir), "receipts", "maintenance receipt directory");
    const receiptPath = join(receiptDir, `${new Date().toISOString().replaceAll(":", "-")}-${digest.slice(0, 16)}.json`);
    writeReceipt(receiptPath, receipt);
    const removeArgs = ["worktree", "remove"];
    if (options.force && validation.status.length > 0) removeArgs.push("--force");
    removeArgs.push("--", target.path);
    git(context.top, removeArgs);
    const after = repoContext(context.top);
    if (after.records.some((record) => record.path === target.path) || existsSync(target.path)) {
      fail(`Git did not fully remove the worktree; inspect receipt ${receiptPath}`);
    }
    process.stdout.write(`  receipt: ${receiptPath}\n`);
  } finally {
    release();
  }
}

function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === "clean") {
    commandClean(args);
    return;
  }
  if (command === "worktree-remove") {
    commandWorktreeRemove(args);
    return;
  }
  fail("usage: workspace-maintenance.mjs <clean|worktree-remove> [arguments]", EXIT.usage);
}

try {
  main();
} catch (error) {
  if (error instanceof MaintenanceError) {
    process.stderr.write(`error: ${error.message}\n`);
    process.exitCode = error.exitCode;
  } else {
    process.stderr.write(`error: ${error?.stack || error}\n`);
    process.exitCode = EXIT.operational;
  }
}
