// يسحب أسعار كل الأجهزة اللي في صفحة "وين أرخص" ويطلع ملف واحد جاهز للحفظ
// الاستخدام: node update.js <ملف الإخراج> ["بحث إضافي" ...]
// الإخراج: { rows: {...}, updatedAt, stats: { xcite, eureka, best }, problems: [...] }
const fs = require('fs');
const { STORES, scrape, chromium, UA } = require('./compare');
const { normalize } = require('./normalize');

// كلمات البحث لاكس سايت وبيست (لسامسونق بدون "galaxy": اكس سايت ما يكتبها دايماً)
const QUERIES = [
  // ايفون 18 موقوف مؤقتاً بطلب المستخدم (ما عليه سوق حالياً): رجّع 'iphone 18 pro max', 'iphone 18 pro', 'iphone 18' لما يطلب
  'iphone 17 pro max', 'iphone 17 pro', 'iphone 17 256gb', 'iphone 17 512gb',
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
  const xcite = STORES.find(s => s.key === 'xcite'), best = STORES.find(s => s.key === 'best'), eureka = STORES.find(s => s.key === 'eureka'), jarir = STORES.find(s => s.key === 'jarir');
  const extraStores = ['hs', 'alpha', 'blink', 'gait'].map(k => STORES.find(s => s.key === k));

  async function run(store, q) {
    let r = await scrape(browser, store, q);
    if (!r.items.length) r = await scrape(browser, store, q); // محاولة ثانية
    if (!r.items.length) problems.push(`${store.name}: no results for "${q}"${r.error ? ' (' + r.error + ')' : ''}`);
    results.push(r);
    process.stderr.write(`${store.name.padEnd(16)} ${q.padEnd(22)} ${r.items.length}\n`);
  }

  for (const q of queries) { await run(xcite, q); await run(best, q); await run(jarir, q); for (const st of extraStores) await run(st, q); }
  // يوريكا: نفتح قائمة كل ماركة مرة وحدة (يغطي كل الموديلات)
  const brands = new Set(['iphone', 'samsung']);
  for (const q of extra) if (!/iphone|apple|samsung|galaxy|s\d\d|z\s?(fold|flip)/i.test(q)) brands.add(q.split(/\s+/)[0]);
  for (const b of brands) await run(eureka, b);

  // نخلي الجهاز اللي له سعر في اكس سايت أو بيست (عشان فيه مقارنة)،
  // أو اللي المستخدم طلبه بالاسم حتى لو موجود بيوريكا بس
  const all = normalize(results), rows = {};
  for (const [id, r] of Object.entries(all)) {
    const hay = (r.model + ' ' + r.storage).toLowerCase();
    const requested = extra.some(q => words(q).every(w => hay.replace(/\s+/g, '').includes(w.replace(/\s+/g, '')) || hay.includes(w)));
    // من سامسونق المستخدم يبي الالترا بس هالفترة (لا عادي ولا بلس ولا FE ولا فولد/فليب)، إلا لو طلب جهاز بالاسم
    // ومن ايفون ما يبي Air ولا e
    // ومن ايفون: 17 و18 بس (العادي و Pro و Pro Max)، بدون Air ولا e ولا الموديلات القديمة
    const skipped = (r.brand === 'Samsung' && !/\bUltra\b/.test(r.model)) || (r.brand === 'Apple' && (/\bAir\b|\d+e$|Plus/.test(r.model) || !/iPhone 17\b/.test(r.model)));
    if ((r.xcite || r.best || r.jarir || r.hs || r.alpha || r.blink || r.gait || requested) && (!skipped || requested)) rows[id] = r;
  }
  // ===== تأكيد من صفحة المنتج: الأرخص لكل جهاز لازم يكون "In Stock" وبنفس السعر =====
  // لو مو متوفر أو السعر تغيّر، ناخذ المرشح اللي بعده من نفس المحل، ونعيد لين يطلع أرخص سعر مؤكد
  const page = await browser.newPage({ userAgent: UA, viewport: { width: 1366, height: 900 } });
  const checked = new Map();
  async function verify(c) {
    // بلينك وجيت: التوفر والسعر قريناهم من بيانات المتجر نفسه لكل سعة/لون
    if (c.preVerified) return { ok: true };
    if (!c.href) return { ok: false, why: 'no link' };
    // جرير يحجب صفحات المنتجات عن المتصفح الآلي: نخلي السعر بس ما نقدر نأكد التوفر
    if (/jarir\.com/.test(c.href)) return { ok: false, drop: false, why: 'Jarir blocks product pages' };
    if (checked.has(c.href)) return checked.get(c.href);
    let res;
    try {
      await page.goto(c.href, { waitUntil: 'domcontentloaded', timeout: 60000 });
      // نستنى لين تبين حالة التوفر (يوريكا بطيء)، لحد ٢٠ ثانية
      let text = '';
      for (let w = 0; w < 10; w++) {
        await page.waitForTimeout(2000);
        text = await page.evaluate(() => document.body.innerText);
        if (/in stock|add to cart|add to bag|out of stock|sold out/i.test(text)) break;
      }
      const out = /out of stock|sold out|غير متوفر|نفذت/i.test(text);
      const inStock = /in stock|add to cart|add to bag/i.test(text);
      const priceOk = text.includes(c.price.toFixed(3));
      if (out && !inStock) res = { ok: false, drop: true, why: 'out of stock' };
      else if (inStock && !priceOk) res = { ok: false, drop: true, why: 'price changed' };
      else if (inStock) res = { ok: true };
      else res = { ok: false, drop: false, why: 'page did not load' }; // ما نشيله بس ما نأكده
    } catch (e) { res = { ok: false, drop: false, why: 'page failed' }; }
    checked.set(c.href, res);
    return res;
  }
  const KEYS = ['xcite', 'eureka', 'best', 'jarir', 'hs', 'alpha', 'blink', 'gait'];
  let checks = 0;
  for (const [id, r] of Object.entries(rows)) {
    const cand = r._cand || {};
    for (const k of KEYS) (cand[k] ||= []).sort((a, b) => a.price - b.price);
    const verified = {};
    // جولتين: الأرخص من كل المحلات، وبعدها الأرخص من غير جرير (عشان يكون فيه دايماً خيار مؤكد التوفر)
    for (const pool of [KEYS, KEYS.filter(k => k !== 'jarir')]) {
      for (let guard = 0; guard < 12 && checks < 160; guard++) {
        const live = pool.filter(k => cand[k].length);
        if (!live.length) break;
        const min = Math.min(...live.map(k => cand[k][0].price));
        const todo = live.filter(k => cand[k][0].price === min && !verified[k]);
        if (!todo.length) break; // الأرخص (وأي محل بنفس السعر) انشيك
        for (const k of todo) {
          checks++;
          const v = await verify(cand[k][0]);
          if (v.ok) verified[k] = true;
          else if (v.drop) { process.stderr.write(`  drop ${k} ${id} ${cand[k][0].price} (${v.why})\n`); cand[k].shift(); }
          else { process.stderr.write(`  unverified ${k} ${id} ${cand[k][0].price} (${v.why})\n`); verified[k] = 'unknown'; }
        }
      }
    }
    for (const k of KEYS) {
      const c = cand[k][0];
      r[k] = c ? { price: c.price, color: c.color, href: c.href, ...((verified[k] === true || c.preVerified) && { verified: true }) } : null;
    }
    delete r._cand;
    if (!KEYS.some(k => r[k])) delete rows[id];
  }
  await browser.close();
  process.stderr.write(`verified with ${checks} product-page checks\n`);

  const stats = { xcite: 0, eureka: 0, best: 0, jarir: 0, hs: 0, alpha: 0, blink: 0, gait: 0 };
  for (const r of Object.values(rows)) for (const k of Object.keys(stats)) if (r[k]) stats[k]++;
  for (const [k, n] of Object.entries(stats)) if (!n) problems.push(`${k}: no prices at all`);
  const result = { rows, updatedAt: Date.now(), stats, problems };
  fs.writeFileSync(out, JSON.stringify(result, null, 1));
  console.log(JSON.stringify({ devices: Object.keys(rows).length, stats, problems }, null, 1));
  // سطر واحد تقراه صفحة "وين أرخص" من سجل الجلسة وتحفظه بنفسها
  console.log('PRICES_JSON_BEGIN' + JSON.stringify(result) + 'PRICES_JSON_END');
})();
