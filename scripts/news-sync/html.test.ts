import assert from "node:assert/strict";
import test from "node:test";

import {
  decodeEntities,
  findAnchors,
  splitTableCells,
  splitTableRows,
  stripTags,
  textOf,
} from "./html.ts";

test("decodeEntities decodes the entity forms the CMS emits", () => {
  assert.equal(decodeEntities("R&amp;D"), "R&D");
  assert.equal(decodeEntities("&lt;b&gt;"), "<b>");
  assert.equal(decodeEntities("&quot;quoted&quot;"), '"quoted"');
  assert.equal(decodeEntities("it&apos;s"), "it's");
  assert.equal(decodeEntities("a&nbsp;b"), "a b");
  assert.equal(decodeEntities("Malaca&ntilde;ang"), "Malacañang");
  assert.equal(decodeEntities("&#39;"), "'");
  assert.equal(decodeEntities("&#x41;"), "A");
});

test("decodeEntities is a single pass, so &amp;lt; stays literal text", () => {
  assert.equal(decodeEntities("&amp;lt;"), "&lt;");
});

test("decodeEntities leaves unknown or malformed references untouched", () => {
  assert.equal(decodeEntities("&notarealentity;"), "&notarealentity;");
  assert.equal(decodeEntities("100% &  more"), "100% &  more");
});

test("stripTags drops inline tags without splitting words", () => {
  // The CMS splits words across <span> boundaries; inserting a space here would
  // corrupt the subject text of RMC 87-2026 into "p ublishes".
  assert.equal(stripTags("p</span><span>ublishes"), "publishes");
  assert.equal(stripTags("<strong>RMC No. 89-2026</strong>"), "RMC No. 89-2026");
});

test("stripTags treats block boundaries as word boundaries", () => {
  assert.equal(textOf("<p>first</p><p>second</p>"), "first second");
  assert.equal(textOf("a<br />b"), "a b");
  assert.equal(textOf("<td>one</td><td>two</td>"), "one two");
});

test("stripTags removes comments and script/style bodies", () => {
  assert.equal(textOf("<!-- hidden -->visible"), "visible");
  assert.equal(textOf("<style>p{color:red}</style>text"), "text");
  assert.equal(textOf("<script>var a = 1 < 2;</script>text"), "text");
});

test("textOf strips, decodes, collapses whitespace and trims", () => {
  const html =
    '<p class="MsoNormal"><span><strong>Revenue Memorandum Circular No. 089-2026 </strong>' +
    "Providing Extension of the Deadlines.&nbsp;" +
    '<a title="more" href="https://example.test/a.pdf">more</a>&nbsp;</span></p>';
  assert.equal(
    textOf(html),
    "Revenue Memorandum Circular No. 089-2026 Providing Extension of the Deadlines. more",
  );
});

test("findAnchors returns each href with its decoded link text", () => {
  const html =
    '<a title="more" href="https://bir-cdn.bir.gov.ph/BIR/pdf/RMC No. 88-2026_redacted.pdf" ' +
    'target="_blank" rel="noopener">more</a> |&nbsp;' +
    "<a href='https://bir-cdn.bir.gov.ph/BIR/pdf/MC No. 122 s.2026.pdf'>MC No. 122</a>";
  assert.deepEqual(findAnchors(html), [
    {
      href: "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC No. 88-2026_redacted.pdf",
      text: "more",
    },
    { href: "https://bir-cdn.bir.gov.ph/BIR/pdf/MC No. 122 s.2026.pdf", text: "MC No. 122" },
  ]);
});

test("findAnchors decodes entity-escaped query separators and skips hrefless anchors", () => {
  assert.deepEqual(findAnchors('<a href="/a?x=1&amp;y=2">link</a>'), [
    { href: "/a?x=1&y=2", text: "link" },
  ]);
  assert.deepEqual(findAnchors('<a name="anchor">no href</a>'), []);
});

test("splitTableRows and splitTableCells read the archive table shape", () => {
  const table =
    '<table border="1">\n<thead>\n<tr style="height: 35px;">' +
    "<th><strong>NO. OF ISSUANCE</strong></th><th><strong>SUBJECT</strong></th>" +
    "<th><strong>DATE OF ISSUE</strong></th></tr>\n" +
    '<tr><td style="width: 20%;">RMC No. 89-2026</td>' +
    '<td><span>Providing Extension of the Deadlines.</span> <a href="/rmc89.pdf">Full Text</a></td>' +
    "<td>August 10, 2026</td></tr>\n</thead>\n</table>";

  const rows = splitTableRows(table);
  assert.equal(rows.length, 2);
  assert.deepEqual(splitTableCells(rows[0]).map(textOf), [
    "NO. OF ISSUANCE",
    "SUBJECT",
    "DATE OF ISSUE",
  ]);

  const dataCells = splitTableCells(rows[1]);
  assert.equal(dataCells.length, 3);
  assert.equal(textOf(dataCells[0]), "RMC No. 89-2026");
  assert.equal(textOf(dataCells[2]), "August 10, 2026");
  assert.deepEqual(findAnchors(dataCells[1]), [{ href: "/rmc89.pdf", text: "Full Text" }]);
});

test("splitTableCells tolerates omitted closing tags", () => {
  assert.deepEqual(splitTableCells("<td>a<td>b<td>c").map(textOf), ["a", "b", "c"]);
});

test("splitTableRows returns an empty list for markup without rows", () => {
  assert.deepEqual(splitTableRows("<p>no table here</p>"), []);
});
