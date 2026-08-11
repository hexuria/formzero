// OCR noise tolerance for the scanned BIR issuance PDFs.
//
// RMC PDFs carry a machine-OCR text layer whose damage is systematic: digits
// become letter lookalikes (`4l`, `RDONo.T-`, `I 16`), spaces get injected
// inside tokens (`06 1 9-F`), and month names lose two characters
// (`A]ugttst`, `Aueust`). These helpers are deliberately narrow: apply them to
// a token you already believe is a number or a date, never to whole prose.
//
// Every repair is reported through `notes` so the review report can show the
// reasoning chain that produced a date.

const DIGIT_LOOKALIKES: ReadonlyMap<string, string> = new Map([
  ["l", "1"],
  ["I", "1"],
  ["|", "1"],
  ["O", "0"],
  ["o", "0"],
  ["S", "5"],
  ["B", "8"],
  ["T", "7"],
  ["Z", "2"],
  ["G", "6"],
]);

const MONTH_NAMES: readonly string[] = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
];

const MAX_MONTH_DISTANCE = 2;

// Characters an OCR'd digit can appear as; drives the day/year token classes.
const DIGITISH = "0-9OolI|SBTZG";

const NOISY_DATE_PATTERN = new RegExp(
  String.raw`([A-Za-z][A-Za-z\[\]().,]{1,13}?)\s+` +
    String.raw`([${DIGITISH}](?:\s?[${DIGITISH}])?)\s*[,.]?\s*` +
    String.raw`([${DIGITISH}](?:\s?[${DIGITISH}]){3})`,
  "gu",
);

export type NoisyDate = {
  iso: string;
  notes: string[];
};

/**
 * Maps digit lookalikes to digits and removes every inner space.
 * `"06 1 9-F"` -> `"0619-F"`, `"I 16"` -> `"116"`, `"1 l"` -> `"11"`.
 * Characters outside the lookalike table pass through untouched, so callers
 * must still validate the result before trusting it as a number.
 */
export function normalizeDigits(text: string): string {
  let normalized = "";
  for (const character of text) {
    if (/\s/u.test(character)) continue;
    normalized += DIGIT_LOOKALIKES.get(character) ?? character;
  }
  return normalized;
}

/**
 * Glyphs the OCR emits in place of a letter it could not resolve: any
 * punctuation or symbol, plus the thin-stroke letters that punctuation is
 * routinely confused with. Both damage classes appear in one line of the
 * RMC 62-2026 table header — `Due Date` printed as `I)ue Date` (`D` became
 * `I` + `)`) and `Extended Due Date` as `E:rtended Due Date` (`x` became
 * `:` + `r`).
 */
const GLYPH_DEBRIS = String.raw`(?:[^\p{L}\p{N}\s]|[ilIjrt1])`;

/** One letter the OCR lost, on which it spent one or two glyphs. */
const DAMAGED_LETTER = `${GLYPH_DEBRIS}{1,2}`;

/**
 * Regex source matching `word` as printed, or with any *one* of its letters
 * replaced by OCR debris. One damaged letter per word is the tolerance the
 * scanned circulars actually need, and it keeps the pattern anchored on every
 * remaining letter — `Extended` still demands seven exact letters, so widening
 * the probe cannot turn arbitrary prose into a table header.
 *
 * Callers must apply the `i` and `u` flags; the source itself carries no case
 * folding.
 */
export function ocrTolerantWord(word: string): string {
  if (!/^[A-Za-z]+$/u.test(word)) {
    throw new Error(`ocrTolerantWord expects a plain alphabetic word, got "${word}"`);
  }
  // Exact spelling first, so a clean header never pays for the tolerance.
  const spellings = [word];
  for (let index = 0; index < word.length; index += 1) {
    spellings.push(word.slice(0, index) + DAMAGED_LETTER + word.slice(index + 1));
  }
  return `(?:${spellings.join("|")})`;
}

/** `ocrTolerantWord` over every word of a phrase, separated by whitespace. */
export function ocrTolerantPhrase(phrase: string): string {
  return phrase
    .trim()
    .split(/\s+/u)
    .map(ocrTolerantWord)
    .join(String.raw`\s+`);
}

export function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  let previous = Array.from({ length: b.length + 1 }, (_value, index) => index);
  let current = new Array<number>(b.length + 1).fill(0);

  for (let i = 1; i <= a.length; i += 1) {
    current[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const substitution = previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1);
      const deletion = previous[j] + 1;
      const insertion = current[j - 1] + 1;
      current[j] = Math.min(substitution, deletion, insertion);
    }
    const swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/**
 * Resolves an OCR-damaged month token to a 1-12 month number, comparing only
 * the letters (brackets and punctuation are dropped first) with a Levenshtein
 * budget of 2. Ambiguous ties resolve to null rather than guessing.
 */
export function fuzzyMonth(token: string): number | null {
  const letters = token.replace(/[^A-Za-z]/gu, "").toLowerCase();
  if (letters.length < 3) return null;

  let best: number | null = null;
  let bestDistance = Number.POSITIVE_INFINITY;
  let ambiguous = false;

  for (let index = 0; index < MONTH_NAMES.length; index += 1) {
    const distance = levenshtein(letters, MONTH_NAMES[index]);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index + 1;
      ambiguous = false;
    } else if (distance === bestDistance) {
      ambiguous = true;
    }
  }

  if (best === null || bestDistance > MAX_MONTH_DISTANCE) return null;
  if (ambiguous && bestDistance > 0) return null;
  return best;
}

function titleCase(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

function daysInMonth(year: number, month: number): number {
  const lengths = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return lengths[month - 1];
}

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

/**
 * Parses the first `<month> <day>[,.] <year>` literal in `text`, tolerating OCR
 * damage on all three tokens, and rejects impossible civil dates. Returns null
 * when nothing in the text yields a valid date, so callers can fall back to a
 * document-level anchor instead of publishing a guess.
 */
export function parseNoisyDate(text: string): NoisyDate | null {
  NOISY_DATE_PATTERN.lastIndex = 0;
  for (const match of text.matchAll(NOISY_DATE_PATTERN)) {
    const monthToken = match[1];
    const dayToken = match[2];
    const yearToken = match[3];

    const month = fuzzyMonth(monthToken);
    if (month === null) continue;

    const dayDigits = normalizeDigits(dayToken);
    const yearDigits = normalizeDigits(yearToken);
    if (!/^[0-9]{1,2}$/u.test(dayDigits)) continue;
    if (!/^[0-9]{4}$/u.test(yearDigits)) continue;

    const day = Number.parseInt(dayDigits, 10);
    const year = Number.parseInt(yearDigits, 10);
    if (year < 1900 || year > 2999) continue;
    if (day < 1 || day > daysInMonth(year, month)) continue;

    const notes: string[] = [];
    const canonicalMonth = MONTH_NAMES[month - 1];
    const monthLetters = monthToken.replace(/[^A-Za-z]/gu, "").toLowerCase();
    if (monthLetters !== canonicalMonth) {
      notes.push(
        `OCR month "${monthToken}" read as ${titleCase(canonicalMonth)} ` +
          `(edit distance ${levenshtein(monthLetters, canonicalMonth)})`,
      );
    }
    if (dayToken !== dayDigits) {
      notes.push(`OCR day "${dayToken}" read as ${dayDigits}`);
    }
    if (yearToken !== yearDigits) {
      notes.push(`OCR year "${yearToken}" read as ${yearDigits}`);
    }

    return { iso: `${yearDigits}-${pad2(month)}-${pad2(day)}`, notes };
  }
  return null;
}
