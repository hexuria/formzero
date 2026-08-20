#!/usr/bin/env node

import { readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, "..");
const rootOutputPath = "src/app.native";
const rootSourcePath = "src/app-root.fragment";
const maxRuntimeWatchedMarkupBytes = 256 * 1024;

// Native markup templates must be defined before their first use. Keep this
// order explicit and stable: shared components, seven main pages plus the
// reviewer gallery, eleven form pages, and seven auxiliary surfaces. Each group
// becomes one bounded Native import; the editable root stays in app.native.
const sourceGroups = [
  {
    name: "shared components",
    outputPath: "src/app-shared.generated.native",
    imports: [],
    files: [
      "src/components/shell.native",
      "src/components/multi-select-combobox.native",
    ],
  },
  {
    name: "main pages",
    outputPath: "src/app-pages.generated.native",
    imports: ["src/app-shared.generated.native"],
    files: [
      "src/pages/global-dashboard.fragment",
      "src/pages/taxpayer-dashboard.native",
      "src/pages/profile-setup.native",
      "src/pages/tax-form-profile.native",
      "src/pages/taxpayer-dashboard-page.native",
      "src/pages/import-data.native",
      "src/pages/background-tasks.native",
      "src/pages/tax-calendar.native",
      "src/pages/settings.native",
      "src/pages/screen-gallery.native",
    ],
  },
  {
    name: "forms",
    outputPath: "src/app-forms.generated.native",
    imports: ["src/app-shared.generated.native"],
    files: [
      "src/pages/forms/0605.native",
      "src/pages/forms/0619-e.native",
      "src/pages/forms/0619-f.native",
      "src/pages/forms/1601-c.native",
      "src/pages/forms/1601-eq.native",
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
    outputPath: "src/app-auxiliary.generated.native",
    imports: [],
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
];

const sourceFiles = [
  ...sourceGroups.flatMap((group) => group.files),
  rootSourcePath,
];
const generatedTemplateIncludes = new Set([
  "d-s",
  "multi-select-combobox",
  "profile-calendar-multi-select-combobox",
  "tax-profile-form-context",
  "taxpayer-calendar-section",
  "taxpayer-form-library-section",
  "form-field",
  "form-field-bound",
  "profile-setup-content",
]);

function normalizeFragment(source) {
  return source.replace(/\r\n?/g, "\n").replace(/\n+$/u, "");
}

// Native SDK's runtime markup watcher reads at most 256 KiB. Keep editable
// fragments readable, but remove generated-only indentation and blank lines so
// a hot reload never truncates an otherwise valid document.
function compactGeneratedMarkup(source, templateAliases) {
  return applyTemplateAliases(source, templateAliases)
    .split("\n")
    .map((line) => line.trimStart())
    .filter((line) => line.length > 0)
    .join("\n")
    // Inter-element line breaks are source formatting, not rendered text.
    // Removing only `>\n<` boundaries preserves multi-line attribute and
    // text content while reclaiming enough of the watcher's fixed 256 KiB
    // budget for independently editable page fragments.
    .replace(/>\n(?=<)/gu, ">")
    // Attribute layout is also source-only. Collapse whitespace inside tags
    // while preserving quoted values and all text-node whitespace. This buys
    // room for additional independently testable templates without changing
    // what the Native parser or accessibility tree receives.
    .replace(/<[^>]*>/gsu, compactTagWhitespace)
    // Native text nodes render ordinary source line breaks as ordinary
    // spacing. Normalize those generated-only boundaries to one space and
    // drop indentation at the node edges; editable fragments stay readable.
    .replace(/>([^<]+)</gsu, (_, text) => {
      const compact = text.replace(/\s+/gu, " ").trim();
      return `>${compact}<`;
    });
}

function collectTemplateAliases(sources) {
  const aliases = new Map();
  const seen = new Set();
  for (const source of sources) {
    for (const match of source.matchAll(/<template\s+name="([^"]+)"/gu)) {
      const name = match[1];
      if (seen.has(name)) continue;
      seen.add(name);
      aliases.set(name, compactTemplateAlias(aliases.size));
    }
  }
  return aliases;
}

function applyTemplateAliases(source, aliases) {
  return source
    .replace(
      /<template(\s+)name\s*=\s*"([^"]+)"/gu,
      (match, spacing, name) =>
        aliases.has(name)
          ? `<template${spacing}name="${aliases.get(name)}"`
          : match,
    )
    .replace(/\btemplate\s*=\s*"([^"]+)"/gu, (match, name) =>
      aliases.has(name) ? `template="${aliases.get(name)}"` : match,
    );
}

// Template names are generated-only linkage. A base-26 identifier is both
// valid Native markup and shorter than the previous `t0`/`t10` sequence,
// which matters because the runtime watcher has a hard 256 KiB ceiling.
function compactTemplateAlias(index) {
  const alphabet = "abcdefghijklmnopqrstuvwxyz";
  let value = index;
  let alias = "";
  do {
    alias = alphabet[value % alphabet.length] + alias;
    value = Math.floor(value / alphabet.length) - 1;
  } while (value >= 0);
  return alias;
}

