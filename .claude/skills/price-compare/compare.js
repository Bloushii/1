// يفتح صفحات البحث في اكس سايت ويوريكا وبيست اليوسفي ويطلع اسم الجهاز وسعره
// الاستخدام: node compare.js "iphone 17 pro 256"
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

const STORES = [
  { key: 'xcite',  name: 'X-cite',          url: q => `https://www.xcite.com/search?q=${q}`, link: '/p$' },
  // يوريكا: البحث عندهم ما يشتغل من هنا، فنفتح قسم الهواتف الذكية ونفلتر على الماركة
  { key: 'eureka', name: 'Eureka',          url: () => 'https://www.eureka.com.kw/products/browse/phones/mobile-phones/smart-phones', eurekaBrowse: true, link: '/products/details/' },
  { key: 'best',   name: 'Best Al-Yousifi', url: q => `https://best.com.kw/en/search/${q}`, link: '/product/' },
  // جرير: صفحات المنتجات محمية (Cloudflare)، فناخذ نتائج البحث اللي توصل للصفحة نفسها (فيها السعر بعد الخصم وكود الموديل)
  { key: 'hs',     name: 'H&S',             url: q => `https://www.hsstore.com/filterSearch?q=${q}&orderBy=11`, link: 'hsstore\\.com/(apple|samsung)-' },
  { key: 'alpha',  name: 'Alpha Store',     url: q => `https://www.alphastore.com.kw/?s=${q}&post_type=product&lang=en`, link: '/product/' },
  // بلينك (Shopify): كل منتج فيه سعات وألوان، ناخذ سعر وتوفر كل وحدة من بيانات المتجر نفسه
  { key: 'blink',  name: 'Blink',           url: q => `https://www.blink.com.kw/search?type=product&q=${q}`, shopify: true },
  // جيت: صفحة المنتج فيها أزرار (الموديل/السعة)، نضغط كل وحدة ونقرا السعر والتوفر
  { key: 'gait',   name: 'Gait',            url: q => `https://gait.com.kw/g_kw_en/catalogsearch/result/?q=${q}`, gaitPage: true },
  { key: 'jarir',  name: 'Jarir',           url: q => `https://www.jarir.com/kw-en/catalogsearch/result?search=${q}`, jarirSearch: true },
];

// يدعم "359.900 KD" (اكس سايت ويوريكا) و "KD 349.900" (بيست)
const PRICE = /(?:(?:KD|KWD|د\.ك)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?))|(?:(\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?)\s*(?:KD|KWD|د\.ك))/i;
const NOT_PRICE = /credit|\/mo|month|installment|قسط/i; // أقساط شهرية مو سعر
const num = m => parseFloat((m[1] || m[2]).replace(/,/g, ''));

function eurekaBrand(query) {
  const q = query.toLowerCase();
  if (/iphone|apple|ايفون/.test(q)) return 'IPHONE';
  if (/samsung|galaxy|سامسونق|سامسونج|\bs2\d|\ba\d\d\b|\bz\s?(fold|flip)/.test(q)) return 'SAMSUNG';
  return q.split(/\s+/)[0].toUpperCase();
}

// يقرا سطور الصفحة: اسم الجهاز وبعده السعر (أول سعر = الحالي، الثاني إن وجد = قبل الخصم)
function parseLines(lines, query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const items = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i].toLowerCase();
    if (l.length < 12 || PRICE.test(lines[i]) || !words.every(w => l.includes(w))) continue;
    const prices = [];
    for (let j = i + 1; j < Math.min(i + 6, lines.length) && prices.length < 2; j++) {
      if (NOT_PRICE.test(lines[j])) break;
      const m = lines[j].match(PRICE);
      if (m) prices.push(num(m));
      else if (prices.length) break;
    }
    // بيست يكتب "OUT OF STOCK" بالسطر اللي فوق اسم الجهاز
    // (نشيك ٣ سطور فوق الاسم لين نوصل لسعر الجهاز اللي قبله، عشان لو جت شارة ثانية مثل "Best Seller" بالنص)
    let outOfStock = false;
    for (let j = i - 1; j >= Math.max(0, i - 3); j--) {
      if (PRICE.test(lines[j]) || NOT_PRICE.test(lines[j])) break;
      if (/out of stock|sold out|غير متوفر|نفذت/i.test(lines[j])) { outOfStock = true; break; }
    }
    if (prices.length) items.push({ title: lines[i], price: Math.min(...prices), was: prices.length > 1 ? Math.max(...prices) : null, ...(outOfStock && { outOfStock: true }) });
  }
  return items;
}

