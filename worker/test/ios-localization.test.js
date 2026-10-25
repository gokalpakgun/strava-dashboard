import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

function entries(locale) {
  const source = readFileSync(new URL(`../../ios/TempoHealth/Sources/${locale}.lproj/Localizable.strings`, import.meta.url), 'utf8');
  return [...source.matchAll(/^("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");$/gm)]
    .map(match => [JSON.parse(match[1]), JSON.parse(match[2])]);
}
function argumentsOf(format) {
  const argumentsByIndex = new Map();
  let next = 1;
  for (let index = 0; index < format.length; index++) {
    if (format[index] !== '%') continue;
    const match = /^%(?:(\d+)\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t)?([diuoxXfFeEgGaAcsp@%])/.exec(format.slice(index));
    assert.ok(match, `Invalid format token in ${format}`);
    const position = match[1] ? Number(match[1]) : next++;
    if (match[2] === '%') {
      assert.equal(match[0], '%%', `Literal percent cannot use an argument index in ${format}`);
      if (!match[1]) next--;
    } else {
      assert.ok(!argumentsByIndex.has(position) || argumentsByIndex.get(position) === match[2], `Argument type changes in ${format}`);
      argumentsByIndex.set(position, match[2]);
    }
    index += match[0].length - 1;
  }
  return [...argumentsByIndex.entries()].sort((a, b) => a[0] - b[0]);
}
for (const locale of ['en', 'tr']) {
  test(`iOS ${locale} translations preserve Foundation format argument types and unique keys`, () => {
    const rows = entries(locale);
    assert.ok(rows.length > 800, 'Read the real shipped string table');
    assert.equal(new Set(rows.map(([key]) => key)).size, rows.length, 'Duplicate translations');
    for (const [key, translated] of rows) {
      // Plain text can contain a literal percent sign. Only check entries whose
      // source actually takes Foundation format arguments.
      if (!/%(?:\d+\$)?(?:\.\d+)?[@diuf]/.test(key)) continue;
      assert.deepEqual(argumentsOf(translated), argumentsOf(key), `${locale}: ${key}`);
    }
  });
}
