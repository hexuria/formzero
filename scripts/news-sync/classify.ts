// Decides which issuances are deadline-extension circulars and therefore worth
// downloading and mining the PDF for. A miss costs nothing beyond the notice
// still being published without overrides; a false positive costs one wasted
// PDF fetch that the extractor then finds nothing in. Both are cheap, so this
// stays a plain lexical test with no scoring.

// Both an extension word and a deadline word must be present, in either order:
// BIR titles the extension circulars "Providing Extension of the Deadlines …"
// (extension first) but also "… Deadline … Extended to …" (deadline first).
const EXTENSION_WORD = String.raw`\bexten(?:d|ds|ded|ding|sion|sions)\b`;
const DEADLINE_WORD = String.raw`\bdeadlines?\b`;

const EXTENSION_THEN_DEADLINE = new RegExp(`${EXTENSION_WORD}[\\s\\S]*?${DEADLINE_WORD}`, "iu");
const DEADLINE_THEN_EXTENSION = new RegExp(`${DEADLINE_WORD}[\\s\\S]*?${EXTENSION_WORD}`, "iu");

/**
 * True when `subject` reads as a deadline-extension issuance. Whitespace is
 * collapsed first so line-wrapped or `&nbsp;`-padded subjects behave like the
 * single-line form.
 */
export function isDeadlineExtension(subject: string): boolean {
  const normalized = subject.replace(/\s+/gu, " ").trim();
  if (normalized === "") return false;
  return EXTENSION_THEN_DEADLINE.test(normalized) || DEADLINE_THEN_EXTENSION.test(normalized);
}
