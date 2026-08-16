import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, linkSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, readlinkSync, readdirSync, realpathSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptPath = join(dirname(fileURLToPath(import.meta.url)), "workspace-maintenance.mjs");

function run(args, cwd, env = {}) {
  return spawnSync(process.execPath, [scriptPath, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
}

function skipWindowsMutation(context, reason = "Windows mutation is intentionally unsupported") {
  if (process.platform !== "win32") return false;
  context.skip(reason);
  return true;
}

async function waitForPath(path) {
  const deadline = Date.now() + 10_000;
  while (!existsSync(path)) {
    if (Date.now() >= deadline) throw new Error(`timed out waiting for ${path}`);
    await new Promise((resolveReady) => setTimeout(resolveReady, 20));
  }
}

async function readHookMarker(path) {
  await waitForPath(path);
  const deadline = Date.now() + 1_000;
  while (true) {
    try {
      const markerStat = lstatSync(path);
      assert.equal(markerStat.isFile() && !markerStat.isSymbolicLink(), true);
      return JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
      if (Date.now() >= deadline) throw error;
      await new Promise((resolveReady) => setTimeout(resolveReady, 10));
    }
  }
}

function releaseTestHook(release) {
  if (existsSync(release)) return;
  const pending = `${release}.pending`;
  writeFileSync(pending, "continue\n", { mode: 0o600 });
  renameSync(pending, release);
}

async function runPausedAtHook(args, cwd, hook, mutate, extraEnv = {}) {
  const hookRoot = mkdtempSync(join(tmpdir(), "workspace-maintenance-hook-"));
  const marker = join(hookRoot, "marker.json");
  const release = join(hookRoot, "release");
  const child = spawn(process.execPath, [scriptPath, ...args], {
    cwd,
    env: {
      ...process.env,
      ...extraEnv,
      NODE_ENV: "test",
      NODE_TEST_CONTEXT: "child-v8",
      WORKSPACE_MAINTENANCE_TEST_HOOK: hook,
      WORKSPACE_MAINTENANCE_TEST_MARKER: marker,
      WORKSPACE_MAINTENANCE_TEST_RELEASE: release,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const completed = new Promise((resolveCompleted, rejectCompleted) => {
    child.once("error", rejectCompleted);
    child.once("close", (status, signal) => resolveCompleted({ status, signal }));
  });
  try {
    await mutate(await readHookMarker(marker));
    releaseTestHook(release);
    const result = await completed;
    return { ...result, stdout, stderr };
  } finally {
    releaseTestHook(release);
    if (child.exitCode === null) child.kill("SIGTERM");
    await completed.catch(() => {});
    rmSync(hookRoot, { recursive: true, force: true });
  }
}

async function runKilledAtHook(args, cwd, hook, beforeKill = async () => {}, extraEnv = {}) {
  const hookRoot = mkdtempSync(join(tmpdir(), "workspace-maintenance-kill-hook-"));
  const marker = join(hookRoot, "marker.json");
  const release = join(hookRoot, "release");
  const child = spawn(process.execPath, [scriptPath, ...args], {
    cwd,
    env: {
      ...process.env,
      ...extraEnv,
      NODE_ENV: "test",
      NODE_TEST_CONTEXT: "child-v8",
      WORKSPACE_MAINTENANCE_TEST_HOOK: hook,
      WORKSPACE_MAINTENANCE_TEST_MARKER: marker,
      WORKSPACE_MAINTENANCE_TEST_RELEASE: release,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const completed = new Promise((resolveCompleted, rejectCompleted) => {
    child.once("error", rejectCompleted);
    child.once("close", (status, signal) => resolveCompleted({ status, signal }));
  });
  try {
    const markerReached = readHookMarker(marker).then((payload) => ({ kind: "marker", payload }));
    const earlyExit = completed.then((result) => ({ kind: "exit", result }));
    const first = await Promise.race([markerReached, earlyExit]);
    if (first.kind === "exit") {
      assert.fail(
        `maintenance child exited before reaching ${hook}: `
        + `status=${first.result.status} signal=${first.result.signal}; stderr=${stderr}`,
      );
    }
    const { payload } = first;
    assert.equal(payload.name, hook);
    assert.equal(existsSync(release), false);
    await beforeKill(payload, { childPid: child.pid, marker, release });
    assert.equal(child.exitCode, null, `maintenance child exited before SIGKILL at ${hook}`);
    assert.equal(child.signalCode, null, `maintenance child was signaled before SIGKILL at ${hook}`);
    assert.equal(child.kill("SIGKILL"), true, `could not SIGKILL maintenance child at ${hook}`);
    const result = await completed;
    assert.equal(result.status, null);
    assert.equal(result.signal, "SIGKILL");
    assert.equal(existsSync(release), false);
    return { ...result, childPid: child.pid, payload, stdout, stderr };
  } finally {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
    await completed.catch(() => {});
    rmSync(hookRoot, { recursive: true, force: true });
  }
}

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function makeRepo(prefix = "workspace-maintenance-test-") {
  const fixture = mkdtempSync(join(tmpdir(), prefix));
  const root = join(fixture, "primary");
  mkdirSync(root);
  git(root, "init", "-b", "main");
  git(root, "config", "user.name", "Workspace Maintenance Test");
  git(root, "config", "user.email", "workspace-maintenance@example.invalid");
  git(root, "config", "commit.gpgsign", "false");
  git(root, "config", "core.hooksPath", "/dev/null");
  writeFileSync(join(root, ".gitignore"), [
    ".native/", ".zig-cache/", "zig-cache/", "zig-pkg/", "zig-out/",
    "node_modules/", "coverage/", "test-results/", "scripts/news-sync/work/",
    "*.log", ".env", ".env.*", "*.key", "*.p12", "reference/",
  ].join("\n") + "\n");
  mkdirSync(join(root, "src"));
  writeFileSync(join(root, "src", "app.native"), "tracked generated file\n");
  writeFileSync(join(root, "README.md"), "fixture\n");
  git(root, "add", ".gitignore", "README.md", "src/app.native");
  git(root, "commit", "-m", "fixture root");
  git(root, "remote", "add", "origin", ".");
  git(root, "update-ref", "refs/remotes/origin/main", "HEAD");
  const worktree = join(fixture, "candidate");
  git(root, "worktree", "add", "-b", "candidate", worktree, "main");
  return { fixture, root, worktree };
}

function linkedWorktreeMaintenancePaths(root, worktree) {
  const commonRaw = git(root, "rev-parse", "--git-common-dir");
  const commonDir = realpathSync(resolve(root, commonRaw));
  const gitDir = realpathSync(git(worktree, "rev-parse", "--absolute-git-dir"));
  const key = createHash("sha256").update(`${commonDir}\0${gitDir}`).digest("hex");
  const stateRoot = join(commonDir, "buwiz-workspace-maintenance");
  return {
    commonDir,
    gitDir,
    state: join(stateRoot, "cleanup-state", `${key}.json`),
  };
}

function cleanupJournalFromResult(result) {
  const path = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1]
    ?? result.stdout.match(/journal: (.+journal\.json)/u)?.[1];
  assert.ok(path && isAbsolute(path), `cleanup command did not expose an absolute journal: ${result.stderr}`);
  return path;
}

function cleanupLockPath(root) {
  const commonDir = realpathSync(resolve(root, git(root, "rev-parse", "--git-common-dir")));
  return join(commonDir, "buwiz-workspace-maintenance", "lock.json");
}

function physicalTreeSnapshot(root) {
  const entries = [];
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    const stat = lstatSync(current);
    const relativePath = relative(root, current);
    const type = stat.isDirectory() ? "directory" : stat.isFile() ? "file" : stat.isSymbolicLink() ? "symlink" : "other";
    entries.push({
      relativePath,
      type,
      dev: stat.dev,
      ino: stat.ino,
      mode: stat.mode,
      mtimeMs: stat.mtimeMs,
      size: stat.size,
      contentDigest: type === "file" ? createHash("sha256").update(readFileSync(current)).digest("hex") : null,
      linkTarget: type === "symlink" ? readlinkSync(current) : null,
    });
    if (type === "directory") {
      for (const name of readdirSync(current).sort().reverse()) stack.push(join(current, name));
    }
  }
  return entries;
}

function linkedWorktreeTopology(worktree) {
  const commonRaw = git(worktree, "rev-parse", "--git-common-dir");
  return {
    root: realpathSync(git(worktree, "rev-parse", "--show-toplevel")),
    gitDir: realpathSync(git(worktree, "rev-parse", "--absolute-git-dir")),
    commonDir: realpathSync(resolve(worktree, commonRaw)),
    head: git(worktree, "rev-parse", "HEAD"),
    branch: git(worktree, "symbolic-ref", "HEAD"),
    status: git(worktree, "status", "--porcelain=v2", "--untracked-files=all", "--ignore-submodules=none"),
  };
}

function seedArtifacts(worktree) {
  const paths = [
    ".native/state.bin", ".zig-cache/cache.bin", "zig-cache/cache.bin",
    "zig-pkg/package.bin", "zig-out/bin/app", "node_modules/pkg/index.js",
    "coverage/report.json", "test-results/results.xml",
    "scripts/news-sync/work/download.pdf",
  ];
  for (const relative of paths) {
    const absolute = join(worktree, relative);
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, relative);
  }
  return paths;
}

function seedProtected(worktree) {
  const paths = [
    ".env", ".env.local", "signing.key", "signing.p12", "debug.log",
    "reference/capture.bin", ".zig-cache.backup/cache.bin",
  ];
  for (const relative of paths) {
    const absolute = join(worktree, relative);
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, `protected:${relative}`);
  }
  return new Map(paths.map((relative) => [relative, readFileSync(join(worktree, relative), "utf8")]));
}

function assertProtected(worktree, expected) {
  for (const [relative, contents] of expected) {
    assert.equal(readFileSync(join(worktree, relative), "utf8"), contents, relative);
  }
  assert.equal(readFileSync(join(worktree, "src/app.native"), "utf8"), "tracked generated file\n");
}

function rewriteReceipt(receiptPath, mutate) {
  const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
  mutate(receipt);
  receipt.contentsDigest = createHash("sha256")
    .update(JSON.stringify({
      sourceWorktrees: receipt.sourceWorktrees,
      sourceWorktreeGitDirs: receipt.sourceWorktreeGitDirs,
      moves: receipt.moves,
      nativeSymlinks: receipt.nativeSymlinks,
      dependencySymlinks: receipt.dependencySymlinks,
    }))
    .digest("hex");
  writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function cloneManifestLeaf(manifest) {
  const leaf = manifest.find((entry) => entry.type === "file" || entry.type === "symlink");
  assert.ok(leaf, "expected a deletion-manifest leaf");
  return { ...leaf };
}

function purgeCaptureRelativePathFor(operationId, relativePath) {
  const digest = createHash("sha256").update(relativePath).digest("hex");
  const name = `.buwiz-purge-${operationId.slice(0, 16)}-${digest}`;
  const slash = relativePath.lastIndexOf("/");
  return slash === -1 ? name : `${relativePath.slice(0, slash)}/${name}`;
}

function recomputePurgeJournalDigests(journal) {
  journal.manifestDigest = createHash("sha256").update(JSON.stringify(journal.manifest)).digest("hex");
  journal.authorizationDigest = createHash("sha256").update(JSON.stringify({
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

function recomputeCleanJournalAuthorization(journal) {
  for (const move of journal.moves ?? []) {
    if (Array.isArray(move.manifest)) {
      move.manifestDigest = createHash("sha256").update(JSON.stringify(move.manifest)).digest("hex");
    }
  }
  journal.authorizationDigest = createHash("sha256").update(JSON.stringify({
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

function recomputeWorktreeRemovalAuthorization(journal) {
  journal.authorizationDigest = createHash("sha256").update(JSON.stringify({
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

function forgeTraversalManifestEntry(manifest, relativePath, captureRelativePath = undefined) {
  const forged = cloneManifestLeaf(manifest);
  forged.relativePath = relativePath;
  if (captureRelativePath !== undefined) forged.captureRelativePath = captureRelativePath;
  manifest.push(forged);
  return forged;
}

test("clean with no target lists choices, exits 2, and changes nothing", () => {
  const { root, worktree } = makeRepo();
  try {
    seedArtifacts(worktree);
    const before = git(root, "worktree", "list", "--porcelain");
    const result = run(["clean"], worktree);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /choose a cleanup target; nothing was deleted/u);
    assert.ok(
      result.stderr.includes(worktree)
        || result.stderr.includes(worktree.replaceAll("\\", "/"))
        || result.stderr.includes(worktree.replaceAll("/", "\\")),
      result.stderr,
    );
    assert.match(result.stderr, /zig-cache: 2 roots/u);
    for (const target of ["zig-cache", "zig-packages", "build", "native", "deps", "reports", "news-scratch", "standard", "all"]) {
      assert.match(result.stderr, new RegExp(`\\b${target}\\b`, "u"));
    }
    assert.equal(git(root, "worktree", "list", "--porcelain"), before);
    assert.ok(existsSync(join(worktree, ".zig-cache/cache.bin")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean dry-run reports exact artifacts without mutating them", () => {
  const { root, worktree } = makeRepo();
  try {
    seedArtifacts(worktree);
    const result = run(["clean", "zig-cache", "--dry-run"], worktree);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /\.zig-cache/u);
    assert.match(result.stdout, /zig-cache/u);
    assert.doesNotMatch(result.stdout, /zig-out/u);
    assert.ok(existsSync(join(worktree, ".zig-cache/cache.bin")));
    assert.ok(existsSync(join(worktree, "zig-cache/cache.bin")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("test hooks stay inactive without the complete test-only gate", () => {
  const { root, worktree } = makeRepo();
  const hookRoot = mkdtempSync(join(tmpdir(), "workspace-maintenance-inactive-hook-"));
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const marker = join(hookRoot, "marker.json");
    const result = run(["clean", "build", "--dry-run"], worktree, {
      NODE_ENV: "test",
      WORKSPACE_MAINTENANCE_TEST_HOOK: "before-artifact-rename",
      WORKSPACE_MAINTENANCE_TEST_MARKER: marker,
      WORKSPACE_MAINTENANCE_TEST_RELEASE: join(hookRoot, "release"),
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(marker), false);
  } finally {
    rmSync(hookRoot, { recursive: true, force: true });
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("printed purge command safely quotes receipt paths containing apostrophes", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-'test-");
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt?.includes("'"));
    assert.match(cleaned.stdout, /'"'"'/u);
    const command = cleaned.stdout.match(/reclaim disk with: (just clean purge .+ --force)/u)?.[1];
    assert.ok(command);
    const parsed = spawnSync("/bin/sh", ["-c", `set -- ${command}; printf '%s' "$4"`], { encoding: "utf8" });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.equal(parsed.stdout, receipt);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("post-rename failure prints an exact resumable cleanup journal", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "rollback sentinel\n");
    const result = run(["clean", "build"], worktree, {
      NODE_ENV: "test",
      NODE_TEST_CONTEXT: "child-v8",
      WORKSPACE_MAINTENANCE_TEST_FAIL_AT: "after-artifact-rename",
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /resume only with: just clean resume/u);
    assert.equal(existsSync(join(worktree, "zig-out")), false);
    const journal = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1];
    assert.ok(journal && existsSync(journal));
    const resumed = run(["clean", "resume", journal, "--force"], worktree);
    assert.equal(resumed.status, 0, resumed.stderr);
    const receiptPath = resumed.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath && existsSync(receiptPath));
    const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
    assert.equal(readFileSync(join(receipt.moves[0].destination, "bin", "app"), "utf8"), "rollback sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("post-rename destination replacement is preserved and blocks resume", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    let replacement;
    const result = await runPausedAtHook(
      ["clean", "build"],
      worktree,
      "after-artifact-rename",
      ({ destination }) => {
        renameSync(destination, `${destination}.original`);
        mkdirSync(destination);
        replacement = join(destination, "external-sentinel.txt");
        writeFileSync(replacement, "replacement survives\n");
      },
    );
    assert.equal(result.status, 3);
    const journal = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1];
    assert.ok(journal && existsSync(journal));
    const receipt = JSON.parse(readFileSync(journal, "utf8"));
    const resumed = run(["clean", "resume", journal, "--force"], worktree);
    assert.equal(resumed.status, 3);
    assert.match(resumed.stderr, /destination.*changed|destination was replaced|unknown content/u);
    assert.equal(readFileSync(replacement, "utf8"), "replacement survives\n");
    assert.equal(readFileSync(`${receipt.moves[0].destination}.original/bin/app`, "utf8"), "original\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("pre-first-move failure leaves an exact resumable cleanup journal", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    let transactionRoot;
    const result = await runPausedAtHook(
      ["clean", "build"],
      worktree,
      "before-artifact-rename",
      (payload) => { transactionRoot = payload.transactionRoot; },
      { WORKSPACE_MAINTENANCE_TEST_ACTION: "fail" },
    );
    assert.equal(result.status, 3);
    assert.equal(existsSync(transactionRoot), true);
    assert.equal(readFileSync(join(worktree, "zig-out", "bin", "app"), "utf8"), "original\n");
    const journal = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1];
    assert.ok(journal && existsSync(journal));
    const resumed = run(["clean", "resume", journal, "--force"], worktree);
    assert.equal(resumed.status, 0, resumed.stderr);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("zero-move failure retains unknown scaffolding content and reports its transaction", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    let sentinel;
    let transactionRoot;
    const result = await runPausedAtHook(
      ["clean", "build"],
      worktree,
      "before-artifact-rename",
      (payload) => {
        transactionRoot = payload.transactionRoot;
        sentinel = join(payload.transactionRoot, "unknown-sentinel.txt");
        writeFileSync(sentinel, "must survive\n");
      },
      { WORKSPACE_MAINTENANCE_TEST_ACTION: "fail" },
    );
    assert.equal(result.status, 3);
    const journal = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1];
    assert.ok(journal && existsSync(journal));
    const resumed = run(["clean", "resume", journal, "--force"], worktree);
    assert.equal(resumed.status, 3);
    assert.match(resumed.stderr, /unknown content/u);
    assert.equal(readFileSync(sentinel, "utf8"), "must survive\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("post-rename failure does not follow a changed source ancestor", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const artifact = join(worktree, "scripts", "news-sync", "work", "download.pdf");
    const external = join(root, "external-news");
    mkdirSync(dirname(artifact), { recursive: true });
    mkdirSync(external);
    writeFileSync(artifact, "quarantined sentinel\n");
    const result = await runPausedAtHook(
      ["clean", "news-scratch"],
      worktree,
      "after-artifact-rename",
      ({ source }) => {
        const newsSync = dirname(source);
        renameSync(newsSync, `${newsSync}.original`);
        symlinkSync(external, newsSync);
      },
      { WORKSPACE_MAINTENANCE_TEST_ACTION: "fail" },
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /resume only with: just clean resume/u);
    assert.equal(existsSync(join(external, "work", "download.pdf")), false);
    const journal = result.stderr.match(/just clean resume '([^']+journal\.json)' --force/u)?.[1];
    assert.ok(journal && existsSync(journal));
    const resumed = run(["clean", "resume", journal, "--force"], worktree);
    assert.equal(resumed.status, 0, resumed.stderr);
    const receiptPath = resumed.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath && existsSync(receiptPath));
    const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
    assert.equal(readFileSync(join(receipt.moves[0].destination, "download.pdf"), "utf8"), "quarantined sentinel\n");
    assert.equal(existsSync(join(external, "download.pdf")), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("direct clean succeeds when its caller does not hold the worktree", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const result = spawnSync(process.execPath, [scriptPath, "clean", "build"], {
      cwd: worktree,
      encoding: "utf8",
      env: { ...process.env, WORKSPACE_MAINTENANCE_CWD: "" },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(join(worktree, "zig-out")), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("the public Just clean recipe trusts only its verified launcher ancestry", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const justfile = join(worktree, "Justfile");
    writeFileSync(justfile, [
      "set positional-arguments",
      "",
      "clean *args:",
      `    @WORKSPACE_MAINTENANCE_CWD=\"$(git rev-parse --show-toplevel)\" WORKSPACE_MAINTENANCE_JUST_PID=\"$PPID\" WORKSPACE_MAINTENANCE_JUST_EXE=\"$(command -v just)\" node ${JSON.stringify(scriptPath)} clean \"$@\"`,
      "",
    ].join("\n"));
    const result = spawnSync("/bin/sh", ["-c", 'just -f "$1" clean build; workspace_status=$?; :; exit "$workspace_status"', "workspace-maintenance-test", justfile], {
      cwd: worktree,
      encoding: "utf8",
      env: process.env,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(join(worktree, "zig-out")), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("the public Just clean recipe still blocks an unrelated active shell", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let activeShell;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const justfile = join(worktree, "Justfile");
    writeFileSync(justfile, [
      "set positional-arguments",
      "",
      "clean *args:",
      `    @WORKSPACE_MAINTENANCE_CWD=\"$(git rev-parse --show-toplevel)\" WORKSPACE_MAINTENANCE_JUST_PID=\"$PPID\" WORKSPACE_MAINTENANCE_JUST_EXE=\"$(command -v just)\" node ${JSON.stringify(scriptPath)} clean \"$@\"`,
      "",
    ].join("\n"));
    activeShell = spawn("/bin/sh", ["-c", "read workspace_maintenance_test_input"], {
      cwd: worktree,
      stdio: ["pipe", "ignore", "ignore"],
    });
    await new Promise((resolveReady) => setTimeout(resolveReady, 150));

    const result = spawnSync("/bin/sh", ["-c", 'just -f "$1" clean build; workspace_status=$?; :; exit "$workspace_status"', "workspace-maintenance-test", justfile], {
      cwd: worktree,
      encoding: "utf8",
      env: process.env,
    });
    assert.equal(result.status, 3);
    assert.match(result.stderr, /process state.*active/u);
    assert.equal(existsSync(join(worktree, "zig-out")), true);
  } finally {
    activeShell?.stdin?.end();
    activeShell?.kill("SIGTERM");
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("launcher ancestry cannot exempt an open file inside the selected artifact", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const justfile = join(worktree, "Justfile");
    writeFileSync(justfile, [
      "set positional-arguments",
      "",
      "clean *args:",
      `    @WORKSPACE_MAINTENANCE_CWD=\"$(git rev-parse --show-toplevel)\" WORKSPACE_MAINTENANCE_JUST_PID=\"$PPID\" WORKSPACE_MAINTENANCE_JUST_EXE=\"$(command -v just)\" node ${JSON.stringify(scriptPath)} clean \"$@\"`,
      "",
    ].join("\n"));
    const result = spawnSync("/bin/sh", [
      "-c",
      'exec 9<"$2"; just -f "$1" clean build; workspace_status=$?; exec 9<&-; exit "$workspace_status"',
      "workspace-maintenance-test",
      justfile,
      join(worktree, "zig-out", "bin", "app"),
    ], {
      cwd: worktree,
      encoding: "utf8",
      env: process.env,
    });
    assert.equal(result.status, 3);
    assert.match(result.stderr, /process state.*active/u);
    assert.match(result.stderr, /zig-out\/bin\/app/u);
    assert.equal(existsSync(join(worktree, "zig-out")), true);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("launcher trust rejects a forged Just process id", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const result = run(["clean", "build"], worktree, {
      WORKSPACE_MAINTENANCE_JUST_PID: String(process.ppid),
      WORKSPACE_MAINTENANCE_JUST_EXE: process.execPath,
    });
    assert.equal(result.status, 3);
    assert.match(result.stderr, /is not Just|not the direct parent/u);
    assert.equal(existsSync(join(worktree, "zig-out")), true);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean all requires force and never widens the literal artifact catalog", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    seedArtifacts(worktree);
    const protectedFiles = seedProtected(worktree);
    const refused = run(["clean", "all"], worktree);
    assert.equal(refused.status, 3);
    assert.match(refused.stderr, /requires --force/u);
    assert.ok(existsSync(join(worktree, "zig-out/bin/app")));

    const applied = run(["clean", "all", "--force"], worktree);
    assert.equal(applied.status, 0, applied.stderr);
    assert.match(applied.stdout, /nothing has been permanently deleted/u);
    const receiptMatch = applied.stdout.match(/receipt: (.+receipt\.json)/u);
    assert.ok(receiptMatch);
    assert.ok(existsSync(receiptMatch[1]));
    for (const relative of [".native", ".zig-cache", "zig-cache", "zig-pkg", "zig-out", "node_modules", "coverage", "test-results", "scripts/news-sync/work"]) {
      assert.equal(existsSync(join(worktree, relative)), false, relative);
    }
    assertProtected(worktree, protectedFiles);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean refuses an artifact root symlink without touching its target", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const sentinel = join(root, "sentinel");
    mkdirSync(sentinel);
    writeFileSync(join(sentinel, "keep.txt"), "keep\n");
    symlinkSync(sentinel, join(worktree, "zig-out"));
    const result = run(["clean", "build"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /symbolic link/u);
    assert.equal(readFileSync(join(sentinel, "keep.txt"), "utf8"), "keep\n");
    assert.ok(lstatSync(join(worktree, "zig-out")).isSymbolicLink());
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean refuses a dangling artifact root symlink", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const missingTarget = join(root, "missing-sentinel-target");
    symlinkSync(missingTarget, join(worktree, "zig-out"));
    const result = run(["clean", "build"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /symbolic link artifact root/u);
    assert.ok(lstatSync(join(worktree, "zig-out")).isSymbolicLink());
    assert.equal(existsSync(missingTarget), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean refuses a nested symlink without touching its external target", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const sentinel = join(root, "external-sentinel");
    mkdirSync(sentinel);
    writeFileSync(join(sentinel, "keep.txt"), "keep\n");
    mkdirSync(join(worktree, "zig-out", "nested"), { recursive: true });
    symlinkSync(sentinel, join(worktree, "zig-out", "nested", "outside"));
    const result = run(["clean", "build"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /nested symbolic link/u);
    assert.equal(readFileSync(join(sentinel, "keep.txt"), "utf8"), "keep\n");
    assert.ok(existsSync(join(worktree, "zig-out", "nested", "outside")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean deps treats normal nested package links as leaves and purge never follows them", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const external = join(root, "external-tool");
    mkdirSync(join(worktree, "node_modules", "pkg", "bin"), { recursive: true });
    mkdirSync(join(worktree, "node_modules", ".bin"), { recursive: true });
    mkdirSync(external);
    writeFileSync(join(worktree, "node_modules", "pkg", "bin", "tool.js"), "internal tool\n");
    writeFileSync(join(external, "keep.txt"), "external target survives\n");
    symlinkSync("../pkg/bin/tool.js", join(worktree, "node_modules", ".bin", "internal-tool"));
    symlinkSync(external, join(worktree, "node_modules", ".bin", "external-tool"));

    const preview = run(["clean", "deps", "--dry-run"], worktree);
    assert.equal(preview.status, 0, preview.stderr);
    const cleaned = run(["clean", "deps"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const transactionRoot = JSON.parse(readFileSync(receiptPath, "utf8")).transactionRoot;
    assert.equal(existsSync(join(worktree, "node_modules")), false);

    const purged = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(purged.status, 0, purged.stderr);
    assert.equal(existsSync(transactionRoot), false);
    assert.equal(existsSync(receiptPath), true);
    assert.equal(readFileSync(join(external, "keep.txt"), "utf8"), "external target survives\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a dependency link changed after quarantine", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "node_modules", "pkg"), { recursive: true });
    writeFileSync(join(worktree, "node_modules", "pkg", "target.js"), "target\n");
    symlinkSync("target.js", join(worktree, "node_modules", "pkg", "link.js"));
    const cleaned = run(["clean", "deps"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const destination = JSON.parse(readFileSync(receiptPath, "utf8")).moves[0].destination;
    const link = join(destination, "pkg", "link.js");
    unlinkSync(link);
    const external = join(root, "replacement-target");
    mkdirSync(external);
    writeFileSync(join(external, "keep.txt"), "replacement target survives\n");
    symlinkSync(external, link);

    const purged = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /dependency link.*changed identity/u);
    assert.equal(existsSync(dirname(receiptPath)), true);
    assert.ok(lstatSync(link).isSymbolicLink());
    assert.equal(readFileSync(join(external, "keep.txt"), "utf8"), "replacement target survives\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean native quarantines and purges generated identity links without following them", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    const assets = join(worktree, "assets");
    mkdirSync(nativeIdentity, { recursive: true });
    mkdirSync(assets);
    writeFileSync(join(nativeIdentity, "identity.json"), "fixture identity\n");
    writeFileSync(join(worktree, "src", "source-sentinel.native"), "source sentinel\n");
    writeFileSync(join(assets, "asset-sentinel.txt"), "asset sentinel\n");
    symlinkSync(join(worktree, "src"), join(nativeIdentity, "src"));
    symlinkSync(assets, join(nativeIdentity, "assets"));

    const cleaned = run(["clean", "native"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    assert.equal(existsSync(join(worktree, ".native")), false);
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(assets, "asset-sentinel.txt"), "utf8"), "asset sentinel\n");

    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transactionRoot = JSON.parse(readFileSync(receipt, "utf8")).transactionRoot;
    const preview = run(["clean", "purge", receipt, "--dry-run"], worktree);
    assert.equal(preview.status, 0, preview.stderr);
    assert.ok(existsSync(transactionRoot));
    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 0, purged.stderr);
    assert.equal(existsSync(transactionRoot), false);
    assert.equal(existsSync(receipt), true);
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(assets, "asset-sentinel.txt"), "utf8"), "asset sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean native dry-run accepts generated identity links without changing them", () => {
  const { root, worktree } = makeRepo();
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    const source = join(worktree, "src");
    const assets = join(worktree, "assets");
    mkdirSync(nativeIdentity, { recursive: true });
    mkdirSync(assets);
    writeFileSync(join(nativeIdentity, "identity.json"), "fixture identity\n");
    writeFileSync(join(source, "source-sentinel.native"), "source sentinel\n");
    writeFileSync(join(assets, "asset-sentinel.txt"), "asset sentinel\n");
    symlinkSync(source, join(nativeIdentity, "src"));
    symlinkSync(assets, join(nativeIdentity, "assets"));

    const preview = run(["clean", "native", "--dry-run"], worktree);
    assert.equal(preview.status, 0, preview.stderr);
    assert.match(preview.stdout, /Would clean/u);
    assert.ok(lstatSync(join(nativeIdentity, "src")).isSymbolicLink());
    assert.ok(lstatSync(join(nativeIdentity, "assets")).isSymbolicLink());
    assert.equal(realpathSync(join(nativeIdentity, "src")), realpathSync(source));
    assert.equal(realpathSync(join(nativeIdentity, "assets")), realpathSync(assets));
    assert.equal(readFileSync(join(source, "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(assets, "asset-sentinel.txt"), "utf8"), "asset sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a replaced quarantined Native link and preserves both targets", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    const assets = join(worktree, "assets");
    const attacker = join(root, "attacker-target");
    mkdirSync(nativeIdentity, { recursive: true });
    mkdirSync(assets);
    mkdirSync(attacker);
    writeFileSync(join(worktree, "src", "source-sentinel.native"), "source sentinel\n");
    writeFileSync(join(attacker, "attacker-sentinel.txt"), "attacker sentinel\n");
    symlinkSync(join(worktree, "src"), join(nativeIdentity, "src"));
    symlinkSync(assets, join(nativeIdentity, "assets"));

    const cleaned = run(["clean", "native"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = JSON.parse(readFileSync(receipt, "utf8")).transactionRoot;
    const quarantinedSrc = JSON.parse(readFileSync(receipt, "utf8")).moves[0].destination;
    const srcLink = join(quarantinedSrc, "identities", "fixture-identity", "src");
    assert.equal(realpathSync(srcLink), realpathSync(join(worktree, "src")));
    unlinkSync(srcLink);
    symlinkSync(attacker, srcLink);
    assert.equal(readlinkSync(srcLink), attacker);

    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /not recorded by the receipt or changed identity/u);
    assert.ok(existsSync(transaction));
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(attacker, "attacker-sentinel.txt"), "utf8"), "attacker sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("moving a worktree leaves quarantined Native links purgeable without following them", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  const movedParent = join(dirname(worktree), "moved-native-parent");
  const movedWorktree = join(movedParent, "candidate");
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    const assets = join(worktree, "assets");
    mkdirSync(nativeIdentity, { recursive: true });
    mkdirSync(assets);
    writeFileSync(join(worktree, "src", "source-sentinel.native"), "source sentinel\n");
    writeFileSync(join(assets, "asset-sentinel.txt"), "asset sentinel\n");
    symlinkSync(join(worktree, "src"), join(nativeIdentity, "src"));
    symlinkSync(assets, join(nativeIdentity, "assets"));
    const cleaned = run(["clean", "native"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);

    mkdirSync(movedParent);
    git(root, "worktree", "move", worktree, movedWorktree);
    const purged = run(["clean", "purge", receipt, "--force"], root);
    assert.equal(purged.status, 0, purged.stderr);
    assert.equal(readFileSync(join(movedWorktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(movedWorktree, "assets", "asset-sentinel.txt"), "utf8"), "asset sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a safe-looking Native link injected after quarantine", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    mkdirSync(nativeIdentity, { recursive: true });
    writeFileSync(join(nativeIdentity, "identity.json"), "fixture identity\n");
    writeFileSync(join(worktree, "src", "source-sentinel.native"), "source sentinel\n");

    const cleaned = run(["clean", "native"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = JSON.parse(readFileSync(receipt, "utf8")).transactionRoot;
    const nativeDestination = JSON.parse(readFileSync(receipt, "utf8")).moves[0].destination;
    const injectedIdentity = join(nativeDestination, "identities", "injected-identity");
    mkdirSync(injectedIdentity);
    symlinkSync(join(worktree, "src"), join(injectedIdentity, "src"));

    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /not recorded by the receipt|nested symbolic link/u);
    assert.ok(existsSync(transaction));
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean native refuses generated identity links to any other target", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const nativeIdentity = join(worktree, ".native", "identities", "fixture-identity");
    const sentinel = join(root, "external-source");
    mkdirSync(nativeIdentity, { recursive: true });
    mkdirSync(sentinel);
    writeFileSync(join(sentinel, "keep.txt"), "keep\n");
    symlinkSync(sentinel, join(nativeIdentity, "src"));

    const result = run(["clean", "native"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /generated Native identity link|nested symbolic link/u);
    assert.equal(readFileSync(join(sentinel, "keep.txt"), "utf8"), "keep\n");
    assert.ok(lstatSync(join(nativeIdentity, "src")).isSymbolicLink());
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean native refuses a generated identity link at any other depth", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const nested = join(worktree, ".native", "identities", "fixture-identity", "nested");
    mkdirSync(nested, { recursive: true });
    writeFileSync(join(worktree, "src", "keep.native"), "keep\n");
    symlinkSync(join(worktree, "src"), join(nested, "src"));

    const result = run(["clean", "native"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /nested symbolic link/u);
    assert.equal(readFileSync(join(worktree, "src", "keep.native"), "utf8"), "keep\n");
    assert.ok(lstatSync(join(nested, "src")).isSymbolicLink());
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("clean refuses a symlinked artifact ancestor without touching its target", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const externalNews = join(root, "external-news-sync");
    mkdirSync(join(worktree, "scripts"));
    mkdirSync(join(externalNews, "work"), { recursive: true });
    writeFileSync(join(externalNews, "work", "keep.txt"), "keep\n");
    symlinkSync(externalNews, join(worktree, "scripts", "news-sync"));

    const result = run(["clean", "news-scratch"], worktree);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /symbolic link artifact ancestor/u);
    assert.equal(readFileSync(join(externalNews, "work", "keep.txt"), "utf8"), "keep\n");
    assert.ok(lstatSync(join(worktree, "scripts", "news-sync")).isSymbolicLink());
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge requires an exact receipt and force, then reclaims only its quarantine", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    mkdirSync(join(worktree, "zig-out", "share", "nested"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "share", "nested", "data.bin"), "data\n");
    writeFileSync(join(worktree, "zig-out", "root.txt"), "root\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = JSON.parse(readFileSync(receipt, "utf8")).transactionRoot;

    const noForce = run(["clean", "purge", receipt], worktree);
    assert.equal(noForce.status, 3);
    assert.ok(existsSync(transaction));
    const preview = run(["clean", "purge", receipt, "--dry-run"], worktree);
    assert.equal(preview.status, 0, preview.stderr);
    assert.ok(existsSync(transaction));
    const arbitrary = run(["clean", "purge", join(root, "README.md"), "--force"], worktree);
    assert.equal(arbitrary.status, 3);
    assert.ok(existsSync(transaction));

    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 0, purged.stderr);
    assert.equal(existsSync(transaction), false);
    assert.equal(readFileSync(join(root, "README.md"), "utf8"), "fixture\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge tombstone boundary refuses a replacement transaction", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = JSON.parse(readFileSync(receipt, "utf8")).transactionRoot;
    const original = `${transaction}.original`;
    const replacementSentinel = join(transaction, "replacement-sentinel.txt");
    const purged = await runPausedAtHook(
      ["clean", "purge", receipt, "--force"],
      worktree,
      "before-purge-tombstone",
      () => {
        renameSync(transaction, original);
        mkdirSync(transaction);
        writeFileSync(replacementSentinel, "must survive\n");
      },
    );
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /authorized deletion manifest|identity changed at tombstone boundary/u);
    assert.equal(readFileSync(replacementSentinel, "utf8"), "must survive\n");
    assert.ok(existsSync(join(original, "receipt.json")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses content inserted after its pre-tombstone manifest", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const transaction = JSON.parse(readFileSync(receiptPath, "utf8")).transactionRoot;
    const sentinel = join(transaction, "late-before-tombstone.bin");
    const result = await runPausedAtHook(
      ["clean", "purge", receiptPath, "--force"],
      worktree,
      "before-purge-tombstone",
      () => { writeFileSync(sentinel, "must survive\n"); },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /authorized deletion manifest/u);
    assert.equal(readFileSync(sentinel, "utf8"), "must survive\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge revalidates receipt-bound contents after tombstoning", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let tombstone;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
    const transaction = receipt.transactionRoot;
    const injectedRelative = relative(transaction, join(dirname(receipt.moves[0].destination), "late-unrecorded.bin"));
    const purged = await runPausedAtHook(
      ["clean", "purge", receiptPath, "--force"],
      worktree,
      "after-purge-tombstone",
      (payload) => {
        tombstone = payload.tombstone;
        writeFileSync(join(payload.tombstone, injectedRelative), "must survive\n");
      },
    );
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /quarantine transaction contains content not named by the receipt|purge tombstone contains unknown content/u);
    assert.ok(tombstone);
    assert.equal(readFileSync(join(tombstone, injectedRelative), "utf8"), "must survive\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge retains a replacement introduced before leaf capture", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    const cleaned = run(["clean", "build"], worktree);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const result = await runPausedAtHook(
      ["clean", "purge", receipt, "--force"],
      worktree,
      "before-delete-entry-rename",
      ({ path }) => {
        unlinkSync(path);
        writeFileSync(path, "replacement survives\n");
      },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /retained at/u);
    assert.match(result.stderr, /entry changed before capture/u);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge retains a replacement capture introduced after leaf rename", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let capture;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    const cleaned = run(["clean", "build"], worktree);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const result = await runPausedAtHook(
      ["clean", "purge", receipt, "--force"],
      worktree,
      "after-delete-entry-rename",
      (payload) => {
        capture = payload.capture;
        renameSync(payload.capture, `${payload.capture}.original`);
        writeFileSync(payload.capture, "replacement capture survives\n");
      },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /capture does not match/u);
    assert.equal(readFileSync(capture, "utf8"), "replacement capture survives\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge preserves a replacement created at the original leaf name after staging", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let replacement;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    const cleaned = run(["clean", "build"], worktree);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const result = await runPausedAtHook(
      ["clean", "purge", receipt, "--force"],
      worktree,
      "after-delete-entry-rename",
      ({ path }) => {
        replacement = path;
        writeFileSync(path, "replacement survives\n");
      },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /not recursively deleted|retained at/u);
    assert.equal(readFileSync(replacement, "utf8"), "replacement survives\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge retains late unknown content when directory removal is not empty", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let sentinel;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "original\n");
    const cleaned = run(["clean", "build"], worktree);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const result = await runPausedAtHook(
      ["clean", "purge", receipt, "--force"],
      worktree,
      "before-delete-directory-rmdir",
      ({ path }) => {
        sentinel = join(path, "late-unknown.bin");
        writeFileSync(sentinel, "unknown survives\n");
      },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /retained at/u);
    assert.equal(readFileSync(sentinel, "utf8"), "unknown survives\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses an unrecorded regular file inside a destination bucket", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
    const injected = join(dirname(receipt.moves[0].destination), "unrecorded.bin");
    writeFileSync(injected, "must not be purged\n");

    const purged = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /not named by the receipt|contains unknown content/u);
    assert.ok(existsSync(dirname(receiptPath)));
    assert.equal(readFileSync(injected, "utf8"), "must not be purged\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a same-bucket artifact omitted from the receipt", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "coverage"));
    mkdirSync(join(worktree, "test-results"));
    writeFileSync(join(worktree, "coverage", "report.json"), "coverage\n");
    writeFileSync(join(worktree, "test-results", "results.xml"), "results\n");
    const cleaned = run(["clean", "reports"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const original = JSON.parse(readFileSync(receiptPath, "utf8"));
    assert.equal(original.moves.length, 2);
    const omittedDestination = original.moves[1].destination;
    rewriteReceipt(receiptPath, (receipt) => {
      receipt.moves = receipt.moves.slice(0, 1);
    });

    const purged = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /durable and transaction cleanup receipts differ/u);
    assert.ok(existsSync(omittedDestination));
    assert.ok(existsSync(dirname(receiptPath)));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a receipt whose recorded artifact size was tampered", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    rewriteReceipt(receiptPath, (receipt) => {
      receipt.moves[0].bytes += 1;
    });

    const purged = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /durable and transaction cleanup receipts differ/u);
    assert.ok(existsSync(dirname(receiptPath)));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge resumes safely after real SIGKILL at every durable deletion phase", async (context) => {
  if (skipWindowsMutation(context)) return;
  const hooks = [
    "after-purge-journal-create",
    "after-purge-journal-deleting",
    "after-purge-tombstone",
    "after-delete-entry-rename",
    "after-delete-entry-unlink",
    "after-purge-root-rmdir",
    "after-purge-complete-before-state",
  ];
  for (const hook of hooks) {
    await context.test(hook, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-purge-kill-${hook}-`);
      try {
        mkdirSync(join(worktree, "zig-out", "bin", "nested"), { recursive: true });
        writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
        writeFileSync(join(worktree, "zig-out", "bin", "nested", "data"), "data\n");
        const cleaned = run(["clean", "build"], worktree);
        assert.equal(cleaned.status, 0, cleaned.stderr);
        const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
        assert.ok(receiptPath);
        const transactionRoot = JSON.parse(readFileSync(receiptPath, "utf8")).transactionRoot;

        await runKilledAtHook(["clean", "purge", receiptPath, "--force"], worktree, hook);
        const resumed = run(["clean", "purge", receiptPath, "--force"], worktree);
        assert.equal(resumed.status, 0, `${hook}: ${resumed.stderr}`);
        assert.equal(existsSync(transactionRoot), false, hook);
        const second = run(["clean", "purge", receiptPath, "--force"], worktree);
        assert.equal(second.status, 0, `${hook} second run: ${second.stderr}`);
        assert.match(second.stdout, /already complete/u);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("purge refuses a live same-operation lock and preserves it", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let paused;
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    const hookRoot = mkdtempSync(join(tmpdir(), "workspace-maintenance-live-purge-lock-"));
    const marker = join(hookRoot, "marker.json");
    const release = join(hookRoot, "release");
    paused = spawn(process.execPath, [scriptPath, "clean", "purge", receiptPath, "--force"], {
      cwd: worktree,
      env: {
        ...process.env,
        NODE_ENV: "test",
        NODE_TEST_CONTEXT: "child-v8",
        WORKSPACE_MAINTENANCE_TEST_HOOK: "after-purge-journal-deleting",
        WORKSPACE_MAINTENANCE_TEST_MARKER: marker,
        WORKSPACE_MAINTENANCE_TEST_RELEASE: release,
      },
      stdio: ["ignore", "ignore", "ignore"],
    });
    await waitForPath(marker);
    const lockPath = join(root, ".git", "buwiz-workspace-maintenance", "lock.json");
    const before = readFileSync(lockPath, "utf8");
    const refused = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(refused.status, 3);
    assert.match(refused.stderr, /already held or cannot be proven stale/u);
    assert.equal(readFileSync(lockPath, "utf8"), before);
    releaseTestHook(release);
    await new Promise((resolveClosed) => paused.once("close", resolveClosed));
    paused = null;
  } finally {
    paused?.kill("SIGKILL");
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses corrupt or different-operation locks without replacing them", async (context) => {
  if (skipWindowsMutation(context)) return;
  for (const variant of ["corrupt", "different-operation"]) {
    await context.test(variant, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-purge-lock-${variant}-`);
      try {
        mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
        writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
        const cleaned = run(["clean", "build"], worktree);
        assert.equal(cleaned.status, 0, cleaned.stderr);
        const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
        assert.ok(receiptPath);
        await runKilledAtHook(
          ["clean", "purge", receiptPath, "--force"],
          worktree,
          "after-purge-journal-deleting",
        );
        const lockPath = join(root, ".git", "buwiz-workspace-maintenance", "lock.json");
        if (variant === "corrupt") {
          writeFileSync(lockPath, "not json\n");
        } else {
          const owner = JSON.parse(readFileSync(lockPath, "utf8"));
          owner.operationId = "0".repeat(64);
          writeFileSync(lockPath, `${JSON.stringify(owner, null, 2)}\n`);
        }
        const before = readFileSync(lockPath, "utf8");
        const refused = run(["clean", "purge", receiptPath, "--force"], worktree);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /lock is corrupt|cannot be proven stale/u);
        assert.equal(readFileSync(lockPath, "utf8"), before);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree-remove requires one exact absolute registered path", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    for (const target of ["candidate", `${worktree}/..`, join(root, "missing")]) {
      const result = run(["worktree-remove", target, "--force"], root);
      assert.equal(result.status, 3);
      assert.ok(existsSync(worktree));
    }
    const primary = run(["worktree-remove", realpathSync(root), "--force"], worktree);
    assert.equal(primary.status, 3);
    assert.match(primary.stderr, /primary worktree/u);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree-remove removes a clean merged fixture through Git and preserves its branch", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    const result = run(["worktree-remove", realpathSync(worktree)], root);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(worktree), false);
    assert.match(git(root, "show-ref", "--verify", "refs/heads/candidate"), /refs\/heads\/candidate/u);
    assert.doesNotMatch(git(root, "worktree", "list", "--porcelain"), new RegExp(worktree, "u"));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree-remove preserves target branch history and exact sibling topology", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  const sibling = join(dirname(worktree), "sibling");
  try {
    git(root, "worktree", "add", "-b", "sibling", sibling, "main");
    const targetHead = git(worktree, "rev-parse", "HEAD");
    const targetRef = git(worktree, "symbolic-ref", "HEAD");
    const targetReflogBefore = git(root, "reflog", "show", "--format=%H %gs", targetRef);
    const siblingBefore = linkedWorktreeTopology(sibling);
    const siblingAdminNamesBefore = physicalTreeSnapshot(siblingBefore.gitDir)
      .map(({ relativePath, type }) => ({ relativePath, type }));
    const siblingRefBefore = git(root, "show-ref", "--verify", siblingBefore.branch);
    const siblingReflogBefore = git(root, "reflog", "show", "--format=%H %gs", siblingBefore.branch);

    const removed = run(["worktree-remove", realpathSync(worktree)], root);
    assert.equal(removed.status, 0, removed.stderr);
    assert.equal(existsSync(worktree), false);
    assert.equal(git(root, "rev-parse", targetRef), targetHead);
    assert.equal(git(root, "reflog", "show", "--format=%H %gs", targetRef), targetReflogBefore);
    assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore);
    assert.deepEqual(
      physicalTreeSnapshot(siblingBefore.gitDir).map(({ relativePath, type }) => ({ relativePath, type })),
      siblingAdminNamesBefore,
    );
    assert.equal(git(root, "show-ref", "--verify", siblingBefore.branch), siblingRefBefore);
    assert.equal(git(root, "reflog", "show", "--format=%H %gs", siblingBefore.branch), siblingReflogBefore);
    const listed = git(root, "worktree", "list", "--porcelain");
    assert.doesNotMatch(listed, new RegExp(worktree, "u"));
    assert.match(listed, new RegExp(realpathSync(sibling), "u"));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal lock protects staged administration data from Git prune", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-prune-protection-");
  const sibling = join(dirname(worktree), "sibling");
  try {
    git(root, "worktree", "add", "-b", "sibling", sibling, "main");
    const target = realpathSync(worktree);
    const targetHead = git(worktree, "rev-parse", "HEAD");
    const targetRef = git(worktree, "symbolic-ref", "HEAD");
    const targetAdmin = realpathSync(git(worktree, "rev-parse", "--absolute-git-dir"));
    const siblingBefore = linkedWorktreeTopology(sibling);
    let receiptPath;
    const result = await runPausedAtHook(
      ["worktree-remove", target],
      root,
      "after-worktree-holding-rename",
      async (marker) => {
        receiptPath = marker.receiptPath;
        assert.equal(existsSync(target), false);
        assert.ok(existsSync(marker.holdingPath));
        assert.ok(existsSync(targetAdmin));
        assert.match(readFileSync(join(targetAdmin, "locked"), "utf8"), /^buwiz-worktree-remove:/u);
        git(root, "worktree", "prune");
        assert.ok(existsSync(targetAdmin));
        assert.equal(git(root, "rev-parse", targetRef), targetHead);
        assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore);
      },
      { WORKSPACE_MAINTENANCE_TEST_ACTION: "fail" },
    );
    assert.equal(result.status, 3, result.stderr);
    assert.ok(receiptPath && existsSync(receiptPath));
    const resumed = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
    assert.equal(resumed.status, 0, resumed.stderr);
    assert.equal(existsSync(targetAdmin), false);
    assert.equal(git(root, "rev-parse", targetRef), targetHead);
    assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal resumes after SIGKILL at every durable boundary", async (context) => {
  if (skipWindowsMutation(context)) return;
  const hooks = [
    "after-worktree-removal-journal-create",
    "after-worktree-git-move",
    "after-worktree-holding-rename",
    "after-worktree-admin-holding-rename",
    "after-worktree-admin-entry-rename",
    "after-worktree-admin-entry-unlink",
    "after-worktree-admin-root-rmdir",
    "after-worktree-root-entry-rename",
    "after-worktree-root-entry-unlink",
    "after-worktree-root-rmdir",
    "after-worktree-removal-complete-write",
  ];
  for (const hook of hooks) {
    await context.test(hook, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-remove-kill-${hook}-`);
      const sibling = join(dirname(worktree), "sibling");
      try {
        git(root, "worktree", "add", "-b", "sibling", sibling, "main");
        const target = realpathSync(worktree);
        const targetHead = git(worktree, "rev-parse", "HEAD");
        const targetRef = git(worktree, "symbolic-ref", "HEAD");
        const siblingBefore = linkedWorktreeTopology(sibling);
        const siblingFilesBefore = physicalTreeSnapshot(sibling);
          const siblingAdminBefore = physicalTreeSnapshot(siblingBefore.gitDir)
          .map(({ relativePath, type, contentDigest, linkTarget }) => ({
            relativePath,
            type,
            contentDigest,
            linkTarget,
          }));
        let receiptPath;
        const killed = await runKilledAtHook(
          ["worktree-remove", target],
          root,
          hook,
          (payload) => {
            assert.ok(isAbsolute(payload.receiptPath), `${hook}: receiptPath must be absolute`);
            receiptPath = payload.receiptPath;
          },
        );
        assert.equal(killed.signal, "SIGKILL");
        assert.ok(receiptPath && existsSync(receiptPath), hook);
        const staleLock = join(root, ".git", "buwiz-workspace-maintenance", "lock.json");
        if (hook === "after-worktree-removal-complete-write") {
          const completedReceipt = JSON.parse(readFileSync(receiptPath, "utf8"));
          assert.equal(completedReceipt.state, "complete", hook);
          if (existsSync(staleLock)) {
            const staleOwner = JSON.parse(readFileSync(staleLock, "utf8"));
            assert.equal(staleOwner.pid, killed.childPid, hook);
            assert.equal(staleOwner.kind, "worktree-remove", hook);
          }
        } else {
          assert.ok(existsSync(staleLock), `${hook}: SIGKILL must leave the owned lock`);
          const staleOwner = JSON.parse(readFileSync(staleLock, "utf8"));
          assert.equal(staleOwner.pid, killed.childPid, hook);
          assert.equal(staleOwner.kind, "worktree-remove", hook);
        }

        const resumed = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(resumed.status, 0, `${hook}: ${resumed.stderr}`);
        assert.equal(existsSync(staleLock), false, hook);
        assert.equal(existsSync(target), false, hook);
        assert.equal(git(root, "rev-parse", targetRef), targetHead, hook);
        assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore, hook);
        assert.deepEqual(physicalTreeSnapshot(sibling), siblingFilesBefore, hook);
        assert.deepEqual(
          physicalTreeSnapshot(siblingBefore.gitDir)
            .map(({ relativePath, type, contentDigest, linkTarget }) => ({
              relativePath,
              type,
              contentDigest,
              linkTarget,
            })),
          siblingAdminBefore,
          hook,
        );
        const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
        assert.equal(receipt.operation, "worktree-remove", hook);
        assert.equal(receipt.state, "complete", hook);
        for (const path of [
          receipt.registeredTombstone,
          receipt.holdingPath,
          receipt.adminHoldingPath,
        ]) {
          assert.equal(existsSync(path), false, `${hook}: ${path}`);
        }
        assert.doesNotMatch(git(root, "worktree", "list", "--porcelain"), new RegExp(target, "u"));

        const second = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(second.status, 0, `${hook} second resume: ${second.stderr}`);
        assert.match(second.stdout, /already complete/u);
        assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore, `${hook} second resume`);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree removal resume refuses a live owner without replacing its lock", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-remove-live-lock-");
  try {
    const target = realpathSync(worktree);
    let receiptPath;
    const interrupted = await runPausedAtHook(
      ["worktree-remove", target],
      root,
      "after-worktree-removal-journal-create",
      (payload) => {
        receiptPath = payload.receiptPath;
        assert.ok(isAbsolute(receiptPath));
        const lockPath = join(root, ".git", "buwiz-workspace-maintenance", "lock.json");
        const lockBefore = readFileSync(lockPath, "utf8");
        const owner = JSON.parse(lockBefore);
        assert.equal(owner.kind, "worktree-remove");
        const refused = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /lock is already held|cannot be proven stale/u);
        assert.equal(readFileSync(lockPath, "utf8"), lockBefore);
      },
      { WORKSPACE_MAINTENANCE_TEST_ACTION: "fail" },
    );
    assert.equal(interrupted.status, 3);
    assert.ok(receiptPath && existsSync(receiptPath));
    assert.ok(existsSync(target));

    const resumed = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
    assert.equal(resumed.status, 0, resumed.stderr);
    assert.equal(existsSync(target), false);
    assert.equal(JSON.parse(readFileSync(receiptPath, "utf8")).state, "complete");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal resume preserves corrupt and different-operation locks", async (context) => {
  if (skipWindowsMutation(context)) return;
  for (const variant of ["corrupt", "different-operation"]) {
    await context.test(variant, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-remove-lock-${variant}-`);
      try {
        const target = realpathSync(worktree);
        const killed = await runKilledAtHook(
          ["worktree-remove", target],
          root,
          "after-worktree-removal-journal-create",
        );
        const receiptPath = killed.payload.receiptPath;
        assert.ok(isAbsolute(receiptPath) && existsSync(receiptPath));
        const lockPath = join(root, ".git", "buwiz-workspace-maintenance", "lock.json");
        if (variant === "corrupt") {
          writeFileSync(lockPath, "not json\n");
        } else {
          const owner = JSON.parse(readFileSync(lockPath, "utf8"));
          owner.kind = "clean-purge";
          writeFileSync(lockPath, `${JSON.stringify(owner, null, 2)}\n`);
        }
        const lockBefore = readFileSync(lockPath, "utf8");
        const refused = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /lock/u);
        assert.equal(readFileSync(lockPath, "utf8"), lockBefore);
        assert.ok(existsSync(target));
        assert.notEqual(JSON.parse(readFileSync(receiptPath, "utf8")).state, "complete");
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree removal resume preserves content inserted after SIGKILL", async (context) => {
  if (skipWindowsMutation(context)) return;
  const cases = [
    {
      hook: "after-worktree-git-move",
      insert(payload) {
        mkdirSync(payload.original);
        const sentinel = join(payload.original, "late-original.txt");
        writeFileSync(sentinel, "late original survives\n");
        return sentinel;
      },
    },
    {
      hook: "after-worktree-holding-rename",
      insert(payload) {
        const sentinel = join(payload.holdingPath, "late-held.txt");
        writeFileSync(sentinel, "late held survives\n");
        return sentinel;
      },
    },
    {
      hook: "after-worktree-admin-holding-rename",
      insert(payload) {
        const sentinel = join(payload.adminHoldingPath, "late-admin.txt");
        writeFileSync(sentinel, "late admin survives\n");
        return sentinel;
      },
    },
    {
      hook: "after-worktree-admin-entry-rename",
      insert(payload) {
        const sentinel = join(payload.root, "late-admin-leaf.txt");
        writeFileSync(sentinel, "late admin leaf survives\n");
        return sentinel;
      },
    },
    {
      hook: "after-worktree-root-entry-rename",
      insert(payload) {
        const sentinel = join(payload.root, "late-root-leaf.txt");
        writeFileSync(sentinel, "late root leaf survives\n");
        return sentinel;
      },
    },
  ];
  for (const crashCase of cases) {
    await context.test(crashCase.hook, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-remove-insert-${crashCase.hook}-`);
      const sibling = join(dirname(worktree), "sibling");
      try {
        git(root, "worktree", "add", "-b", "sibling", sibling, "main");
        const target = realpathSync(worktree);
        const targetRef = git(worktree, "symbolic-ref", "HEAD");
        const targetHead = git(worktree, "rev-parse", "HEAD");
        const siblingBefore = linkedWorktreeTopology(sibling);
        let sentinel;
        const killed = await runKilledAtHook(
          ["worktree-remove", target],
          root,
          crashCase.hook,
          (payload) => {
            assert.ok(isAbsolute(payload.receiptPath));
            sentinel = crashCase.insert(payload);
          },
        );
        const receiptPath = killed.payload.receiptPath;
        const sentinelContents = readFileSync(sentinel, "utf8");
        const refused = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /changed|repopulated|unknown content|manifest/u);
        assert.equal(readFileSync(sentinel, "utf8"), sentinelContents);
        assert.notEqual(JSON.parse(readFileSync(receiptPath, "utf8")).state, "complete");
        assert.equal(git(root, "rev-parse", targetRef), targetHead);
        assert.deepEqual(linkedWorktreeTopology(sibling), siblingBefore);
        assert.equal(
          existsSync(join(root, ".git", "buwiz-workspace-maintenance", "lock.json")),
          false,
        );
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree removal preserves a repopulated original path and its staged tree", async (context) => {
  if (skipWindowsMutation(context)) return;
  for (const replacementType of ["file", "directory"]) {
    await context.test(replacementType, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-original-${replacementType}-`);
      try {
        const original = realpathSync(worktree);
        const result = await runPausedAtHook(
          ["worktree-remove", original], root, "after-worktree-git-move",
          async (marker) => {
            assert.equal(marker.original, original);
            assert.ok(existsSync(marker.registeredTombstone));
            if (replacementType === "file") writeFileSync(original, "late original file\n");
            else {
              mkdirSync(original);
              writeFileSync(join(original, "late.txt"), "late original directory\n");
            }
          },
        );
        assert.equal(result.status, 3);
        assert.match(result.stderr, /original worktree path was repopulated/u);
        if (replacementType === "file") assert.equal(readFileSync(original, "utf8"), "late original file\n");
        else assert.equal(readFileSync(join(original, "late.txt"), "utf8"), "late original directory\n");
        const receiptDir = join(root, ".git", "buwiz-workspace-maintenance", "receipts");
        const receipt = readdirSync(receiptDir).map((name) => join(receiptDir, name))
          .find((path) => JSON.parse(readFileSync(path, "utf8")).operation === "worktree-remove");
        assert.ok(receipt);
        const details = JSON.parse(readFileSync(receipt, "utf8"));
        assert.equal(details.state, "root-move-intent");
        assert.ok(existsSync(details.registeredTombstone));
        const listed = git(root, "worktree", "list", "--porcelain");
        assert.match(listed, new RegExp(original, "u"));
        assert.match(listed, new RegExp(details.gitLockReason, "u"));
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree removal preserves a repopulated registered tombstone and held tree", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-registered-repopulation-");
  try {
    const result = await runPausedAtHook(
      ["worktree-remove", realpathSync(worktree)], root, "after-worktree-holding-rename",
      async (marker) => {
        assert.equal(existsSync(marker.registeredTombstone), false);
        assert.ok(existsSync(marker.holdingPath));
        mkdirSync(marker.registeredTombstone);
        writeFileSync(join(marker.registeredTombstone, "late.txt"), "late registered tombstone\n");
      },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /root topology is inconsistent or was repopulated/u);
    const receiptDir = join(root, ".git", "buwiz-workspace-maintenance", "receipts");
    const receipt = readdirSync(receiptDir).map((name) => join(receiptDir, name))
      .find((path) => JSON.parse(readFileSync(path, "utf8")).operation === "worktree-remove");
    assert.ok(receipt);
    const details = JSON.parse(readFileSync(receipt, "utf8"));
    assert.equal(details.state, "root-held");
    assert.equal(readFileSync(join(details.registeredTombstone, "late.txt"), "utf8"), "late registered tombstone\n");
    assert.ok(existsSync(details.holdingPath));
    assert.ok(existsSync(join(details.holdingPath, ".git")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal blocks an admin lock inserted at deregistration boundary", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-admin-lock-");
  try {
    const result = await runPausedAtHook(
      ["worktree-remove", realpathSync(worktree)], root, "before-worktree-admin-delete",
      async (marker) => { writeFileSync(join(marker.adminRoot, "late-probe.lock"), "late admin lock\n"); },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /administration (?:contents changed during staging|directory no longer matches its authorized deletion manifest|contains lock files)/u);
    const receiptDir = join(root, ".git", "buwiz-workspace-maintenance", "receipts");
    const receipt = readdirSync(receiptDir).map((name) => join(receiptDir, name))
      .find((path) => JSON.parse(readFileSync(path, "utf8")).operation === "worktree-remove");
    assert.ok(receipt);
    const details = JSON.parse(readFileSync(receipt, "utf8"));
    assert.equal(details.state, "admin-move-intent");
    assert.equal(readFileSync(join(details.targetGitDir, "late-probe.lock"), "utf8"), "late admin lock\n");
    assert.ok(existsSync(details.holdingPath));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal refuses a hard-linked administration file before Git can rewrite it", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-admin-hardlink-");
  try {
    const maintenance = linkedWorktreeMaintenancePaths(root, worktree);
    const adminGitdir = join(maintenance.gitDir, "gitdir");
    const sentinel = join(dirname(root), "external-gitdir-sentinel");
    linkSync(adminGitdir, sentinel);
    const before = readFileSync(sentinel, "utf8");

    const result = run(["worktree-remove", realpathSync(worktree)], root);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /hard-linked regular files/u);
    assert.equal(readFileSync(sentinel, "utf8"), before);
    assert.ok(existsSync(worktree));
    assert.match(git(root, "worktree", "list", "--porcelain"), new RegExp(realpathSync(worktree), "u"));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree removal blocks late held-tree content before final deletion", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-held-tree-change-");
  try {
    const result = await runPausedAtHook(
      ["worktree-remove", realpathSync(worktree)], root, "before-worktree-delete",
      async (marker) => { writeFileSync(join(marker.holdingPath, "late-held.txt"), "late held content\n"); },
    );
    assert.equal(result.status, 3);
    assert.match(result.stderr, /purge tombstone contains unknown content|ENOTEMPTY/u);
    const receiptDir = join(root, ".git", "buwiz-workspace-maintenance", "receipts");
    const receipt = readdirSync(receiptDir).map((name) => join(receiptDir, name))
      .find((path) => JSON.parse(readFileSync(path, "utf8")).operation === "worktree-remove");
    assert.ok(receipt);
    const details = JSON.parse(readFileSync(receipt, "utf8"));
    assert.equal(details.state, "root-delete-intent");
    assert.equal(readFileSync(join(details.holdingPath, "late-held.txt"), "utf8"), "late held content\n");
    assert.equal(existsSync(details.targetGitDir), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree-remove requires every cleanup receipt to be purged, even with force", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);

    for (const args of [
      ["worktree-remove", realpathSync(worktree)],
      ["worktree-remove", realpathSync(worktree), "--force"],
    ]) {
      const blocked = run(args, root);
      assert.equal(blocked.status, 3);
      assert.match(blocked.stderr, /unpurged cleanup receipts/u);
      assert.ok(blocked.stderr.includes(receipt));
      assert.ok(existsSync(worktree));
    }

    const purged = run(["clean", "purge", receipt, "--force"], root);
    assert.equal(purged.status, 0, purged.stderr);
    const removed = run(["worktree-remove", realpathSync(worktree)], root);
    assert.equal(removed.status, 0, removed.stderr);
    assert.equal(existsSync(worktree), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("moving a worktree cannot hide its outstanding cleanup receipt", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  const movedParent = join(dirname(worktree), "moved-parent");
  const movedWorktree = join(movedParent, "candidate");
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);

    mkdirSync(movedParent);
    git(root, "worktree", "move", worktree, movedWorktree);
    const blocked = run(["worktree-remove", realpathSync(movedWorktree), "--force"], root);
    assert.equal(blocked.status, 3);
    assert.match(blocked.stderr, /cleanup (?:intent|receipt)|unpurged cleanup/u);
    assert.ok(blocked.stderr.includes(receipt));
    assert.ok(existsSync(movedWorktree));

    const purged = run(["clean", "purge", receipt, "--force"], root);
    assert.equal(purged.status, 0, purged.stderr);
    const removed = run(["worktree-remove", realpathSync(movedWorktree)], root);
    assert.equal(removed.status, 0, removed.stderr);
    assert.equal(existsSync(movedWorktree), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("exact cross-worktree clean changes only the selected linked worktree", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  const third = join(dirname(worktree), "third");
  try {
    git(root, "worktree", "add", "-b", "third", third, "main");
    mkdirSync(join(root, "zig-out", "bin"), { recursive: true });
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    mkdirSync(join(third, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(root, "zig-out", "bin", "primary"), "primary\n");
    writeFileSync(join(worktree, "zig-out", "bin", "selected"), "selected\n");
    writeFileSync(join(third, "zig-out", "bin", "third"), "third\n");
    const callerBefore = linkedWorktreeTopology(worktree);
    const thirdBefore = linkedWorktreeTopology(third);
    const topologyBefore = git(root, "worktree", "list", "--porcelain");

    const cleaned = run(["clean", "build", "--worktree", realpathSync(third), "--force"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    assert.ok(existsSync(join(root, "zig-out", "bin", "primary")));
    assert.ok(existsSync(join(worktree, "zig-out", "bin", "selected")));
    assert.equal(existsSync(join(third, "zig-out")), false);
    assert.deepEqual(linkedWorktreeTopology(worktree), callerBefore);
    assert.deepEqual(linkedWorktreeTopology(third), thirdBefore);
    assert.equal(git(root, "worktree", "list", "--porcelain"), topologyBefore);

    const purged = run(["clean", "purge", receipt, "--force"], root);
    assert.equal(purged.status, 0, purged.stderr);
    assert.ok(existsSync(join(root, "zig-out", "bin", "primary")));
    assert.ok(existsSync(join(worktree, "zig-out", "bin", "selected")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("a missing outstanding cleanup state blocks removal after a worktree move", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  const movedParent = join(dirname(worktree), "moved-missing-state-parent");
  const movedWorktree = join(movedParent, "candidate");
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const maintenance = linkedWorktreeMaintenancePaths(root, worktree);
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    assert.equal(JSON.parse(readFileSync(maintenance.state, "utf8")).state, "receipt");

    mkdirSync(movedParent);
    git(root, "worktree", "move", worktree, movedWorktree);
    unlinkSync(maintenance.state);

    const blocked = run(["worktree-remove", realpathSync(movedWorktree), "--force"], root);
    assert.equal(blocked.status, 3);
    assert.match(blocked.stderr, /cleanup quarantine state is uncertain|cleanup receipt|quarantine transaction/u);
    assert.ok(existsSync(movedWorktree));
    assert.ok(existsSync(receipt));
    assert.equal(existsSync(maintenance.state), false);
    assert.match(git(root, "worktree", "list", "--porcelain"), new RegExp(realpathSync(movedWorktree), "u"));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("a corrupt cleanup state blocks forced worktree removal and preserves its receipt", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const maintenance = linkedWorktreeMaintenancePaths(root, worktree);
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const state = JSON.parse(readFileSync(maintenance.state, "utf8"));
    state.transactionRoot = join(dirname(state.transactionRoot), "wrong-transaction");
    writeFileSync(maintenance.state, `${JSON.stringify(state, null, 2)}\n`);

    const blocked = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(blocked.status, 3);
    assert.match(blocked.stderr, /cleanup state does not match its receipt|cleanup quarantine state is uncertain/u);
    assert.ok(existsSync(worktree));
    assert.ok(existsSync(receipt));
    assert.equal(JSON.parse(readFileSync(maintenance.state, "utf8")).transactionRoot, state.transactionRoot);
    assert.match(git(root, "worktree", "list", "--porcelain"), new RegExp(realpathSync(worktree), "u"));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("dirty and unmerged worktrees require force, while immutable guards still hold", (context) => {
  if (skipWindowsMutation(context)) return;
  const dirty = makeRepo();
  try {
    writeFileSync(join(dirty.worktree, "dirty.txt"), "dirty\n");
    const normal = run(["worktree-remove", realpathSync(dirty.worktree)], dirty.root);
    assert.equal(normal.status, 3);
    assert.match(normal.stderr, /working tree is not clean/u);
    assert.ok(existsSync(dirty.worktree));

    const forced = run(["worktree-remove", realpathSync(dirty.worktree), "--force"], dirty.root);
    assert.equal(forced.status, 0, forced.stderr);
    assert.equal(existsSync(dirty.worktree), false);
  } finally {
    rmSync(dirname(dirty.root), { recursive: true, force: true });
  }

  const unmerged = makeRepo();
  try {
    writeFileSync(join(unmerged.worktree, "ahead.txt"), "ahead\n");
    git(unmerged.worktree, "add", "ahead.txt");
    git(unmerged.worktree, "commit", "-m", "ahead");
    const normal = run(["worktree-remove", realpathSync(unmerged.worktree)], unmerged.root);
    assert.equal(normal.status, 3);
    assert.match(normal.stderr, /not an ancestor/u);
    const forced = run(["worktree-remove", realpathSync(unmerged.worktree), "--force"], unmerged.root);
    assert.equal(forced.status, 0, forced.stderr);
    assert.match(git(unmerged.root, "show-ref", "--verify", "refs/heads/candidate"), /refs\/heads\/candidate/u);
  } finally {
    rmSync(dirname(unmerged.root), { recursive: true, force: true });
  }
});

test("forced detached removal retains the commit through a rescue ref", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    git(worktree, "checkout", "--detach");
    writeFileSync(join(worktree, "detached.txt"), "retained\n");
    git(worktree, "add", "detached.txt");
    git(worktree, "commit", "-m", "detached ahead");
    const detachedHead = git(worktree, "rev-parse", "HEAD");

    const normal = run(["worktree-remove", realpathSync(worktree)], root);
    assert.equal(normal.status, 3);
    assert.ok(existsSync(worktree));

    const forced = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(forced.status, 0, forced.stderr);
    const rescueRef = forced.stdout.match(/rescue ref: (refs\/buwiz\/worktree-rescue\/\S+)/u)?.[1];
    assert.ok(rescueRef);
    assert.equal(git(root, "rev-parse", rescueRef), detachedHead);
    assert.equal(existsSync(worktree), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("force cannot remove the current worktree or a worktree in an in-progress Git operation", (context) => {
  if (skipWindowsMutation(context)) return;
  const current = makeRepo();
  try {
    const currentResult = run(["worktree-remove", realpathSync(current.worktree), "--force"], current.worktree);
    assert.equal(currentResult.status, 3);
    assert.match(currentResult.stderr, /current worktree/u);
    assert.ok(existsSync(current.worktree));
  } finally {
    rmSync(dirname(current.root), { recursive: true, force: true });
  }

  const operation = makeRepo();
  try {
    const gitDir = git(operation.worktree, "rev-parse", "--git-dir");
    writeFileSync(resolve(operation.worktree, gitDir, "MERGE_HEAD"), git(operation.worktree, "rev-parse", "HEAD") + "\n");
    const result = run(["worktree-remove", realpathSync(operation.worktree), "--force"], operation.root);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /Git operation is in progress/u);
    assert.ok(existsSync(operation.worktree));
  } finally {
    rmSync(dirname(operation.root), { recursive: true, force: true });
  }
});

test("protected ignored data blocks worktree removal even with force", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    writeFileSync(join(worktree, ".env"), "SECRET=fixture-only\n");
    const result = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /ignored data/u);
    assert.equal(readFileSync(join(worktree, ".env"), "utf8"), "SECRET=fixture-only\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("any ignored content blocks worktree removal, including catalog artifacts and local backups", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, ".zig-cache"));
    writeFileSync(join(worktree, ".zig-cache", "cache.bin"), "cache\n");
    writeFileSync(join(root, ".git", "info", "exclude"), ".native.backup*/\n");
    mkdirSync(join(worktree, ".native.backup-20260813"));
    writeFileSync(join(worktree, ".native.backup-20260813", "keep.bin"), "keep\n");
    const result = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /\.zig-cache/u);
    assert.match(result.stderr, /\.native\.backup-20260813/u);
    assert.ok(existsSync(worktree));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("cross-worktree clean rejects primary, current, and a parent with a registered descendant", (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");

    const primary = run(["clean", "build", "--worktree", realpathSync(root), "--force"], worktree);
    assert.equal(primary.status, 3);
    assert.match(primary.stderr, /primary worktree/u);

    const current = run(["clean", "build", "--worktree", realpathSync(worktree), "--force"], worktree);
    assert.equal(current.status, 3);
    assert.match(current.stderr, /current worktree/u);

    const child = join(worktree, "nested-child");
    git(root, "worktree", "add", "-b", "nested-child", child, "main");
    const parent = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(parent.status, 3);
    assert.match(parent.stderr, /registered descendant worktree/u);
    assert.ok(existsSync(child));

    const all = run(["clean", "build", "--all-worktrees", "--force"], root);
    assert.equal(all.status, 3);
    assert.match(all.stderr, /read-only/u);
    assert.ok(existsSync(join(worktree, "zig-out", "bin", "app")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("an active process is an immutable blocker", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo();
  let processHandle;
  try {
    processHandle = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
      cwd: worktree,
      stdio: "ignore",
    });
    await new Promise((resolveReady) => setTimeout(resolveReady, 150));
    const result = run(["worktree-remove", realpathSync(worktree), "--force"], root);
    assert.equal(result.status, 3);
    assert.match(result.stderr, /process state is (?:active|unknown)/u);
    assert.ok(existsSync(worktree));
  } finally {
    processHandle?.kill("SIGTERM");
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("cleanup resumes safely after real SIGKILL at every durable phase", async (context) => {
  if (skipWindowsMutation(context, "Windows mutation intentionally unsupported")) return;
  const checkpoints = [
    "after-clean-journal-create",
    "after-clean-journal-moving",
    "after-artifact-rename-0",
    "after-artifact-rename-1",
    "after-clean-journal-internal-receipt",
    "after-clean-internal-receipt",
    "after-clean-journal-durable-receipt",
    "after-clean-durable-receipt",
    "after-clean-state-update",
    "after-clean-journal-complete",
    "after-clean-complete",
  ];
  for (const checkpoint of checkpoints) {
    await context.test(checkpoint, async () => {
      const { root, worktree } = makeRepo();
      try {
        mkdirSync(join(worktree, ".zig-cache"), { recursive: true });
        mkdirSync(join(worktree, "zig-cache"), { recursive: true });
        writeFileSync(join(worktree, ".zig-cache", "one.bin"), "one\n");
        writeFileSync(join(worktree, "zig-cache", "two.bin"), "two\n");
        const killed = await runKilledAtHook(["clean", "zig-cache"], worktree, checkpoint);
        const journalRoot = join(dirname(cleanupLockPath(root)), "clean-operations");
        const journal = killed.payload.journalPath
          ?? (existsSync(journalRoot)
            ? join(journalRoot, readdirSync(journalRoot)[0], "journal.json")
            : null);
        assert.ok(journal && existsSync(journal), `missing journal after ${checkpoint}`);

        const noForce = run(["clean", "resume", journal], worktree);
        assert.equal(noForce.status, 3);
        assert.match(noForce.stderr, /requires --force/u);

        const preview = run(["clean", "resume", journal, "--dry-run"], worktree);
        assert.equal(preview.status, 0, preview.stderr);
        const beforeResume = JSON.parse(readFileSync(journal, "utf8"));

        const resumed = run(["clean", "resume", journal, "--force"], worktree);
        assert.equal(resumed.status, 0, resumed.stderr);
        const receiptPath = resumed.stdout.match(/receipt: (.+receipt\.json)/u)?.[1]
          ?? JSON.parse(readFileSync(journal, "utf8")).durableReceiptPath;
        assert.ok(receiptPath && existsSync(receiptPath));
        const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
        assert.equal(receipt.moves.length, 2);
        assert.equal(readFileSync(join(receipt.moves[0].destination, "one.bin"), "utf8"), "one\n");
        assert.equal(readFileSync(join(receipt.moves[1].destination, "two.bin"), "utf8"), "two\n");
        assert.equal(existsSync(join(worktree, ".zig-cache")), false);
        assert.equal(existsSync(join(worktree, "zig-cache")), false);
        assert.equal(beforeResume.authorizationDigest, JSON.parse(readFileSync(journal, "utf8")).authorizationDigest);

        const second = run(["clean", "resume", journal, "--force"], worktree);
        assert.equal(second.status, 0, second.stderr);
        assert.match(second.stdout, /already complete/u);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("cleanup resume refuses ambiguous, missing, changed, and unknown artifact state", async (context) => {
  if (skipWindowsMutation(context, "Windows mutation intentionally unsupported")) return;
  for (const variant of ["both", "neither", "source-changed", "destination-changed", "unknown"]) {
    await context.test(variant, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-clean-resume-${variant}-`);
      try {
        mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
        writeFileSync(join(worktree, "zig-out", "bin", "app"), "authorized\n");
        let killed;
        if (["destination-changed", "unknown"].includes(variant)) {
          killed = await runKilledAtHook(["clean", "build"], worktree, "after-artifact-rename-0");
        } else {
          killed = await runKilledAtHook(["clean", "build"], worktree, "after-clean-journal-moving");
        }
        const journalRoot = join(dirname(cleanupLockPath(root)), "clean-operations");
        const journalPath = killed.payload.journalPath
          ?? join(journalRoot, readdirSync(journalRoot)[0], "journal.json");
        const journal = JSON.parse(readFileSync(journalPath, "utf8"));
        const move = journal.moves[0];
        if (variant === "both") {
          mkdirSync(move.destination, { recursive: true });
          writeFileSync(join(move.destination, "replacement.txt"), "keep\n");
        } else if (variant === "neither") {
          rmSync(move.source, { recursive: true });
        } else if (variant === "source-changed") {
          writeFileSync(join(move.source, "bin", "app"), "changed\n");
        } else if (variant === "destination-changed") {
          writeFileSync(join(move.destination, "bin", "app"), "changed\n");
        } else {
          writeFileSync(join(journal.transactionRoot, "unknown.bin"), "keep\n");
        }
        const refused = run(["clean", "resume", journalPath, "--force"], worktree);
        assert.equal(refused.status, 3, refused.stderr);
        assert.match(refused.stderr, /both exist|both missing|source was replaced|destination.*changed|unknown content/u);
        if (variant === "both") assert.equal(readFileSync(join(move.destination, "replacement.txt"), "utf8"), "keep\n");
        if (variant === "unknown") assert.equal(readFileSync(join(journal.transactionRoot, "unknown.bin"), "utf8"), "keep\n");
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("cleanup resume refuses live, corrupt, wrong-operation, and foreign-host locks", async (context) => {
  if (skipWindowsMutation(context, "Windows mutation intentionally unsupported")) return;
  for (const variant of ["live", "corrupt", "wrong-operation", "foreign-host"]) {
    await context.test(variant, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-clean-lock-${variant}-`);
      try {
        mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
        writeFileSync(join(worktree, "zig-out", "bin", "app"), "authorized\n");
        const killed = await runKilledAtHook(["clean", "build"], worktree, "after-clean-journal-moving");
        const journalRoot = join(dirname(cleanupLockPath(root)), "clean-operations");
        const journalPath = killed.payload.journalPath
          ?? join(journalRoot, readdirSync(journalRoot)[0], "journal.json");
        const lock = cleanupLockPath(root);
        if (variant === "corrupt") {
          writeFileSync(lock, "not json\n");
        } else {
          const owner = JSON.parse(readFileSync(lock, "utf8"));
          if (variant === "live") owner.pid = process.pid;
          if (variant === "wrong-operation") owner.operationId = "0".repeat(64);
          if (variant === "foreign-host") owner.host = "foreign-host.invalid";
          writeFileSync(lock, `${JSON.stringify(owner, null, 2)}\n`);
        }
        const before = readFileSync(lock, "utf8");
        const refused = run(["clean", "resume", journalPath, "--force"], worktree);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /lock is corrupt|cannot be proven stale/u);
        assert.equal(readFileSync(lock, "utf8"), before);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("unknown or corrupt durable cleanup receipt metadata blocks worktree removal", async (context) => {
  if (skipWindowsMutation(context, "Windows mutation intentionally unsupported")) return;
  for (const variant of ["unknown-entry", "corrupt-receipt"]) {
    await context.test(variant, () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-durable-${variant}-`);
      try {
        const durableRoot = join(root, ".git", "buwiz-workspace-maintenance", "cleanup-receipts");
        const operationRoot = join(durableRoot, "a".repeat(64));
        mkdirSync(operationRoot, { recursive: true });
        if (variant === "unknown-entry") {
          writeFileSync(join(durableRoot, "unexpected"), "keep\n");
        } else {
          writeFileSync(join(operationRoot, "receipt.json"), "not json\n");
        }
        const result = run(["worktree-remove", realpathSync(worktree), "--force"], root);
        assert.equal(result.status, 3);
        assert.match(result.stderr, /cleanup quarantine state is uncertain|unknown entry|not valid JSON/u);
        assert.ok(existsSync(worktree));
        if (variant === "unknown-entry") assert.equal(readFileSync(join(durableRoot, "unexpected"), "utf8"), "keep\n");
        else assert.equal(readFileSync(join(operationRoot, "receipt.json"), "utf8"), "not json\n");
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("purge after tombstone refuses a forged traversal manifest and leaves the sentinel unchanged", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-purge-forge-");
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receiptPath = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receiptPath);
    let tombstone;
    await runKilledAtHook(
      ["clean", "purge", receiptPath, "--force"],
      worktree,
      "after-purge-tombstone",
      (payload) => { tombstone = payload.tombstone; },
    );
    assert.ok(tombstone && existsSync(tombstone));
    const sentinel = join(dirname(tombstone), "external-sentinel");
    writeFileSync(sentinel, "purge sentinel must survive\n");
    const journalPath = join(dirname(receiptPath), "purge.json");
    const journal = JSON.parse(readFileSync(journalPath, "utf8"));
    forgeTraversalManifestEntry(
      journal.manifest,
      "../external-sentinel",
      purgeCaptureRelativePathFor(journal.operationId, "../external-sentinel"),
    );
    recomputePurgeJournalDigests(journal);
    writeJson(journalPath, journal);

    const refused = run(["clean", "purge", receiptPath, "--force"], worktree);
    assert.equal(refused.status, 3);
    assert.match(refused.stderr, /canonical deletion-manifest descendant|orphaned path|escapes its deletion root/u);
    assert.equal(readFileSync(sentinel, "utf8"), "purge sentinel must survive\n");
    assert.ok(existsSync(tombstone));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree resume after holding transitions refuses forged root and admin manifests", async (context) => {
  if (skipWindowsMutation(context)) return;
  const cases = [
    {
      hook: "after-worktree-holding-rename",
      namespace: "root",
      manifestKey: "rootManifest",
      holdingKey: "holdingPath",
    },
    {
      hook: "after-worktree-admin-holding-rename",
      namespace: "admin",
      manifestKey: "adminManifest",
      holdingKey: "adminHoldingPath",
    },
  ];
  for (const crashCase of cases) {
    await context.test(crashCase.hook, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-worktree-forge-${crashCase.namespace}-`);
      try {
        const target = realpathSync(worktree);
        const killed = await runKilledAtHook(["worktree-remove", target], root, crashCase.hook);
        const receiptPath = killed.payload.receiptPath;
        const holdingPath = killed.payload[crashCase.holdingKey];
        assert.ok(isAbsolute(receiptPath) && existsSync(receiptPath));
        assert.ok(holdingPath && existsSync(holdingPath));
        const sentinel = join(dirname(holdingPath), "external-sentinel");
        writeFileSync(sentinel, `${crashCase.namespace} sentinel must survive\n`);
        const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
        forgeTraversalManifestEntry(
          receipt[crashCase.manifestKey],
          "../external-sentinel",
          purgeCaptureRelativePathFor(`${receipt.operationId}-${crashCase.namespace}`, "../external-sentinel"),
        );
        recomputeWorktreeRemovalAuthorization(receipt);
        writeJson(receiptPath, receipt);
        const holdingBefore = physicalTreeSnapshot(holdingPath);

        const refused = run(["worktree-remove", "--resume", receiptPath, "--force"], root);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /canonical deletion-manifest descendant|orphaned path|escapes its deletion root/u);
        assert.equal(readFileSync(sentinel, "utf8"), `${crashCase.namespace} sentinel must survive\n`);
        assert.ok(existsSync(holdingPath));
        assert.deepEqual(physicalTreeSnapshot(holdingPath), holdingBefore);
        assert.notEqual(JSON.parse(readFileSync(receiptPath, "utf8")).state, "complete");
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("worktree resume refuses a forged foreign receipt without moving a stale lock", async (context) => {
  if (skipWindowsMutation(context)) return;
  const victim = makeRepo("workspace-maintenance-foreign-lock-victim-");
  const attacker = makeRepo("workspace-maintenance-foreign-lock-attacker-");
  try {
    const target = realpathSync(victim.worktree);
    const killed = await runKilledAtHook(
      ["worktree-remove", target],
      victim.root,
      "after-worktree-git-move",
      (payload) => {
        mkdirSync(payload.original);
        writeFileSync(join(payload.original, "late.txt"), "repopulated\n");
      },
    );
    const receiptPath = killed.payload.receiptPath;
    const lockPath = join(victim.root, ".git", "buwiz-workspace-maintenance", "lock.json");
    assert.ok(existsSync(lockPath));
    const lockBefore = readFileSync(lockPath, "utf8");

    const foreignResume = run(["worktree-remove", "--resume", receiptPath, "--force"], attacker.root);
    assert.equal(foreignResume.status, 3);
    assert.equal(readFileSync(lockPath, "utf8"), lockBefore);

    const attackerReceiptDir = join(attacker.root, ".git", "buwiz-workspace-maintenance", "receipts");
    mkdirSync(attackerReceiptDir, { recursive: true });
    const forgedPath = join(attackerReceiptDir, "forged-foreign.json");
    const forged = JSON.parse(readFileSync(receiptPath, "utf8"));
    forged.commonDir = realpathSync(join(victim.root, ".git"));
    recomputeWorktreeRemovalAuthorization(forged);
    writeJson(forgedPath, forged);
    const forgedResume = run(["worktree-remove", "--resume", forgedPath, "--force"], attacker.root);
    assert.equal(forgedResume.status, 3);
    assert.equal(readFileSync(lockPath, "utf8"), lockBefore);
    assert.equal(readFileSync(join(killed.payload.original, "late.txt"), "utf8"), "repopulated\n");
    assert.ok(existsSync(killed.payload.registeredTombstone));
  } finally {
    rmSync(dirname(victim.root), { recursive: true, force: true });
    rmSync(dirname(attacker.root), { recursive: true, force: true });
  }
});

test("cleanup resume rejects malformed manifest and symlink relative paths before any rename", async (context) => {
  if (skipWindowsMutation(context)) return;
  const variants = ["manifest", "symlink"];
  for (const variant of variants) {
    await context.test(variant, async () => {
      const { root, worktree } = makeRepo(`workspace-maintenance-clean-forge-${variant}-`);
      try {
        mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
        writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
        mkdirSync(join(worktree, "node_modules", "pkg"), { recursive: true });
        writeFileSync(join(worktree, "node_modules", "pkg", "index.js"), "pkg\n");
        symlinkSync("index.js", join(worktree, "node_modules", "pkg", "self"));
        const target = variant === "symlink" ? "deps" : "build";
        const source = variant === "symlink"
          ? join(worktree, "node_modules")
          : join(worktree, "zig-out");
        const killed = await runKilledAtHook(
          ["clean", target],
          worktree,
          "after-clean-journal-create",
        );
        const journalPath = killed.payload.journalPath;
        assert.ok(isAbsolute(journalPath) && existsSync(journalPath));
        const journal = JSON.parse(readFileSync(journalPath, "utf8"));
        if (variant === "manifest") {
          forgeTraversalManifestEntry(journal.moves[0].manifest, "../external-sentinel");
        } else {
          assert.ok(journal.moves[0].dependencySymlinks.length > 0);
          journal.moves[0].dependencySymlinks[0].relativePath = "../evil";
        }
        recomputeCleanJournalAuthorization(journal);
        writeJson(journalPath, journal);

        const refused = run(["clean", "resume", journalPath, "--force"], worktree);
        assert.equal(refused.status, 3);
        assert.match(refused.stderr, /canonical deletion-manifest descendant|invalid symlink relative path/u);
        assert.ok(existsSync(source));
        assert.equal(existsSync(journal.moves[0].destination), false);
      } finally {
        rmSync(dirname(root), { recursive: true, force: true });
      }
    });
  }
});

test("deletion manifests reject malformed relative paths, roots, orphans, and capture collisions", async (context) => {
  if (skipWindowsMutation(context)) return;
  const { root, worktree } = makeRepo("workspace-maintenance-manifest-table-");
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    writeFileSync(join(worktree, "zig-out", "root.txt"), "root\n");
    const killed = await runKilledAtHook(
      ["clean", "build"],
      worktree,
      "after-clean-journal-create",
    );
    const journalPath = killed.payload.journalPath;
    const originalBytes = readFileSync(journalPath);
    const source = join(worktree, "zig-out");
    const cases = [
      ["traversal", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "../external-sentinel")],
      ["absolute", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "/tmp/external-sentinel")],
      ["a/../../x", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "a/../../x")],
      ["a/../b", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "a/../b")],
      ["repeated separators", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "a//b")],
      ["trailing separator", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "a/b/")],
      ["backslash traversal", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "..\\external-sentinel")],
      ["drive", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "C:/Windows/system32")],
      ["UNC", (journal) => forgeTraversalManifestEntry(journal.moves[0].manifest, "//server/share/victim")],
      ["duplicate root", (journal) => {
        const rootEntry = journal.moves[0].manifest.find((entry) => entry.relativePath === "");
        journal.moves[0].manifest.push({ ...rootEntry });
      }],
      ["missing root", (journal) => {
        journal.moves[0].manifest = journal.moves[0].manifest.filter((entry) => entry.relativePath !== "");
      }],
      ["orphan child", (journal) => {
        const forged = cloneManifestLeaf(journal.moves[0].manifest);
        forged.relativePath = "no-such-parent/child";
        journal.moves[0].manifest.push(forged);
      }],
      ["capture collisions", (journal) => {
        const move = journal.moves[0];
        const leaf = move.manifest.find((entry) => entry.type === "file" && !entry.relativePath.includes("/"));
        assert.ok(leaf);
        for (const entry of move.manifest) {
          if (entry.type === "directory") {
            entry.captureRelativePath = null;
            continue;
          }
          const slash = entry.relativePath.lastIndexOf("/");
          const parent = slash === -1 ? "" : entry.relativePath.slice(0, slash);
          const name = `.cap-${slash === -1 ? entry.relativePath : entry.relativePath.slice(slash + 1)}`;
          entry.captureRelativePath = parent ? `${parent}/${name}` : name;
        }
        move.manifest.push({ ...leaf, relativePath: "collision-sibling", captureRelativePath: leaf.captureRelativePath });
      }],
    ];
    for (const [name, mutate] of cases) {
      await context.test(name, () => {
        writeFileSync(journalPath, originalBytes);
        const journal = JSON.parse(readFileSync(journalPath, "utf8"));
        mutate(journal);
        recomputeCleanJournalAuthorization(journal);
        writeJson(journalPath, journal);
        const refused = run(["clean", "resume", journalPath, "--force"], worktree);
        assert.equal(refused.status, 3, `${name}: ${refused.stderr}`);
        assert.ok(existsSync(source), name);
        assert.equal(existsSync(journal.moves[0].destination), false, name);
      });
    }
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});
