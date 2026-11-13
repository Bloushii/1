// يحول نتائج compare.js لصف واحد لكل جهاز+سعة، وفيه أرخص سعر بكل محل
// الاستخدام: node normalize.js <مجلد فيه ملفات JSON من compare.js>
const fs = require('fs'), path = require('path');
const KEY = { 'X-cite': 'xcite', 'Eureka': 'eureka', 'Best Al-Yousifi': 'best' };
const ACCESSORY = /case|cover|protector|glass|charger|cable|adapter|strap|band|lens|holder|stand|skin|pouch|earbuds|buds|watch|tab\b|tablet|ipad/i;

function model(t) {
  const s = t.toLowerCase().replace(/[”"″]/g, ' ');
  if (ACCESSORY.test(s)) return null;
  if (/iphone/.test(s)) {
    if (/iphone\s*air/.test(s)) return ['Apple', 'iPhone Air'];
    const m = s.match(/iphone\s*(\d{2})\s*(pro\s*max|promax|pro|plus|e\b)?/) || s.match(/iphone\s*(\d{2})(e)\b/);
    if (!m) return null;
    const suf = (m[2] || '').replace(/\s+/g, ' ').trim();
    const name = { 'pro max': ' Pro Max', 'promax': ' Pro Max', 'pro': ' Pro', 'plus': ' Plus', 'e': 'e' }[suf] ?? '';
    return ['Apple', `iPhone ${m[1]}${name}`];
  }
  if (/samsung|galaxy/.test(s)) {
    let m = s.match(/\bz\s*(fold|flip)\s*(\d+)\s*(fe)?/);
    if (m) return ['Samsung', `Galaxy Z ${m[1][0].toUpperCase()}${m[1].slice(1)}${m[2]}${m[3] ? ' FE' : ''}`];
    m = s.match(/\bs(\d{2})\s*(ultra|\+|plus|fe|edge)?/);
    if (m) {
      const suf = { ultra: ' Ultra', '+': '+', plus: '+', fe: ' FE', edge: ' Edge' }[m[2]] ?? '';
      return ['Samsung', `Galaxy S${m[1]}${suf}`];
    }
    m = s.match(/\ba(\d{2})s?\b/);
    if (m) return ['Samsung', `Galaxy A${m[1]}`];
  }
  return null;
}

function storage(t) {
  const m = t.match(/\b(1|2)\s*TB\b/i); if (m) return m[1] + 'TB';
  const all = [...t.matchAll(/\b(64|128|256|512)\s*GB\b/gi)].map(x => +x[1]);
  // آخر رقم أو أكبر رقم: الرام دايماً أصغر من السعة
  return all.length ? Math.max(...all) + 'GB' : null;
}

function color(t) {
  const parts = t.split(/\s[-–]\s/);
  // يوريكا ما يحط شرطة قبل اللون: ناخذ اللي بعد آخر "Ram" أو "5G" أو "GB"
  const c = parts.length > 1 ? parts.pop() : (t.split(/\b(?:ram|5g|4g|gb|tb)\b/i).pop() || '');
  return c.replace(/[.,]$/, '').replace(/\b[A-Z0-9]{2,}-[A-Z0-9]{4,}\b/g, '').trim();
}

const idOf = (m, st) => (m + ' ' + st).toLowerCase().replace(/\+/g, 'plus').replace(/[^a-z0-9]+/g, '-');

// results: مصفوفة من { store, items } (من compare.js)
function normalize(results, rows = {}) {
  for (const r of results) {
    const k = KEY[r.store];
    if (!k) continue;
    for (const it of r.items) {
      if (it.price < 60 || it.outOfStock || /result \(/i.test(it.title)) continue;
      // نسخ مو خليجية (يوريكا أحياناً يكتبها غلط مثل "Ameriacn")
      if (/japan|amer[ia]|\bjp\b|\busa?\b|\bus version|international/i.test(it.title)) continue;
      const m = model(it.title), st = storage(it.title);
      if (!m || !st) continue;
      const id = idOf(m[1], st);
      const row = rows[id] ||= { brand: m[0], model: m[1], storage: st, xcite: null, eureka: null, best: null };
      const cur = row[k];
      if (!cur || it.price < cur.price) row[k] = { price: it.price, color: color(it.title) };
    }
  }
  return rows;
}

module.exports = { normalize, model, storage, color, idOf };

if (require.main === module) {
  const dir = process.argv[2];
  const all = [];
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) all.push(...JSON.parse(fs.readFileSync(path.join(dir, f))).results);
  console.log(JSON.stringify(normalize(all), null, 1));
}