async function pageLines(browser, store, query) {
  const page = await browser.newPage({ userAgent: UA, viewport: { width: 1366, height: 900 } });
  try {
    await page.goto(store.url(encodeURIComponent(query)), { waitUntil: 'domcontentloaded', timeout: 60000 });
    if (store.eurekaBrowse) {
      await page.waitForTimeout(9000);
      const brand = eurekaBrand(query);
      const label = page.locator('label', { hasText: new RegExp(`^\\s*${brand}\\s*$`, 'i') }).first();
      if (!(await label.count())) throw new Error(`brand filter ${brand} not found`);
      await label.click();
      await page.waitForTimeout(5000);
      // زر "View More" يجيب 24 جهاز زيادة كل مرة، والترتيب من الأرخص للأغلى فلازم نوصل للآخر
      for (let k = 0; k < 40; k++) {
        const more = page.locator('button.viewMore:visible');
        if (!(await more.count())) break;
        await more.first().click().catch(() => {});
        await page.waitForTimeout(2500);
      }
    } else {
      await page.waitForTimeout(8000);
    }
    const lines = (await page.evaluate(() => document.body.innerText)).split('\n').map(s => s.trim()).filter(Boolean);
    // كل كرت جهاز لحاله: الاسم + الرابط (فيه كود المنتج، مثل -US أو -JP) + نص الكرت (الأسعار والتوفر)
    const cards = await page.evaluate(linkRe => {
      const re = new RegExp(linkRe), out = [], seen = new Set();
      const anchors = [...document.querySelectorAll('a[href]')].filter(a => re.test(a.href.split('?')[0]));
      for (const a of anchors) {
        const href = a.href; if (seen.has(href)) continue;
        let c = a;
        while (c.parentElement) {
          const up = c.parentElement;
          const hrefs = new Set([...up.querySelectorAll('a[href]')].filter(x => re.test(x.href.split('?')[0])).map(x => x.href));
          if (hrefs.size > 1) break;
          c = up;
          if (/(KD|KWD)\s*\d|\d\s*(KD|KWD)/.test(c.innerText || '')) { /* keep climbing while still one product */ }
        }
        const text = (c.innerText || '').trim();
        if (!/(KD|KWD|د\.ك)/.test(text)) continue;
        const title = [...c.querySelectorAll('a[href]')].filter(x => x.href === href).map(x => x.textContent.trim()).sort((x, y) => y.length - x.length)[0] || '';
        seen.add(href);
        out.push({ href, title, text });
      }
      return out;
    }, store.link || '^$');
    return { lines, cards };
  } finally { await page.close(); }
}

