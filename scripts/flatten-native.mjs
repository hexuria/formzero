#!/usr/bin/env node

import { readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "..");
const outputPath = "src/app.native";
const maxRuntimeWatchedMarkupBytes = 256 * 1024;

// Native markup templates must be defined before their first use. Keep this
// order explicit and stable: shared components, seven main pages plus the
// reviewer gallery, ten form pages, seven auxiliary surfaces, then the
// editable root.
const sourceGroups = [
  {
    name: "shared components",
    files: [
      "src/components/shell.native",
      "src/components/multi-select-combobox.native",
    ],
  },
  {
    name: "main pages",
    files: [
      "src/pages/global-dashboard.fragment",
      "src/pages/taxpayer-dashboard.native",
      "src/pages/profile-setup.native",
      "src/pages/import-data.native",
      "src/pages/background-tasks.native",
      "src/pages/tax-calendar.native",
      "src/pages/settings.native",
      "src/pages/screen-gallery.native",
    ],
  },
  {
    name: "forms",
    files: [
      "src/pages/forms/0605.native",
      "src/pages/forms/0619-e.native",
      "src/pages/forms/0619-f.native",
      "src/pages/forms/1601-c.native",
      "src/pages/forms/1701.native",
      "src/pages/forms/1701q.native",
      "src/pages/forms/1702-mx.native",
      "src/pages/forms/1702-rt.native",
      "src/pages/forms/2550q.native",
      "src/pages/forms/2551q.native",
    ],
  },
  {
    name: "auxiliary surfaces",
    files: [
      "src/pages/auxiliary/lock-screen.native",
      "src/pages/auxiliary/profile-auth-overlay.native",
      "src/pages/auxiliary/admin-auth-overlay.native",
      "src/pages/auxiliary/command-palette.native",
      "src/pages/auxiliary/html-print-preview.native",
      "src/pages/auxiliary/email-confirmation.native",
      "src/pages/auxiliary/background-task-debug-log.native",
    ],
  },
  {
    name: "root",
    files: ["src/app-root.fragment"],
  },
];

const sourceFiles = sourceGroups.flatMap((group) => group.files);
const generatedTemplateIncludes = new Set([
  "multi-select-combobox",
  "tax-profile-form-context",
  "taxpayer-form-library-section",
  "form-field",
  "form-field-bound",
]);

function normalizeFragment(source) {
  return source.replace(/\r\n?/g, "\n").replace(/\n+$/u, "");
}

// Native SDK's runtime markup watcher reads at most 256 KiB. Keep editable
// fragments readable, but remove generated-only indentation and blank lines so
// a hot reload never truncates an otherwise valid document.
function compactGeneratedMarkup(source) {
  return source
    .split("\n")
    .map((line) => line.trimStart())
    .filter((line) => line.length > 0)
    .join("\n");
}

/**
 * A `.native` source is also linted as a standalone document. Cross-fragment
 * `<use>` nodes therefore look undefined even though their shared template is
 * ordered before them in the generated application. Keep that source
 * boundary truthful with an explicit comment directive, expanded only while
 * assembling `app.native`.
 */
function expandGeneratedTemplateIncludes(source, relativePath) {
  return source.replace(
    /<!--\s*@include-template\s+([A-Za-z][A-Za-z0-9-]*)([\s\S]*?)-->/gu,
    (_, templateName, rawAttributes) => {
      if (!generatedTemplateIncludes.has(templateName)) {
        throw new Error(
          `Unknown generated template include ${templateName} in ${relativePath}`,
          );
      }
      const attributes = rawAttributes.trim();
      if (/[<>]/u.test(attributes)) {
        throw new Error(
          `Invalid generated template attributes for ${templateName} in ${relativePath}`,
        );
      }
      return attributes.length === 0
        ? `<use template="${templateName}"/>`
        : `<use template="${templateName}"
${attributes}/>`;
    },
  );
}

async function readRequiredFile(relativePath) {
  const absolutePath = path.join(projectRoot, relativePath);

  let fileStats;
  try {
    fileStats = await stat(absolutePath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      throw new Error(`Missing required Native source: ${relativePath}`, {
        cause: error,
      });
    }
    throw error;
  }

  if (!fileStats.isFile()) {
    throw new Error(`Native source is not a regular file: ${relativePath}`);
  }

  const source = normalizeFragment(await readFile(absolutePath, "utf8"));
  rejectXmlEntities(source, relativePath);
  // Include directives are themselves comments, so they must be expanded
  // before comments are dropped.
  return stripComments(expandGeneratedTemplateIncludes(source, relativePath));
}

// Comments in a fragment explain the markup to whoever edits it, and the
// sources keep them. The runtime never reads them, so shipping them inside
// app.native spends a budget the hot-reload watcher enforces at 256 KiB.
function stripComments(source) {
  return source
    .replace(/<!--[\s\S]*?-->/gu, "")
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .join("\n");
}

// The markup engine copies text through verbatim: it has no XML entity
// decoder, so `&amp;` reaches the screen as those five characters. This is
// easy to write by reflex and invisible until someone looks at the running
// app, so refuse it at generation time and name the line.
const xmlEntityPattern = /&(?:#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/;

function rejectXmlEntities(source, relativePath) {
  const lines = source.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const match = xmlEntityPattern.exec(lines[index]);
    if (!match) continue;
    throw new Error(
      `${relativePath}:${index + 1}: this markup never decodes XML entities, ` +
        `so ${match[0]} renders literally - write the character itself`,
    );
  }
}

// The one thing a human who opens the generated file needs to know. The
// concatenation order lives in `sourceGroups` above, which is its own
// authority; repeating all 28 entries here only spent runtime budget.
function generatedHeader() {
  return [
    "<!-- GENERATED FILE - DO NOT EDIT. Edit the sources listed in",
    "     scripts/flatten-native.mjs, then run `npm run generate`. -->",
  ].join("\n");
}

async function main() {
  const fragments = [];
  for (const relativePath of sourceFiles) {
    fragments.push(await readRequiredFile(relativePath));
  }

  const generated = `${compactGeneratedMarkup(
    `${generatedHeader()}\n${fragments.join("\n")}`,
  )}\n`;
  const generatedBytes = Buffer.byteLength(generated, "utf8");
  if (generatedBytes >= maxRuntimeWatchedMarkupBytes) {
    throw new Error(
      `${outputPath} is ${generatedBytes} bytes; Native runtime hot reload ` +
        `requires less than ${maxRuntimeWatchedMarkupBytes} bytes`,
    );
  }
  const absoluteOutputPath = path.join(projectRoot, outputPath);

  let current = null;
  try {
    current = await readFile(absoluteOutputPath, "utf8");
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }

  // Report the remaining budget on every run. The ceiling is enforced above,
  // but a number only seen when the build breaks arrives too late to plan
  // around.
  const headroom = maxRuntimeWatchedMarkupBytes - generatedBytes;
  const budget = `${generatedBytes} bytes, ${headroom} free`;

  if (current === generated) {
    process.stdout.write(`${outputPath} is already up to date (${budget}).\n`);
    return;
  }

  await writeFile(absoluteOutputPath, generated, "utf8");
  process.stdout.write(
    `Generated ${outputPath} from ${sourceFiles.length} ordered sources ` +
      `(${budget}).\n`,
  );
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`flatten-native: ${message}\n`);
  process.exitCode = 1;
});
