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
const FOREIGN = /japan|amer[ia]|ameriacn|\bjp\b|\busa?\b|international|[-_](us|jp|usa|hk|ch)(?=[\/?#._-]|$)/i;

function parseCards(cards, query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const items = [];
  for (const c of cards) {
    // بيست يلف الكرت كله بالرابط، فننظف الاسم من الأسعار والشارات
    const title = (c.title || c.text.split('\n')[0]).replace(/\s+/g, ' ')
      .split(/\s(?:KD|KWD)\s*\d|\s\d[\d,.]*\s*(?:KD|KWD)\b|\sOn Credit|\sOUT OF STOCK|\sBest Seller|\s\d+%/i)[0].replace(/^(?:OUT OF STOCK|Best Seller|New)\s+/i, '').trim();
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

async function scrape(browser, store, query) {
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
