// يسحب أسعار كل الأجهزة اللي في صفحة "وين أرخص" ويطلع ملف واحد جاهز للحفظ
// الاستخدام: node update.js <ملف الإخراج> ["بحث إضافي" ...]
// الإخراج: { rows: {...}, updatedAt, stats: { xcite, eureka, best }, problems: [...] }
const fs = require('fs');
const { STORES, scrape, chromium } = require('./compare');
const { normalize } = require('./normalize');

// كلمات البحث لاكس سايت وبيست (لسامسونق بدون "galaxy": اكس سايت ما يكتبها دايماً)
const QUERIES = [
  'iphone 18 pro max', 'iphone 18 pro', 'iphone 18',
  'iphone 17 pro max', 'iphone 17 pro', 'iphone 17 256gb', 'iphone 17 512gb', 'iphone air', 'iphone 17e',
  's26 ultra', 's25 ultra',
];
const words = s => s.toLowerCase().replace(/galaxy|samsung|apple/g, '').split(/\s+/).filter(Boolean);

(async () => {
  const out = process.argv[2];
  if (!out) { console.error('usage: node update.js <out.json> ["extra query" ...]'); process.exit(1); }
  const extra = process.argv.slice(3).map(s => s.trim()).filter(Boolean);
  const queries = [...new Set([...QUERIES, ...extra.map(s => s.toLowerCase())])];
  const browser = await chromium.launch();
  const results = [], problems = [];
  const xcite = STORES.find(s => s.key === 'xcite'), best = STORES.find(s => s.key === 'best'), eureka = STORES.find(s => s.key === 'eureka');

  async function run(store, q) {
    let r = await scrape(browser, store, q);
    if (!r.items.length) r = await scrape(browser, store, q); // محاولة ثانية
    if (!r.items.length) problems.push(`${store.name}: no results for "${q}"${r.error ? ' (' + r.error + ')' : ''}`);
    results.push(r);
    process.stderr.write(`${store.name.padEnd(16)} ${q.padEnd(22)} ${r.items.length}\n`);
  }

  for (const q of queries) { await run(xcite, q); await run(best, q); }
  // يوريكا: نفتح قائمة كل ماركة مرة وحدة (يغطي كل الموديلات)
  const brands = new Set(['iphone', 'samsung']);
  for (const q of extra) if (!/iphone|apple|samsung|galaxy|s\d\d|z\s?(fold|flip)/i.test(q)) brands.add(q.split(/\s+/)[0]);
  for (const b of brands) await run(eureka, b);
  await browser.close();

  // نخلي الجهاز اللي له سعر في اكس سايت أو بيست (عشان فيه مقارنة)،
  // أو اللي المستخدم طلبه بالاسم حتى لو موجود بيوريكا بس
  const all = normalize(results), rows = {};
  for (const [id, r] of Object.entries(all)) {
    const hay = (r.model + ' ' + r.storage).toLowerCase();
    const requested = extra.some(q => words(q).every(w => hay.replace(/\s+/g, '').includes(w.replace(/\s+/g, '')) || hay.includes(w)));
    // من سامسونق المستخدم يبي الالترا بس هالفترة (لا عادي ولا بلس ولا FE ولا فولد/فليب)، إلا لو طلب جهاز بالاسم
    const skipped = r.brand === 'Samsung' && !/\bUltra\b/.test(r.model);
    if ((r.xcite || r.best || requested) && (!skipped || requested)) rows[id] = r;
  }
  const stats = { xcite: 0, eureka: 0, best: 0 };
  for (const r of Object.values(rows)) for (const k of Object.keys(stats)) if (r[k]) stats[k]++;
  for (const [k, n] of Object.entries(stats)) if (!n) problems.push(`${k}: no prices at all`);
  const result = { rows, updatedAt: Date.now(), stats, problems };
  fs.writeFileSync(out, JSON.stringify(result, null, 1));
  console.log(JSON.stringify({ devices: Object.keys(rows).length, stats, problems }, null, 1));
  // سطر واحد تقراه صفحة "وين أرخص" من سجل الجلسة وتحفظه بنفسها
  console.log('PRICES_JSON_BEGIN' + JSON.stringify(result) + 'PRICES_JSON_END');
})();
