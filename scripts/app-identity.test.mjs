import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  BASE_IDENTITY,
  prepareIdentity,
  renderManifest,
  resolveBuildRef,
  resolveIdentity,
  sanitizeRef,
} from "./app-identity.mjs";

test("main keeps the canonical production identity", () => {
  const identity = resolveIdentity({ ref: "refs/heads/main" });
  assert.equal(identity.isMain, true);
  assert.equal(identity.appName, "buwiz");
  assert.equal(identity.displayName, "Buwiz App");
  assert.equal(identity.bundleId, "dev.goldcoders.buwiz");
  assert.equal(identity.shellRole, "Buwiz App application");
});

test("branch identity is readable, deterministic, and collision resistant", () => {
  const ref = "feature/TIN & Filing Scope";
  const hash = createHash("sha256").update(ref).digest("hex").slice(0, 12);
  const identity = resolveIdentity({ ref });
  assert.equal(identity.slug, `feature-tin-filing-scope-${hash}`);
  assert.equal(identity.appName, `buwiz-feature-tin-filing-scope-${hash}`);
  assert.equal(identity.displayName, `Buwiz App — feature-tin-filing-scope-${hash}`);
  assert.equal(
    identity.bundleId,
    `dev.goldcoders.buwiz.feature-tin-filing-scope-${hash}`,
  );
  assert.equal(
    identity.shellRole,
    "Buwiz App application",
  );
  assert.notEqual(sanitizeRef("feature/a"), sanitizeRef("feature-a"));
  assert.notEqual(sanitizeRef("Feature/A"), sanitizeRef("feature/a"));
});

test("punctuation, unicode, numeric starts, and long refs stay portable", () => {
  assert.match(sanitizeRef("123/!!!"), /^branch-123-[a-f0-9]{12}$/);
  assert.match(sanitizeRef("🔥/税"), /^branch-[a-f0-9]{12}$/);
  const identity = resolveIdentity({ ref: `feature/${"very-long-name-".repeat(20)}` });
  assert.ok(identity.appName.length <= 51);
  assert.match(identity.appName, /^buwiz-[a-z][a-z0-9-]+-[a-f0-9]{12}$/);
});

test("CI head ref wins and detached HEAD fails closed without an explicit ref", () => {
  assert.equal(
    resolveBuildRef({
      env: {
        GITHUB_HEAD_REF: "feature/pr-head",
        GITHUB_REF_NAME: "123/merge",
      },
      repositoryRoot: "/unused",
      detectGitBranch: () => null,
    }),
    "feature/pr-head",
  );
  assert.throws(
    () => resolveBuildRef({
      env: {},
      repositoryRoot: "/unused",
      detectGitBranch: () => null,
    }),
    /Set BUWIZ_BUILD_REF/,
  );
});

test("an attached branch cannot be overridden into the production identity", () => {
  assert.equal(
    resolveBuildRef({
      env: {},
      repositoryRoot: "/unused",
      detectGitBranch: () => "feature/attached",
    }),
    "feature/attached",
  );
  assert.throws(
    () => resolveBuildRef({
      env: { BUWIZ_BUILD_REF: "main" },
      repositoryRoot: "/unused",
      detectGitBranch: () => "feature/attached",
    }),
    /does not match the checked-out branch/,
  );
});

test("remote-looking local branches stay isolated from explicit remote refs", () => {
  assert.equal(resolveIdentity({ ref: "origin/main" }).isMain, false);
  assert.equal(resolveIdentity({ ref: "refs/heads/origin/main" }).isMain, false);
  assert.equal(resolveIdentity({ ref: "refs/remotes/origin/main" }).isMain, true);
});

test("the CLI rejects ref overrides that could bypass checkout identity", () => {
  const script = fileURLToPath(new URL("./app-identity.mjs", import.meta.url));
  const result = spawnSync(process.execPath, [script, "resolve", "--ref", "main"], {
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unknown argument: --ref/);
});

test("manifest preparation cannot override an attached checkout branch", () => {
  const root = mkdtempSync(join(tmpdir(), "buwiz-app-identity-"));
  try {
    mkdirSync(join(root, "src"));
    mkdirSync(join(root, "assets"));
    writeFileSync(
      join(root, "app.zon"),
      `.{\n.id = "old.id",\n.name = "old",\n.display_name = "Old",\n.shell = .{ .windows = .{ .{\n.title = "Old",\n.views = .{ .{\n.role = "Old application",\n.accessibility_label = "Old",\n}, },\n}, }, },\n}\n`,
    );
    execFileSync("git", ["init", "--quiet"], { cwd: root });
    execFileSync(
      "git",
      ["symbolic-ref", "HEAD", "refs/heads/feature/attached"],
      { cwd: root },
    );

    const identity = prepareIdentity({
      repositoryRoot: root,
      env: {},
      ref: "main",
      detectGitBranch: () => "main",
    });

    assert.equal(identity.ref, "feature/attached");
    assert.equal(identity.isMain, false);
    assert.match(identity.appName, /^buwiz-feature-attached-[a-f0-9]{12}$/);
    assert.match(
      readFileSync(join(root, identity.manifestPath), "utf8"),
      new RegExp(`\\.name = ${JSON.stringify(identity.appName)}`),
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("generated manifest uses one coherent identity", () => {
  const source = `.{\n.id = "old.id",\n.name = "old",\n.display_name = "Old",\n.shell = .{ .windows = .{ .{\n.title = "Old",\n.views = .{ .{\n.role = "Old application",\n.accessibility_label = "Old",\n}, },\n}, }, },\n}\n`;
  const identity = {
    ...BASE_IDENTITY,
    appName: "buwiz-review-12345678",
    displayName: "Buwiz App — review-12345678",
    bundleId: "dev.goldcoders.buwiz.review-12345678",
    shellRole: "Buwiz App application",
  };
  const rendered = renderManifest(source, identity);
  assert.match(rendered, /\.id = "dev\.goldcoders\.buwiz\.review-12345678"/);
  assert.match(rendered, /\.name = "buwiz-review-12345678"/);
  assert.match(rendered, /\.title = "Buwiz App — review-12345678"/);
  assert.match(rendered, /\.role = "Buwiz App application"/);
});

test("the formatted source manifest renders without changing its indentation", () => {
  const source = readFileSync(new URL("../app.zon", import.meta.url), "utf8");
  const identity = resolveIdentity({ ref: "feature/formatted-manifest" });
  const rendered = renderManifest(source, identity);
  assert.match(rendered, /^  \.id = "dev\.goldcoders\.buwiz\./m);
  assert.match(rendered, /^  \.name = "buwiz-feature-formatted-manifest-/m);
  assert.match(rendered, /\.role = "Buwiz App application",/m);
});
