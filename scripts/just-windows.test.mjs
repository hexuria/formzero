import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptsRoot = dirname(fileURLToPath(import.meta.url));
const powershell = process.platform === "win32" ? "powershell.exe" : "pwsh";

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function makeRepository() {
  const root = mkdtempSync(join(tmpdir(), "buwiz-windows-maintenance-test-"));
  const scripts = join(root, "scripts");
  mkdirSync(scripts);
  cpSync(join(scriptsRoot, "just-windows.ps1"), join(scripts, "just-windows.ps1"));
  cpSync(
    join(scriptsRoot, "workspace-maintenance.mjs"),
    join(scripts, "workspace-maintenance.mjs"),
  );
  writeFileSync(join(scripts, "app-identity.mjs"), [
    'import { mkdirSync, writeFileSync } from "node:fs";',
    'mkdirSync(".native", { recursive: true });',
    'writeFileSync(".native/identity-was-prepared", "unexpected mutation\\n");',
    'process.stdout.write(JSON.stringify({',
    '  appName: "fixture",',
    '  displayName: "Fixture",',
    '  bundleId: "invalid.example.fixture",',
    '  manifestPath: ".native/fixture.zig.zon",',
    '}));',
    "",
  ].join("\n"));
  writeFileSync(join(root, ".gitignore"), [
    ".native/", ".zig-cache/", "zig-cache/", "zig-pkg/", "zig-out/",
    "node_modules/", "coverage/", "test-results/", "scripts/news-sync/work/",
  ].join("\n") + "\n");
  writeFileSync(join(root, "README.md"), "fixture\n");
  mkdirSync(join(root, ".native"));
  writeFileSync(join(root, ".native", "sentinel"), "must remain unchanged\n");
  git(root, "init", "-b", "main");
  git(root, "config", "user.name", "Windows Maintenance Test");
  git(root, "config", "user.email", "windows-maintenance@example.invalid");
  git(root, "config", "commit.gpgsign", "false");
  git(root, "config", "core.hooksPath", "/dev/null");
  git(root, "add", ".gitignore", "README.md", "scripts");
  git(root, "commit", "-m", "fixture");
  return root;
}

function snapshot(root) {
  function walk(directory, prefix = "") {
    return readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .flatMap((entry) => {
        const relative = join(prefix, entry.name);
        if (entry.isDirectory()) return [`directory:${relative}`, ...walk(join(directory, entry.name), relative)];
        return [`file:${relative}:${readFileSync(join(directory, entry.name), "utf8")}`];
      });
  }
  return walk(root);
}

function runMaintenance(root, ...args) {
  return spawnSync(powershell, [
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", join(root, "scripts", "just-windows.ps1"),
    "maintenance",
    ...args,
  ], { cwd: root, encoding: "utf8" });
}

for (const [name, args, expectedStatus, expectedOutput] of [
  ["inventory", ["clean", "list", "--json"], 0, /"artifacts"/u],
  ["cleanup dry-run", ["clean", "build", "--dry-run"], 0, /Would clean/u],
  ["worktree inventory", ["worktree-remove"], 1, /Registered worktrees:/u],
]) {
  test(`Windows maintenance ${name} does not prepare app identity or mutate .native`, () => {
    const root = makeRepository();
    try {
      const nativeRoot = join(root, ".native");
      const before = snapshot(nativeRoot);
      const result = runMaintenance(root, ...args);
      assert.equal(result.status, expectedStatus, result.stderr || result.stdout);
      assert.match(`${result.stdout}\n${result.stderr}`, expectedOutput);
      assert.deepEqual(snapshot(nativeRoot), before);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
}