function compactTagWhitespace(tag) {
  if (tag.startsWith("<!--")) return tag;
  let output = "";
  let quote = null;
  let pendingSpace = false;
  for (const character of tag) {
    if (quote !== null) {
      output += character;
      if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") {
      if (pendingSpace && output.at(-1) !== "<") output += " ";
      pendingSpace = false;
      quote = character;
      output += character;
      continue;
    }
    if (/\s/u.test(character)) {
      pendingSpace = true;
      continue;
    }
    if (
      pendingSpace &&
      output.at(-1) !== "<" &&
      character !== ">" &&
      character !== "/"
    ) {
      output += " ";
    }
    pendingSpace = false;
    output += character;
  }
  return output;
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
  return "<!-- GENERATED; edit fragments and run npm run generate. -->";
}

function relativeImportPath(outputPath, importedOutputPath) {
  const relativePath = path.posix.relative(
    path.posix.dirname(outputPath),
    importedOutputPath,
  );
  return relativePath.length > 0 ? relativePath : path.posix.basename(outputPath);
}

function generatedOutput(outputPath, imports, body) {
  const importLines = imports.map(
    (importedOutputPath) =>
      `<import src="${relativeImportPath(outputPath, importedOutputPath)}"/>`,
  );
  return `${[generatedHeader(), ...importLines, body].join("\n")}\n`;
}

function firstMismatch(left, right) {
  const sharedLength = Math.min(left.length, right.length);
  for (let index = 0; index < sharedLength; index += 1) {
    if (left[index] !== right[index]) return index;
  }
  return sharedLength;
}

async function main() {
  const sources = new Map();
  for (const relativePath of sourceFiles) {
    sources.set(relativePath, await readRequiredFile(relativePath));
  }

  // Alias collection follows the historical monolith's exact source order.
  // Applying this one map to every shard keeps template definitions and uses
  // byte-for-byte identical once Native resolves the imports.
  const aliases = collectTemplateAliases(
    sourceFiles.map((relativePath) => sources.get(relativePath)),
  );
  const compactFiles = (files) =>
    compactGeneratedMarkup(
      files.map((relativePath) => sources.get(relativePath)).join("\n"),
      aliases,
    );

  const groupBodies = sourceGroups.map((group) => compactFiles(group.files));
  const rootBody = compactFiles([rootSourcePath]);
  const legacyBody = compactFiles(sourceFiles);
  const modularBody = [...groupBodies, rootBody].join("");
  if (modularBody !== legacyBody) {
    const mismatch = firstMismatch(modularBody, legacyBody);
    throw new Error(
      `generated shards diverge from the legacy monolith at byte ${mismatch}`,
    );
  }

  const outputs = sourceGroups.map((group, index) => ({
    path: group.outputPath,
    source: generatedOutput(group.outputPath, group.imports, groupBodies[index]),
    sourceCount: group.files.length,
  }));
  outputs.push({
    path: rootOutputPath,
    source: generatedOutput(
      rootOutputPath,
      sourceGroups.map((group) => group.outputPath),
      rootBody,
    ),
    sourceCount: 1,
  });

  // The watcher enforces the cap per file. Validate the complete output set
  // before touching any file so a failed generation cannot leave a mixed
  // monolithic/modular state behind.
  for (const output of outputs) {
    output.bytes = Buffer.byteLength(output.source, "utf8");
    output.headroom = maxRuntimeWatchedMarkupBytes - output.bytes;
    if (output.headroom <= 0) {
      throw new Error(
        `${output.path} is ${output.bytes} bytes; Native runtime hot reload ` +
          `requires less than ${maxRuntimeWatchedMarkupBytes} bytes`,
      );
    }
  }

  for (const output of outputs) {
    const absoluteOutputPath = path.join(projectRoot, output.path);
    let current = null;
    try {
      current = await readFile(absoluteOutputPath, "utf8");
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }

    if (current === output.source) {
      process.stdout.write(
        `${output.path} is already up to date ` +
          `(${output.bytes} bytes, ${output.headroom} free).\n`,
      );
      continue;
    }

    await writeFile(absoluteOutputPath, output.source, "utf8");
    process.stdout.write(
      `Generated ${output.path} from ${output.sourceCount} ordered sources ` +
        `(${output.bytes} bytes, ${output.headroom} free).\n`,
    );
  }

  const minimumHeadroom = Math.min(...outputs.map((output) => output.headroom));
  process.stdout.write(
    `Minimum Native markup watcher headroom: ${minimumHeadroom} bytes.\n`,
  );
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`flatten-native: ${message}\n`);
  process.exitCode = 1;
});
