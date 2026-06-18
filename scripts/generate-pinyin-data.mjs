import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const tempRoot = process.env.FLASH_ZH_TEMP_ROOT || path.join(process.env.TEMP || process.env.TMP || 'C:/Temp', 'opencode');
const charDataFile = path.join(tempRoot, 'ib-pinyin-data', 'pinyin.txt');
const phraseDataFiles = [
  path.join(tempRoot, 'phrase-pinyin-data', 'pinyin.txt'),
  path.join(tempRoot, 'phrase-pinyin-data', 'large_pinyin.txt'),
  path.join(tempRoot, 'phrase-pinyin-data', 'overwrite.txt'),
];
const phraseOutputDir = path.join(repoRoot, 'lua', 'flash_zh', 'data', 'pinyin_phrase_shards');

const charMap = new Map();
for (const line of fs.readFileSync(charDataFile, 'utf8').split(/\r?\n/)) {
  if (!line || line.startsWith('#')) continue;
  const [left, right] = line.split(': ');
  if (!left || !right) continue;
  const codePoint = Number.parseInt(left.slice(2), 16);
  const char = String.fromCodePoint(codePoint);
  const plain = normalizePinyin(right.split(' #')[0]);
  if (plain.length > 0) charMap.set(char, plain.join(','));
}

const charOutput = [
  'return {',
  ...Array.from(charMap.entries())
    .sort((a, b) => a[0].localeCompare(b[0], 'zh-Hans-CN'))
    .map(([char, value]) => `  [${luaString(char)}] = ${luaString(value)},`),
  '}',
  '',
].join('\n');

const phraseMap = new Map();
for (const file of phraseDataFiles) {
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const [rawPhrase, rawPinyin] = line.split(': ');
    if (!rawPhrase || !rawPinyin) continue;
    const phrase = rawPhrase.replace(/_\d+$/, '');
    const plain = normalizePinyin(rawPinyin.split(' #')[0]);
    if (plain.length === 0) continue;
    const full = plain.join('');
    const abbr = plain.map(item => item[0]).join('');
    const variants = phraseMap.get(phrase) ?? new Map();
    variants.set(full, abbr);
    phraseMap.set(phrase, variants);
  }
}

fs.writeFileSync(path.join(repoRoot, 'lua', 'flash_zh', 'data', 'pinyin_char_data.lua'), charOutput, 'utf8');

fs.rmSync(phraseOutputDir, { recursive: true, force: true });
fs.mkdirSync(phraseOutputDir, { recursive: true });

const shardMap = new Map();
for (const [phrase, variants] of phraseMap.entries()) {
  const key = shardName(phrase[0]);
  const lines = shardMap.get(key) ?? [];
  const items = Array.from(variants.entries()).map(([full, abbr]) => `${full},${abbr}`).join(';');
  lines.push(`${phrase}\t${items}`);
  shardMap.set(key, lines);
}

for (const [key, lines] of shardMap.entries()) {
  lines.sort((a, b) => a.localeCompare(b, 'zh-Hans-CN'));
  fs.writeFileSync(path.join(phraseOutputDir, `${key}.txt`), lines.join('\n') + '\n', 'utf8');
}

function normalizePinyin(value) {
  return Array.from(new Set(
    value.trim().split(/\s+/).flatMap(item => item.split(',')).map(item => item.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ü/g, 'v').toLowerCase()).filter(Boolean)
  ));
}

function luaString(value) {
  return JSON.stringify(value).replace(/\\u2028|\\u2029/g, match => (match === '\\u2028' ? '\\\\u2028' : '\\\\u2029'));
}

function shardName(char) {
  return char.codePointAt(0).toString(16).toUpperCase().padStart(5, '0');
}
