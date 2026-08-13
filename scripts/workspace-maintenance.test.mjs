import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, readlinkSync, readdirSync, realpathSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
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

async function waitForPath(path) {
  const deadline = Date.now() + 10_000;
  while (!existsSync(path)) {
    if (Date.now() >= deadline) throw new Error(`timed out waiting for ${path}`);
    await new Promise((resolveReady) => setTimeout(resolveReady, 20));
  }
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
    await waitForPath(marker);
    await mutate(JSON.parse(readFileSync(marker, "utf8")));
    writeFileSync(release, "continue\n");
    const result = await completed;
    return { ...result, stdout, stderr };
  } finally {
    if (!existsSync(release)) writeFileSync(release, "continue\n");
    if (child.exitCode === null) child.kill("SIGTERM");
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
    .update(JSON.stringify({ moves: receipt.moves, nativeSymlinks: receipt.nativeSymlinks }))
    .digest("hex");
  writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`);
}

test("clean with no target lists choices, exits 2, and changes nothing", () => {
  const { root, worktree } = makeRepo();
  try {
    seedArtifacts(worktree);
    const before = git(root, "worktree", "list", "--porcelain");
    const result = run(["clean"], worktree);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /choose a cleanup target; nothing was deleted/u);
    assert.match(result.stderr, new RegExp(worktree, "u"));
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

test("printed purge command safely quotes receipt paths containing apostrophes", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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

test("post-rename failure records the move and rolls the artifact back", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "rollback sentinel\n");
    const result = run(["clean", "build"], worktree, {
      NODE_ENV: "test",
      WORKSPACE_MAINTENANCE_TEST_FAIL_AT: "after-artifact-rename",
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /injected test failure/u);
    assert.equal(readFileSync(join(worktree, "zig-out", "bin", "app"), "utf8"), "rollback sentinel\n");
    const quarantineNamespace = join(dirname(worktree), ".buwiz-workspace-maintenance");
    const quarantineFiles = existsSync(quarantineNamespace)
      ? readdirSync(quarantineNamespace, { recursive: true })
      : [];
    assert.equal(quarantineFiles.some((name) => name.endsWith("receipt.json")), false);
    assert.equal(quarantineFiles.some((name) => name.includes(".deleting-")), false);
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("rollback refuses source-ancestor symlink drift and retains quarantine", async (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    assert.match(result.stderr, /rollback was incomplete|source ancestors changed|ENOTDIR/u);
    assert.equal(existsSync(join(external, "work", "download.pdf")), false);
    assert.match(result.stderr, /quarantine retained at (.+)/u);
    const retained = result.stderr.match(/quarantine retained at (.+?)(?::|\n)/u)?.[1];
    assert.ok(retained && existsSync(retained));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("direct clean succeeds when its caller does not hold the worktree", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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

test("clean refuses an artifact root symlink without touching its target", () => {
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

test("clean refuses a dangling artifact root symlink", () => {
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

test("clean refuses a nested symlink without touching its external target", () => {
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

test("clean native quarantines and purges generated identity links without following them", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    const preview = run(["clean", "purge", receipt, "--dry-run"], worktree);
    assert.equal(preview.status, 0, preview.stderr);
    assert.ok(existsSync(dirname(receipt)));
    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 0, purged.stderr);
    assert.equal(existsSync(dirname(receipt)), false);
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(assets, "asset-sentinel.txt"), "utf8"), "asset sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a replaced quarantined Native link and preserves both targets", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    const transaction = dirname(receipt);
    const quarantinedSrc = JSON.parse(readFileSync(receipt, "utf8")).moves[0].destination;
    const srcLink = join(quarantinedSrc, "identities", "fixture-identity", "src");
    assert.equal(realpathSync(srcLink), realpathSync(join(worktree, "src")));
    unlinkSync(srcLink);
    symlinkSync(attacker, srcLink);
    assert.equal(readlinkSync(srcLink), attacker);

    const purged = run(["clean", "purge", receipt, "--force"], worktree);
    assert.equal(purged.status, 3);
    assert.match(purged.stderr, /does not target its source worktree/u);
    assert.ok(existsSync(transaction));
    assert.equal(readFileSync(join(worktree, "src", "source-sentinel.native"), "utf8"), "source sentinel\n");
    assert.equal(readFileSync(join(attacker, "attacker-sentinel.txt"), "utf8"), "attacker sentinel\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a safe-looking Native link injected after quarantine", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    const transaction = dirname(receipt);
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

test("clean native refuses generated identity links to any other target", () => {
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

test("clean native refuses a generated identity link at any other depth", () => {
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

test("clean refuses a symlinked artifact ancestor without touching its target", () => {
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = dirname(receipt);

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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
  const { root, worktree } = makeRepo();
  try {
    mkdirSync(join(worktree, "zig-out", "bin"), { recursive: true });
    writeFileSync(join(worktree, "zig-out", "bin", "app"), "app\n");
    const cleaned = run(["clean", "build"], worktree);
    assert.equal(cleaned.status, 0, cleaned.stderr);
    const receipt = cleaned.stdout.match(/receipt: (.+receipt\.json)/u)?.[1];
    assert.ok(receipt);
    const transaction = dirname(receipt);
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
    assert.match(purged.stderr, /identity changed at tombstone boundary/u);
    assert.equal(readFileSync(replacementSentinel, "utf8"), "must survive\n");
    assert.ok(existsSync(join(original, "receipt.json")));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses an unrecorded regular file inside a destination bucket", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    assert.match(purged.stderr, /not named by the receipt/u);
    assert.ok(existsSync(dirname(receiptPath)));
    assert.equal(readFileSync(injected, "utf8"), "must not be purged\n");
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a same-bucket artifact omitted from the receipt", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    assert.match(purged.stderr, /not named by the receipt/u);
    assert.ok(existsSync(omittedDestination));
    assert.ok(existsSync(dirname(receiptPath)));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("purge refuses a receipt whose recorded artifact size was tampered", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
    assert.match(purged.stderr, /size does not match its receipt/u);
    assert.ok(existsSync(dirname(receiptPath)));
  } finally {
    rmSync(dirname(root), { recursive: true, force: true });
  }
});

test("worktree-remove requires one exact absolute registered path", () => {
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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

test("worktree-remove requires every cleanup receipt to be purged, even with force", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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

test("dirty and unmerged worktrees require force, while immutable guards still hold", (context) => {
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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

test("force cannot remove the current worktree or a worktree in an in-progress Git operation", () => {
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

test("protected ignored data blocks worktree removal even with force", () => {
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

test("any ignored content blocks worktree removal, including catalog artifacts and local backups", () => {
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

test("cross-worktree clean rejects primary, current, and a parent with a registered descendant", () => {
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
  if (process.platform === "win32") context.skip("Windows mutation is intentionally unsupported");
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