// نسخ مو خليجية: من الاسم أو من كود المنتج في الرابط (بيست يكتبها بالكود بس: IPH-18P-256-SLV-US)
const FOREIGN = /japan|amer[ia]|ameriacn|\bjp\b|\busa?\b|international|\bh\.?k\b|hong ?kong|[-_](us|jp|usa|hk|ch)(?=[\/?#._-]|$)/i;

function parseCards(cards, query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const items = [];
  for (const c of cards) {
    // بيست يلف الكرت كله بالرابط، فننظف الاسم من الأسعار والشارات
    const title = (c.title || c.text.split('\n')[0]).replace(/\s+/g, ' ')
      .split(/\s(?:KD|KWD)\s*\d|\s\d[\d,.]*\s*(?:KD|KWD)\b|\d{1,3}\.\d{3}(?:\s*(?:KD|KWD))?|\sOn Credit|\sOUT OF STOCK|\sBest Seller|\s\d+%/i)[0].replace(/^(?:OUT OF STOCK|Best Seller|New)\s+/i, '').trim();
    if (title.length < 8 || !words.every(w => title.toLowerCase().includes(w))) continue;
    const prices = c.text.split('\n').map(l => l.trim()).filter(l => !NOT_PRICE.test(l)).map(l => l.match(PRICE)).filter(Boolean).map(num);
    if (!prices.length) continue;
    const item = { title, price: Math.min(...prices), was: prices.length > 1 ? Math.max(...prices) : null, href: c.href };
    if (/out of stock|sold out|غير متوفر|نفذت|notify me/i.test(c.text)) item.outOfStock = true;
    if (FOREIGN.test(title) || FOREIGN.test(c.href.split('/').slice(3).join('/'))) item.foreign = true;
    items.push(item);
  }
  return items;
}

async function scrapeJarir(browser, store, query) {
  const page = await browser.newPage({ userAgent: UA, viewport: { width: 1366, height: 900 } });
  let data = null;
  page.on('response', async r => { if (/ac\.cnstrc\.com\/v1\/search\//.test(r.url())) { try { data = await r.json(); } catch (e) {} } });
  try {
    await page.goto(store.url(encodeURIComponent(query)), { waitUntil: 'domcontentloaded', timeout: 60000 });
    for (let w = 0; w < 10 && !data; w++) await page.waitForTimeout(1500);
  } finally { await page.close(); }
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const items = [];
  for (const res of data?.response?.results || []) {
    const d = res.data || {}, m = d.metadata || {};
    let extra = {}; try { extra = JSON.parse(m.additionalDataToReturn || '{}'); } catch (e) {}
    // الاسم مثل: "Apple iPhone 17 Pro, 256 GB, Deep Blue, 5G, ..." → نخليه بصيغة الباقين
    const raw = res.value || m.name || '';
    const parts = raw.split(',').map(x => x.trim());
    const title = (parts[0] + ' ' + (parts[1] || '').replace(/\s+/g, '').replace(/^1000GB$/, '1TB') + ' - ' + (parts[2] || '')).trim();
    if (!words.every(w => raw.toLowerCase().replace(/\s+gb/g, 'gb').includes(w) || title.toLowerCase().includes(w))) continue;
    const list = Number(d.price || m.price), final = Number(extra.GTM_final_price || list);
    if (!final) continue;
    const mpn = String(m.mpn || '');
    items.push({
      title, price: final, was: list > final ? list : null,
      href: d.url ? 'https://www.jarir.com/kw-en/' + d.url : null,
      unverifiable: true,
      // كود أبل: AH/AE = خليجي، LL = أمريكي، J = ياباني
      ...(/(LL|J|CH|ZP)A?$/i.test(mpn.replace(/\/A$/i, '')) && { foreign: true }),
    });
  }
  return items;
}

async function scrapeShopify(browser, store, query) {
  const page = await browser.newPage({ userAgent: UA, viewport: { width: 1366, height: 900 } });
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const items = [];
  try {
    await page.goto(store.url(encodeURIComponent(query)), { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(6000);
    const handles = await page.evaluate(() => [...new Set([...document.querySelectorAll('a[href*="/products/"]')].map(a => a.pathname.split('/products/')[1]).filter(Boolean))].slice(0, 30));
    for (const h of handles) {
      const j = await page.evaluate(async h => { const r = await fetch('/products/' + h + '.js'); return r.ok ? r.json() : null; }, h).catch(() => null);
      if (!j || !/iphone|galaxy|samsung/i.test(j.title)) continue;
      const base = j.title.replace(/\s*-\s*eSIM\b/i, '').trim();
      for (const v of j.variants || []) {
        const title = /\d+\s?(GB|TB)/i.test(base) ? base + ' - ' + v.title : base + ' ' + v.title.replace(/\s*\/\s*/, ' - ');
        if (!words.every(w => title.toLowerCase().replace(/(\d+)\s+(gb|tb)/g, '$1$2').includes(w))) continue;
        items.push({
          title, price: v.price / 100, was: v.compare_at_price && v.compare_at_price > v.price ? v.compare_at_price / 100 : null,
          href: location_origin(store) + '/products/' + h + '?variant=' + v.id,
          ...(!v.available && { outOfStock: true }), ...(v.available && { preVerified: true }),
          ...((FOREIGN.test(j.title) || FOREIGN.test(v.title)) && { foreign: true }),
        });
      }
    }
  } finally { await page.close(); }
  return items;
}
const location_origin = store => new URL(store.url('x')).origin;

// جيت: نجمع صفحات المنتجات من البحث، ونخزنها عشان ما نعيد نفس الصفحة لكل بحث
const gaitCache = new Map();
async function scrapeGait(browser, store, query) {
  const page = await browser.newPage({ userAgent: UA, viewport: { width: 1366, height: 900 } });
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  try {
    await page.goto(store.url(encodeURIComponent(query)), { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(6000);
    // روابط نتائج البحث بس (مو قائمة الموقع فوق اللي توديك لصفحات أقسام)
    const links = await page.evaluate(() => [...new Set([...document.querySelectorAll('a.product-item-link, .product-item-info a.product-item-photo, .products a.product-item-link')].filter(a => /^(iphone|samsung|galaxy)\b/i.test(a.textContent.trim() || a.getAttribute('title') || '') && !/case|cover|glass|protector|charger|cable|band/i.test(a.textContent)).map(a => a.href.split('?')[0]))].slice(0, 6));
    for (const url of links) {
      if (gaitCache.has(url)) continue;
      const found = [];
      try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
        await page.waitForTimeout(6000);
        const groups = await page.evaluate(() => {
          const h1 = document.querySelector('h1'); let c = h1;
          const isSize = e => e.children.length === 0 && /^\d+\s?(GB|TB)$/i.test(e.textContent.trim());
          while (c && ![...c.querySelectorAll('*')].some(isSize)) c = c.parentElement;
          if (!c) return null;
          c.setAttribute('data-main-product', '1');
          const btns = [...c.querySelectorAll('button')].map(b => b.textContent.trim()).filter(Boolean);
          const COLOR = /orange|blue|silver|black|white|gr[ae]y|gold|green|purple|violet|pink|lavender|sage|burgundy|glacier|mist|titanium|cream|graphite/i;
          return { models: [...new Set(btns.filter(t => /^(iphone|galaxy)\b/i.test(t)))], sizes: [...new Set(btns.filter(t => /^\d+\s?(GB|TB)$/i.test(t)))], colors: [...new Set(btns.filter(t => t.length < 30 && COLOR.test(t)))] };
        });
        if (!groups) { gaitCache.set(url, []); continue; }
        const click = t => page.evaluate(t => { const c = document.querySelector('[data-main-product]'); const b = [...c.querySelectorAll('button')].find(b => b.textContent.trim() === t); if (b) b.click(); }, t);
        const read = () => page.evaluate(() => {
          const c = document.querySelector('[data-main-product]'); const t = c.innerText.split('\n').map(s => s.trim()).filter(Boolean);
          const prices = t.filter(l => /^KD\s*\d/.test(l)).map(l => parseFloat(l.replace(/[^\d.]/g, ''))).slice(0, 2);
          return { title: document.querySelector('h1')?.textContent.trim() || '', sku: (t.find(l => /^SKU:/i.test(l)) || '').replace(/SKU:\s*|\s*\|.*$/gi, ''), prices, stock: t.find(l => /IN-STOCK|OUT OF STOCK|OUT-OF-STOCK|SOLD OUT/i.test(l)) || '' };
        });
        const seen = new Set();
        // كل تركيبة: موديل × سعة × لون (بعض السعات ما تجي إلا بألوان معينة)
        for (const m of (groups.models.length ? groups.models : [null])) {
          for (const sz of groups.sizes) for (const col of (groups.colors.length ? groups.colors : [null])) {
            if (m) { await click(m); await page.waitForTimeout(900); }
            if (col) { await click(col); await page.waitForTimeout(900); }
            await click(sz); await page.waitForTimeout(1800);
            const r = await read();
            if (!new RegExp(sz.replace(/\s/g, '\\s?'), 'i').test(r.title)) continue; // التركيبة مو موجودة والصفحة نطت لغيرها
            if (!r.title || seen.has(r.sku || r.title) || !r.prices.length) continue;
            seen.add(r.sku || r.title);
            const [a, b] = r.prices; const price = b && b < a && b > 50 ? b : a;
            found.push({ title: r.title, price, was: price < a ? a : null, href: url,
              ...(/IN-STOCK/i.test(r.stock) ? { preVerified: true } : { outOfStock: true }),
              ...(/(LL|J|CH|ZP)\/A$/i.test(r.sku) && { foreign: true }) });
          }
        }
      } catch (e) { /* صفحة وحدة فشلت: نكمل الباقي */ }
      gaitCache.set(url, found);
    }
    const all = [...gaitCache.values()].flat();
    return all.filter(it => words.every(w => it.title.toLowerCase().includes(w)));
  } finally { await page.close(); }
}

async function scrape(browser, store, query) {
  if (store.shopify || store.gaitPage) {
    try { return { store: store.name, items: await (store.shopify ? scrapeShopify : scrapeGait)(browser, store, query), via: store.shopify ? 'shopify' : 'gait' }; }
    catch (e) { return { store: store.name, error: e.message.split('\n')[0], items: [] }; }
  }
  if (store.jarirSearch) {
    try { return { store: store.name, items: await scrapeJarir(browser, store, query), via: 'search' }; }
    catch (e) { return { store: store.name, error: e.message.split('\n')[0], items: [] }; }
  }
  try {
    const { lines, cards } = await pageLines(browser, store, query);
    const fromCards = parseCards(cards, query);
    // الكروت أدق (فيها الرابط والتوفر)؛ لو الموقع غيّر شكله ورجعت فاضية نرجع لقراءة السطور
    return { store: store.name, items: fromCards.length ? fromCards : parseLines(lines, query), via: fromCards.length ? 'cards' : 'lines' };
  } catch (e) {
    return { store: store.name, error: e.message.split('\n')[0], items: [] };
  }
}

module.exports = { STORES, scrape, pageLines, parseLines, parseCards, FOREIGN, UA, chromium };

if (require.main === module) {
  (async () => {
    const query = process.argv.slice(2).join(' ');
    if (!query) { console.error('usage: node compare.js "<device>"'); process.exit(1); }
    const browser = await chromium.launch();
    // واحد واحد: بيست يرجع فاضي لو انفتحت المواقع كلها مع بعض
    const results = [];
    for (const s of STORES) {
      let r = await scrape(browser, s, query);
      if (!r.items.length) r = await scrape(browser, s, query); // محاولة ثانية
      results.push(r);
    }
    await browser.close();
    console.log(JSON.stringify({ query, results }, null, 2));
  })();
}
