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
  readlinkSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { hostname, tmpdir } from "node:os";
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
const executedTestHooks = new Set();

class MaintenanceError extends Error {
  constructor(message, exitCode = EXIT.operational) {
    super(message);
    this.exitCode = exitCode;
  }
}

function fail(message, exitCode = EXIT.operational) {
  throw new MaintenanceError(message, exitCode);
}

function posixShellQuote(value) {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

function testHooksEnabled() {
  return process.env.NODE_ENV === "test"
    && /^child(?:-|$)/u.test(process.env.NODE_TEST_CONTEXT || "");
}

function runTestHook(name, payload = {}) {
  if (!testHooksEnabled()
    || process.env.WORKSPACE_MAINTENANCE_TEST_HOOK !== name
    || executedTestHooks.has(name)) {
    return;
  }
  executedTestHooks.add(name);
  const marker = process.env.WORKSPACE_MAINTENANCE_TEST_MARKER;
  const release = process.env.WORKSPACE_MAINTENANCE_TEST_RELEASE;
  const action = process.env.WORKSPACE_MAINTENANCE_TEST_ACTION || "continue";
  if (!marker || !release || !isAbsolute(marker) || !isAbsolute(release)
    || resolve(marker) !== marker || resolve(release) !== release
    || dirname(marker) !== dirname(release)
    || basename(marker) !== "marker.json" || basename(release) !== "release"
    || !["continue", "fail"].includes(action)) {
    fail(`invalid test-hook configuration for ${name}`, EXIT.safety);
  }
  const temporaryRoot = realpathExisting(tmpdir(), "system temporary directory");
  const hookRoot = realpathExisting(dirname(marker), "test-hook directory");
  const hookRootStat = physicalStat(hookRoot, "test-hook directory", "directory");
  const wrongOwner = typeof process.getuid === "function" && hookRootStat.uid !== process.getuid();
  if (!isContained(temporaryRoot, hookRoot) || (hookRootStat.mode & 0o777) !== 0o700 || wrongOwner) {
    fail(`test-hook directory is outside the system temporary directory: ${hookRoot}`, EXIT.safety);
  }
  let fd;
  try {
    fd = openSync(marker, "wx", 0o600);
    writeFileSync(fd, `${JSON.stringify({ name, ...payload })}\n`);
    fsyncSync(fd);
  } catch (error) {
    fail(`could not create test-hook marker ${marker}: ${error.message}`, EXIT.safety);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
  const signal = new Int32Array(new SharedArrayBuffer(4));
  const deadline = Date.now() + 10_000;
  while (lstatOptional(release, "test-hook release") === null) {
    if (Date.now() >= deadline) {
      fail(`timed out waiting for test-hook release: ${name}`, EXIT.safety);
    }
    Atomics.wait(signal, 0, 0, 20);
  }
  const releaseIdentity = identity(release, "test-hook release", "file");
  const releaseStat = lstatSync(release);
  const releaseWrongOwner = typeof process.getuid === "function" && releaseStat.uid !== process.getuid();
  if ((releaseStat.mode & 0o077) !== 0 || releaseWrongOwner
    || readFileSync(release, "utf8") !== "continue\n" || !identityMatches(releaseIdentity)) {
    fail(`test-hook release is not an exact private signal: ${release}`, EXIT.safety);
  }
  if (action === "fail") {
    fail(`injected test failure at ${name}`, EXIT.safety);
  }
}

function injectTestFailure(name) {
  if (testHooksEnabled()
    && process.env.WORKSPACE_MAINTENANCE_TEST_FAIL_AT === name) {
    fail(`injected test failure at ${name}`, EXIT.safety);
  }
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

function lstatOptional(path, label) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    fail(`${label} could not be inspected: ${path}: ${error.message}`, EXIT.safety);
  }
}

function physicalArtifactPath(root, relativePath, inventoryOnly = false) {
  const absolute = resolve(root, relativePath);
  const relativeFromRoot = relative(root, absolute);
  if (!relativeFromRoot || relativeFromRoot === ".." || relativeFromRoot.startsWith(`..${sep}`)
    || isAbsolute(relativeFromRoot)) {
    fail(`artifact path escapes its registered worktree: ${relativePath}`, EXIT.safety);
  }
  if (realpathExisting(root, "registered worktree root") !== root) {
    fail(`registered worktree root must be canonical and physical: ${root}`, EXIT.safety);
  }

  const parts = relativeFromRoot.split(sep);
  const ancestors = [identity(root, "registered worktree root", "directory")];
  let current = root;
  for (const part of parts.slice(0, -1)) {
    current = join(current, part);
    const stat = lstatOptional(current, "artifact ancestor");
    if (stat === null) return { absolute, ancestors, exists: false };
    if (stat.isSymbolicLink()) {
      const unsafe = `symbolic link artifact ancestor: ${current}`;
      if (inventoryOnly) return { absolute, ancestors, exists: true, unsafe };
      fail(`refusing ${unsafe}`, EXIT.safety);
    }
    if (!stat.isDirectory()) {
      const unsafe = `non-directory artifact ancestor: ${current}`;
      if (inventoryOnly) return { absolute, ancestors, exists: true, unsafe };
      fail(`refusing ${unsafe}`, EXIT.safety);
    }
    if (realpathExisting(current, "artifact ancestor") !== current || !isContained(root, current)) {
      fail(`artifact ancestor escapes its registered worktree: ${current}`, EXIT.safety);
    }
    ancestors.push(identity(current, "artifact ancestor", "directory"));
  }
  return { absolute, ancestors, exists: lstatOptional(absolute, "artifact root") !== null };
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

function requireDistinctNonOverlappingPaths(paths, label) {
  for (let left = 0; left < paths.length; left += 1) {
    for (let right = left + 1; right < paths.length; right += 1) {
      if (isContained(paths[left], paths[right]) || isContained(paths[right], paths[left])) {
        fail(`cleanup receipt contains duplicate or overlapping ${label}: ${paths[left]} and ${paths[right]}`, EXIT.safety);
      }
    }
  }
}

function validateReceiptTransactionLayout(transactionRoot, receiptPath, destinations) {
  const destinationSet = new Set(destinations);
  const structuralDirectories = new Set([transactionRoot]);
  for (const destination of destinations) {
    let parent = dirname(destination);
    while (parent !== transactionRoot) {
      if (!isContained(transactionRoot, parent)) {
        fail(`cleanup receipt destination escapes its transaction: ${destination}`, EXIT.safety);
      }
      structuralDirectories.add(parent);
      parent = dirname(parent);
    }
  }

  const stack = [transactionRoot];
  while (stack.length) {
    const current = stack.pop();
    if (current === receiptPath || destinationSet.has(current)) continue;
    if (!structuralDirectories.has(current)) {
      fail(`quarantine transaction contains content not named by the receipt: ${current}`, EXIT.safety);
    }
    physicalStat(current, "quarantine structural directory", "directory");
    for (const name of readdirSync(current)) stack.push(join(current, name));
  }
}

function rebaseContainedPath(path, originalRoot, replacementRoot, label) {
  const relativePath = relative(originalRoot, path);
  if (!relativePath || relativePath === ".." || relativePath.startsWith(`..${sep}`)
    || isAbsolute(relativePath)) {
    fail(`${label} is not below its transaction root: ${path}`, EXIT.safety);
  }
  return join(replacementRoot, relativePath);
}

function fileIdentityMatchesAt(expected, path) {
  try {
    const stat = lstatSync(path);
    return stat.isFile() && !stat.isSymbolicLink()
      && stat.dev === expected.dev && stat.ino === expected.ino
      && stat.mode === expected.mode && stat.mtimeMs === expected.mtimeMs;
  } catch {
    return false;
  }
}

function manifestType(stat) {
  if (stat.isDirectory()) return "directory";
  if (stat.isFile()) return "file";
  if (stat.isSymbolicLink()) return "symlink";
  fail("cleanup manifest encountered an unsupported filesystem entry", EXIT.safety);
}

function manifestEntry(root, path) {
  const stat = lstatSync(path);
  const type = manifestType(stat);
  return {
    relativePath: relative(root, path),
    type,
    dev: stat.dev,
    ino: stat.ino,
    mode: stat.mode,
    mtimeMs: stat.mtimeMs,
    size: stat.size,
    linkTarget: type === "symlink" ? readlinkSync(path) : null,
  };
}

function manifestEntryMatchesAt(entry, path, options = {}) {
  const { allowDirectoryMetadataChange = false } = options;
  try {
    const stat = lstatSync(path);
    return manifestType(stat) === entry.type
      && stat.dev === entry.dev && stat.ino === entry.ino && stat.mode === entry.mode
      && (allowDirectoryMetadataChange && entry.type === "directory"
        || (stat.mtimeMs === entry.mtimeMs && stat.size === entry.size))
      && (entry.type !== "symlink" || readlinkSync(path) === entry.linkTarget);
  } catch {
    return false;
  }
}

function buildDeletionManifest(root) {
  const entries = [];
  const stack = [root];
  while (stack.length) {
    const path = stack.pop();
    const entry = manifestEntry(root, path);
    entries.push(entry);
    if (entry.type === "directory") {
      for (const name of readdirSync(path)) stack.push(join(path, name));
    }
  }
  return entries;
}

function deletionManifestsEqual(left, right) {
  if (left.length !== right.length) return false;
  const rightByPath = new Map(right.map((entry) => [entry.relativePath, entry]));
  return rightByPath.size === right.length && left.every((entry) => {
    const candidate = rightByPath.get(entry.relativePath);
    return candidate && JSON.stringify(candidate) === JSON.stringify(entry);
  });
}

function captureStableDeletionManifest(root, label) {
  const manifest = buildDeletionManifest(root);
  if (!deletionManifestsEqual(manifest, buildDeletionManifest(root))) {
    fail(`${label} changed while its deletion manifest was captured: ${root}`, EXIT.safety);
  }
  return manifest;
}

function requireExactDeletionManifest(root, manifest, label) {
  const observed = buildDeletionManifest(root);
  if (!deletionManifestsEqual(manifest, observed)) {
    fail(`${label} no longer matches its authorized deletion manifest; retained at ${root}`, EXIT.safety);
  }
}

function deletionDepth(entry) {
  return entry.relativePath ? entry.relativePath.split(sep).length : 0;
}

function deleteIdentityManifest(root, manifest) {
  const byRelativePath = new Map(manifest.map((entry) => [entry.relativePath, entry]));
  if (byRelativePath.size !== manifest.length || byRelativePath.get("")?.type !== "directory") {
    fail(`deletion manifest is incomplete; retained at ${root}`, EXIT.safety);
  }
  const parentIdentity = identity(dirname(root), "purge tombstone parent", "directory");
  const verifyParents = (path) => {
    if (!identityMatches(parentIdentity)) return false;
    let current = dirname(path);
    while (isContained(root, current)) {
      const entry = byRelativePath.get(relative(root, current));
      if (!entry || entry.type !== "directory"
        || !manifestEntryMatchesAt(entry, current, { allowDirectoryMetadataChange: true })) return false;
      if (current === root) break;
      current = dirname(current);
    }
    return true;
  };

  const leaves = manifest
    .filter((entry) => entry.type !== "directory")
    .sort((left, right) => deletionDepth(right) - deletionDepth(left)
      || left.relativePath.localeCompare(right.relativePath));
  const directories = manifest
    .filter((entry) => entry.type === "directory")
    .sort((left, right) => deletionDepth(right) - deletionDepth(left)
      || left.relativePath.localeCompare(right.relativePath));

  try {
    for (const entry of leaves) {
      const path = join(root, entry.relativePath);
      const capture = join(dirname(path), `.${basename(path)}.deleting-${randomUUID()}`);
      runTestHook("before-delete-entry-rename", { relativePath: entry.relativePath, path, capture, root });
      if (!verifyParents(path) || !manifestEntryMatchesAt(entry, path)
        || lstatOptional(capture, "purge capture") !== null) {
        fail(`purge entry changed before capture: ${path}`, EXIT.safety);
      }
      renameSync(path, capture);
      runTestHook("after-delete-entry-rename", { relativePath: entry.relativePath, path, capture, root });
      if (!verifyParents(capture) || !manifestEntryMatchesAt(entry, capture)) {
        fail(`purge capture does not match its manifest entry: ${capture}`, EXIT.safety);
      }
      runTestHook("before-delete-entry-unlink", { relativePath: entry.relativePath, path, capture, root });
      if (!verifyParents(capture) || !manifestEntryMatchesAt(entry, capture)) {
        fail(`purge capture changed before unlink: ${capture}`, EXIT.safety);
      }
      unlinkSync(capture);
    }
    for (const entry of directories) {
      const path = join(root, entry.relativePath);
      runTestHook("before-delete-directory-rmdir", { relativePath: entry.relativePath, path, root });
      if ((path === root ? !identityMatches(parentIdentity) : !verifyParents(path))
        || !manifestEntryMatchesAt(entry, path, { allowDirectoryMetadataChange: true })) {
        fail(`purge directory changed before removal: ${path}`, EXIT.safety);
      }
      rmdirSync(path);
    }
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    fail(`purge stopped; unverified content was not recursively deleted; retained at ${root}: ${detail}`, EXIT.safety);
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
  const receiptIdentity = identity(receiptReal, "cleanup receipt", "file");
  let receiptText;
  let receipt;
  try {
    receiptText = readFileSync(receiptReal, "utf8");
    receipt = JSON.parse(receiptText);
  } catch {
    fail(`cleanup receipt is not valid JSON: ${receiptReal}`, EXIT.safety);
  }
  if (!identityMatches(receiptIdentity)) {
    fail(`cleanup receipt changed while it was being read: ${receiptReal}`, EXIT.safety);
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
  if (new Set(receipt.sourceWorktrees).size !== receipt.sourceWorktrees.length) {
    fail(`cleanup receipt contains duplicate source worktrees: ${receiptReal}`, EXIT.safety);
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
  const expectedDigest = createHash("sha256")
    .update(JSON.stringify({ moves: receipt.moves, nativeSymlinks: receipt.nativeSymlinks }))
    .digest("hex");
  if (receipt.contentsDigest !== expectedDigest) {
    fail(`cleanup receipt digest is invalid: ${receiptReal}`, EXIT.safety);
  }
  const plannedMoves = receipt.moves.map((move) => {
    if (!move || typeof move.source !== "string" || typeof move.destination !== "string"
      || typeof move.bytes !== "number" || typeof move.entries !== "number") {
      fail(`cleanup receipt contains an invalid move entry: ${receiptReal}`, EXIT.safety);
    }
    const destination = resolve(move.destination);
    if (destination !== move.destination || destination === transactionRoot
      || !isContained(transactionRoot, destination) || destination === receiptReal) {
      fail(`cleanup receipt destination escapes its transaction: ${move.destination}`, EXIT.safety);
    }
    physicalStat(destination, "quarantined artifact root", "directory");
    if (!isAbsolute(move.source) || resolve(move.source) !== move.source) {
      fail(`cleanup receipt source is not an exact absolute path: ${move.source}`, EXIT.safety);
    }
    const sourceMatches = receipt.sourceWorktrees
      .filter((root) => typeof root === "string" && isContained(root, move.source))
      .map((root) => ({ root, relativePath: relative(root, move.source) }))
      .filter(({ relativePath }) => ALL_TARGETS.flatMap((name) => TARGETS[name]).includes(relativePath));
    if (sourceMatches.length !== 1) {
      fail(`cleanup receipt source is outside the literal artifact catalog: ${move.source}`, EXIT.safety);
    }
    const [{ root: sourceRoot, relativePath: sourceRelative }] = sourceMatches;
    const expectedDestination = join(
      transactionRoot,
      createHash("sha256").update(sourceRoot).digest("hex").slice(0, 12),
      sourceRelative,
    );
    if (destination !== expectedDestination) {
      fail(`cleanup receipt destination does not match its recorded source: ${move.destination}`, EXIT.safety);
    }
    return { move, destination };
  });
  requireDistinctNonOverlappingPaths(plannedMoves.map(({ move }) => move.source), "move sources");
  requireDistinctNonOverlappingPaths(plannedMoves.map(({ destination }) => destination), "move destinations");
  validateReceiptTransactionLayout(
    transactionRoot,
    receiptReal,
    plannedMoves.map(({ destination }) => destination),
  );
  const receiptSymlinks = verifiedReceiptNativeSymlinks(receipt, receiptReal);
  for (const { move, destination } of plannedMoves) {
    const actual = directorySize(destination, { receiptSymlinks });
    if (actual.bytes !== move.bytes || actual.entries !== move.entries) {
      fail(`quarantined artifact size does not match its receipt: ${destination}`, EXIT.safety);
    }
  }
  const size = directorySize(transactionRoot, { receiptSymlinks });
  const deletionManifest = captureStableDeletionManifest(transactionRoot, "quarantine transaction");
  return {
    receipt,
    receiptPath: receiptReal,
    receiptIdentity,
    receiptFileDigest: createHash("sha256").update(receiptText).digest("hex"),
    transactionRoot,
    quarantineRoot,
    transactionIdentity: identity(transactionRoot, "quarantine transaction", "directory"),
    quarantineIdentity: identity(quarantineRoot, "quarantine root", "directory"),
    deletionManifest,
    size,
  };
}

function validateTombstonedReceipt(parsed, tombstone) {
  const tombstoneReceipt = join(tombstone, relative(parsed.transactionRoot, parsed.receiptPath));
  if (!fileIdentityMatchesAt(parsed.receiptIdentity, tombstoneReceipt)) {
    fail(`cleanup receipt identity changed after tombstoning; retained at ${tombstone}`, EXIT.safety);
  }
  const receiptText = readFileSync(tombstoneReceipt, "utf8");
  if (createHash("sha256").update(receiptText).digest("hex") !== parsed.receiptFileDigest
    || !fileIdentityMatchesAt(parsed.receiptIdentity, tombstoneReceipt)) {
    fail(`cleanup receipt changed after tombstoning; retained at ${tombstone}`, EXIT.safety);
  }
  const rebasedMoves = parsed.receipt.moves.map((move) => ({
    ...move,
    destination: rebaseContainedPath(
      move.destination,
      parsed.transactionRoot,
      tombstone,
      "cleanup receipt destination",
    ),
  }));
  const rebasedReceipt = {
    ...parsed.receipt,
    transactionRoot: tombstone,
    moves: rebasedMoves,
    nativeSymlinks: parsed.receipt.nativeSymlinks.map((link) => ({
      ...link,
      path: rebaseContainedPath(
        link.path,
        parsed.transactionRoot,
        tombstone,
        "cleanup receipt Native identity link",
      ),
    })),
  };
  const destinations = rebasedMoves.map((move) => move.destination);
  validateReceiptTransactionLayout(tombstone, tombstoneReceipt, destinations);
  const receiptSymlinks = verifiedReceiptNativeSymlinks(rebasedReceipt, tombstoneReceipt);
  for (const move of rebasedMoves) {
    const actual = directorySize(move.destination, { receiptSymlinks });
    if (actual.bytes !== move.bytes || actual.entries !== move.entries) {
      fail(`quarantined artifact changed after tombstoning; retained at ${tombstone}`, EXIT.safety);
    }
  }
  directorySize(tombstone, { receiptSymlinks });
  requireExactDeletionManifest(tombstone, parsed.deletionManifest, "tombstoned quarantine transaction");
  return parsed.deletionManifest;
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
      || verified.size.entries !== planned.size.entries
      || !deletionManifestsEqual(verified.deletionManifest, planned.deletionManifest)) {
      fail("quarantine changed after planning; nothing was purged", EXIT.safety);
    }
    runTestHook("before-purge-tombstone", { path: verified.transactionRoot });
    requireExactDeletionManifest(
      verified.transactionRoot,
      planned.deletionManifest,
      "quarantine transaction",
    );
    const tombstone = moveVerifiedDirectoryToTombstone(
      verified.transactionRoot,
      verified.transactionIdentity,
      "purge",
    );
    const manifest = validateTombstonedReceipt(verified, tombstone);
    runTestHook("after-purge-manifest", { root: tombstone });
    deleteIdentityManifest(tombstone, manifest);
    if (existsSync(tombstone)) {
      fail(`quarantine purge did not complete: ${tombstone}`);
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

function allowedNativeIdentityLink(root, artifactRelativePath, linkPath) {
  if (artifactRelativePath !== ".native") return false;
  const linkRelative = relative(join(root, ".native"), linkPath).split(sep);
  if (linkRelative.length !== 3 || linkRelative[0] !== "identities"
    || !linkRelative[1] || !["src", "assets"].includes(linkRelative[2])) {
    return false;
  }
  const leaf = linkRelative[2];
  try {
    const expectedTarget = join(root, leaf);
    physicalStat(expectedTarget, `generated Native ${leaf} target`, "directory");
    const declaredTarget = resolve(dirname(linkPath), readlinkSync(linkPath));
    const expectedReal = realpathSync(expectedTarget);
    return realpathSync(declaredTarget) === expectedReal && realpathSync(linkPath) === expectedReal;
  } catch {
    return false;
  }
}

function verifiedReceiptNativeSymlinks(receipt, receiptPath) {
  const allowed = new Map();
  const recorded = receipt.nativeSymlinks;
  if (!Array.isArray(recorded)) {
    fail(`cleanup receipt does not record its Native identity links: ${receiptPath}`, EXIT.safety);
  }
  for (const entry of recorded) {
    if (!entry || typeof entry.path !== "string" || typeof entry.target !== "string"
      || ![entry.dev, entry.ino, entry.mode, entry.mtimeMs].every((value) => typeof value === "number")) {
      fail(`cleanup receipt contains an invalid Native identity link: ${receiptPath}`, EXIT.safety);
    }
    allowed.set(entry.path, entry);
  }
  const discovered = new Set();
  for (const move of receipt.moves) {
    const sourceRoot = receipt.sourceWorktrees.find((root) => typeof root === "string" && isContained(root, move.source));
    if (!sourceRoot || relative(sourceRoot, move.source) !== ".native") continue;
    const identitiesRoot = join(move.destination, "identities");
    const identitiesStat = lstatOptional(identitiesRoot, "quarantined Native identities directory");
    if (identitiesStat === null) continue;
    physicalStat(identitiesRoot, "quarantined Native identities directory", "directory");
    if (realpathExisting(identitiesRoot, "quarantined Native identities directory") !== identitiesRoot) {
      fail(`quarantined Native identities directory escapes its physical path: ${identitiesRoot}`, EXIT.safety);
    }
    for (const name of readdirSync(identitiesRoot)) {
      const identityRoot = join(identitiesRoot, name);
      const identityStat = lstatSync(identityRoot);
      if (identityStat.isSymbolicLink() || !identityStat.isDirectory()) continue;
      if (realpathExisting(identityRoot, "quarantined Native identity directory") !== identityRoot) {
        fail(`quarantined Native identity directory escapes its physical path: ${identityRoot}`, EXIT.safety);
      }
      for (const leaf of ["src", "assets"]) {
        const candidate = join(identityRoot, leaf);
        const stat = lstatOptional(candidate, "quarantined Native identity link");
        if (!stat?.isSymbolicLink()) continue;
        discovered.add(candidate);
        const expectedTarget = join(sourceRoot, leaf);
        const expectedReal = realpathExisting(expectedTarget, `source worktree ${leaf}`);
        if (realpathExisting(resolve(dirname(candidate), readlinkSync(candidate)), "quarantined Native identity link target") !== expectedReal
          || realpathExisting(candidate, "quarantined Native identity link") !== expectedReal) {
          fail(`quarantined Native identity link does not target its source worktree ${leaf}: ${candidate}`, EXIT.safety);
        }
        const recordedLink = allowed.get(candidate);
        if (!recordedLink || recordedLink.target !== expectedReal
          || recordedLink.dev !== stat.dev || recordedLink.ino !== stat.ino
          || recordedLink.mode !== stat.mode || recordedLink.mtimeMs !== stat.mtimeMs) {
          fail(`quarantined Native identity link was not recorded by the receipt or changed identity: ${candidate}`, EXIT.safety);
        }
      }
    }
  }
  if ([...allowed.keys()].some((path) => !discovered.has(path))) {
    fail(`cleanup receipt records a missing Native identity link: ${receiptPath}`, EXIT.safety);
  }
  return allowed;
}

function directorySize(path, options = {}) {
  const { root = path, artifactRelativePath = null, inventoryOnly = false, receiptSymlinks = null } = options;
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
      const receiptLink = receiptSymlinks?.get(current);
      const receiptAllowsLink = receiptLink !== undefined
        && stat.dev === receiptLink.dev && stat.ino === receiptLink.ino
        && stat.mode === receiptLink.mode && stat.mtimeMs === receiptLink.mtimeMs;
      if (!inventoryOnly && !receiptAllowsLink && !allowedNativeIdentityLink(root, artifactRelativePath, current)) {
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

function nativeSymlinkSnapshot(root, artifactRelativePath, artifactRoot) {
  if (artifactRelativePath !== ".native") return [];
  const links = [];
  const stack = [artifactRoot];
  while (stack.length) {
    const current = stack.pop();
    const stat = lstatSync(current);
    if (stat.isSymbolicLink()) {
      if (!allowedNativeIdentityLink(root, artifactRelativePath, current)) {
        fail(`refusing nested symbolic link inside artifact root: ${current}`, EXIT.safety);
      }
      links.push({
        relativePath: relative(artifactRoot, current),
        target: realpathExisting(current, "generated Native identity link"),
        dev: stat.dev,
        ino: stat.ino,
        mode: stat.mode,
        mtimeMs: stat.mtimeMs,
      });
      continue;
    }
    if (stat.isDirectory()) {
      for (const name of readdirSync(current)) stack.push(join(current, name));
    }
  }
  return links.sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function nativeSymlinkSnapshotsEqual(left, right) {
  return JSON.stringify(left ?? []) === JSON.stringify(right ?? []);
}

function nativeSymlinksMatchAt(entry, artifactRoot) {
  return (entry.nativeSymlinks ?? []).every((link) => {
    const path = join(artifactRoot, link.relativePath);
    try {
      const stat = lstatSync(path);
      return stat.isSymbolicLink()
        && stat.dev === link.dev && stat.ino === link.ino
        && stat.mode === link.mode && stat.mtimeMs === link.mtimeMs
        && realpathSync(path) === link.target;
    } catch {
      return false;
    }
  });
}

function snapshotEntry(root, relativePath, options = {}) {
  const physicalPath = physicalArtifactPath(root, relativePath, options.inventoryOnly);
  const { absolute, ancestors } = physicalPath;
  if (!physicalPath.exists) {
    return { relativePath, absolute, exists: false, ancestors };
  }
  if (physicalPath.unsafe) {
    return { relativePath, absolute, exists: true, unsafe: physicalPath.unsafe, bytes: 0, entries: 1, ancestors };
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
  const tracked = git(root, ["ls-files", "--error-unmatch", "--", relativePath], { allowFailure: true });
  if (tracked.status === 0) {
    fail(`refusing tracked artifact path: ${absolute}`, EXIT.safety);
  }
  const ignored = git(root, ["check-ignore", "--quiet", "--no-index", "--", relativePath], { allowFailure: true });
  if (ignored.status !== 0) {
    fail(`refusing artifact path that is not ignored: ${absolute}`, EXIT.safety);
  }
  const size = directorySize(absolute, { root, artifactRelativePath: relativePath, inventoryOnly: options.inventoryOnly });
  const nativeSymlinks = options.inventoryOnly ? [] : nativeSymlinkSnapshot(root, relativePath, absolute);
  return {
    relativePath,
    absolute,
    exists: true,
    dev: stat.dev,
    ino: stat.ino,
    mode: stat.mode,
    mtimeMs: stat.mtimeMs,
    ancestors,
    nativeSymlinks,
    ...size,
  };
}

function snapshotMatches(entry) {
  if (entry.ancestors?.some((ancestor) => !identityMatches(ancestor))) {
    return false;
  }
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
    && stat.mtimeMs === entry.mtimeMs
    && nativeSymlinksMatchAt(entry, entry.absolute);
}

function snapshotsEquivalent(planned, verified) {
  return verified.exists
    && planned.absolute === verified.absolute
    && planned.dev === verified.dev && planned.ino === verified.ino
    && planned.mode === verified.mode && planned.mtimeMs === verified.mtimeMs
    && nativeSymlinkSnapshotsEqual(planned.nativeSymlinks, verified.nativeSymlinks);
}

function snapshotRootMatchesAt(entry, path) {
  try {
    const stat = lstatSync(path);
    return stat.isDirectory() && !stat.isSymbolicLink()
      && stat.dev === entry.dev
      && stat.ino === entry.ino
      && stat.mode === entry.mode
      && stat.mtimeMs === entry.mtimeMs;
  } catch {
    return false;
  }
}

function directoryIdentityMatchesAt(expected, path) {
  try {
    const stat = lstatSync(path);
    return stat.isDirectory() && !stat.isSymbolicLink()
      && stat.dev === expected.dev && stat.ino === expected.ino
      && stat.mode === expected.mode;
  } catch {
    return false;
  }
}

function moveVerifiedDirectoryToTombstone(path, expectedIdentity, label) {
  if (!directoryIdentityMatchesAt(expectedIdentity, path)) {
    fail(`${label} identity changed before tombstoning; retained at ${path}`, EXIT.safety);
  }
  const parent = dirname(path);
  const parentIdentity = identity(parent, `${label} parent`, "directory");
  const tombstone = join(parent, `.${basename(path)}.deleting-${randomUUID()}`);
  if (lstatOptional(tombstone, `${label} tombstone`) !== null) {
    fail(`${label} tombstone already exists: ${tombstone}`, EXIT.safety);
  }
  runTestHook(`before-${label}-tombstone`, { path, tombstone });
  if (!identityMatches(parentIdentity) || !directoryIdentityMatchesAt(expectedIdentity, path)
    || lstatOptional(tombstone, `${label} tombstone`) !== null) {
    fail(`${label} identity changed at tombstone boundary; retained at ${path}`, EXIT.safety);
  }
  renameSync(path, tombstone);
  if (!directoryIdentityMatchesAt(expectedIdentity, tombstone)) {
    fail(`${label} tombstone does not match the verified directory; retained at ${tombstone}`, EXIT.safety);
  }
  if (lstatOptional(path, `${label} original path`) !== null) {
    fail(`${label} original path was repopulated during tombstoning; retained at ${tombstone}`, EXIT.safety);
  }
  runTestHook(`after-${label}-tombstone`, { path, tombstone });
  return tombstone;
}

function ensurePhysicalRelativeDirectory(parent, relativePath, label) {
  let current = parent;
  const identities = [identity(parent, `${label} root`, "directory")];
  for (const part of relativePath.split(sep).filter((entry) => entry && entry !== ".")) {
    if (part === "..") {
      fail(`${label} escapes its physical parent: ${relativePath}`, EXIT.safety);
    }
    current = ensurePhysicalChild(current, part, label);
    identities.push(identity(current, label, "directory"));
  }
  return { path: current, identities };
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

function parseProcessId(value, label) {
  if (!/^[1-9][0-9]*$/u.test(value || "")) {
    fail(`${label} must be one positive process id`, EXIT.safety);
  }
  const pid = Number.parseInt(value, 10);
  if (!Number.isSafeInteger(pid)) {
    fail(`${label} is outside the supported process id range`, EXIT.safety);
  }
  return pid;
}

function processRecord(pid) {
  const result = spawnSync("ps", ["-o", "pid=,ppid=,comm=", "-p", String(pid)], { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    fail(`could not verify maintenance launcher process ${pid}`, EXIT.safety);
  }
  const lines = result.stdout.split("\n").map((line) => line.trim()).filter(Boolean);
  if (lines.length !== 1) {
    fail(`maintenance launcher process ${pid} returned ambiguous process state`, EXIT.safety);
  }
  const match = lines[0].match(/^(\d+)\s+(\d+)\s+(.+)$/u);
  if (!match || Number.parseInt(match[1], 10) !== pid) {
    fail(`maintenance launcher process ${pid} returned malformed process state`, EXIT.safety);
  }
  return { pid, ppid: Number.parseInt(match[2], 10), command: match[3] };
}

function lsofExecutable() {
  if (existsSync("/usr/sbin/lsof")) return "/usr/sbin/lsof";
  if (existsSync("/usr/bin/lsof")) return "/usr/bin/lsof";
  fail("lsof is unavailable", EXIT.safety);
}

function processExecutable(pid) {
  const result = spawnSync(lsofExecutable(), ["-nP", "-a", "-p", String(pid), "-d", "txt", "-Fn"], { encoding: "utf8" });
  if (result.error || result.status !== 0) {
    fail(`could not verify maintenance launcher executable for process ${pid}`, EXIT.safety);
  }
  const paths = result.stdout.split("\n").filter((line) => line.startsWith("n")).map((line) => line.slice(1));
  if (paths.length === 0) {
    fail(`maintenance launcher process ${pid} returned no executable`, EXIT.safety);
  }
  return realpathExisting(paths[0], "maintenance launcher executable");
}

function trustedLauncherPids() {
  const suppliedPid = process.env.WORKSPACE_MAINTENANCE_JUST_PID;
  const suppliedExecutable = process.env.WORKSPACE_MAINTENANCE_JUST_EXE;
  if (!suppliedPid && !suppliedExecutable) return new Set();
  if (!suppliedPid || !suppliedExecutable) {
    fail("maintenance launcher proof requires both Just process and executable", EXIT.safety);
  }
  const justPid = parseProcessId(suppliedPid, "WORKSPACE_MAINTENANCE_JUST_PID");
  const declaredExecutable = realpathExisting(suppliedExecutable, "declared Just executable");
  const just = processRecord(justPid);
  if (basename(just.command) !== "just" || basename(declaredExecutable) !== "just") {
    fail(`maintenance launcher process ${justPid} is not Just`, EXIT.safety);
  }
  if (processExecutable(justPid) !== declaredExecutable) {
    fail(`maintenance launcher process ${justPid} does not match its declared executable`, EXIT.safety);
  }
  const trusted = new Set([just.pid]);
  if (process.ppid !== justPid) {
    const recipeShell = processRecord(process.ppid);
    if (recipeShell.ppid !== justPid || !["bash", "dash", "ksh", "sh", "zsh"].includes(basename(recipeShell.command))) {
      fail("maintenance process is not a direct recipe-shell child of Just", EXIT.safety);
    }
    trusted.add(recipeShell.pid);
  }
  let ancestorPid = just.ppid;
  for (let depth = 0; ancestorPid > 1 && depth < 32; depth += 1) {
    let ancestor;
    try {
      ancestor = processRecord(ancestorPid);
    } catch (error) {
      if (error instanceof MaintenanceError) break;
      throw error;
    }
    trusted.add(ancestor.pid);
    ancestorPid = ancestor.ppid;
  }
  return trusted;
}

function processProof(root, trustedPids = new Set(), artifactRoots = []) {
  let lsof;
  try {
    lsof = lsofExecutable();
  } catch (error) {
    if (error instanceof MaintenanceError) return { state: "unknown", detail: error.message };
    throw error;
  }
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
      current = { pid: Number.parseInt(value, 10), command: "", files: [] };
      processes.push(current);
    } else if (!current) {
      return { state: "unknown", detail: `unparseable lsof field: ${field}` };
    } else if (type === "c") {
      current.command = value;
    } else if (type === "f") {
      current.files.push({ descriptor: value, path: null });
    } else if (type === "n") {
      if (current.files.length === 0 || current.files.at(-1).path !== null) {
        return { state: "unknown", detail: `unparseable lsof path field: ${field}` };
      }
      current.files.at(-1).path = value;
    }
  }
  if (processes.some((entry) => Number.isNaN(entry.pid) || entry.files.some((file) => file.path === null))) {
    return { state: "unknown", detail: "lsof returned an invalid process id" };
  }
  const isSafeLauncher = (entry) => trustedPids.has(entry.pid) && entry.files.every((file) =>
    file.descriptor === "cwd"
      && isAbsolute(file.path)
      && !artifactRoots.some((artifactRoot) => isContained(artifactRoot, file.path)));
  const active = processes.filter((entry) => !isSafeLauncher(entry) && !processHasMarker(entry.pid, marker));
  return active.length > 0
    ? { state: "active", detail: active.slice(0, 8).map((entry) => `${entry.pid} ${entry.command} ${entry.files.map((file) => `${file.descriptor}:${file.path}`).join(", ")}`).join("\n") }
    : { state: "clear", detail: "no open files" };
}

function processHasMarker(pid, marker) {
  if (pid === process.pid) return true;
  const result = spawnSync("ps", ["eww", "-p", String(pid)], { encoding: "utf8" });
  if (result.error || result.status !== 0) return false;
  return result.stdout.includes(`${marker}=1`);
}

function requireClearProcesses(root, artifactRoots) {
  const proof = processProof(root, trustedLauncherPids(), artifactRoots);
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

function quarantineLocation(context, targetRoot) {
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
      return { parent: parentReal, namespace: maintenanceParent, base: candidate, identity, targetDevice };
    }
    const next = dirname(parentReal);
    if (next === parentReal) {
      fail(`could not find a same-filesystem quarantine outside registered worktrees for ${targetRoot}`, EXIT.safety);
    }
    parent = next;
  }
}

function quarantineBase(context, targetRoot, create = true) {
  const location = quarantineLocation(context, targetRoot);
  const maintenanceParentReal = create
    ? ensurePhysicalChild(location.parent, ".buwiz-workspace-maintenance", "quarantine namespace")
    : realpathExisting(location.namespace, "quarantine namespace");
  physicalStat(maintenanceParentReal, "quarantine namespace", "directory");
  if (maintenanceParentReal !== location.namespace) {
    fail(`quarantine namespace escapes its physical parent: ${location.namespace}`, EXIT.safety);
  }
  const candidateReal = create
    ? ensurePhysicalChild(maintenanceParentReal, location.identity, "quarantine base")
    : realpathExisting(location.base, "quarantine base");
  physicalStat(candidateReal, "quarantine base", "directory");
  if (candidateReal !== location.base) {
    fail(`quarantine base escapes its physical parent: ${location.base}`, EXIT.safety);
  }
  if (context.records.some((record) => record.pathReal && isContained(record.pathReal, candidateReal))) {
    fail(`quarantine base overlaps a registered worktree: ${candidateReal}`, EXIT.safety);
  }
  if (lstatSync(candidateReal).dev !== location.targetDevice) {
    fail(`quarantine base is on a different filesystem: ${candidateReal}`, EXIT.safety);
  }
  return candidateReal;
}

function outstandingCleanupReceipts(context, target) {
  const location = quarantineLocation(context, target.pathReal);
  if (lstatOptional(location.namespace, "quarantine namespace") === null) {
    return { receipts: [], uncertainty: null };
  }
  try {
    physicalStat(location.namespace, "quarantine namespace", "directory");
    if (realpathExisting(location.namespace, "quarantine namespace") !== location.namespace) {
      fail(`quarantine namespace escapes its physical parent: ${location.namespace}`, EXIT.safety);
    }
    if (lstatOptional(location.base, "quarantine base") === null) {
      return { receipts: [], uncertainty: null };
    }
    const base = quarantineBase(context, target.pathReal, false);
    const receipts = [];
    for (const name of readdirSync(base)) {
      const transactionRoot = join(base, name);
      physicalStat(transactionRoot, "quarantine transaction", "directory");
      if (realpathExisting(transactionRoot, "quarantine transaction") !== transactionRoot) {
        fail(`quarantine transaction escapes its physical path: ${transactionRoot}`, EXIT.safety);
      }
      const recoveryPath = join(transactionRoot, "recovery.json");
      if (lstatOptional(recoveryPath, "cleanup recovery receipt") !== null) {
        physicalStat(recoveryPath, "cleanup recovery receipt", "file");
        fail(`cleanup transaction requires manual recovery: ${recoveryPath}`, EXIT.safety);
      }
      const receiptPath = join(transactionRoot, "receipt.json");
      physicalStat(receiptPath, "cleanup receipt", "file");
      const parsed = parseReceipt(receiptPath, context);
      if (parsed.receipt.sourceWorktrees.includes(target.path)) {
        receipts.push(receiptPath);
      }
    }
    return { receipts, uncertainty: null };
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    return { receipts: [], uncertainty: detail };
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

function recoveryPayload(plan, moved, transactionRoot, quarantineRoot, digest, reason) {
  const payload = {
    version: VERSION,
    operation: "clean-partial",
    recovery: true,
    createdAt: new Date().toISOString(),
    digest,
    transactionRoot,
    quarantineRoot,
    sourceWorktrees: plan.map((item) => item.record.path),
    reason,
    moves: moved.map(({ source, destination, entry, verification }) => ({
      source,
      destination,
      verification,
      expectedRootIdentity: {
        type: "directory",
        dev: entry.dev,
        ino: entry.ino,
        mode: entry.mode,
        mtimeMs: entry.mtimeMs,
      },
      bytes: entry.bytes,
      entries: entry.entries,
      nativeSymlinks: entry.nativeSymlinks.map((link) => ({
        relativePath: link.relativePath,
        target: link.target,
        dev: link.dev,
        ino: link.ino,
        mode: link.mode,
        mtimeMs: link.mtimeMs,
      })),
    })),
    nativeSymlinks: moved.flatMap(({ destination, entry }) => entry.nativeSymlinks.map((link) => ({
      path: join(destination, link.relativePath),
      target: link.target,
      dev: link.dev,
      ino: link.ino,
      mode: link.mode,
      mtimeMs: link.mtimeMs,
    }))),
  };
  payload.contentsDigest = createHash("sha256")
    .update(JSON.stringify({ moves: payload.moves, nativeSymlinks: payload.nativeSymlinks }))
    .digest("hex");
  return payload;
}

function removeKnownEmptyDirectories(identities) {
  const unique = new Map(identities.map((entry) => [entry.path, entry]));
  const ordered = [...unique.values()].sort((left, right) =>
    right.path.split(sep).length - left.path.split(sep).length
      || left.path.localeCompare(right.path));
  for (const expected of ordered) {
    if (!identityMatches(expected)) {
      return `structural directory identity changed: ${expected.path}`;
    }
    try {
      rmdirSync(expected.path);
    } catch (error) {
      return `structural directory was not empty or could not be removed: ${expected.path}: ${error.message}`;
    }
  }
  return null;
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
    requireClearProcesses(item.record.pathReal, item.entries.map((entry) => entry.absolute));
  }
  const digest = createHash("sha256").update(JSON.stringify(plan.map((item) => ({ path: item.record.path, head: item.record.HEAD, entries: item.entries })))).digest("hex");
  const moved = [];
  const transactionRoot = join(quarantineBase(context, plan[0].record.pathReal), `${digest.slice(0, 16)}-${randomUUID()}`);
  const quarantineRoot = dirname(transactionRoot);
  const quarantineIdentity = identity(quarantineRoot, "quarantine base", "directory");
  const quarantineNamespaceIdentity = identity(dirname(quarantineRoot), "quarantine namespace", "directory");
  const release = acquireLock(context.commonDir, digest);
  let transactionIdentity = null;
  const transactionDirectories = [];
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
      requireClearProcesses(item.record.pathReal, item.entries.map((entry) => entry.absolute));
      if (!item.entries.every(snapshotMatches)) {
        fail("artifact state changed after planning; nothing was deleted", EXIT.safety);
      }
      for (const entry of item.entries) {
        const verified = snapshotEntry(item.record.pathReal, entry.relativePath);
        if (!snapshotsEquivalent(entry, verified) || !snapshotMatches(entry)) {
          fail(`artifact eligibility changed after planning: ${entry.absolute}`, EXIT.safety);
        }
      }
    }
    if (realpathExisting(quarantineRoot, "quarantine base") !== quarantineRoot
      || !identityMatches(quarantineIdentity) || !identityMatches(quarantineNamespaceIdentity)) {
      fail("quarantine base changed after planning; nothing was deleted", EXIT.safety);
    }
    const transactionReal = ensurePhysicalChild(quarantineRoot, basename(transactionRoot), "quarantine transaction");
    transactionIdentity = identity(transactionReal, "quarantine transaction", "directory");
    transactionDirectories.push(transactionIdentity);
    for (const item of plan) {
      for (const entry of item.entries) {
        if (!identityMatches(quarantineIdentity) || !identityMatches(quarantineNamespaceIdentity) || !identityMatches(transactionIdentity)) {
          fail("quarantine topology changed immediately before moving artifacts", EXIT.safety);
        }
        if (!snapshotMatches(entry)) {
          fail(`artifact changed immediately before quarantine: ${entry.absolute}`, EXIT.safety);
        }
        const verified = snapshotEntry(item.record.pathReal, entry.relativePath);
        if (!snapshotsEquivalent(entry, verified) || !snapshotMatches(entry)) {
          fail(`artifact eligibility changed immediately before quarantine: ${entry.absolute}`, EXIT.safety);
        }
        const destination = join(transactionRoot, createHash("sha256").update(item.record.path).digest("hex").slice(0, 12), entry.relativePath);
        if (!isContained(transactionRoot, destination)) {
          fail(`quarantine destination escaped its transaction: ${destination}`, EXIT.safety);
        }
        const destinationParent = ensurePhysicalRelativeDirectory(
          transactionRoot,
          relative(transactionRoot, dirname(destination)),
          "quarantine destination directory",
        );
        transactionDirectories.push(...destinationParent.identities.filter((entry) =>
          entry.path !== transactionRoot && isContained(transactionRoot, entry.path)));
        runTestHook("before-artifact-rename", {
          source: entry.absolute,
          destination,
          destinationParent: destinationParent.path,
          transactionRoot,
        });
        if (destinationParent.path !== dirname(destination)
          || !destinationParent.identities.every(identityMatches)
          || !identityMatches(transactionIdentity)
          || !entry.ancestors.every(identityMatches)
          || !snapshotRootMatchesAt(entry, entry.absolute)) {
          fail(`artifact or quarantine identity changed at rename boundary: ${entry.absolute}`, EXIT.safety);
        }
        renameSync(entry.absolute, destination);
        const movedEntry = { source: entry.absolute, destination, entry, verification: "uncertain" };
        moved.push(movedEntry);
        runTestHook("after-artifact-rename", { source: entry.absolute, destination });
        injectTestFailure("after-artifact-rename");
        if (!snapshotRootMatchesAt(entry, destination) || !nativeSymlinksMatchAt(entry, destination)) {
          fail(`quarantined artifact identity does not match its snapshot: ${destination}`, EXIT.safety);
        }
        movedEntry.verification = "verified";
      }
    }
    const receipt = {
      version: VERSION,
      operation: "clean",
      createdAt: new Date().toISOString(),
      digest,
      contentsDigest: null,
      transactionRoot,
      quarantineRoot,
      sourceWorktrees: plan.map((item) => item.record.path),
      moves: moved.map(({ source, destination, entry }) => {
        return { source, destination, bytes: entry.bytes, entries: entry.entries };
      }),
      nativeSymlinks: moved.flatMap(({ destination, entry }) => {
        return entry.nativeSymlinks.map((link) => ({
          path: join(destination, link.relativePath),
          target: link.target,
          dev: link.dev,
          ino: link.ino,
          mode: link.mode,
          mtimeMs: link.mtimeMs,
        }));
      }),
    };
    receipt.contentsDigest = createHash("sha256")
      .update(JSON.stringify({ moves: receipt.moves, nativeSymlinks: receipt.nativeSymlinks }))
      .digest("hex");
    writeReceipt(join(transactionRoot, "receipt.json"), receipt);
    process.stdout.write(`Quarantined artifacts; nothing has been permanently deleted.\n  receipt: ${join(transactionRoot, "receipt.json")}\n`);
    process.stdout.write(`Review it, then reclaim disk with: just clean purge ${posixShellQuote(join(transactionRoot, "receipt.json"))} --force\n`);
  } catch (error) {
    if (moved.length > 0 && transactionIdentity && existsSync(transactionRoot)) {
      const reason = error instanceof MaintenanceError ? error.message : error?.message || String(error);
      const recoveryPath = join(transactionRoot, "recovery.json");
      if (!identityMatches(quarantineNamespaceIdentity)
        || !identityMatches(quarantineIdentity)
        || !identityMatches(transactionIdentity)) {
        fail(`artifact cleanup failed; moved artifacts retained at ${transactionRoot}; recovery receipt was not written because the quarantine identity changed: ${reason}`, EXIT.safety);
      }
      try {
        writeReceipt(
          recoveryPath,
          recoveryPayload(plan, moved, transactionRoot, quarantineRoot, digest, reason),
        );
      } catch (receiptError) {
        fail(`artifact cleanup failed; moved artifacts retained at ${transactionRoot}; recovery receipt could not be written: ${receiptError.message}`, EXIT.safety);
      }
      fail(`artifact cleanup failed after moving artifacts; no automatic rollback was attempted; recovery retained at ${recoveryPath}: ${reason}`, EXIT.safety);
    }
    if (transactionIdentity && existsSync(transactionRoot)) {
      const cleanupFailure = removeKnownEmptyDirectories(transactionDirectories);
      if (cleanupFailure) {
        const reason = error instanceof MaintenanceError ? error.message : error?.message || String(error);
        fail(`artifact cleanup failed before any artifact moved; no unknown content was deleted; transaction retained at ${transactionRoot}: ${cleanupFailure}; original failure: ${reason}`, EXIT.safety);
      }
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
  const cleanup = outstandingCleanupReceipts(context, target);
  if (cleanup.uncertainty) {
    blockers.push(`cleanup quarantine state is uncertain: ${cleanup.uncertainty}`);
  } else if (cleanup.receipts.length) {
    blockers.push(`worktree has unpurged cleanup receipts; purge them before removal: ${cleanup.receipts.join(", ")}`);
  }
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
  return { blockers, status, refOid, merged, process, protectedPaths, cleanup };
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
