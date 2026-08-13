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
const PURGE_JOURNAL_VERSION = 3;
const WORKTREE_REMOVAL_JOURNAL_VERSION = 1;
const CLEAN_JOURNAL_VERSION = 3;
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
  const actual = realpathExisting(process.cwd(), "process working directory");
  const supplied = process.env.WORKSPACE_MAINTENANCE_CWD;
  if (!supplied) return actual;
  if (!isAbsolute(supplied) || resolve(supplied) !== supplied) {
    fail("WORKSPACE_MAINTENANCE_CWD must be one exact absolute path", EXIT.safety);
  }
  const declared = realpathExisting(supplied, "declared maintenance working directory");
  const actualCommon = realpathExisting(
    resolve(actual, gitText(actual, ["rev-parse", "--git-common-dir"])),
    "actual Git common directory",
  );
  const declaredCommon = realpathExisting(
    resolve(declared, gitText(declared, ["rev-parse", "--git-common-dir"])),
    "declared Git common directory",
  );
  if (actualCommon !== declaredCommon) {
    fail("WORKSPACE_MAINTENANCE_CWD belongs to a different repository", EXIT.safety);
  }
  if (declared !== actual) {
    fail("WORKSPACE_MAINTENANCE_CWD cannot retarget the actual process worktree", EXIT.safety);
  }
  return actual;
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
    "  just clean resume /exact/cleanup/journal.json --dry-run",
    "  just clean resume /exact/cleanup/journal.json --force",
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
    nlink: stat.nlink,
    mtimeMs: stat.mtimeMs,
    size: stat.size,
    contentDigest: type === "file"
      ? createHash("sha256").update(readFileSync(path)).digest("hex")
      : null,
    linkTarget: type === "symlink" ? readlinkSync(path) : null,
  };
}

function manifestEntryMatchesAt(entry, path, options = {}) {
  const { allowDirectoryMetadataChange = false } = options;
  try {
    const stat = lstatSync(path);
    return manifestType(stat) === entry.type
      && stat.dev === entry.dev && stat.ino === entry.ino && stat.mode === entry.mode
      && (entry.type === "directory" || stat.nlink === entry.nlink)
      && (allowDirectoryMetadataChange && entry.type === "directory"
        || (stat.mtimeMs === entry.mtimeMs && stat.size === entry.size))
      && (entry.type !== "symlink" || readlinkSync(path) === entry.linkTarget)
      && (entry.type !== "file"
        || createHash("sha256").update(readFileSync(path)).digest("hex") === entry.contentDigest);
  } catch {
    return false;
  }
}

function decodeLinuxMountPath(value) {
  return value.replaceAll(/\\([0-7]{3})/gu, (_, octal) => String.fromCharCode(Number.parseInt(octal, 8)));
}

function parseLinuxMountInfo(text) {
  return text.split("\n").filter(Boolean).map((line) => {
    const fields = line.split(" ");
    const separator = fields.indexOf("-");
    if (separator < 6 || separator + 3 > fields.length) {
      fail("Linux mount table is malformed", EXIT.safety);
    }
    const mountpoint = decodeLinuxMountPath(fields[4]);
    if (!isAbsolute(mountpoint)) fail("Linux mount table contains a non-absolute mountpoint", EXIT.safety);
    return resolve(mountpoint);
  });
}

function parseMacMounts(text) {
  return text.split("\n").filter(Boolean).map((line) => {
    const match = line.match(/^.+ on ((?:\\[0-7]{3}|[^\\\n])+) \([^\n]+\)$/u);
    if (!match) fail("macOS mount table is malformed", EXIT.safety);
    const mountpoint = match[1].replaceAll(/\\([0-7]{3})/gu, (_, octal) =>
      String.fromCharCode(Number.parseInt(octal, 8)));
    if (mountpoint.includes("\\")) fail("macOS mount table contains an unsupported escape", EXIT.safety);
    if (!isAbsolute(mountpoint)) fail("macOS mount table contains a non-absolute mountpoint", EXIT.safety);
    return resolve(mountpoint);
  });
}

function mountpoints() {
  if (process.platform === "linux") {
    return parseLinuxMountInfo(readFileSync("/proc/self/mountinfo", "utf8"));
  }
  if (process.platform === "darwin") {
    const result = run("/sbin/mount", []);
    return parseMacMounts(result.stdout);
  }
  fail("mount-boundary verification is unavailable on this platform", EXIT.safety);
}

function requireNoNestedMounts(root, label) {
  const rootReal = realpathExisting(root, label);
  const nested = mountpoints().filter((mountpoint) => mountpoint !== rootReal && isContained(rootReal, mountpoint));
  if (nested.length > 0) {
    fail(`${label} contains nested mountpoints: ${nested.join(", ")}`, EXIT.safety);
  }
}

function buildDeletionManifest(root) {
  requireNoNestedMounts(root, "deletion manifest root");
  const entries = [];
  const stack = [root];
  const rootDevice = lstatSync(root).dev;
  while (stack.length) {
    const path = stack.pop();
    const entry = manifestEntry(root, path);
    if (entry.dev !== rootDevice) {
      fail(`deletion manifest crosses a filesystem boundary: ${path}`, EXIT.safety);
    }
    entries.push(entry);
    if (entry.type === "directory") {
      for (const name of readdirSync(path)) stack.push(join(path, name));
    }
  }
  return entries;
}

function requireNoHardlinkedFiles(manifest, root, label) {
  const hardlinks = manifest.filter((entry) => entry.type === "file" && entry.nlink !== 1);
  if (hardlinks.length > 0) {
    fail(`${label} contains hard-linked regular files: ${hardlinks.map((entry) => join(root, entry.relativePath)).join(", ")}`, EXIT.safety);
  }
}

function requireNoAdministrationLocks(manifest, adminRoot) {
  const locks = manifest
    .map((entry) => entry.relativePath)
    .filter((relativePath) => relativePath && basename(relativePath).endsWith(".lock"));
  if (locks.length > 0) {
    fail(`linked worktree administration contains lock files: ${locks.map((path) => join(adminRoot, path)).join(", ")}`, EXIT.safety);
  }
}

function worktreeIndexSemantics(root) {
  return git(root, ["ls-files", "--stage", "-z"], { encoding: "buffer" }).stdout;
}

function stagedWorktreeGit(gitDir, workTree, args) {
  return run("git", [`--git-dir=${gitDir}`, `--work-tree=${workTree}`, ...args], { encoding: "buffer" }).stdout;
}

function requireManifestEntriesUnchanged(root, expectedManifest, label) {
  const observed = buildDeletionManifest(root);
  const expectedByPath = new Map(expectedManifest.map((entry) => [entry.relativePath, entry]));
  const observedByPath = new Map(observed.map((entry) => [entry.relativePath, entry]));
  if (expectedByPath.size !== expectedManifest.length || observedByPath.size !== observed.length
    || expectedByPath.size !== observedByPath.size
    || [...expectedByPath.keys()].some((path) => !observedByPath.has(path))) {
    fail(`${label} contents changed; retained at ${root}`, EXIT.safety);
  }
  for (const [relativePath, expected] of expectedByPath) {
    const actual = observedByPath.get(relativePath);
    const unchanged = expected.type === "directory"
      ? actual.type === "directory" && actual.dev === expected.dev && actual.ino === expected.ino
        && actual.mode === expected.mode
      : JSON.stringify(actual) === JSON.stringify(expected);
    if (!unchanged) fail(`${label} entry changed: ${join(root, relativePath)}`, EXIT.safety);
  }
}

function deletionManifestsEqual(left, right) {
  if (left.length !== right.length) return false;
  const rightByPath = new Map(right.map((entry) => [entry.relativePath, entry]));
  return rightByPath.size === right.length && left.every((entry) => {
    const candidate = rightByPath.get(entry.relativePath);
    return candidate && JSON.stringify(candidate) === JSON.stringify(entry);
  });
}

function deletionManifestDigest(manifest) {
  return createHash("sha256").update(JSON.stringify(manifest)).digest("hex");
}

