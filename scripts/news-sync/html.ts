// Minimal, dependency-free HTML text extraction for the BIR CMS payloads.
//
// The CMS ships rich-text blobs authored in a WYSIWYG editor: nested <span>
// wrappers that split words in half (`p</span><span>ublishes`), Word-pasted
// `&nbsp;` runs, and one plain <table> for the yearly archive. Everything here
// is a pure function over a string; no I/O, no DOM, no network.

export type Anchor = {
  href: string;
  text: string;
};

// Only the entities the BIR payloads actually contain. Numeric references are
// handled generically below, so this table covers named forms only.
const NAMED_ENTITIES: ReadonlyMap<string, string> = new Map([
  ["amp", "&"],
  ["lt", "<"],
  ["gt", ">"],
  ["quot", '"'],
  ["apos", "'"],
  ["nbsp", " "],
  ["ensp", " "],
  ["emsp", " "],
  ["thinsp", " "],
  ["shy", ""],
  ["ndash", "–"],
  ["mdash", "—"],
  ["lsquo", "‘"],
  ["rsquo", "’"],
  ["ldquo", "“"],
  ["rdquo", "”"],
  ["hellip", "…"],
  ["bull", "•"],
  ["middot", "·"],
  ["deg", "°"],
  ["reg", "®"],
  ["copy", "©"],
  ["trade", "™"],
  ["ntilde", "ñ"],
  ["Ntilde", "Ñ"],
  ["aacute", "á"],
  ["eacute", "é"],
  ["iacute", "í"],
  ["oacute", "ó"],
  ["uacute", "ú"],
  ["Aacute", "Á"],
  ["Eacute", "É"],
  ["Iacute", "Í"],
  ["Oacute", "Ó"],
  ["Uacute", "Ú"],
  ["uuml", "ü"],
  ["Uuml", "Ü"],
]);

// Tags whose boundaries are word boundaries. Everything else (span, strong, a,
// em, sup, font, …) is inline and must vanish without inserting a space, or the
// CMS's mid-word <span> splits would corrupt the text.
const BLOCK_TAGS: ReadonlySet<string> = new Set([
  "address",
  "article",
  "aside",
  "blockquote",
  "br",
  "caption",
  "col",
  "colgroup",
  "dd",
  "div",
  "dl",
  "dt",
  "fieldset",
  "figcaption",
  "figure",
  "footer",
  "form",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "header",
  "hr",
  "li",
  "main",
  "nav",
  "ol",
  "p",
  "pre",
  "section",
  "table",
  "tbody",
  "td",
  "tfoot",
  "th",
  "thead",
  "tr",
  "ul",
]);

export function decodeEntities(text: string): string {
  // One pass, so `&amp;lt;` decodes to the literal text `&lt;` rather than `<`.
  return text.replace(
    /&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});/gu,
    (match: string, body: string): string => {
      if (body.startsWith("#")) {
        const hex = body[1] === "x" || body[1] === "X";
        const codePoint = Number.parseInt(hex ? body.slice(2) : body.slice(1), hex ? 16 : 10);
        if (!Number.isInteger(codePoint) || codePoint <= 0 || codePoint > 0x10ffff) {
          return match;
        }
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) return match;
        return String.fromCodePoint(codePoint);
      }
      return NAMED_ENTITIES.get(body) ?? match;
    },
  );
}

export function stripTags(html: string): string {
  const withoutComments = html.replace(/<!--[\s\S]*?-->/gu, "");
  const withoutScripts = withoutComments.replace(
    /<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/giu,
    " ",
  );
  return withoutScripts.replace(
    /<\/?([A-Za-z][A-Za-z0-9]*)\b[^>]*>/gu,
    (_match: string, name: string): string =>
      BLOCK_TAGS.has(name.toLowerCase()) ? " " : "",
  );
}

export function textOf(html: string): string {
  return decodeEntities(stripTags(html)).replace(/\s+/gu, " ").trim();
}

export function findAnchors(html: string): Anchor[] {
  const anchors: Anchor[] = [];
  for (const match of html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a\s*>/giu)) {
    const attributes = match[1] ?? "";
    const href = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/iu.exec(attributes);
    if (!href) continue;
    const raw = href[1] ?? href[2] ?? href[3] ?? "";
    anchors.push({ href: decodeEntities(raw).trim(), text: textOf(match[2] ?? "") });
  }
  return anchors;
}

// Slices the inner HTML of every element opened by `openPattern`. A cell/row
// ends at its own close tag, at the next sibling's open tag, or at the end of
// the input — CMS tables in the wild omit close tags often enough that a strict
// paired regex silently drops rows.
function sliceElements(html: string, openPattern: RegExp, closePattern: RegExp): string[] {
  const opens = [...html.matchAll(openPattern)];
  const slices: string[] = [];
  for (let index = 0; index < opens.length; index += 1) {
    const open = opens[index];
    const start = open.index + open[0].length;
    const next = opens[index + 1];
    const limit = next === undefined ? html.length : next.index;
    const segment = html.slice(start, limit);
    const close = closePattern.exec(segment);
    slices.push(close === null ? segment : segment.slice(0, close.index));
  }
  return slices;
}

export function splitTableRows(html: string): string[] {
  return sliceElements(html, /<tr\b[^>]*>/giu, /<\/tr\s*>/iu);
}

export function splitTableCells(rowHtml: string): string[] {
  return sliceElements(rowHtml, /<t[dh]\b[^>]*>/giu, /<\/t[dh]\s*>/iu);
}
