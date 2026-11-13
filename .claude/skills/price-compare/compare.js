// يفتح صفحات البحث في اكس سايت ويوريكا وبيست اليوسفي ويطلع اسم الجهاز وسعره
// الاستخدام: node compare.js "iphone 17 pro 256"
const { chromium } = require('playwright');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

const STORES = [
  { key: 'xcite',  name: 'X-cite',          url: q => `https://www.xcite.com/search?q=${q}` },
  // يوريكا: البحث عندهم ما يشتغل من هنا، فنفتح قسم الهواتف الذكية ونفلتر على الماركة
  { key: 'eureka', name: 'Eureka',          url: () => 'https://www.eureka.com.kw/products/browse/phones/mobile-phones/smart-phones', eurekaBrowse: true },
  { key: 'best',   name: 'Best Al-Yousifi', url: q => `https://best.com.kw/en/search/${q}` },
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
    const outOfStock = i > 0 && /out of stock|sold out|غير متوفر|نفذت/i.test(lines[i - 1]);
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
    return (await page.evaluate(() => document.body.innerText)).split('\n').map(s => s.trim()).filter(Boolean);
  } finally { await page.close(); }
}

async function scrape(browser, store, query) {
  try {
    return { store: store.name, items: parseLines(await pageLines(browser, store, query), query) };
  } catch (e) {
    return { store: store.name, error: e.message.split('\n')[0], items: [] };
  }
}

module.exports = { STORES, scrape, pageLines, parseLines, chromium };

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