function fsyncDirectory(path, label) {
  let fd;
  try {
    fd = openSync(path, "r");
    fsyncSync(fd);
  } catch (error) {
    fail(`could not durably sync ${label}: ${path}: ${error.message}`, EXIT.safety);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function durableFileIdentity(path, label) {
  const stat = physicalStat(path, label, "file");
  const contents = readFileSync(path);
  const result = {
    dev: stat.dev,
    ino: stat.ino,
    mode: stat.mode,
    mtimeMs: stat.mtimeMs,
    size: stat.size,
    digest: createHash("sha256").update(contents).digest("hex"),
  };
  const second = physicalStat(path, label, "file");
  if (second.dev !== result.dev || second.ino !== result.ino || second.mode !== result.mode
    || second.mtimeMs !== result.mtimeMs || second.size !== result.size) {
    fail(`${label} changed while its identity was captured: ${path}`, EXIT.safety);
  }
  return result;
}

function durableFileIdentityMatchesAt(expected, path) {
  try {
    const stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()
      || stat.dev !== expected.dev || stat.ino !== expected.ino
      || stat.mode !== expected.mode || stat.mtimeMs !== expected.mtimeMs
      || stat.size !== expected.size) return false;
    const digest = createHash("sha256").update(readFileSync(path)).digest("hex");
    const second = lstatSync(path);
    return digest === expected.digest && second.isFile() && !second.isSymbolicLink()
      && second.dev === expected.dev && second.ino === expected.ino
      && second.mode === expected.mode && second.mtimeMs === expected.mtimeMs
      && second.size === expected.size;
  } catch {
    return false;
  }
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

function purgeCaptureRelativePath(operationId, entry) {
  const digest = createHash("sha256").update(entry.relativePath).digest("hex");
  return join(dirname(entry.relativePath), `.buwiz-purge-${operationId.slice(0, 16)}-${digest}`);
}

function authorizedPurgeManifest(manifest, operationId) {
  const authorized = manifest.map((entry) => ({
    ...entry,
    captureRelativePath: entry.type === "directory"
      ? null
      : purgeCaptureRelativePath(operationId, entry),
  }));
  const paths = new Set(manifest.map(({ relativePath }) => relativePath));
  const captures = authorized.filter(({ captureRelativePath }) => captureRelativePath !== null)
    .map(({ captureRelativePath }) => captureRelativePath);
  if (new Set(captures).size !== captures.length
    || captures.some((capture) => paths.has(capture))) {
    fail("purge manifest contains an ambiguous deterministic capture path", EXIT.safety);
  }
  return authorized;
}

function validatePartialPurgeTree(root, manifest) {
  requireNoNestedMounts(root, "purge tombstone");
  const expected = new Map(manifest.map((entry) => [entry.relativePath, entry]));
  const captures = new Map(manifest
    .filter(({ captureRelativePath }) => captureRelativePath !== null)
    .map((entry) => [entry.captureRelativePath, entry]));
  const stack = [root];
  while (stack.length) {
    const path = stack.pop();
    const relativePath = relative(root, path);
    const expectedEntry = expected.get(relativePath);
    const capturedEntry = captures.get(relativePath);
    if (expectedEntry) {
      if (expectedEntry.type === "directory") {
        if (!manifestEntryMatchesAt(expectedEntry, path, { allowDirectoryMetadataChange: true })) {
          fail(`purge directory changed during recovery: ${path}`, EXIT.safety);
        }
      } else if (!manifestEntryMatchesAt(expectedEntry, path)) {
        fail(`purge entry changed during recovery: ${path}`, EXIT.safety);
      }
    } else if (capturedEntry) {
      if (!manifestEntryMatchesAt(capturedEntry, path)) {
        fail(`purge capture changed during recovery: ${path}`, EXIT.safety);
      }
    } else {
      fail(`purge tombstone contains unknown content: ${path}`, EXIT.safety);
    }
    if (lstatSync(path).isDirectory()) {
      for (const name of readdirSync(path)) stack.push(join(path, name));
    }
  }
}

function deleteIdentityManifest(root, manifest, options = {}) {
  const operationId = options.operationId ?? null;
  const resumable = operationId !== null;
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
    if (resumable) validatePartialPurgeTree(root, manifest);
    for (const entry of leaves) {
      const path = join(root, entry.relativePath);
      const capture = resumable
        ? join(root, entry.captureRelativePath)
        : join(dirname(path), `.${basename(path)}.deleting-${randomUUID()}`);
      runTestHook("before-delete-entry-rename", { relativePath: entry.relativePath, path, capture, root });
      const originalStat = lstatOptional(path, "purge entry");
      const captureStat = lstatOptional(capture, "purge capture");
      if (originalStat !== null && captureStat !== null) {
        fail(`purge entry and capture both exist: ${path}`, EXIT.safety);
      }
      if (originalStat === null && captureStat === null) continue;
      if (originalStat !== null) {
        if (!verifyParents(path) || !manifestEntryMatchesAt(entry, path)) {
          fail(`purge entry changed before capture: ${path}`, EXIT.safety);
        }
        renameSync(path, capture);
        fsyncDirectory(dirname(path), "purge capture parent");
      }
      runTestHook("after-delete-entry-rename", { relativePath: entry.relativePath, path, capture, root });
      if (!verifyParents(capture) || !manifestEntryMatchesAt(entry, capture)) {
        fail(`purge capture does not match its manifest entry: ${capture}`, EXIT.safety);
      }
      runTestHook("before-delete-entry-unlink", { relativePath: entry.relativePath, path, capture, root });
      if (!verifyParents(capture) || !manifestEntryMatchesAt(entry, capture)) {
        fail(`purge capture changed before unlink: ${capture}`, EXIT.safety);
      }
      unlinkSync(capture);
      fsyncDirectory(dirname(capture), "purge capture parent");
      runTestHook("after-delete-entry-unlink", { relativePath: entry.relativePath, path, capture, root });
    }
    for (const entry of directories) {
      const path = join(root, entry.relativePath);
      runTestHook("before-delete-directory-rmdir", { relativePath: entry.relativePath, path, root });
      if (lstatOptional(path, "purge directory") === null) continue;
      if ((path === root ? !identityMatches(parentIdentity) : !verifyParents(path))
        || !manifestEntryMatchesAt(entry, path, { allowDirectoryMetadataChange: true })) {
        fail(`purge directory changed before removal: ${path}`, EXIT.safety);
      }
      rmdirSync(path);
      fsyncDirectory(dirname(path), "purge directory parent");
      runTestHook("after-delete-directory-rmdir", { relativePath: entry.relativePath, path, root });
      if (resumable && entry.relativePath === "") {
        runTestHook("after-purge-root-rmdir", { path, root });
      }
    }
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    fail(`purge stopped; unverified content was not recursively deleted; retained at ${root}: ${detail}`, EXIT.safety);
  }
}

function cleanupReceiptBindings(context, handle, requireRegistered) {
  const { receipt, internalPath, durablePath } = handle;
  if (receipt.version !== VERSION || receipt.operation !== "clean"
    || receipt.transactionRoot !== dirname(internalPath)
    || !Array.isArray(receipt.sourceWorktrees) || receipt.sourceWorktrees.length === 0
    || !Array.isArray(receipt.sourceWorktreeGitDirs)
    || receipt.sourceWorktreeGitDirs.length !== receipt.sourceWorktrees.length
    || new Set(receipt.sourceWorktrees).size !== receipt.sourceWorktrees.length
    || new Set(receipt.sourceWorktreeGitDirs).size !== receipt.sourceWorktreeGitDirs.length) {
    fail(`cleanup receipt has an unsupported or incomplete schema: ${durablePath}`, EXIT.safety);
  }
  const sourceRecords = receipt.sourceWorktrees.map((sourceRoot, index) => {
    if (!isAbsolute(sourceRoot) || resolve(sourceRoot) !== sourceRoot) {
      fail(`cleanup receipt contains a non-canonical source worktree: ${sourceRoot}`, EXIT.safety);
    }
    const sourceGitDir = receipt.sourceWorktreeGitDirs[index];
    if (!isAbsolute(sourceGitDir) || resolve(sourceGitDir) !== sourceGitDir) {
      fail(`cleanup receipt contains a non-canonical source worktree identity: ${sourceGitDir}`, EXIT.safety);
    }
    const registered = context.records.find((candidate) =>
      candidate.gitDirReal === sourceGitDir && !candidate.missing);
    if (requireRegistered && !registered) {
      fail(`cleanup receipt source identity is no longer a registered worktree: ${sourceGitDir}`, EXIT.safety);
    }
    return {
      historicalRoot: sourceRoot,
      record: registered ?? { path: sourceRoot, pathReal: null, gitDirReal: sourceGitDir },
      registered,
    };
  });
  const sourceStates = sourceRecords.map(({ record }) => {
    const indexed = readCleanupState(context, record);
    if (!indexed || indexed.state.transactionRoot !== receipt.transactionRoot
      || indexed.state.receiptPath !== internalPath
      || indexed.state.durableReceiptPath !== durablePath) {
      fail(`cleanup receipt is not bound to its source worktree identity: ${durablePath}`, EXIT.safety);
    }
    return { ...indexed, record, payload: indexed.state };
  });
  const lifecycleStates = new Set(sourceStates.map(({ payload }) => payload.state));
  return {
    sourceRecords,
    sourceStates,
    lifecycle: lifecycleStates.size === 1 ? [...lifecycleStates][0] : null,
    lifecycleStates,
  };
}

function parseReceipt(receiptPath, context, allowedStates = ["receipt"]) {
  const handle = resolveCleanupReceiptHandle(context, receiptPath);
  const {
    receipt,
    receiptText,
    receiptIdentity,
    internalPath: receiptReal,
    durablePath,
    durableIdentity,
  } = handle;
  if (receiptIdentity === null) {
    fail(`transaction cleanup receipt is missing: ${handle.internalPath}`, EXIT.safety);
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
  if (!Array.isArray(receipt.moves) || receipt.moves.length === 0) {
    fail(`cleanup receipt has an unsupported or incomplete schema: ${receiptReal}`, EXIT.safety);
  }
  const { sourceRecords, sourceStates, lifecycle } = cleanupReceiptBindings(context, handle, true);
  if (lifecycle === null || !allowedStates.includes(lifecycle)) {
    fail(`cleanup receipt is in ${lifecycle} state, not ${allowedStates.join(" or ")}: ${durablePath}`, EXIT.safety);
  }
  const expectedDigest = createHash("sha256")
    .update(JSON.stringify({
      sourceWorktrees: receipt.sourceWorktrees,
      sourceWorktreeGitDirs: receipt.sourceWorktreeGitDirs,
      moves: receipt.moves,
      nativeSymlinks: receipt.nativeSymlinks,
      dependencySymlinks: receipt.dependencySymlinks,
    }))
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
    const sourceMatches = sourceRecords
      .filter(({ historicalRoot }) => isContained(historicalRoot, move.source))
      .map(({ historicalRoot, record }) => ({
        root: historicalRoot,
        currentRoot: record.pathReal,
        relativePath: relative(historicalRoot, move.source),
      }))
      .filter(({ relativePath }) => ALL_TARGETS.flatMap((name) => TARGETS[name]).includes(relativePath));
    if (sourceMatches.length !== 1) {
      fail(`cleanup receipt source is outside the literal artifact catalog: ${move.source}`, EXIT.safety);
    }
    const [{ root: sourceRoot, currentRoot: sourceCurrentRoot, relativePath: sourceRelative }] = sourceMatches;
    const expectedDestination = join(
      transactionRoot,
      createHash("sha256").update(sourceRoot).digest("hex").slice(0, 12),
      sourceRelative,
    );
    if (destination !== expectedDestination) {
      fail(`cleanup receipt destination does not match its recorded source: ${move.destination}`, EXIT.safety);
    }
    return { move, destination, sourceRelative, sourceCurrentRoot };
  });
  requireDistinctNonOverlappingPaths(plannedMoves.map(({ move }) => move.source), "move sources");
  requireDistinctNonOverlappingPaths(plannedMoves.map(({ destination }) => destination), "move destinations");
  validateReceiptTransactionLayout(
    transactionRoot,
    receiptReal,
    plannedMoves.map(({ destination }) => destination),
  );
  const verificationReceipt = {
    ...receipt,
    sourceWorktreeCurrentRoots: sourceRecords.map(({ record }) => record.pathReal),
  };
  const receiptSymlinks = new Map([
    ...verifiedReceiptNativeSymlinks(verificationReceipt, receiptReal),
    ...verifiedReceiptDependencySymlinks(verificationReceipt, receiptReal),
  ]);
  for (const { move, destination, sourceRelative } of plannedMoves) {
    const actual = directorySize(destination, {
      artifactRelativePath: sourceRelative,
      receiptSymlinks,
    });
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
    durableReceiptPath: durablePath,
    durableReceiptIdentity: durableIdentity,
    durableReceiptFileDigest: createHash("sha256").update(receiptText).digest("hex"),
    transactionRoot,
    quarantineRoot,
    transactionIdentity: identity(transactionRoot, "quarantine transaction", "directory"),
    quarantineIdentity: identity(quarantineRoot, "quarantine root", "directory"),
    deletionManifest,
    sourceRecords,
    sourceStates,
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
  if (!fileIdentityMatchesAt(parsed.durableReceiptIdentity, parsed.durableReceiptPath)
    || createHash("sha256").update(readFileSync(parsed.durableReceiptPath)).digest("hex")
      !== parsed.durableReceiptFileDigest
    || readFileSync(parsed.durableReceiptPath, "utf8") !== receiptText
    || !fileIdentityMatchesAt(parsed.durableReceiptIdentity, parsed.durableReceiptPath)) {
    fail(`durable cleanup receipt changed after tombstoning; retained at ${tombstone}`, EXIT.safety);
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
    sourceWorktreeCurrentRoots: parsed.sourceRecords.map(({ record }) => record.pathReal),
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
    dependencySymlinks: parsed.receipt.dependencySymlinks.map((link) => ({
      ...link,
      path: rebaseContainedPath(
        link.path,
        parsed.transactionRoot,
        tombstone,
        "cleanup receipt dependency link",
      ),
    })),
  };
  const destinations = rebasedMoves.map((move) => move.destination);
  validateReceiptTransactionLayout(tombstone, tombstoneReceipt, destinations);
  const receiptSymlinks = new Map([
    ...verifiedReceiptNativeSymlinks(rebasedReceipt, tombstoneReceipt),
    ...verifiedReceiptDependencySymlinks(rebasedReceipt, tombstoneReceipt),
  ]);
  for (const move of rebasedMoves) {
    const sourceRoot = rebasedReceipt.sourceWorktrees.find((root) =>
      typeof root === "string" && isContained(root, move.source));
    const sourceRelative = sourceRoot ? relative(sourceRoot, move.source) : null;
    const actual = directorySize(move.destination, {
      artifactRelativePath: sourceRelative,
      receiptSymlinks,
    });
    if (actual.bytes !== move.bytes || actual.entries !== move.entries) {
      fail(`quarantined artifact changed after tombstoning; retained at ${tombstone}`, EXIT.safety);
    }
  }
  directorySize(tombstone, { receiptSymlinks });
  requireExactDeletionManifest(tombstone, parsed.deletionManifest, "tombstoned quarantine transaction");
  return parsed.deletionManifest;
}

function resolveCleanupReceiptHandle(context, requestedPath) {
  if (!isAbsolute(requestedPath) || resolve(requestedPath) !== requestedPath
    || basename(requestedPath) !== "receipt.json") {
    fail(`purge requires an exact absolute receipt.json path: ${requestedPath}`, EXIT.safety);
  }
  const durableRoot = join(context.commonDir, "buwiz-workspace-maintenance", "cleanup-receipts");
  const requestedIsDurable = requestedPath !== durableRoot && isContained(durableRoot, requestedPath);
  let readablePath = requestedPath;
  if (lstatOptional(readablePath, "requested cleanup receipt") === null) {
    if (requestedIsDurable) {
      fail(`requested cleanup receipt does not exist: ${requestedPath}`, EXIT.safety);
    }
    readablePath = durableCleanupReceiptPath(context.commonDir, requestedPath, false);
  }
  const requestedReal = realpathExisting(readablePath, "requested cleanup receipt");
  if (requestedReal !== readablePath) {
    fail(`cleanup receipt must be canonical and not a symlink: ${readablePath}`, EXIT.safety);
  }
  const requestedIdentity = identity(readablePath, "requested cleanup receipt", "file");
  let requestedText;
  let requestedReceipt;
  try {
    requestedText = readFileSync(readablePath, "utf8");
    requestedReceipt = JSON.parse(requestedText);
  } catch {
    fail(`cleanup receipt is not valid JSON: ${readablePath}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(requestedIdentity, readablePath)) {
    fail(`cleanup receipt changed while it was being read: ${readablePath}`, EXIT.safety);
  }

  const readableIsDurable = readablePath !== durableRoot && isContained(durableRoot, readablePath);
  let internalPath;
  if (readableIsDurable) {
    if (typeof requestedReceipt.transactionRoot !== "string"
      || !isAbsolute(requestedReceipt.transactionRoot)
      || resolve(requestedReceipt.transactionRoot) !== requestedReceipt.transactionRoot) {
      fail(`durable cleanup receipt does not name an exact transaction root: ${readablePath}`, EXIT.safety);
    }
    internalPath = join(requestedReceipt.transactionRoot, "receipt.json");
  } else {
    internalPath = requestedPath;
  }
  const durablePath = durableCleanupReceiptPath(context.commonDir, internalPath, false);
  if (readableIsDurable && readablePath !== durablePath) {
    fail(`durable cleanup receipt path does not match its transaction identity: ${readablePath}`, EXIT.safety);
  }

  const durableReal = realpathExisting(durablePath, "durable cleanup receipt");
  if (durableReal !== durablePath) {
    fail(`durable cleanup receipt must be canonical and not a symlink: ${durablePath}`, EXIT.safety);
  }
  const internalStat = lstatOptional(internalPath, "transaction cleanup receipt");
  let internalIdentity = null;
  let internalText = null;
  if (internalStat !== null) {
    const internalReal = realpathExisting(internalPath, "transaction cleanup receipt");
    if (internalReal !== internalPath) {
      fail(`transaction cleanup receipt must be canonical and not a symlink: ${internalPath}`, EXIT.safety);
    }
    internalIdentity = readablePath === internalPath
      ? requestedIdentity
      : identity(internalPath, "transaction cleanup receipt", "file");
    internalText = readablePath === internalPath
      ? requestedText
      : readFileSync(internalPath, "utf8");
  }
  const durableIdentity = readablePath === durablePath
    ? requestedIdentity
    : identity(durablePath, "durable cleanup receipt", "file");
  const durableText = readablePath === durablePath
    ? requestedText
    : readFileSync(durablePath, "utf8");
  if ((internalText !== null && internalText !== durableText)
    || (internalIdentity !== null && !fileIdentityMatchesAt(internalIdentity, internalPath))
    || !fileIdentityMatchesAt(durableIdentity, durablePath)) {
    fail(`durable and transaction cleanup receipts differ or changed: ${durablePath}`, EXIT.safety);
  }
  let receipt;
  try {
    receipt = JSON.parse(internalText ?? durableText);
  } catch {
    fail(`cleanup receipt is not valid JSON: ${internalPath}`, EXIT.safety);
  }
  return {
    requestedPath,
    internalPath,
    durablePath,
    receipt,
    receiptText: internalText ?? durableText,
    receiptIdentity: internalIdentity,
    durableIdentity,
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
  const requestedReceiptPath = positionals[1];
  const handle = resolveCleanupReceiptHandle(context, requestedReceiptPath);
  let journalEntry = readPurgeJournal(context, handle);
  let planned = null;
  if (journalEntry === null) {
    planned = parseReceipt(requestedReceiptPath, context);
  }
  const transactionRoot = journalEntry?.journal.transactionRoot ?? planned.transactionRoot;
  const manifest = journalEntry?.journal.manifest ?? planned.deletionManifest;
  const bytes = manifest
    .filter((entry) => entry.type === "file")
    .reduce((total, entry) => total + entry.size, 0);
  process.stdout.write(`${options.dryRun ? "Would permanently purge" : "Permanently purging"} ${transactionRoot}\n`);
  process.stdout.write(`  ${bytes} bytes, ${manifest.length} entries\n`);
  if (options.dryRun) {
    if (journalEntry) process.stdout.write(`  recovery phase: ${journalEntry.journal.phase}\n`);
    return;
  }
  requireMutationPlatform();
  if (journalEntry === null) {
    requireNoHardlinkedFiles(planned.deletionManifest, planned.transactionRoot, "quarantine transaction");
    journalEntry = createPurgeJournal(context, planned);
  }
  const release = acquirePurgeLock(context.commonDir, journalEntry);
  try {
    const fresh = repoContext(invocationCwd());
    if (!contextTopologyEqual(context, fresh)) {
      fail("repository worktree topology changed after planning; nothing was purged", EXIT.safety);
    }
    const refreshedHandle = resolveCleanupReceiptHandle(fresh, requestedReceiptPath);
    const refreshed = readPurgeJournal(fresh, refreshedHandle);
    if (!refreshed || refreshed.journal.authorizationDigest !== journalEntry.journal.authorizationDigest) {
      fail(`purge journal changed after locking: ${journalEntry.path}`, EXIT.safety);
    }
    journalEntry = refreshed;
    const bindings = cleanupReceiptBindings(fresh, refreshedHandle, true);
    const { journal } = journalEntry;
    const transactionStat = lstatOptional(journal.transactionRoot, "quarantine transaction");
    const tombstoneStat = lstatOptional(journal.tombstonePath, "purge tombstone");

    if (journal.phase === "complete") {
      if (transactionStat !== null || tombstoneStat !== null) {
        fail(`completed purge paths were repopulated; refusing deletion: ${journal.transactionRoot}`, EXIT.safety);
      }
      if ([...bindings.lifecycleStates].some((state) => state !== "purged")) {
        updateCleanupStates(
          fresh,
          bindings.sourceStates,
          journal.transactionRoot,
          "purged",
          journal.internalReceiptPath,
          journal.durableReceiptPath,
          journal.tombstonePath,
        );
      }
      process.stdout.write("Purge already complete; the quarantined artifacts are no longer recoverable.\n");
      return;
    }

    if (journal.phase === "authorized") {
      if (transactionStat === null || tombstoneStat !== null) {
        fail(`authorized purge topology is inconsistent; no content was deleted`, EXIT.safety);
      }
      const verified = parseReceipt(requestedReceiptPath, fresh, ["receipt", "purging"]);
      const authorizedWithoutCaptures = journal.manifest.map(({ captureRelativePath: _capture, ...entry }) => entry);
      if (!deletionManifestsEqual(verified.deletionManifest, authorizedWithoutCaptures)) {
        fail("quarantine changed after purge authorization; nothing was purged", EXIT.safety);
      }
      updatePurgeJournal(journalEntry, "deleting");
    }

    if (journalEntry.journal.phase !== "deleting") {
      fail(`purge journal entered an unsupported phase: ${journalEntry.journal.phase}`, EXIT.safety);
    }
    if ([...bindings.lifecycleStates].some((state) => !["receipt", "purging"].includes(state))) {
      fail(`cleanup source state is incompatible with purge recovery: ${[...bindings.lifecycleStates].join(", ")}`, EXIT.safety);
    }
    if ([...bindings.lifecycleStates].some((state) => state !== "purging")) {
      updateCleanupStates(
        fresh,
        bindings.sourceStates,
        journal.transactionRoot,
        "purging",
        journal.internalReceiptPath,
        journal.durableReceiptPath,
        journal.tombstonePath,
      );
    }

    let original = lstatOptional(journal.transactionRoot, "quarantine transaction");
    let tombstone = lstatOptional(journal.tombstonePath, "purge tombstone");
    if (original !== null && tombstone !== null) {
      fail(`both purge transaction and tombstone exist; refusing deletion`, EXIT.safety);
    }
    if (original !== null) {
      const originalManifest = journal.manifest.map(({ captureRelativePath: _capture, ...entry }) => entry);
      runTestHook("before-purge-tombstone", {
        path: journal.transactionRoot,
        tombstone: journal.tombstonePath,
      });
      requireExactDeletionManifest(journal.transactionRoot, originalManifest, "quarantine transaction");
      const parentIdentity = identity(dirname(journal.transactionRoot), "quarantine transaction parent", "directory");
      if (!identityMatches(parentIdentity)
        || lstatOptional(journal.tombstonePath, "purge tombstone") !== null) {
        fail(`purge identity changed at tombstone boundary; retained at ${journal.transactionRoot}`, EXIT.safety);
      }
      renameSync(journal.transactionRoot, journal.tombstonePath);
      fsyncDirectory(dirname(journal.transactionRoot), "purge tombstone parent");
      runTestHook("after-purge-tombstone", {
        path: journal.transactionRoot,
        tombstone: journal.tombstonePath,
      });
      original = lstatOptional(journal.transactionRoot, "quarantine transaction");
      tombstone = lstatOptional(journal.tombstonePath, "purge tombstone");
      if (original !== null || tombstone === null) {
        fail(`purge tombstone transition is inconsistent; refusing deletion`, EXIT.safety);
      }
    }
    if (tombstone !== null) {
      validatePartialPurgeTree(journal.tombstonePath, journal.manifest);
      runTestHook("after-purge-manifest", { root: journal.tombstonePath });
      deleteIdentityManifest(journal.tombstonePath, journal.manifest, {
        operationId: journal.operationId,
      });
    }
    if (lstatOptional(journal.transactionRoot, "quarantine transaction") !== null) {
      fail(`original quarantine path was repopulated during purge and was preserved: ${journal.transactionRoot}`, EXIT.safety);
    }
    if (lstatOptional(journal.tombstonePath, "purge tombstone") !== null) {
      fail(`quarantine purge did not complete: ${journal.tombstonePath}`, EXIT.safety);
    }
    updatePurgeJournal(journalEntry, "complete");
    runTestHook("after-purge-complete-before-state", { journalPath: journalEntry.path });
    updateCleanupStates(
      fresh,
      bindings.sourceStates,
      journal.transactionRoot,
      "purged",
      journal.internalReceiptPath,
      journal.durableReceiptPath,
      journal.tombstonePath,
    );
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
    if (allowed.has(entry.path)) {
      fail(`cleanup receipt contains a duplicate Native identity link: ${entry.path}`, EXIT.safety);
    }
    allowed.set(entry.path, { ...entry, kind: "native" });
  }
  const discovered = new Set();
  for (const move of receipt.moves) {
    const sourceIndex = receipt.sourceWorktrees.findIndex((root) =>
      typeof root === "string" && isContained(root, move.source));
    if (sourceIndex < 0 || relative(receipt.sourceWorktrees[sourceIndex], move.source) !== ".native") continue;
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
        const recordedLink = allowed.get(candidate);
        if (!recordedLink || recordedLink.target !== readlinkSync(candidate)
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

function verifiedReceiptDependencySymlinks(receipt, receiptPath) {
  const recorded = receipt.dependencySymlinks;
  if (!Array.isArray(recorded)) {
    fail(`cleanup receipt does not record its dependency links: ${receiptPath}`, EXIT.safety);
  }
  const dependencyRoots = receipt.moves.flatMap((move) => {
    const sourceRoot = receipt.sourceWorktrees.find((root) =>
      typeof root === "string" && isContained(root, move.source));
    return sourceRoot && relative(sourceRoot, move.source) === "node_modules"
      ? [move.destination]
      : [];
  });
  const allowed = new Map();
  for (const entry of recorded) {
    if (!entry || typeof entry.path !== "string" || resolve(entry.path) !== entry.path
      || typeof entry.target !== "string"
      || ![entry.dev, entry.ino, entry.mode, entry.mtimeMs].every((value) => typeof value === "number")
      || !dependencyRoots.some((root) => entry.path !== root && isContained(root, entry.path))) {
      fail(`cleanup receipt contains an invalid dependency link: ${receiptPath}`, EXIT.safety);
    }
    if (allowed.has(entry.path)) {
      fail(`cleanup receipt contains a duplicate dependency link: ${entry.path}`, EXIT.safety);
    }
    allowed.set(entry.path, { ...entry, kind: "dependency" });
  }

  const discovered = new Set();
  for (const dependencyRoot of dependencyRoots) {
    const rootDevice = lstatSync(dependencyRoot).dev;
    const stack = [dependencyRoot];
    while (stack.length) {
      const current = stack.pop();
      const stat = lstatSync(current);
      if (stat.dev !== rootDevice) {
        fail(`dependency artifact crosses a filesystem boundary: ${current}`, EXIT.safety);
      }
      if (stat.isSymbolicLink()) {
        discovered.add(current);
        const recordedLink = allowed.get(current);
        if (!recordedLink || recordedLink.target !== readlinkSync(current)
          || recordedLink.dev !== stat.dev || recordedLink.ino !== stat.ino
          || recordedLink.mode !== stat.mode || recordedLink.mtimeMs !== stat.mtimeMs) {
          fail(`quarantined dependency link was not recorded by the receipt or changed identity: ${current}`, EXIT.safety);
        }
        continue;
      }
      if (stat.isDirectory()) {
        for (const name of readdirSync(current)) stack.push(join(current, name));
      }
    }
  }
  if (discovered.size !== allowed.size || [...allowed.keys()].some((path) => !discovered.has(path))) {
    fail(`cleanup receipt records a missing dependency link: ${receiptPath}`, EXIT.safety);
  }
  return allowed;
}

function directorySize(path, options = {}) {
  const {
    root = path,
    artifactRelativePath = null,
    inventoryOnly = false,
    receiptSymlinks = null,
  } = options;
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
        && stat.mode === receiptLink.mode && stat.mtimeMs === receiptLink.mtimeMs
        && (receiptLink.kind !== "dependency" || readlinkSync(current) === receiptLink.target);
      const unquarantinedDependencyLink = artifactRelativePath === "node_modules"
        && receiptSymlinks === null;
      if (!inventoryOnly && !receiptAllowsLink && !unquarantinedDependencyLink
        && !allowedNativeIdentityLink(root, artifactRelativePath, current)) {
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
        target: readlinkSync(current),
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

function dependencySymlinkSnapshot(artifactRelativePath, artifactRoot) {
  if (artifactRelativePath !== "node_modules") return [];
  const links = [];
  const stack = [artifactRoot];
  while (stack.length) {
    const current = stack.pop();
    const stat = lstatSync(current);
    if (stat.isSymbolicLink()) {
      links.push({
        relativePath: relative(artifactRoot, current),
        target: readlinkSync(current),
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
        && readlinkSync(path) === link.target;
    } catch {
      return false;
    }
  });
}

function dependencySymlinksMatchAt(entry, artifactRoot) {
  const expected = entry.dependencySymlinks ?? [];
  let observed;
  try {
    observed = dependencySymlinkSnapshot(entry.relativePath, artifactRoot);
  } catch {
    return false;
  }
  return JSON.stringify(expected) === JSON.stringify(observed);
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
  const dependencySymlinks = options.inventoryOnly ? [] : dependencySymlinkSnapshot(relativePath, absolute);
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
    dependencySymlinks,
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
    && nativeSymlinksMatchAt(entry, entry.absolute)
    && dependencySymlinksMatchAt(entry, entry.absolute);
}

function snapshotsEquivalent(planned, verified) {
  return verified.exists
    && planned.absolute === verified.absolute
    && planned.dev === verified.dev && planned.ino === verified.ino
    && planned.mode === verified.mode && planned.mtimeMs === verified.mtimeMs
    && nativeSymlinkSnapshotsEqual(planned.nativeSymlinks, verified.nativeSymlinks)
    && nativeSymlinkSnapshotsEqual(planned.dependencySymlinks, verified.dependencySymlinks);
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

function ensurePhysicalRelativeDirectory(parent, relativePath, label, options = {}) {
  let current = parent;
  const identities = [identity(parent, `${label} root`, "directory")];
  for (const part of relativePath.split(sep).filter((entry) => entry && entry !== ".")) {
    if (part === "..") {
      fail(`${label} escapes its physical parent: ${relativePath}`, EXIT.safety);
    }
    current = ensurePhysicalChild(current, part, label, options);
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
  const actualCwd = realpathExisting(process.cwd(), "process working directory");
  if (isContained(record.pathReal, actualCwd)) {
    fail(`refusing the actual process worktree: ${supplied}`, EXIT.safety);
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

function ensurePhysicalDirectory(path, label, options = {}) {
  const { durable = false } = options;
  if (!existsSync(path)) {
    const parent = dirname(path);
    if (!existsSync(parent)) {
      mkdirSync(parent, { mode: 0o700 });
      if (durable) fsyncDirectory(dirname(parent), `${label} grandparent`);
    }
    physicalStat(parent, `${label} parent`, "directory");
    mkdirSync(path, { mode: 0o700 });
    if (durable) fsyncDirectory(parent, `${label} parent`);
  }
  physicalStat(path, label, "directory");
  return realpathSync(path);
}

function ensurePhysicalChild(parent, name, label, options = {}) {
  const parentReal = realpathExisting(parent, `${label} parent`);
  physicalStat(parentReal, `${label} parent`, "directory");
  const child = join(parentReal, name);
  const childReal = ensurePhysicalDirectory(child, label, options);
  if (childReal !== child || dirname(childReal) !== parentReal) {
    fail(`${label} escapes its physical parent: ${child}`, EXIT.safety);
  }
  return childReal;
}

function metadataRoot(commonDir) {
  physicalStat(commonDir, "Git common directory", "directory");
  const candidate = join(commonDir, "buwiz-workspace-maintenance");
  const candidateReal = ensurePhysicalDirectory(candidate, "maintenance state directory", { durable: true });
  if (!isContained(commonDir, candidateReal)) {
    fail(`maintenance state directory escapes the Git common directory: ${candidateReal}`, EXIT.safety);
  }
  return candidateReal;
}

function worktreeIdentityKey(commonDir, gitDirReal) {
  return createHash("sha256").update(`${commonDir}\0${gitDirReal}`).digest("hex");
}

function cleanupStatePath(commonDir, gitDirReal, create = true) {
  const stateRoot = create ? metadataRoot(commonDir) : join(commonDir, "buwiz-workspace-maintenance");
  if (!create && lstatOptional(stateRoot, "maintenance state directory") === null) return null;
  if (!create) {
    physicalStat(stateRoot, "maintenance state directory", "directory");
    if (realpathExisting(stateRoot, "maintenance state directory") !== stateRoot) {
      fail(`maintenance state directory escapes the Git common directory: ${stateRoot}`, EXIT.safety);
    }
  }
  const ledgerRoot = create
    ? ensurePhysicalChild(stateRoot, "cleanup-state", "cleanup state directory", { durable: true })
    : join(stateRoot, "cleanup-state");
  if (!create) {
    if (lstatOptional(ledgerRoot, "cleanup state directory") === null) return null;
    physicalStat(ledgerRoot, "cleanup state directory", "directory");
    if (realpathExisting(ledgerRoot, "cleanup ledger directory") !== ledgerRoot) {
      fail(`cleanup state directory escapes its physical path: ${ledgerRoot}`, EXIT.safety);
    }
  }
  return join(ledgerRoot, `${worktreeIdentityKey(commonDir, gitDirReal)}.json`);
}

function cleanupStatePayload(
  context,
  record,
  state,
  transactionRoot = null,
  receiptPath = null,
  durableReceiptPath = null,
  tombstonePath = null,
) {
  return {
    version: VERSION,
    operation: "clean-state",
    state,
    commonDir: context.commonDir,
    sourceWorktreeGitDir: record.gitDirReal,
    sourceWorktree: record.path,
    transactionRoot,
    receiptPath,
    durableReceiptPath,
    tombstonePath,
  };
}

function readCleanupState(context, record) {
  const path = cleanupStatePath(context.commonDir, record.gitDirReal, false);
  if (path === null || lstatOptional(path, "cleanup state") === null) return null;
  const pathIdentity = identity(path, "cleanup state", "file");
  let state;
  try {
    state = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    fail(`cleanup state is not valid JSON: ${path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(pathIdentity, path)
    || state.version !== VERSION || state.operation !== "clean-state"
    || state.commonDir !== context.commonDir
    || state.sourceWorktreeGitDir !== record.gitDirReal
    || !["moving", "receipt", "recovery", "purging", "purged"].includes(state.state)
    || !isAbsolute(state.transactionRoot)
    || (state.receiptPath !== null && !isAbsolute(state.receiptPath))
    || (state.durableReceiptPath !== null && !isAbsolute(state.durableReceiptPath))
    || (state.tombstonePath !== null && !isAbsolute(state.tombstonePath))) {
    fail(`cleanup state is invalid or changed: ${path}`, EXIT.safety);
  }
  return { path, identity: pathIdentity, state };
}

function createCleanupStates(context, plan, transactionRoot) {
  const states = [];
  try {
    for (const { record } of plan) {
      const path = cleanupStatePath(context.commonDir, record.gitDirReal);
      const existing = readCleanupState(context, record);
      if (existing && existing.state.state !== "purged") {
        fail(`worktree already has cleanup state requiring resolution: ${path}`, EXIT.safety);
      }
      const payload = cleanupStatePayload(context, record, "moving", transactionRoot);
      const stateIdentity = existing
        ? replacePhysicalJson(path, existing.identity, payload, "cleanup state")
        : (writeReceipt(path, payload), identity(path, "cleanup state", "file"));
      fsyncDirectory(dirname(path), "cleanup state directory");
      states.push({
        record,
        path,
        identity: stateIdentity,
        payload,
      });
    }
    return states;
  } catch (error) {
    for (const state of states) {
      try {
        if (fileIdentityMatchesAt(state.identity, state.path)) unlinkSync(state.path);
      } catch { /* Leave uncertainty visible if state cannot be safely removed. */ }
    }
    throw error;
  }
}

function updateCleanupStates(
  context,
  states,
  transactionRoot,
  state,
  receiptPath,
  durableReceiptPath,
  tombstonePath = null,
) {
  for (const entry of states) {
    const payload = cleanupStatePayload(
      context, entry.record, state, transactionRoot, receiptPath, durableReceiptPath, tombstonePath,
    );
    const currentIdentity = identity(entry.path, "cleanup state", "file");
    const current = JSON.parse(readFileSync(entry.path, "utf8"));
    if (current.commonDir !== context.commonDir
      || current.sourceWorktreeGitDir !== entry.record.gitDirReal
      || !fileIdentityMatchesAt(currentIdentity, entry.path)) {
      fail(`cleanup state changed before update: ${entry.path}`, EXIT.safety);
    }
    entry.identity = currentIdentity;
    entry.identity = replacePhysicalJson(
      entry.path,
      entry.identity,
      payload,
      "cleanup state",
    );
    fsyncDirectory(dirname(entry.path), "cleanup state directory");
    entry.payload = payload;
  }
}

function durableCleanupReceiptPath(commonDir, requestedReceiptPath, create = true) {
  const stateRoot = create
    ? metadataRoot(commonDir)
    : join(commonDir, "buwiz-workspace-maintenance");
  if (!create) {
    physicalStat(stateRoot, "maintenance state directory", "directory");
    if (realpathExisting(stateRoot, "maintenance state directory") !== stateRoot
      || !isContained(commonDir, stateRoot)) {
      fail(`maintenance state directory escapes the Git common directory: ${stateRoot}`, EXIT.safety);
    }
  }
  const root = create
    ? ensurePhysicalChild(stateRoot, "cleanup-receipts", "durable cleanup receipt directory", { durable: true })
    : join(stateRoot, "cleanup-receipts");
  if (!create) {
    physicalStat(root, "durable cleanup receipt directory", "directory");
    if (realpathExisting(root, "durable cleanup receipt directory") !== root) {
      fail(`durable cleanup receipt directory escapes its physical path: ${root}`, EXIT.safety);
    }
  }
  const operationRoot = create
    ? ensurePhysicalChild(
      root,
      createHash("sha256").update(requestedReceiptPath).digest("hex"),
      "durable cleanup operation directory",
      { durable: true },
    )
    : join(root, createHash("sha256").update(requestedReceiptPath).digest("hex"));
  if (!create) {
    physicalStat(operationRoot, "durable cleanup operation directory", "directory");
    if (realpathExisting(operationRoot, "durable cleanup operation directory") !== operationRoot) {
      fail(`durable cleanup operation directory escapes its physical path: ${operationRoot}`, EXIT.safety);
    }
  }
  return join(operationRoot, "receipt.json");
}

function purgeJournalPath(durableReceiptPath) {
  return join(dirname(durableReceiptPath), "purge.json");
}

function purgeAuthorizationDigest(journal) {
  return createHash("sha256").update(JSON.stringify({
    version: journal.version,
    operation: journal.operation,
    operationId: journal.operationId,
    commonDir: journal.commonDir,
    durableReceiptPath: journal.durableReceiptPath,
    durableReceiptIdentity: journal.durableReceiptIdentity,
    internalReceiptPath: journal.internalReceiptPath,
    receiptDigest: journal.receiptDigest,
    transactionRoot: journal.transactionRoot,
    tombstonePath: journal.tombstonePath,
    sourceWorktreeGitDirs: journal.sourceWorktreeGitDirs,
    manifest: journal.manifest,
    manifestDigest: journal.manifestDigest,
    createdAt: journal.createdAt,
  })).digest("hex");
}

function validatePurgeJournalSchema(journal, path, context, handle) {
  const allowedPhases = ["authorized", "deleting", "complete"];
  if (!journal || journal.version !== PURGE_JOURNAL_VERSION
    || journal.operation !== "clean-purge"
    || !allowedPhases.includes(journal.phase)
    || journal.commonDir !== context.commonDir
    || journal.durableReceiptPath !== handle.durablePath
    || journal.internalReceiptPath !== handle.internalPath
    || journal.receiptDigest !== createHash("sha256").update(handle.receiptText).digest("hex")
    || !durableFileIdentityMatchesAt(journal.durableReceiptIdentity, handle.durablePath)
    || !isAbsolute(journal.transactionRoot) || journal.transactionRoot !== handle.receipt.transactionRoot
    || !isAbsolute(journal.tombstonePath)
    || dirname(journal.tombstonePath) !== dirname(journal.transactionRoot)
    || !Array.isArray(journal.sourceWorktreeGitDirs)
    || JSON.stringify(journal.sourceWorktreeGitDirs) !== JSON.stringify(handle.receipt.sourceWorktreeGitDirs)
    || !Array.isArray(journal.manifest) || journal.manifest.length === 0
    || journal.manifestDigest !== deletionManifestDigest(journal.manifest)
    || journal.authorizationDigest !== purgeAuthorizationDigest(journal)
    || typeof journal.createdAt !== "string" || typeof journal.updatedAt !== "string") {
    fail(`purge journal is invalid or changed: ${path}`, EXIT.safety);
  }
  const expectedOperationId = createHash("sha256")
    .update(`${context.commonDir}\0${handle.durablePath}\0${journal.receiptDigest}`)
    .digest("hex");
  if (journal.operationId !== expectedOperationId
    || journal.tombstonePath !== join(
      dirname(journal.transactionRoot),
      `.${basename(journal.transactionRoot)}.purging-${journal.operationId.slice(0, 24)}`,
    )) {
    fail(`purge journal does not use its deterministic operation paths: ${path}`, EXIT.safety);
  }
  const expectedManifest = authorizedPurgeManifest(
    journal.manifest.map(({ captureRelativePath: _capture, ...entry }) => entry),
    journal.operationId,
  );
  if (!deletionManifestsEqual(expectedManifest, journal.manifest)) {
    fail(`purge journal manifest has invalid capture paths: ${path}`, EXIT.safety);
  }
  return journal;
}

function readPurgeJournal(context, handle) {
  const path = purgeJournalPath(handle.durablePath);
  if (lstatOptional(path, "purge journal") === null) return null;
  const journalIdentity = identity(path, "purge journal", "file");
  let journal;
  try {
    journal = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    fail(`purge journal is not valid JSON: ${path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(journalIdentity, path)) {
    fail(`purge journal changed while it was read: ${path}`, EXIT.safety);
  }
  validatePurgeJournalSchema(journal, path, context, handle);
  return { path, identity: journalIdentity, journal };
}

function createPurgeJournal(context, parsed) {
  const receiptDigest = parsed.receiptFileDigest;
  const operationId = createHash("sha256")
    .update(`${context.commonDir}\0${parsed.durableReceiptPath}\0${receiptDigest}`)
    .digest("hex");
  const manifest = authorizedPurgeManifest(parsed.deletionManifest, operationId);
  const createdAt = new Date().toISOString();
  const journal = {
    version: PURGE_JOURNAL_VERSION,
    operation: "clean-purge",
    operationId,
    phase: "authorized",
    commonDir: context.commonDir,
    durableReceiptPath: parsed.durableReceiptPath,
    durableReceiptIdentity: durableFileIdentity(parsed.durableReceiptPath, "durable cleanup receipt"),
    internalReceiptPath: parsed.receiptPath,
    receiptDigest,
    transactionRoot: parsed.transactionRoot,
    tombstonePath: join(
      dirname(parsed.transactionRoot),
      `.${basename(parsed.transactionRoot)}.purging-${operationId.slice(0, 24)}`,
    ),
    sourceWorktreeGitDirs: parsed.receipt.sourceWorktreeGitDirs,
    manifest,
    manifestDigest: deletionManifestDigest(manifest),
    authorizationDigest: null,
    createdAt,
    updatedAt: createdAt,
  };
  journal.authorizationDigest = purgeAuthorizationDigest(journal);
  const path = purgeJournalPath(parsed.durableReceiptPath);
  writeReceipt(path, journal);
  fsyncDirectory(dirname(path), "purge journal parent");
  runTestHook("after-purge-journal-create", { journalPath: path });
  return { path, identity: identity(path, "purge journal", "file"), journal };
}

function updatePurgeJournal(entry, phase) {
  const currentIdentity = identity(entry.path, "purge journal", "file");
  const current = JSON.parse(readFileSync(entry.path, "utf8"));
  if (current.authorizationDigest !== entry.journal.authorizationDigest
    || current.phase !== entry.journal.phase
    || !fileIdentityMatchesAt(currentIdentity, entry.path)) {
    fail(`purge journal changed before update: ${entry.path}`, EXIT.safety);
  }
  entry.identity = currentIdentity;
  const updated = { ...entry.journal, phase, updatedAt: new Date().toISOString() };
  entry.identity = replacePhysicalJson(entry.path, entry.identity, updated, "purge journal");
  fsyncDirectory(dirname(entry.path), "purge journal parent");
  entry.journal = updated;
  runTestHook(`after-purge-journal-${phase}`, { journalPath: entry.path });
  return entry;
}

function purgeJournalLockPath(commonDir) {
  return join(metadataRoot(commonDir), "lock.json");
}

function purgeLockOwner(journalEntry, token) {
  return {
    version: PURGE_JOURNAL_VERSION,
    kind: "clean-purge",
    operationId: journalEntry.journal.operationId,
    journalPath: journalEntry.path,
    authorizationDigest: journalEntry.journal.authorizationDigest,
    host: hostname(),
    pid: process.pid,
    token,
    startedAt: new Date().toISOString(),
  };
}

function processDefinitelyAbsent(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return false;
  } catch (error) {
    return error?.code === "ESRCH";
  }
}

function reclaimStalePurgeLock(path, journalEntry) {
  const lockIdentity = identity(path, "repository maintenance lock", "file");
  const bytes = readFileSync(path, "utf8");
  let owner;
  try {
    owner = JSON.parse(bytes);
  } catch {
    fail(`repository maintenance lock is corrupt: ${path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(lockIdentity, path)
    || owner.version !== PURGE_JOURNAL_VERSION || owner.kind !== "clean-purge"
    || owner.operationId !== journalEntry.journal.operationId
    || owner.journalPath !== journalEntry.path
    || owner.authorizationDigest !== journalEntry.journal.authorizationDigest
    || owner.host !== hostname() || typeof owner.token !== "string"
    || !processDefinitelyAbsent(owner.pid)) {
    fail(`repository maintenance lock is already held or cannot be proven stale: ${path}`, EXIT.safety);
  }
  const staleRoot = ensurePhysicalChild(metadataRoot(journalEntry.journal.commonDir), "stale-locks", "stale lock directory");
  const stalePath = join(staleRoot, `${owner.token}.json`);
  if (lstatOptional(stalePath, "stale lock capture") !== null) {
    fail(`stale lock capture already exists: ${stalePath}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(lockIdentity, path) || readFileSync(path, "utf8") !== bytes) {
    fail(`repository maintenance lock changed before stale capture: ${path}`, EXIT.safety);
  }
  renameSync(path, stalePath);
  fsyncDirectory(dirname(path), "maintenance lock parent");
  if (!fileIdentityMatchesAt(lockIdentity, stalePath) || readFileSync(stalePath, "utf8") !== bytes) {
    fail(`stale maintenance lock changed during capture: ${stalePath}`, EXIT.safety);
  }
}

function acquirePurgeLock(commonDir, journalEntry) {
  const path = purgeJournalLockPath(commonDir);
  if (lstatOptional(path, "repository maintenance lock") !== null) {
    reclaimStalePurgeLock(path, journalEntry);
  }
  const token = randomUUID();
  const owner = purgeLockOwner(journalEntry, token);
  let fd;
  let lockStat;
  try {
    fd = openSync(path, "wx", 0o600);
    lockStat = fstatSync(fd);
    writeFileSync(fd, `${JSON.stringify(owner, null, 2)}\n`);
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    fsyncDirectory(dirname(path), "maintenance lock parent");
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    fail(`repository maintenance lock is already held: ${path}: ${error.message}`, EXIT.safety);
  }
  return () => {
    try {
      const current = lstatSync(path);
      const currentOwner = JSON.parse(readFileSync(path, "utf8"));
      if (current.isFile() && !current.isSymbolicLink()
        && current.dev === lockStat.dev && current.ino === lockStat.ino
        && currentOwner.token === token) {
        unlinkSync(path);
        fsyncDirectory(dirname(path), "maintenance lock parent");
      } else {
        process.stderr.write(`warning: maintenance lock identity changed; refusing to remove ${path}\n`);
      }
    } catch (error) {
      process.stderr.write(`warning: could not safely release maintenance lock ${path}: ${error.message}\n`);
    }
  };
}

function cleanLockOwner(journalEntry, token) {
  return {
    version: CLEAN_JOURNAL_VERSION,
    kind: "clean-quarantine",
    operationId: journalEntry.journal.operationId,
    journalPath: journalEntry.path,
    authorizationDigest: journalEntry.journal.authorizationDigest,
    host: hostname(),
    pid: process.pid,
    token,
    startedAt: new Date().toISOString(),
  };
}

function reclaimStaleCleanLock(path, journalEntry) {
  const lockIdentity = identity(path, "repository maintenance lock", "file");
  const bytes = readFileSync(path, "utf8");
  let owner;
  try {
    owner = JSON.parse(bytes);
  } catch {
    fail(`repository maintenance lock is corrupt: ${path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(lockIdentity, path)
    || owner.version !== CLEAN_JOURNAL_VERSION || owner.kind !== "clean-quarantine"
    || owner.operationId !== journalEntry.journal.operationId
    || owner.journalPath !== journalEntry.path
    || owner.authorizationDigest !== journalEntry.journal.authorizationDigest
    || owner.host !== hostname() || typeof owner.token !== "string"
    || !processDefinitelyAbsent(owner.pid)) {
    fail(`repository maintenance lock is already held or cannot be proven stale: ${path}`, EXIT.safety);
  }
  const staleRoot = ensurePhysicalChild(metadataRoot(journalEntry.journal.commonDir), "stale-locks", "stale lock directory");
  const stalePath = join(staleRoot, `${owner.token}.json`);
  if (lstatOptional(stalePath, "stale lock capture") !== null) {
    fail(`stale lock capture already exists: ${stalePath}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(lockIdentity, path) || readFileSync(path, "utf8") !== bytes) {
    fail(`repository maintenance lock changed before stale capture: ${path}`, EXIT.safety);
  }
  renameSync(path, stalePath);
  fsyncDirectory(dirname(path), "maintenance lock parent");
  if (!fileIdentityMatchesAt(lockIdentity, stalePath) || readFileSync(stalePath, "utf8") !== bytes) {
    fail(`stale maintenance lock changed during capture: ${stalePath}`, EXIT.safety);
  }
}

function acquireCleanLock(commonDir, journalEntry, allowStaleReclaim) {
  const path = lockPath(commonDir);
  if (lstatOptional(path, "repository maintenance lock") !== null) {
    if (!allowStaleReclaim) {
      fail(`repository maintenance lock is already held: ${path}`, EXIT.safety);
    }
    reclaimStaleCleanLock(path, journalEntry);
  }
  const token = randomUUID();
  const owner = cleanLockOwner(journalEntry, token);
  let fd;
  let lockStat;
  try {
    fd = openSync(path, "wx", 0o600);
    lockStat = fstatSync(fd);
    writeFileSync(fd, `${JSON.stringify(owner, null, 2)}\n`);
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    fsyncDirectory(dirname(path), "maintenance lock parent");
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    fail(`repository maintenance lock is already held: ${path}: ${error.message}`, EXIT.safety);
  }
  return () => {
    try {
      const stat = lstatSync(path);
      const currentOwner = JSON.parse(readFileSync(path, "utf8"));
      if (stat.isFile() && !stat.isSymbolicLink()
        && stat.dev === lockStat.dev && stat.ino === lockStat.ino
        && currentOwner.token === token) {
        unlinkSync(path);
        fsyncDirectory(dirname(path), "maintenance lock parent");
      } else {
        process.stderr.write(`warning: maintenance lock identity changed; refusing to remove ${path}\n`);
      }
    } catch (error) {
      process.stderr.write(`warning: could not safely release maintenance lock ${path}: ${error.message}\n`);
    }
  };
}

function replacePhysicalJson(path, expectedIdentity, value, label) {
  if (!fileIdentityMatchesAt(expectedIdentity, path)) {
    fail(`${label} identity changed before update: ${path}`, EXIT.safety);
  }
  const replacement = `${path}.pending-${randomUUID()}`;
  writeReceipt(replacement, value);
  try {
    if (!fileIdentityMatchesAt(expectedIdentity, path)) {
      fail(`${label} identity changed at update boundary: ${path}`, EXIT.safety);
    }
    renameSync(replacement, path);
  } catch (error) {
    try { unlinkSync(replacement); } catch { /* Retain the original intent on uncertainty. */ }
    throw error;
  }
  return identity(path, label, "file");
}

function updatePhysicalJsonReceipt(path, expectedIdentity, value) {
  return replacePhysicalJson(path, expectedIdentity, value, "maintenance receipt");
}

function worktreeRemovalAuthorizationDigest(journal) {
  return createHash("sha256").update(JSON.stringify({
    version: journal.version,
    operation: journal.operation,
    operationId: journal.operationId,
    commonDir: journal.commonDir,
    primaryWorktree: journal.primaryWorktree,
    target: journal.target,
    targetGitDir: journal.targetGitDir,
    head: journal.head,
    branch: journal.branch,
    detached: journal.detached,
    integrationRef: journal.integrationRef,
    integrationOid: journal.integrationOid,
    forced: journal.forced,
    rescueRef: journal.rescueRef,
    snapshotDigest: journal.snapshotDigest,
    gitLockReason: journal.gitLockReason,
    registeredTombstone: journal.registeredTombstone,
    holdingPath: journal.holdingPath,
    adminHoldingPath: journal.adminHoldingPath,
    rootManifest: journal.rootManifest,
    adminManifest: journal.adminManifest,
    siblingTopology: journal.siblingTopology,
    createdAt: journal.createdAt,
  })).digest("hex");
}

function worktreeRemovalCaptureManifest(manifest, operationId, namespace) {
  return authorizedPurgeManifest(manifest, `${operationId}-${namespace}`);
}

function worktreeRemovalReceiptPayload(details, state = details.state) {
  return {
    ...details,
    state,
    updatedAt: new Date().toISOString(),
  };
}

function validateWorktreeRemovalJournal(journal, path, context) {
  const states = [
    "prepared",
    "root-move-intent",
    "root-held",
    "admin-move-intent",
    "admin-held",
    "admin-delete-intent",
    "root-delete-intent",
    "complete",
  ];
  if (!journal || journal.version !== WORKTREE_REMOVAL_JOURNAL_VERSION
    || journal.operation !== "worktree-remove" || !states.includes(journal.state)
    || journal.commonDir !== context.commonDir || journal.primaryWorktree !== context.primary.path
    || typeof journal.operationId !== "string" || typeof journal.gitLockReason !== "string"
    || !isAbsolute(journal.target) || resolve(journal.target) !== journal.target
    || !isAbsolute(journal.targetGitDir) || resolve(journal.targetGitDir) !== journal.targetGitDir
    || !isAbsolute(journal.registeredTombstone) || !isAbsolute(journal.holdingPath)
    || !isAbsolute(journal.adminHoldingPath)
    || dirname(journal.adminHoldingPath) !== join(context.commonDir, "worktree-admin-holds")
    || !Array.isArray(journal.rootManifest) || journal.rootManifest.length === 0
    || !Array.isArray(journal.adminManifest) || journal.adminManifest.length === 0
    || !Array.isArray(journal.siblingTopology)
    || journal.authorizationDigest !== worktreeRemovalAuthorizationDigest(journal)
    || typeof journal.createdAt !== "string" || typeof journal.updatedAt !== "string") {
    fail(`worktree removal receipt is invalid or changed: ${path}`, EXIT.safety);
  }
  const expectedOperationId = createHash("sha256")
    .update(`${context.commonDir}\0${journal.targetGitDir}\0${journal.snapshotDigest}`)
    .digest("hex");
  if (journal.operationId !== expectedOperationId
    || journal.gitLockReason !== `buwiz-worktree-remove:${journal.operationId}`
    || journal.registeredTombstone !== join(
      dirname(journal.target),
      `.${basename(journal.target)}.removing-${journal.operationId.slice(0, 24)}`,
    )
    || journal.holdingPath !== join(
      dirname(journal.target),
      `.${basename(journal.target)}.holding-${journal.operationId.slice(0, 24)}`,
    )
    || journal.adminHoldingPath !== join(
      context.commonDir,
      "worktree-admin-holds",
      `${basename(journal.targetGitDir)}-${journal.operationId.slice(0, 24)}`,
    )) {
    fail(`worktree removal receipt does not use deterministic operation paths: ${path}`, EXIT.safety);
  }
  const rootManifest = worktreeRemovalCaptureManifest(
    journal.rootManifest.map(({ captureRelativePath: _capture, ...entry }) => entry),
    journal.operationId,
    "root",
  );
  const adminManifest = worktreeRemovalCaptureManifest(
    journal.adminManifest.map(({ captureRelativePath: _capture, ...entry }) => entry),
    journal.operationId,
    "admin",
  );
  if (!deletionManifestsEqual(rootManifest, journal.rootManifest)
    || !deletionManifestsEqual(adminManifest, journal.adminManifest)) {
    fail(`worktree removal receipt has invalid deterministic capture paths: ${path}`, EXIT.safety);
  }
  return journal;
}

function readWorktreeRemovalJournal(path, context) {
  if (!isAbsolute(path) || resolve(path) !== path || basename(path) === "") {
    fail(`worktree removal resume requires one exact absolute receipt path: ${path}`, EXIT.safety);
  }
  const real = realpathExisting(path, "worktree removal receipt");
  if (real !== path || !isContained(join(context.commonDir, "buwiz-workspace-maintenance", "receipts"), real)) {
    fail(`worktree removal receipt is outside its repository maintenance directory: ${path}`, EXIT.safety);
  }
  const receiptIdentity = identity(real, "worktree removal receipt", "file");
  let journal;
  try {
    journal = JSON.parse(readFileSync(real, "utf8"));
  } catch {
    fail(`worktree removal receipt is not valid JSON: ${real}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(receiptIdentity, real)) {
    fail(`worktree removal receipt changed while it was read: ${real}`, EXIT.safety);
  }
  validateWorktreeRemovalJournal(journal, real, context);
  return { path: real, identity: receiptIdentity, journal };
}

function readWorktreeRemovalJournalEnvelope(path) {
  if (!isAbsolute(path) || resolve(path) !== path || basename(path) === "") {
    fail(`worktree removal resume requires one exact absolute receipt path: ${path}`, EXIT.safety);
  }
  const real = realpathExisting(path, "worktree removal receipt");
  const receiptIdentity = identity(real, "worktree removal receipt", "file");
  let journal;
  try {
    journal = JSON.parse(readFileSync(real, "utf8"));
  } catch {
    fail(`worktree removal receipt is not valid JSON: ${real}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(receiptIdentity, real)
    || !journal || journal.version !== WORKTREE_REMOVAL_JOURNAL_VERSION
    || journal.operation !== "worktree-remove"
    || !isAbsolute(journal.commonDir) || resolve(journal.commonDir) !== journal.commonDir
    || !isAbsolute(journal.target) || resolve(journal.target) !== journal.target
    || !isAbsolute(journal.targetGitDir) || resolve(journal.targetGitDir) !== journal.targetGitDir
    || !isAbsolute(journal.registeredTombstone) || !isAbsolute(journal.holdingPath)
    || !isContained(join(journal.commonDir, "buwiz-workspace-maintenance", "receipts"), real)
    || journal.authorizationDigest !== worktreeRemovalAuthorizationDigest(journal)) {
    fail(`worktree removal receipt is invalid or changed: ${real}`, EXIT.safety);
  }
  return { path: real, identity: receiptIdentity, journal };
}

function releaseStaleWorktreeRemovalLockForRefusal(entry) {
  const path = lockPath(entry.journal.commonDir);
  if (lstatOptional(path, "repository maintenance lock") === null) return;
  reclaimStaleWorktreeRemovalLock(path, entry);
}

function updateWorktreeRemovalJournal(entry, state) {
  const currentIdentity = identity(entry.path, "worktree removal receipt", "file");
  let current;
  try {
    current = JSON.parse(readFileSync(entry.path, "utf8"));
  } catch {
    fail(`worktree removal receipt is not valid JSON: ${entry.path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(currentIdentity, entry.path)
    || current.authorizationDigest !== entry.journal.authorizationDigest
    || current.state !== entry.journal.state) {
    fail(`worktree removal receipt changed before update: ${entry.path}`, EXIT.safety);
  }
  const updated = worktreeRemovalReceiptPayload(entry.journal, state);
  entry.identity = replacePhysicalJson(entry.path, currentIdentity, updated, "worktree removal receipt");
  fsyncDirectory(dirname(entry.path), "worktree removal receipt parent");
  entry.journal = updated;
  return entry;
}

function worktreeRemovalLockOwner(entry, token) {
  return {
    version: WORKTREE_REMOVAL_JOURNAL_VERSION,
    kind: "worktree-remove",
    operationId: entry.journal.operationId,
    receiptPath: entry.path,
    authorizationDigest: entry.journal.authorizationDigest,
    host: hostname(),
    pid: process.pid,
    token,
    startedAt: new Date().toISOString(),
  };
}

function reclaimStaleWorktreeRemovalLock(path, entry) {
  const lockIdentity = identity(path, "repository maintenance lock", "file");
  const bytes = readFileSync(path, "utf8");
  let owner;
  try {
    owner = JSON.parse(bytes);
  } catch {
    fail(`repository maintenance lock is corrupt: ${path}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(lockIdentity, path)
    || owner.version !== WORKTREE_REMOVAL_JOURNAL_VERSION || owner.kind !== "worktree-remove"
    || owner.operationId !== entry.journal.operationId || owner.receiptPath !== entry.path
    || owner.authorizationDigest !== entry.journal.authorizationDigest
    || owner.host !== hostname() || typeof owner.token !== "string"
    || !processDefinitelyAbsent(owner.pid)) {
    fail(`repository maintenance lock is already held or cannot be proven stale: ${path}`, EXIT.safety);
  }
  const staleRoot = ensurePhysicalChild(
    metadataRoot(entry.journal.commonDir),
    "stale-locks",
    "stale lock directory",
  );
  const stalePath = join(staleRoot, `worktree-${owner.token}.json`);
  if (lstatOptional(stalePath, "stale lock capture") !== null
    || !fileIdentityMatchesAt(lockIdentity, path) || readFileSync(path, "utf8") !== bytes) {
    fail(`repository maintenance lock changed before stale capture: ${path}`, EXIT.safety);
  }
  renameSync(path, stalePath);
  fsyncDirectory(dirname(path), "maintenance lock parent");
  if (!fileIdentityMatchesAt(lockIdentity, stalePath) || readFileSync(stalePath, "utf8") !== bytes) {
    fail(`stale maintenance lock changed during capture: ${stalePath}`, EXIT.safety);
  }
}

function acquireWorktreeRemovalLock(entry, resume) {
  const path = lockPath(entry.journal.commonDir);
  if (lstatOptional(path, "repository maintenance lock") !== null) {
    if (!resume) fail(`repository maintenance lock is already held: ${path}`, EXIT.safety);
    reclaimStaleWorktreeRemovalLock(path, entry);
  }
  const token = randomUUID();
  const owner = worktreeRemovalLockOwner(entry, token);
  let fd;
  let lockStat;
  try {
    fd = openSync(path, "wx", 0o600);
    lockStat = fstatSync(fd);
    writeFileSync(fd, `${JSON.stringify(owner, null, 2)}\n`);
    fsyncSync(fd);
    closeSync(fd);
    fd = undefined;
    fsyncDirectory(dirname(path), "maintenance lock parent");
  } catch (error) {
    if (fd !== undefined) closeSync(fd);
    fail(`repository maintenance lock is already held: ${path}: ${error.message}`, EXIT.safety);
  }
  return () => {
    try {
      const stat = lstatSync(path);
      const current = JSON.parse(readFileSync(path, "utf8"));
      if (stat.isFile() && !stat.isSymbolicLink() && stat.dev === lockStat.dev
        && stat.ino === lockStat.ino && current.token === token) {
        unlinkSync(path);
        fsyncDirectory(dirname(path), "maintenance lock parent");
      } else {
        process.stderr.write(`warning: maintenance lock identity changed; refusing to remove ${path}\n`);
      }
    } catch (error) {
      process.stderr.write(`warning: could not safely release maintenance lock ${path}: ${error.message}\n`);
    }
  };
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
    ? ensurePhysicalChild(location.parent, ".buwiz-workspace-maintenance", "quarantine namespace", { durable: true })
    : realpathExisting(location.namespace, "quarantine namespace");
  physicalStat(maintenanceParentReal, "quarantine namespace", "directory");
  if (maintenanceParentReal !== location.namespace) {
    fail(`quarantine namespace escapes its physical parent: ${location.namespace}`, EXIT.safety);
  }
  const candidateReal = create
    ? ensurePhysicalChild(maintenanceParentReal, location.identity, "quarantine base", { durable: true })
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

function durableCleanupReceiptsForWorktree(context, gitDirReal) {
  const stateRoot = join(context.commonDir, "buwiz-workspace-maintenance");
  if (lstatOptional(stateRoot, "maintenance state directory") === null) return [];
  physicalStat(stateRoot, "maintenance state directory", "directory");
  if (realpathExisting(stateRoot, "maintenance state directory") !== stateRoot) {
    fail(`maintenance state directory escapes its physical path: ${stateRoot}`, EXIT.safety);
  }
  const durableRoot = join(stateRoot, "cleanup-receipts");
  if (lstatOptional(durableRoot, "durable cleanup receipt directory") === null) return [];
  physicalStat(durableRoot, "durable cleanup receipt directory", "directory");
  if (realpathExisting(durableRoot, "durable cleanup receipt directory") !== durableRoot) {
    fail(`durable cleanup receipt directory escapes its physical path: ${durableRoot}`, EXIT.safety);
  }
  const receipts = [];
  for (const name of readdirSync(durableRoot)) {
    if (!/^[0-9a-f]{64}$/u.test(name)) {
      fail(`durable cleanup receipt directory contains an unknown entry: ${join(durableRoot, name)}`, EXIT.safety);
    }
    const operationRoot = join(durableRoot, name);
    physicalStat(operationRoot, "durable cleanup operation directory", "directory");
    if (realpathExisting(operationRoot, "durable cleanup operation directory") !== operationRoot) {
      fail(`durable cleanup operation directory escapes its physical path: ${operationRoot}`, EXIT.safety);
    }
    const allowed = new Set(["receipt.json", "purge.json"]);
    for (const entry of readdirSync(operationRoot)) {
      if (!allowed.has(entry)) {
        fail(`durable cleanup operation directory contains an unknown entry: ${join(operationRoot, entry)}`, EXIT.safety);
      }
    }
    const durablePath = join(operationRoot, "receipt.json");
    physicalStat(durablePath, "durable cleanup receipt", "file");
    const handle = resolveCleanupReceiptHandle(context, durablePath);
    if (!Array.isArray(handle.receipt.sourceWorktreeGitDirs)) {
      fail(`durable cleanup receipt does not identify source worktrees: ${durablePath}`, EXIT.safety);
    }
    const journal = readPurgeJournal(context, handle);
    if (journal?.journal.phase === "complete") {
      if (lstatOptional(journal.journal.transactionRoot, "purged transaction root") !== null
        || lstatOptional(journal.journal.tombstonePath, "purged tombstone") !== null) {
        fail(`completed purge journal still retains deletion paths: ${journal.path}`, EXIT.safety);
      }
      continue;
    }
    if (journal && ["authorized", "deleting"].includes(journal.journal.phase)) {
      if (handle.receipt.sourceWorktreeGitDirs.includes(gitDirReal)) {
        fail(`cleanup purge requires resuming exact receipt: ${durablePath}`, EXIT.safety);
      }
      continue;
    }
    if (handle.receipt.sourceWorktreeGitDirs.includes(gitDirReal)) receipts.push(durablePath);
  }
  return receipts.sort();
}

function outstandingCleanupReceipts(context, target) {
  let indexedState;
  try {
    indexedState = readCleanupState(context, target);
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    return { receipts: [], uncertainty: detail };
  }
  const indexed = indexedState ?? null;
  if (indexed) {
    const { state } = indexed;
    if (state.state === "purged") {
      try {
        const handle = resolveCleanupReceiptHandle(context, state.durableReceiptPath);
        const journal = readPurgeJournal(context, handle);
        if (!journal || journal.journal.phase !== "complete"
          || lstatOptional(journal.journal.transactionRoot, "purged transaction root") !== null
          || lstatOptional(journal.journal.tombstonePath, "purged tombstone") !== null) {
          fail(`purged cleanup state does not match a completed purge journal: ${indexed.path}`, EXIT.safety);
        }
        return { receipts: [], uncertainty: null };
      } catch (error) {
        const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
        return { receipts: [], uncertainty: detail };
      }
    }
    if (!["receipt", "purging"].includes(state.state)
      || typeof state.receiptPath !== "string"
      || typeof state.durableReceiptPath !== "string") {
      return {
        receipts: [],
        uncertainty: `cleanup state requires resolution (${state.state}): ${indexed.path}`,
      };
    }
    try {
      const handle = resolveCleanupReceiptHandle(context, state.durableReceiptPath);
      const journal = readPurgeJournal(context, handle);
      if (!handle.receipt.sourceWorktreeGitDirs.includes(target.gitDirReal)
        || handle.receipt.transactionRoot !== state.transactionRoot) {
        fail(`cleanup state does not match its receipt: ${indexed.path}`, EXIT.safety);
      }
      if (state.state === "purging") {
        if (!journal || !["authorized", "deleting"].includes(journal.journal.phase)) {
          fail(`cleanup state does not match an resumable purge journal: ${indexed.path}`, EXIT.safety);
        }
        return {
          receipts: [],
          uncertainty: `cleanup purge requires resuming exact receipt: ${state.durableReceiptPath}`,
        };
      }
      return { receipts: [state.durableReceiptPath], uncertainty: null };
    } catch (error) {
      const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
      return { receipts: [], uncertainty: detail };
    }
  }
  try {
    const durableReceipts = durableCleanupReceiptsForWorktree(context, target.gitDirReal);
    if (durableReceipts.length > 0) return { receipts: durableReceipts, uncertainty: null };
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    return { receipts: [], uncertainty: detail };
  }
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
      if (parsed.receipt.sourceWorktreeGitDirs.includes(target.gitDirReal)) {
        receipts.push(parsed.durableReceiptPath);
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

function cleanJournalRoot(commonDir, create = true) {
  const stateRoot = create
    ? metadataRoot(commonDir)
    : join(commonDir, "buwiz-workspace-maintenance");
  if (!create) {
    physicalStat(stateRoot, "maintenance state directory", "directory");
    if (realpathExisting(stateRoot, "maintenance state directory") !== stateRoot) {
      fail(`maintenance state directory escapes its physical path: ${stateRoot}`, EXIT.safety);
    }
  }
  const root = create
    ? ensurePhysicalChild(stateRoot, "clean-operations", "cleanup operation journal directory", { durable: true })
    : join(stateRoot, "clean-operations");
  if (!create) {
    physicalStat(root, "cleanup operation journal directory", "directory");
    if (realpathExisting(root, "cleanup operation journal directory") !== root) {
      fail(`cleanup operation journal directory escapes its physical path: ${root}`, EXIT.safety);
    }
  }
  return root;
}

function cleanJournalAuthorizationDigest(journal) {
  return createHash("sha256").update(JSON.stringify({
    version: journal.version,
    operation: journal.operation,
    operationId: journal.operationId,
    commonDir: journal.commonDir,
    transactionRoot: journal.transactionRoot,
    quarantineRoot: journal.quarantineRoot,
    sourceWorktrees: journal.sourceWorktrees,
    sourceWorktreeGitDirs: journal.sourceWorktreeGitDirs,
    sourceHeads: journal.sourceHeads,
    moves: journal.moves,
    createdAt: journal.createdAt,
  })).digest("hex");
}

function cleanJournalFromPlan(context, plan, transactionRoot, digest) {
  const operationId = createHash("sha256")
    .update(`${context.commonDir}\0${transactionRoot}\0${digest}`)
    .digest("hex");
  const createdAt = new Date().toISOString();
  const moves = plan.flatMap(({ record, entries }) => entries.map((entry) => {
    const manifest = captureStableDeletionManifest(entry.absolute, "cleanup source artifact");
    return {
      source: entry.absolute,
      destination: join(
        transactionRoot,
        createHash("sha256").update(record.path).digest("hex").slice(0, 12),
        entry.relativePath,
      ),
      sourceWorktree: record.path,
      sourceWorktreeGitDir: record.gitDirReal,
      relativePath: entry.relativePath,
      rootIdentity: {
        dev: entry.dev,
        ino: entry.ino,
        mode: entry.mode,
        mtimeMs: entry.mtimeMs,
      },
      manifest,
      manifestDigest: deletionManifestDigest(manifest),
      bytes: entry.bytes,
      entries: entry.entries,
      nativeSymlinks: entry.nativeSymlinks,
      dependencySymlinks: entry.dependencySymlinks,
    };
  }));
  const journal = {
    version: CLEAN_JOURNAL_VERSION,
    operation: "clean-quarantine",
    operationId,
    phase: "authorized",
    commonDir: context.commonDir,
    transactionRoot,
    quarantineRoot: dirname(transactionRoot),
    sourceWorktrees: plan.map(({ record }) => record.path),
    sourceWorktreeGitDirs: plan.map(({ record }) => record.gitDirReal),
    sourceHeads: plan.map(({ record }) => record.HEAD),
    digest,
    moves,
    authorizationDigest: null,
    internalReceiptPath: join(transactionRoot, "receipt.json"),
    durableReceiptPath: durableCleanupReceiptPath(context.commonDir, join(transactionRoot, "receipt.json")),
    createdAt,
    updatedAt: createdAt,
  };
  journal.authorizationDigest = cleanJournalAuthorizationDigest(journal);
  return journal;
}

function validateCleanJournal(journal, path, context) {
  if (!journal || journal.version !== CLEAN_JOURNAL_VERSION
    || journal.operation !== "clean-quarantine"
    || !["authorized", "moving", "internal-receipt", "durable-receipt", "complete"].includes(journal.phase)
    || journal.commonDir !== context.commonDir
    || !isAbsolute(journal.transactionRoot) || !isAbsolute(journal.quarantineRoot)
    || dirname(journal.transactionRoot) !== journal.quarantineRoot
    || !Array.isArray(journal.sourceWorktrees) || journal.sourceWorktrees.length === 0
    || !Array.isArray(journal.sourceWorktreeGitDirs)
    || journal.sourceWorktreeGitDirs.length !== journal.sourceWorktrees.length
    || !Array.isArray(journal.sourceHeads)
    || journal.sourceHeads.length !== journal.sourceWorktrees.length
    || !Array.isArray(journal.moves) || journal.moves.length === 0
    || journal.internalReceiptPath !== join(journal.transactionRoot, "receipt.json")
    || journal.durableReceiptPath !== durableCleanupReceiptPath(context.commonDir, journal.internalReceiptPath, false)
    || journal.authorizationDigest !== cleanJournalAuthorizationDigest(journal)) {
    fail(`cleanup operation journal is invalid or changed: ${path}`, EXIT.safety);
  }
  const expectedOperationId = createHash("sha256")
    .update(`${context.commonDir}\0${journal.transactionRoot}\0${journal.digest}`)
    .digest("hex");
  if (journal.operationId !== expectedOperationId) {
    fail(`cleanup operation journal has an invalid operation identity: ${path}`, EXIT.safety);
  }
  const sourceSet = new Set(journal.sourceWorktrees);
  const destinationSet = new Set();
  for (const move of journal.moves) {
    if (!move || !sourceSet.has(move.sourceWorktree)
      || !journal.sourceWorktreeGitDirs.includes(move.sourceWorktreeGitDir)
      || !ALL_TARGETS.flatMap((name) => TARGETS[name]).includes(move.relativePath)
      || move.source !== join(move.sourceWorktree, move.relativePath)
      || move.destination !== join(
        journal.transactionRoot,
        createHash("sha256").update(move.sourceWorktree).digest("hex").slice(0, 12),
        move.relativePath,
      )
      || !Array.isArray(move.manifest) || move.manifest.length === 0
      || move.manifestDigest !== deletionManifestDigest(move.manifest)
      || destinationSet.has(move.destination)
      || !isContained(journal.transactionRoot, move.destination)) {
      fail(`cleanup operation journal contains an invalid move: ${path}`, EXIT.safety);
    }
    destinationSet.add(move.destination);
  }
  return journal;
}

function createCleanJournal(context, journal) {
  const operationRoot = ensurePhysicalChild(
    cleanJournalRoot(context.commonDir),
    journal.operationId,
    "cleanup operation journal",
    { durable: true },
  );
  const path = join(operationRoot, "journal.json");
  const existing = lstatOptional(path, "cleanup operation journal");
  if (existing !== null) {
    const entry = readCleanJournal(context, path);
    if (entry.journal.authorizationDigest !== journal.authorizationDigest) {
      fail(`cleanup operation journal already exists with different authorization: ${path}`, EXIT.safety);
    }
    if (entry.journal.phase === "complete") {
      process.stdout.write(`Cleanup already complete.\n  receipt: ${entry.journal.durableReceiptPath}\n`);
      return { ...entry, existing: "complete" };
    }
    fail(`cleanup operation is already authorized; resume only with: just clean resume ${posixShellQuote(path)} --force`, EXIT.safety);
  }
  writeReceipt(path, journal);
  fsyncDirectory(operationRoot, "cleanup operation journal directory");
  fsyncDirectory(dirname(operationRoot), "cleanup operation journal root");
  runTestHook("after-clean-journal-create", { journalPath: path });
  return { path, identity: identity(path, "cleanup operation journal", "file"), journal };
}

function readCleanJournal(context, suppliedPath) {
  if (!isAbsolute(suppliedPath) || resolve(suppliedPath) !== suppliedPath
    || basename(suppliedPath) !== "journal.json") {
    fail(`clean resume requires an exact absolute journal.json path: ${suppliedPath}`, EXIT.safety);
  }
  const journalRoot = cleanJournalRoot(context.commonDir, false);
  if (!isContained(journalRoot, suppliedPath) || dirname(dirname(suppliedPath)) !== journalRoot) {
    fail(`cleanup operation journal is outside this repository: ${suppliedPath}`, EXIT.safety);
  }
  const real = realpathExisting(suppliedPath, "cleanup operation journal");
  if (real !== suppliedPath) {
    fail(`cleanup operation journal must be canonical and physical: ${suppliedPath}`, EXIT.safety);
  }
  const journalIdentity = identity(suppliedPath, "cleanup operation journal", "file");
  let journal;
  try {
    journal = JSON.parse(readFileSync(suppliedPath, "utf8"));
  } catch {
    fail(`cleanup operation journal is not valid JSON: ${suppliedPath}`, EXIT.safety);
  }
  if (!fileIdentityMatchesAt(journalIdentity, suppliedPath)) {
    fail(`cleanup operation journal changed while it was read: ${suppliedPath}`, EXIT.safety);
  }
  validateCleanJournal(journal, suppliedPath, context);
  return { path: suppliedPath, identity: journalIdentity, journal };
}

function updateCleanJournal(entry, phase) {
  const currentIdentity = identity(entry.path, "cleanup operation journal", "file");
  const current = JSON.parse(readFileSync(entry.path, "utf8"));
  if (current.authorizationDigest !== entry.journal.authorizationDigest
    || current.phase !== entry.journal.phase
    || !fileIdentityMatchesAt(currentIdentity, entry.path)) {
    fail(`cleanup operation journal changed before update: ${entry.path}`, EXIT.safety);
  }
  const updated = { ...entry.journal, phase, updatedAt: new Date().toISOString() };
  entry.identity = replacePhysicalJson(entry.path, currentIdentity, updated, "cleanup operation journal");
  fsyncDirectory(dirname(entry.path), "cleanup operation journal directory");
  entry.journal = updated;
  runTestHook(`after-clean-journal-${phase}`, { journalPath: entry.path });
  return entry;
}

function cleanReceiptFromJournal(journal) {
  const receipt = {
    version: VERSION,
    operation: "clean",
    createdAt: journal.createdAt,
    digest: journal.digest,
    contentsDigest: null,
    transactionRoot: journal.transactionRoot,
    quarantineRoot: journal.quarantineRoot,
    sourceWorktrees: journal.sourceWorktrees,
    sourceWorktreeGitDirs: journal.sourceWorktreeGitDirs,
    moves: journal.moves.map((move) => ({
      source: move.source,
      destination: move.destination,
      bytes: move.bytes,
      entries: move.entries,
    })),
    nativeSymlinks: journal.moves.flatMap((move) => move.nativeSymlinks.map((link) => ({
      path: join(move.destination, link.relativePath),
      target: link.target,
      dev: link.dev,
      ino: link.ino,
      mode: link.mode,
      mtimeMs: link.mtimeMs,
    }))),
    dependencySymlinks: journal.moves.flatMap((move) => move.dependencySymlinks.map((link) => ({
      path: join(move.destination, link.relativePath),
      target: link.target,
      dev: link.dev,
      ino: link.ino,
      mode: link.mode,
      mtimeMs: link.mtimeMs,
    }))),
  };
  receipt.contentsDigest = createHash("sha256").update(JSON.stringify({
    sourceWorktrees: receipt.sourceWorktrees,
    sourceWorktreeGitDirs: receipt.sourceWorktreeGitDirs,
    moves: receipt.moves,
    nativeSymlinks: receipt.nativeSymlinks,
    dependencySymlinks: receipt.dependencySymlinks,
  })).digest("hex");
  return receipt;
}

function moveMatchesJournalIdentity(move, path) {
  try {
    const stat = lstatSync(path);
    return stat.isDirectory() && !stat.isSymbolicLink()
      && stat.dev === move.rootIdentity.dev
      && stat.ino === move.rootIdentity.ino
      && stat.mode === move.rootIdentity.mode
      && stat.mtimeMs === move.rootIdentity.mtimeMs
      && deletionManifestsEqual(move.manifest, buildDeletionManifest(path))
      && nativeSymlinksMatchAt(move, path)
      && dependencySymlinksMatchAt(move, path);
  } catch {
    return false;
  }
}

function cleanJournalDestinationDirectories(journal) {
  const directories = new Set([journal.transactionRoot]);
  for (const move of journal.moves) {
    let current = dirname(move.destination);
    while (current !== journal.transactionRoot) {
      if (!isContained(journal.transactionRoot, current)) {
        fail(`cleanup journal destination escapes its transaction: ${move.destination}`, EXIT.safety);
      }
      directories.add(current);
      current = dirname(current);
    }
  }
  return directories;
}

function validateCleanTransactionLayout(journal, allowReceipt) {
  const transactionStat = lstatOptional(journal.transactionRoot, "cleanup transaction");
  if (transactionStat === null) return;
  physicalStat(journal.transactionRoot, "cleanup transaction", "directory");
  if (realpathExisting(journal.transactionRoot, "cleanup transaction") !== journal.transactionRoot) {
    fail(`cleanup transaction must be canonical and physical: ${journal.transactionRoot}`, EXIT.safety);
  }
  requireNoNestedMounts(journal.transactionRoot, "cleanup transaction");
  const destinations = new Set(journal.moves.map(({ destination }) => destination));
  const directories = cleanJournalDestinationDirectories(journal);
  const allowedReceipts = allowReceipt
    ? new Set([journal.internalReceiptPath])
    : new Set();
  const stack = [journal.transactionRoot];
  while (stack.length) {
    const current = stack.pop();
    if (destinations.has(current)) {
      const move = journal.moves.find(({ destination }) => destination === current);
      if (!moveMatchesJournalIdentity(move, current)) {
        fail(`cleanup destination changed from its authorized identity: ${current}`, EXIT.safety);
      }
      continue;
    }
    if (allowedReceipts.has(current)) {
      physicalStat(current, "cleanup transaction receipt", "file");
      continue;
    }
    if (!directories.has(current)) {
      fail(`cleanup transaction contains unknown content: ${current}`, EXIT.safety);
    }
    physicalStat(current, "cleanup transaction structural directory", "directory");
    for (const name of readdirSync(current)) stack.push(join(current, name));
  }
}

function cleanJournalRecords(context, journal) {
  return journal.sourceWorktreeGitDirs.map((gitDir, index) => {
    const record = context.records.find((candidate) => candidate.gitDirReal === gitDir && !candidate.missing);
    if (!record || record.path !== journal.sourceWorktrees[index]
      || record.HEAD !== journal.sourceHeads[index]
      || record.locked || record.prunable) {
      fail(`cleanup source worktree topology changed: ${gitDir}`, EXIT.safety);
    }
    return record;
  });
}

function cleanJournalStates(context, journal, records) {
  return records.map((record) => {
    const state = readCleanupState(context, record);
    if (!state || state.state.transactionRoot !== journal.transactionRoot
      || !["moving", "receipt"].includes(state.state.state)) {
      fail(`cleanup state is missing or inconsistent for resume: ${record.gitDirReal}`, EXIT.safety);
    }
    return { ...state, record, payload: state.state };
  });
}

function ensureCleanJournalStates(context, journal, records, options = {}) {
  const { allowCreate = true } = options;
  const existing = records.map((record) => readCleanupState(context, record));
  if (existing.every((state) => state === null)) {
    if (!allowCreate) {
      fail("cleanup state is missing after cleanup authorization progressed", EXIT.safety);
    }
    return createCleanupStates(
      context,
      records.map((record) => ({ record, entries: [] })),
      journal.transactionRoot,
    );
  }
  if (existing.some((state) => state === null)) {
    fail(`cleanup states are only partially present for resume`, EXIT.safety);
  }
  return cleanJournalStates(context, journal, records);
}

function requireCleanProcessesClear(records, journal) {
  for (const record of records) {
    const artifactRoots = journal.moves
      .filter((move) => move.sourceWorktreeGitDir === record.gitDirReal)
      .map((move) => move.source);
    requireClearProcesses(record.pathReal, artifactRoots);
  }
}

function writeOrVerifyCleanReceipt(path, receipt, label) {
  const text = `${JSON.stringify(receipt, null, 2)}\n`;
  const stat = lstatOptional(path, label);
  if (stat === null) {
    writeReceipt(path, receipt);
    fsyncDirectory(dirname(path), `${label} parent`);
    return;
  }
  physicalStat(path, label, "file");
  if (readFileSync(path, "utf8") !== text) {
    fail(`${label} differs from the authorized cleanup receipt: ${path}`, EXIT.safety);
  }
}

function resumeCleanJournal(context, journalEntry, options = {}) {
  const { allowStaleReclaim = true } = options;
  const release = acquireCleanLock(context.commonDir, journalEntry, allowStaleReclaim);
  try {
    const fresh = repoContext(invocationCwd());
    if (!contextTopologyEqual(context, fresh)) {
      fail("repository worktree topology changed before cleanup resume", EXIT.safety);
    }
    const refreshed = readCleanJournal(fresh, journalEntry.path);
    if (refreshed.journal.authorizationDigest !== journalEntry.journal.authorizationDigest) {
      fail(`cleanup operation journal changed after locking: ${journalEntry.path}`, EXIT.safety);
    }
    journalEntry = refreshed;
    const { journal } = journalEntry;
    const records = cleanJournalRecords(fresh, journal);
    const states = ensureCleanJournalStates(fresh, journal, records, {
      allowCreate: journal.phase === "authorized",
    });

    if (journal.phase === "complete") {
      const receipt = cleanReceiptFromJournal(journal);
      validateCleanTransactionLayout(journal, true);
      writeOrVerifyCleanReceipt(journal.internalReceiptPath, receipt, "cleanup transaction receipt");
      writeOrVerifyCleanReceipt(journal.durableReceiptPath, receipt, "durable cleanup receipt");
      if (states.some(({ payload }) => payload.state !== "receipt")) {
        updateCleanupStates(
          fresh, states, journal.transactionRoot, "receipt",
          journal.internalReceiptPath, journal.durableReceiptPath,
        );
      }
      process.stdout.write(`Cleanup already complete.\n  receipt: ${journal.durableReceiptPath}\n`);
      return;
    }

    if (journal.phase === "authorized") {
      if (lstatOptional(journal.transactionRoot, "cleanup transaction") !== null) {
        validateCleanTransactionLayout(journal, false);
      }
      updateCleanJournal(journalEntry, "moving");
    }
    if (journalEntry.journal.phase === "moving"
      && lstatOptional(journal.transactionRoot, "cleanup transaction") === null) {
      const created = ensurePhysicalChild(
        journal.quarantineRoot,
        basename(journal.transactionRoot),
        "cleanup transaction",
        { durable: true },
      );
      if (created !== journal.transactionRoot) {
        fail(`cleanup transaction escaped its quarantine: ${created}`, EXIT.safety);
      }
      fsyncDirectory(journal.quarantineRoot, "cleanup quarantine root");
    }
    if (journalEntry.journal.phase === "moving") {
      validateCleanTransactionLayout(journal, false);
      requireCleanProcessesClear(records, journal);

      for (let index = 0; index < journal.moves.length; index += 1) {
        const move = journal.moves[index];
        const sourceStat = lstatOptional(move.source, "cleanup source artifact");
        const destinationStat = lstatOptional(move.destination, "cleanup destination artifact");
        if (sourceStat !== null && destinationStat !== null) {
          fail(`cleanup source and destination both exist for authorized move: ${move.source}`, EXIT.safety);
        }
        if (sourceStat === null && destinationStat === null) {
          fail(`cleanup source and destination are both missing for authorized move: ${move.source}`, EXIT.safety);
        }
        if (destinationStat !== null) {
          if (!moveMatchesJournalIdentity(move, move.destination)) {
            fail(`cleanup destination was replaced: ${move.destination}`, EXIT.safety);
          }
          continue;
        }
        if (!moveMatchesJournalIdentity(move, move.source)) {
          fail(`cleanup source was replaced: ${move.source}`, EXIT.safety);
        }
        const destinationParent = ensurePhysicalRelativeDirectory(
          journal.transactionRoot,
          relative(journal.transactionRoot, dirname(move.destination)),
          "cleanup destination directory",
          { durable: true },
        );
        if (destinationParent.path !== dirname(move.destination)
          || !destinationParent.identities.every(identityMatches)
          || lstatOptional(move.destination, "cleanup destination artifact") !== null
          || !moveMatchesJournalIdentity(move, move.source)) {
          fail(`cleanup move identity changed at rename boundary: ${move.source}`, EXIT.safety);
        }
        runTestHook("before-artifact-rename", {
          source: move.source,
          destination: move.destination,
          destinationParent: destinationParent.path,
          transactionRoot: journal.transactionRoot,
          moveIndex: index,
        });
        renameSync(move.source, move.destination);
        fsyncDirectory(dirname(move.source), "cleanup source parent");
        fsyncDirectory(dirname(move.destination), "cleanup destination parent");
        runTestHook("after-artifact-rename", {
          source: move.source,
          destination: move.destination,
          moveIndex: index,
        });
        runTestHook(`after-artifact-rename-${index}`, {
          source: move.source,
          destination: move.destination,
          moveIndex: index,
        });
        injectTestFailure("after-artifact-rename");
        if (!moveMatchesJournalIdentity(move, move.destination)) {
          fail(`cleanup destination changed after rename: ${move.destination}`, EXIT.safety);
        }
      }
      validateCleanTransactionLayout(journal, false);
    } else if (!["internal-receipt", "durable-receipt"].includes(journalEntry.journal.phase)) {
      fail(`cleanup journal phase cannot resume: ${journalEntry.journal.phase}`, EXIT.safety);
    }

    const receipt = cleanReceiptFromJournal(journal);
    if (journalEntry.journal.phase === "moving") {
      updateCleanJournal(journalEntry, "internal-receipt");
    }
    validateCleanTransactionLayout(journal, true);
    writeOrVerifyCleanReceipt(journal.internalReceiptPath, receipt, "cleanup transaction receipt");
    runTestHook("after-clean-internal-receipt", { receiptPath: journal.internalReceiptPath });
    if (journalEntry.journal.phase === "internal-receipt") {
      updateCleanJournal(journalEntry, "durable-receipt");
    }
    validateCleanTransactionLayout(journal, true);
    writeOrVerifyCleanReceipt(journal.durableReceiptPath, receipt, "durable cleanup receipt");
    runTestHook("after-clean-durable-receipt", { receiptPath: journal.durableReceiptPath });
    updateCleanupStates(
      fresh, states, journal.transactionRoot, "receipt",
      journal.internalReceiptPath, journal.durableReceiptPath,
    );
    runTestHook("after-clean-state-update", { journalPath: journalEntry.path });
    updateCleanJournal(journalEntry, "complete");
    runTestHook("after-clean-complete", { journalPath: journalEntry.path });
    process.stdout.write(`Quarantined artifacts; nothing has been permanently deleted.\n  receipt: ${journal.durableReceiptPath}\n`);
    process.stdout.write(`Review it, then reclaim disk with: just clean purge ${posixShellQuote(journal.durableReceiptPath)} --force\n`);
  } finally {
    release();
  }
}

function commandCleanResume(positionals, options) {
  if (positionals.length !== 2) {
    fail("clean resume accepts exactly one journal path", EXIT.usage);
  }
  if (options.json || options.worktree || options.allWorktrees) {
    fail("clean resume accepts only --dry-run and --force", EXIT.usage);
  }
  if (!options.dryRun && !options.force) {
    fail("clean resume requires --force (or use --dry-run)", EXIT.safety);
  }
  const context = repoContext(invocationCwd());
  const journalEntry = readCleanJournal(context, positionals[1]);
  process.stdout.write(`${options.dryRun ? "Would resume" : "Resuming"} cleanup ${journalEntry.journal.operationId}\n`);
  process.stdout.write(`  phase: ${journalEntry.journal.phase}\n`);
  process.stdout.write(`  moves: ${journalEntry.journal.moves.length}\n`);
  if (options.dryRun) return;
  requireMutationPlatform();
  resumeCleanJournal(context, journalEntry, { allowStaleReclaim: true });
}

function lockPath(commonDir) {
  return join(metadataRoot(commonDir), "lock.json");
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
  if (positionals[0] === "resume") {
    commandCleanResume(positionals, options);
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
  const transactionName = createHash("sha256")
    .update(`${context.commonDir}\0${digest}\0${plan.map(({ record }) => record.gitDirReal).join("\0")}`)
    .digest("hex");
  const transactionRoot = join(quarantineBase(context, plan[0].record.pathReal), transactionName);
  const quarantineRoot = dirname(transactionRoot);
  const journalPayload = cleanJournalFromPlan(context, plan, transactionRoot, digest);
  const journalEntry = createCleanJournal(context, journalPayload);
  if (journalEntry.existing === "complete") return;
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
    if (realpathExisting(quarantineRoot, "quarantine base") !== quarantineRoot) {
      fail("quarantine base changed after planning; nothing was deleted", EXIT.safety);
    }
    resumeCleanJournal(context, journalEntry, { allowStaleReclaim: false });
    return;
  } catch (error) {
    const reason = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    fail(`artifact cleanup stopped; resume only with: just clean resume ${posixShellQuote(journalEntry.path)} --force: ${reason}`, EXIT.safety);
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

function worktreeRemovalSiblingSnapshot(context, targetGitDir, targetPath = null) {
  return context.records.filter((record) =>
    record.gitDirReal !== targetGitDir && record.path !== targetPath).map((record) => ({
    path: record.path,
    gitDirReal: record.gitDirReal,
    HEAD: record.HEAD,
    branch: record.branch || null,
    detached: Boolean(record.detached),
    missing: record.missing,
  })).sort((left, right) => left.path.localeCompare(right.path));
}

function assertWorktreeRemovalSiblings(context, journal) {
  const observed = worktreeRemovalSiblingSnapshot(context, journal.targetGitDir, journal.target);
  if (JSON.stringify(observed) !== JSON.stringify(journal.siblingTopology)) {
    fail("repository sibling worktree topology changed during worktree removal", EXIT.safety);
  }
}

function worktreeRemovalGitLockMatches(journal, root = null) {
  const locked = join(journal.targetGitDir, "locked");
  if (lstatOptional(locked, "worktree operation lock") === null) return false;
  if (readPhysicalText(locked, "worktree operation lock") !== journal.gitLockReason) return false;
  if (root !== null) {
    const listed = git(journal.primaryWorktree, ["worktree", "list", "--porcelain", "-z"], { encoding: "buffer" });
    const record = parseWorktreePorcelain(listed.stdout).find((candidate) => candidate.path === root);
    if (!record || record.locked !== journal.gitLockReason) return false;
  }
  return true;
}

function verifyWorktreeRemovalTopology(entry, context) {
  const { journal } = entry;
  assertWorktreeRemovalSiblings(context, journal);
  const paths = {
    target: lstatOptional(journal.target, "original worktree path"),
    registered: lstatOptional(journal.registeredTombstone, "registered worktree tombstone"),
    holding: lstatOptional(journal.holdingPath, "worktree holding path"),
    admin: lstatOptional(journal.targetGitDir, "worktree administration directory"),
    adminHolding: lstatOptional(journal.adminHoldingPath, "worktree administration holding path"),
  };
  if (paths.target !== null && paths.registered === null && paths.holding === null) {
    requireExactDeletionManifest(
      journal.target,
      journal.rootManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "original worktree root",
    );
  } else if (paths.target === null && paths.registered !== null && paths.holding === null) {
    requireExactDeletionManifest(
      journal.registeredTombstone,
      journal.rootManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "registered worktree tombstone",
    );
  } else if (paths.target === null && paths.registered === null && paths.holding !== null) {
    validatePartialPurgeTree(journal.holdingPath, journal.rootManifest);
  } else if (paths.target === null && paths.registered === null && paths.holding === null) {
    // Root deletion completed before its terminal journal update.
  } else {
    fail("worktree removal root topology is inconsistent or was repopulated", EXIT.safety);
  }
  if (paths.admin !== null && paths.adminHolding === null) {
    requireExactDeletionManifest(
      journal.targetGitDir,
      journal.adminManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "worktree administration directory",
    );
  } else if (paths.admin === null && paths.adminHolding !== null) {
    validatePartialPurgeTree(journal.adminHoldingPath, journal.adminManifest);
  } else if (paths.admin === null && paths.adminHolding === null) {
    // Administration deletion completed before its next journal update.
  } else {
    fail("worktree removal administration topology is inconsistent or was repopulated", EXIT.safety);
  }
  return paths;
}

function runWorktreeRemovalDeletion(root, manifest, journal, receiptPath, namespace) {
  const byRelativePath = new Map(manifest.map((entry) => [entry.relativePath, entry]));
  if (byRelativePath.size !== manifest.length || byRelativePath.get("")?.type !== "directory") {
    fail(`worktree deletion manifest is incomplete; retained at ${root}`, EXIT.safety);
  }
  const parentIdentity = identity(dirname(root), "worktree deletion parent", "directory");
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
  const hookPayload = (entry, path, capture = null) => ({
    receiptPath,
    root,
    path,
    capture,
    relativePath: entry.relativePath,
  });
  const leaves = manifest
    .filter((entry) => entry.type !== "directory")
    .sort((left, right) => deletionDepth(right) - deletionDepth(left)
      || left.relativePath.localeCompare(right.relativePath));
  const directories = manifest
    .filter((entry) => entry.type === "directory")
    .sort((left, right) => deletionDepth(right) - deletionDepth(left)
      || left.relativePath.localeCompare(right.relativePath));
  try {
    validatePartialPurgeTree(root, manifest);
    for (const entry of leaves) {
      const path = join(root, entry.relativePath);
      const capture = join(root, entry.captureRelativePath);
      const originalStat = lstatOptional(path, "worktree deletion entry");
      const captureStat = lstatOptional(capture, "worktree deletion capture");
      if (originalStat !== null && captureStat !== null) {
        fail(`worktree deletion entry and capture both exist: ${path}`, EXIT.safety);
      }
      if (originalStat === null && captureStat === null) continue;
      if (originalStat !== null) {
        if (!verifyParents(path) || !manifestEntryMatchesAt(entry, path)) {
          fail(`worktree deletion entry changed before capture: ${path}`, EXIT.safety);
        }
        renameSync(path, capture);
        fsyncDirectory(dirname(path), "worktree deletion capture parent");
      }
      runTestHook(`after-worktree-${namespace}-entry-rename`, hookPayload(entry, path, capture));
      if (!verifyParents(capture) || !manifestEntryMatchesAt(entry, capture)) {
        fail(`worktree deletion capture does not match its manifest entry: ${capture}`, EXIT.safety);
      }
      unlinkSync(capture);
      fsyncDirectory(dirname(capture), "worktree deletion capture parent");
      runTestHook(`after-worktree-${namespace}-entry-unlink`, hookPayload(entry, path, capture));
    }
    for (const entry of directories) {
      const path = join(root, entry.relativePath);
      if (lstatOptional(path, "worktree deletion directory") === null) continue;
      if ((path === root ? !identityMatches(parentIdentity) : !verifyParents(path))
        || !manifestEntryMatchesAt(entry, path, { allowDirectoryMetadataChange: true })) {
        fail(`worktree deletion directory changed before removal: ${path}`, EXIT.safety);
      }
      rmdirSync(path);
      fsyncDirectory(dirname(path), "worktree deletion directory parent");
      if (entry.relativePath === "") {
        const hook = namespace === "admin"
          ? "after-worktree-admin-root-rmdir"
          : "after-worktree-root-rmdir";
        runTestHook(hook, hookPayload(entry, path));
      }
    }
  } catch (error) {
    const detail = error instanceof MaintenanceError ? error.message : error?.message || String(error);
    fail(`worktree deletion stopped; unverified content was not recursively deleted; retained at ${root}: ${detail}`, EXIT.safety);
  }
}

function completeWorktreeRemoval(entry, context) {
  try {
    return completeWorktreeRemovalChecked(entry, context);
  } catch (error) {
    if (error instanceof MaintenanceError) throw error;
    const detail = error?.message || String(error);
    fail(`worktree removal stopped safely; staged content was retained: ${detail}`, EXIT.safety);
  }
}

function completeWorktreeRemovalChecked(entry, context) {
  const { journal } = entry;
  if (journal.state === "complete") {
    const paths = verifyWorktreeRemovalTopology(entry, context);
    if (Object.values(paths).some((stat) => stat !== null)) {
      fail("completed worktree removal paths were repopulated", EXIT.safety);
    }
    process.stdout.write(`Worktree removal already complete; receipt: ${entry.path}\n`);
    return;
  }
  let paths = verifyWorktreeRemovalTopology(entry, context);

  if (paths.target !== null) {
    if (journal.state !== "prepared" && journal.state !== "root-move-intent") {
      fail(`worktree removal phase ${journal.state} cannot retain the original root`, EXIT.safety);
    }
    if (!worktreeRemovalGitLockMatches(journal, journal.target)) {
      fail("worktree operation lock is missing or changed", EXIT.safety);
    }
    if (journal.state !== "root-move-intent") updateWorktreeRemovalJournal(entry, "root-move-intent");
    runTestHook("before-worktree-git-move", { path: journal.target, receiptPath: entry.path });
    requireExactDeletionManifest(
      journal.target,
      journal.rootManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "original worktree root",
    );
    renameSync(journal.target, journal.registeredTombstone);
    fsyncDirectory(dirname(journal.target), "worktree root parent");
    runTestHook("after-worktree-git-move", {
      receiptPath: entry.path,
      original: journal.target,
      registeredTombstone: journal.registeredTombstone,
      holdingPath: journal.holdingPath,
    });
    if (lstatOptional(journal.target, "original worktree path") !== null) {
      fail("original worktree path was repopulated after staging; staged content was retained", EXIT.safety);
    }
    paths = verifyWorktreeRemovalTopology(entry, repoContext(journal.primaryWorktree));
  }

  if (paths.registered !== null) {
    if (!worktreeRemovalGitLockMatches(journal)) {
      fail("worktree operation lock is missing or changed before holding rename", EXIT.safety);
    }
    requireExactDeletionManifest(
      journal.registeredTombstone,
      journal.rootManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "registered worktree tombstone",
    );
    renameSync(journal.registeredTombstone, journal.holdingPath);
    fsyncDirectory(dirname(journal.registeredTombstone), "worktree holding parent");
    updateWorktreeRemovalJournal(entry, "root-held");
    runTestHook("after-worktree-holding-rename", {
      receiptPath: entry.path,
      registeredTombstone: journal.registeredTombstone,
      holdingPath: journal.holdingPath,
    });
    paths = verifyWorktreeRemovalTopology(entry, repoContext(journal.primaryWorktree));
  } else if (paths.holding !== null && ["root-move-intent", "prepared"].includes(entry.journal.state)) {
    updateWorktreeRemovalJournal(entry, "root-held");
  }

  if (paths.holding !== null && paths.admin !== null) {
    if (!worktreeRemovalGitLockMatches(journal)) {
      fail("worktree operation lock is missing or changed before deregistration", EXIT.safety);
    }
    if (entry.journal.state !== "admin-move-intent") {
      updateWorktreeRemovalJournal(entry, "admin-move-intent");
    }
    runTestHook("before-worktree-admin-delete", {
      receiptPath: entry.path,
      registeredTombstone: journal.registeredTombstone,
      holdingPath: journal.holdingPath,
      adminRoot: journal.targetGitDir,
      adminHoldingPath: journal.adminHoldingPath,
    });
    requireExactDeletionManifest(
      journal.targetGitDir,
      journal.adminManifest.map(({ captureRelativePath: _capture, ...manifestEntry }) => manifestEntry),
      "worktree administration directory",
    );
    renameSync(journal.targetGitDir, journal.adminHoldingPath);
    fsyncDirectory(dirname(journal.targetGitDir), "worktree administration parent");
    fsyncDirectory(dirname(journal.adminHoldingPath), "worktree administration holding parent");
    updateWorktreeRemovalJournal(entry, "admin-held");
    runTestHook("after-worktree-admin-holding-rename", {
      receiptPath: entry.path,
      adminHoldingPath: journal.adminHoldingPath,
    });
    paths = verifyWorktreeRemovalTopology(entry, repoContext(journal.primaryWorktree));
  } else if (paths.adminHolding !== null && entry.journal.state === "admin-move-intent") {
    updateWorktreeRemovalJournal(entry, "admin-held");
  }

  if (paths.adminHolding !== null) {
    if (entry.journal.state !== "admin-delete-intent") {
      updateWorktreeRemovalJournal(entry, "admin-delete-intent");
    }
    runWorktreeRemovalDeletion(
      journal.adminHoldingPath,
      journal.adminManifest,
      journal,
      entry.path,
      "admin",
    );
    paths = verifyWorktreeRemovalTopology(entry, repoContext(journal.primaryWorktree));
  }
  if (paths.holding !== null) {
    if (entry.journal.state !== "root-delete-intent") {
      updateWorktreeRemovalJournal(entry, "root-delete-intent");
    }
    runTestHook("before-worktree-delete", { receiptPath: entry.path, holdingPath: journal.holdingPath });
    const active = processProof(journal.holdingPath);
    if (active.state !== "clear") {
      fail(`held worktree process state is ${active.state}: ${active.detail}`, EXIT.safety);
    }
    runWorktreeRemovalDeletion(
      journal.holdingPath,
      journal.rootManifest,
      journal,
      entry.path,
      "root",
    );
    paths = verifyWorktreeRemovalTopology(entry, repoContext(journal.primaryWorktree));
  }
  if (Object.values(paths).some((stat) => stat !== null)) {
    fail("worktree removal did not reach its terminal topology", EXIT.safety);
  }
  updateWorktreeRemovalJournal(entry, "complete");
  runTestHook("after-worktree-removal-complete-write", { receiptPath: entry.path });
  process.stdout.write(`  receipt: ${entry.path}\n`);
}

function commandWorktreeRemove(args) {
  const resumeIndex = args.indexOf("--resume");
  if (resumeIndex >= 0) {
    const resumePath = args[resumeIndex + 1];
    const remaining = args.filter((_, index) => index !== resumeIndex && index !== resumeIndex + 1);
    if (resumeIndex !== 0 || !resumePath || resumePath.startsWith("--")
      || remaining.some((arg) => arg !== "--dry-run" && arg !== "--force")
      || new Set(remaining).size !== remaining.length
      || (remaining.includes("--dry-run") && remaining.includes("--force"))) {
      fail("worktree-remove --resume accepts one absolute receipt path and either --dry-run or --force", EXIT.usage);
    }
    if (!remaining.includes("--dry-run") && !remaining.includes("--force")) {
      fail("worktree-remove --resume requires --force (or use --dry-run)", EXIT.safety);
    }
    const envelope = readWorktreeRemovalJournalEnvelope(resumePath);
    const targetPresent = lstatOptional(envelope.journal.target, "original worktree path") !== null;
    const targetStaged = lstatOptional(
      envelope.journal.registeredTombstone,
      "registered worktree tombstone",
    ) !== null || lstatOptional(envelope.journal.holdingPath, "worktree holding path") !== null;
    const adminGone = lstatOptional(
      envelope.journal.targetGitDir,
      "worktree administration directory",
    ) === null;
    if (targetPresent && (targetStaged || adminGone)) {
      if (!remaining.includes("--dry-run")) releaseStaleWorktreeRemovalLockForRefusal(envelope);
      fail("original worktree path was repopulated after staging; staged content was retained", EXIT.safety);
    }
    const context = repoContext(invocationCwd());
    const entry = readWorktreeRemovalJournal(resumePath, context);
    if (remaining.includes("--dry-run")) {
      process.stdout.write(`Would resume worktree removal ${entry.journal.operationId}\n`);
      process.stdout.write(`  phase: ${entry.journal.state}\n`);
      process.stdout.write(`  target: ${entry.journal.target}\n`);
      return;
    }
    requireMutationPlatform();
    const release = acquireWorktreeRemovalLock(entry, true);
    try {
      completeWorktreeRemoval(entry, repoContext(invocationCwd()));
    } finally {
      release();
    }
    return;
  }
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
  const fresh = repoContext(invocationCwd());
  if (!contextTopologyEqual(context, fresh)) {
    fail("repository worktree topology changed after planning; nothing was removed", EXIT.safety);
  }
  const freshTarget = resolveRequestedWorktree(fresh, target.path);
  const rootPlain = captureStableDeletionManifest(freshTarget.pathReal, "worktree root");
  requireNoHardlinkedFiles(rootPlain, freshTarget.pathReal, "worktree root");
  let adminPlain = captureStableDeletionManifest(freshTarget.gitDirReal, "worktree administration directory");
  requireNoHardlinkedFiles(adminPlain, freshTarget.gitDirReal, "worktree administration directory");
  requireNoAdministrationLocks(adminPlain, freshTarget.gitDirReal);
  const refreshed = validateRemoval(fresh, freshTarget, options);
  if (refreshed.blockers.length || !refreshed.status.equals(validation.status)
    || refreshed.refOid !== validation.refOid) {
    fail("worktree state changed after planning; nothing was removed", EXIT.safety);
  }
  let rescueRef = null;
  if (options.force && freshTarget.detached) {
    rescueRef = `refs/buwiz/worktree-rescue/${new Date().toISOString().replaceAll(/[-:.]/gu, "")}-${digest.slice(0, 16)}`;
    git(context.top, ["update-ref", "--create-reflog", rescueRef, freshTarget.HEAD, ""]);
    process.stdout.write(`  rescue ref: ${rescueRef}\n`);
  }
  const operationId = createHash("sha256")
    .update(`${context.commonDir}\0${freshTarget.gitDirReal}\0${digest}`)
    .digest("hex");
  const gitLockReason = `buwiz-worktree-remove:${operationId}`;
  git(context.top, ["worktree", "lock", "--reason", gitLockReason, "--", freshTarget.pathReal]);
  fsyncDirectory(freshTarget.gitDirReal, "worktree administration directory");
  let receiptDurable = false;
  try {
    adminPlain = captureStableDeletionManifest(freshTarget.gitDirReal, "locked worktree administration directory");
    requireNoHardlinkedFiles(adminPlain, freshTarget.gitDirReal, "locked worktree administration directory");
    const adminHoldingRoot = ensurePhysicalChild(
      context.commonDir,
      "worktree-admin-holds",
      "worktree administration holding directory",
    );
    const createdAt = new Date().toISOString();
    const journal = {
      version: WORKTREE_REMOVAL_JOURNAL_VERSION,
      operation: "worktree-remove",
      operationId,
      state: "prepared",
      commonDir: context.commonDir,
      primaryWorktree: context.primary.path,
      target: freshTarget.pathReal,
      targetGitDir: freshTarget.gitDirReal,
      head: freshTarget.HEAD,
      branch: freshTarget.branch || null,
      detached: Boolean(freshTarget.detached),
      integrationRef: options.into,
      integrationOid: validation.refOid,
      forced: options.force,
      rescueRef,
      snapshotDigest: digest,
      gitLockReason,
      registeredTombstone: join(dirname(freshTarget.pathReal), `.${basename(freshTarget.pathReal)}.removing-${operationId.slice(0, 24)}`),
      holdingPath: join(dirname(freshTarget.pathReal), `.${basename(freshTarget.pathReal)}.holding-${operationId.slice(0, 24)}`),
      adminHoldingPath: join(adminHoldingRoot, `${basename(freshTarget.gitDirReal)}-${operationId.slice(0, 24)}`),
      rootManifest: worktreeRemovalCaptureManifest(rootPlain, operationId, "root"),
      adminManifest: worktreeRemovalCaptureManifest(adminPlain, operationId, "admin"),
      siblingTopology: worktreeRemovalSiblingSnapshot(fresh, freshTarget.gitDirReal, freshTarget.pathReal),
      createdAt,
      updatedAt: createdAt,
      authorizationDigest: null,
    };
    journal.authorizationDigest = worktreeRemovalAuthorizationDigest(journal);
    if ([journal.registeredTombstone, journal.holdingPath, journal.adminHoldingPath]
      .some((path) => lstatOptional(path, "worktree removal staging path") !== null)) {
      fail("worktree removal staging path already exists", EXIT.safety);
    }
    const receiptDir = ensurePhysicalChild(metadataRoot(context.commonDir), "receipts", "maintenance receipt directory");
    const receiptPath = join(receiptDir, `${createdAt.replaceAll(":", "-")}-${operationId.slice(0, 24)}.json`);
    writeReceipt(receiptPath, journal);
    fsyncDirectory(receiptDir, "maintenance receipt directory");
    receiptDurable = true;
    const entry = readWorktreeRemovalJournal(receiptPath, fresh);
    const release = acquireWorktreeRemovalLock(entry, false);
    try {
      runTestHook("after-worktree-removal-journal-create", { receiptPath });
      completeWorktreeRemoval(entry, repoContext(invocationCwd()));
    } finally {
      release();
    }
  } catch (error) {
    if (!receiptDurable && lstatOptional(freshTarget.pathReal, "worktree root") !== null
      && worktreeRemovalGitLockMatches({ targetGitDir: freshTarget.gitDirReal, gitLockReason }, freshTarget.pathReal)) {
      git(context.top, ["worktree", "unlock", "--", freshTarget.pathReal], { allowFailure: true });
    }
    throw error;
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
