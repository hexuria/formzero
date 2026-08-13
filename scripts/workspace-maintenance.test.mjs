import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function makeRepo() {
  const fixture = mkdtempSync(join(tmpdir(), "workspace-maintenance-test-"));
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

test("clean invoked from its own worktree does not mistake itself for an active app", (context) => {
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

test("the public Just clean recipe fails closed while Just holds the worktree", (context) => {
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
      `    @WORKSPACE_MAINTENANCE_CWD=\"$(git rev-parse --show-toplevel)\" node ${JSON.stringify(scriptPath)} clean \"$@\"`,
      "",
    ].join("\n"));
    const result = spawnSync("just", ["-f", justfile, "clean", "build"], {
      cwd: worktree,
      encoding: "utf8",
      env: process.env,
    });
    assert.equal(result.status, 3);
    assert.match(result.stderr, /process state.*active/u);
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
