// يفتح صفحة البحث في المواقع الثلاثة ويطلع اسم الجهاز وسعره
// الاستخدام: node compare.js "iphone 17 pro 256"
const { chromium } = require('playwright');

const STORES = [
  { name: 'X-cite',          url: q => `https://www.xcite.com/search?q=${q}` },
  { name: 'Eureka',          url: q => `https://www.eureka.com.kw/products/search?q=${q}` },
  { name: 'Best Al-Yousifi', url: q => `https://best.com.kw/en/search/${q}` },
];
// يدعم "359.900 KD" (اكس سايت) و "KD 349.900" (بيست)
const PRICE = /(?:(?:KD|KWD|د\.ك)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?))|(?:(\d{1,3}(?:,\d{3})*(?:\.\d{1,3})?)\s*(?:KD|KWD|د\.ك))/i;
const NOT_PRICE = /credit|\/mo|month|installment|قسط/i; // أقساط شهرية مو سعر
const num = m => parseFloat((m[1] || m[2]).replace(/,/g, ''));

async function scrape(browser, store, query) {
  const page = await browser.newPage({ userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36' });
  try {
    await page.goto(store.url(encodeURIComponent(query)), { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForTimeout(8000);
    const lines = (await page.evaluate(() => document.body.innerText)).split('\n').map(s => s.trim()).filter(Boolean);
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    const items = [];
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i].toLowerCase();
      if (l.length < 12 || PRICE.test(lines[i]) || !words.every(w => l.includes(w))) continue;
      // أول سعر بعد الاسم = السعر الحالي (العرض)، الثاني إن وجد = السعر قبل الخصم
      const prices = [];
      for (let j = i + 1; j < Math.min(i + 6, lines.length) && prices.length < 2; j++) {
        if (NOT_PRICE.test(lines[j])) break;
        const m = lines[j].match(PRICE);
        if (m) prices.push(num(m));
        else if (prices.length) break;
      }
      if (prices.length) items.push({ title: lines[i], price: Math.min(...prices), was: prices.length > 1 ? Math.max(...prices) : null });
    }
    return { store: store.name, items };
  } catch (e) {
    return { store: store.name, error: e.message.split('\n')[0], items: [] };
  } finally { await page.close(); }
}

(async () => {
  const query = process.argv.slice(2).join(' ');
  if (!query) { console.error('usage: node compare.js "<device>"'); process.exit(1); }
  const browser = await chromium.launch();
  const results = await Promise.all(STORES.map(s => scrape(browser, s, query)));
  await browser.close();
  console.log(JSON.stringify({ query, results }, null, 2));
})();
