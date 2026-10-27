# صفحة قرار اليوم كـ HTML ثابت بدون سكربتات، عشان تنفتح حتى على المتصفحات القديمة
# يقرا ملفات export.py من gold/out ويكتب gold/out/page.html
import json, os, csv, html

OUT = os.path.join(os.path.dirname(__file__), "out")
x = json.load(open(os.path.join(OUT, "decision.json")))[0]
prices = json.load(open(os.path.join(OUT, "prices.json")))
trades = list(csv.DictReader(open(os.path.join(OUT, "trades.csv"))))
e = lambda v: html.escape(str(v))

# رسم السعر: خط SVG بسيط
pts = [float(p["dealer_buy_kwd"]) for p in prices]
lo, hi = min(pts), max(pts)
W, H = 600, 160
path = " ".join(f"{'M' if i == 0 else 'L'}{i * W / (len(pts) - 1):.1f},{H - 10 - (v - lo) / (hi - lo or 1) * (H - 20):.1f}" for i, v in enumerate(pts))

color = {"buy": "var(--ok)", "sell": "var(--bad)", "hold": "var(--warn)"}[x["action"]]
alert = f'<section class="alert"><b>تنبيه خبر</b><p>{e(x["alert"])}</p></section>' if x.get("alert") else ""
rows = "".join(
    f"<tr><td>{e(t['bought'])}</td><td>{e(t['grams'])}</td><td>{float(t['buy_kwd']):.3f}</td>"
    f"<td>{e(t['status'])}</td><td class=\"{'ok' if float(t['profit_kwd']) >= 0 else 'bad'}\">{float(t['profit_kwd']):+.3f}</td></tr>"
    for t in reversed(trades))
table = (f"<table><thead><tr><th>التاريخ</th><th>قرام</th><th>سعر الشراء</th><th>الحالة</th><th>الربح د.ك</th></tr></thead><tbody>{rows}</tbody></table>"
         if trades else '<p class="muted">ما فيه صفقات للحين.</p>')
realized = sum(float(t["profit_kwd"]) for t in trades if t["status"] == "مباعة")

page = f"""<title>قرار الذهب اليومي</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root {{ --bg:#faf8f2; --fg:#1f1b12; --muted:#6b6352; --panel:#ffffff; --line:#e6dfcc; --gold:#9a7412; --ok:#1d7a3d; --bad:#b3261e; --warn:#8a6a00; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#16140f; --fg:#f1ece0; --muted:#a69d88; --panel:#201d16; --line:#3a3427; --gold:#d9b14a; --ok:#5cc282; --bad:#ef7a70; --warn:#e0b84a; color-scheme:dark; }} }}
:root[data-theme="dark"] {{ --bg:#16140f; --fg:#f1ece0; --muted:#a69d88; --panel:#201d16; --line:#3a3427; --gold:#d9b14a; --ok:#5cc282; --bad:#ef7a70; --warn:#e0b84a; color-scheme:dark; }}
body {{ background:var(--bg); color:var(--fg); font-family:-apple-system,"SF Arabic","Geeza Pro",Tahoma,sans-serif; direction:rtl; line-height:1.6;
  padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); padding-block:20px; }}
.wrap {{ max-width:40rem; margin:0 auto; display:grid; gap:14px; }}
h1 {{ margin:0; font-size:1.5rem; color:var(--gold); }}
.muted {{ color:var(--muted); font-size:.85rem; margin:0; }}
.card {{ background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:16px; display:grid; gap:6px; min-width:0; }}
.decision {{ border-right:6px solid {color}; }}
.verdict {{ font-size:2rem; font-weight:700; color:{color}; margin:0; line-height:1.3; }}
.alert {{ border:1px solid var(--bad); border-radius:12px; padding:12px 16px; }}
.alert b {{ color:var(--bad); font-size:.85rem; }} .alert p {{ margin:4px 0 0; font-size:1.05rem; }}
.tiles {{ display:grid; grid-template-columns:repeat(2, minmax(0,1fr)); gap:10px; }}
.tile {{ background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:12px; }}
.tile .n {{ font-size:1.4rem; font-weight:700; font-variant-numeric:tabular-nums; display:block; }}
h2 {{ margin:0; font-size:1.05rem; }}
svg {{ width:100%; height:auto; display:block; }}
.tw {{ overflow-x:auto; }} table {{ width:100%; border-collapse:collapse; font-size:.9rem; font-variant-numeric:tabular-nums; }}
th, td {{ text-align:right; padding:6px 8px; border-bottom:1px solid var(--line); white-space:nowrap; }} th {{ color:var(--muted); font-weight:600; font-size:.8rem; }}
.ok {{ color:var(--ok); }} .bad {{ color:var(--bad); }}
</style>
<div class="wrap">
  <header><h1>قرار الذهب اليومي</h1><p class="muted">ذهب عيار 24 بأسعار دار السبائك · آخر فحص {e(x["checked_at"].replace("T", " ").replace("+00:00", " UTC"))}</p></header>
  {alert}
  <section class="card decision"><p class="muted">قرار اليوم</p><p class="verdict">{e(x["headline"])}</p><p style="margin:0">{e(x["detail"])}</p></section>
  <section class="tiles">
    <div class="tile"><span class="muted">شراؤك من الدار</span><span class="n">{x["dealer_buy_kwd"]:.3f}</span><span class="muted">د.ك للقرام (تقدير)</span></div>
    <div class="tile"><span class="muted">بيعك للدار</span><span class="n">{x["dealer_sell_kwd"]:.3f}</span><span class="muted">د.ك للقرام (تقدير)</span></div>
    <div class="tile"><span class="muted">ذهبك كله</span><span class="n">{e(x["held_grams"])}</span><span class="muted">قرام</span></div>
    <div class="tile"><span class="muted">الربح المحقق</span><span class="n">{realized:.3f}</span><span class="muted">د.ك</span></div>
  </section>
  <section class="card"><h2>الفيدرالي والأخبار</h2><p style="margin:0">{e(x["news"])}</p>
    <p class="muted">المعدل الفني {e(x["score"])}/10 · RSI {e(x["rsi"])} · السعر العالمي {x["spot_usd"]:,.0f}$ · دعم {x["support_usd"]:,}$ · مقاومة {x["resistance_usd"]:,}$</p></section>
  <section class="card"><h2>سعر شرائك من الدار، آخر 6 شهور</h2>
    <svg viewBox="0 0 {W} {H}" role="img" aria-label="رسم سعر الذهب بالدينار"><path d="{path}" fill="none" stroke="var(--gold)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/></svg>
    <p class="muted">من {lo:.3f} إلى {hi:.3f} د.ك · آخر سعر {pts[-1]:.3f}</p></section>
  <section class="card"><h2>صفقاتك</h2><div class="tw">{table}</div></section>
  <p class="muted">تحليل آلي وليس نصيحة مالية مرخصة. الأسعار تقديرية، والسعر الفعلي هو سعر الدار وقت الشراء.</p>
</div>
"""
open(os.path.join(OUT, "page.html"), "w").write(page)
print("ok")
