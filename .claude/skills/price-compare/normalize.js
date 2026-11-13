const fs = require('fs'), path = require('path');
const dir = process.argv[2];
const KEY = { 'X-cite': 'xcite', 'Eureka': 'eureka', 'Best Al-Yousifi': 'best' };
function model(t) {
  const s = t.toLowerCase();
  if (/case|cover|protector|glass|charger|cable/.test(s)) return null;
  if (/iphone/.test(s)) {
    if (/17\s*pro\s*max/.test(s)) return ['Apple', 'iPhone 17 Pro Max'];
    if (/17\s*pro/.test(s)) return ['Apple', 'iPhone 17 Pro'];
    if (/iphone\s*air/.test(s)) return ['Apple', 'iPhone Air'];
    if (/17\s*e\b|17e/.test(s)) return ['Apple', 'iPhone 17e'];
    if (/iphone\s*17\b/.test(s)) return ['Apple', 'iPhone 17'];
    return null;
  }
  if (/samsung|galaxy/.test(s)) {
    if (/s26\s*ultra/.test(s)) return ['Samsung', 'Galaxy S26 Ultra'];
    if (/s26\s*\+|s26\s*plus/.test(s)) return ['Samsung', 'Galaxy S26+'];
    if (/s26\s*fe/.test(s)) return ['Samsung', 'Galaxy S26 FE'];
    if (/s26\b/.test(s)) return ['Samsung', 'Galaxy S26'];
    if (/s25\s*ultra/.test(s)) return ['Samsung', 'Galaxy S25 Ultra'];
  }
  return null;
}
function storage(t) {
  const m = t.match(/\b(1|2)\s*TB\b/i); if (m) return m[1] + 'TB';
  const all = [...t.matchAll(/\b(128|256|512)\s*GB\b/gi)].map(x => x[1]);
  return all.length ? all[all.length - 1] + 'GB' : null;
}
const color = t => (t.split(/\s[-–]\s/).pop() || '').replace(/[.,]$/, '').trim();
const rows = {};
for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
  for (const r of JSON.parse(fs.readFileSync(path.join(dir, f))).results) {
    for (const it of r.items) {
      if (it.price < 100 || /result \(/i.test(it.title)) continue;
      if (/japanese|american/i.test(it.title)) continue; // نسخ مو خليجية
      const m = model(it.title), st = storage(it.title);
      if (!m || !st) continue;
      const id = (m[1] + ' ' + st).toLowerCase().replace(/\+/g, 'plus').replace(/[^a-z0-9]+/g, '-');
      const row = rows[id] ||= { brand: m[0], model: m[1], storage: st, xcite: null, eureka: null, best: null };
      const k = KEY[r.store], cur = row[k];
      if (!cur || it.price < cur.price) row[k] = { price: it.price, color: color(it.title) };
    }
  }
}
console.log(JSON.stringify(rows, null, 1));
