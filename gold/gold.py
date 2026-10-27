import json, sys, os, math
from datetime import date

OZ = 31.1035
PATH = os.path.join(os.path.dirname(__file__), "ledger.json")
d = json.load(open(PATH))
S = d["settings"]
T = d["trades"]

def save():
    json.dump(d, open(PATH, "w"), ensure_ascii=False, indent=2)

def open_lots():
    return [t for t in T if t.get("sell_price") is None]

def realized():
    return sum((t["sell_price"] - t["buy_price"]) * t["grams"] for t in T if t.get("sell_price") is not None)

def next_lot(price):
    # تراكم: كل ما الربح المحقق يغطي قرام، نزيد حجم الصفقة قرام
    return S["base_lot_grams"] + (math.floor(realized() / price) if price else 0)

def target(t):
    return t["buy_price"] * (1 + (S["spread_pct"] + S["target_pct"]) / 100)

cmd, a = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]

if cmd == "price":
    usd_oz = float(a[0]); fx = float(a[1]) if len(a) > 1 else S["usd_kwd"]
    spot = usd_oz / OZ * fx
    buy = spot * (1 + S["dealer_premium_pct"] / 100)
    sell = buy * (1 - S["spread_pct"] / 100)
    print(f"العالمي: {usd_oz:,.2f}$ للأونصة × {fx} = {spot:.3f} د.ك للقرام (24)")
    print(f"تقدير الدار: شراء {buy:.3f} | بيع لهم {sell:.3f}")
    print(f"عشان تربح صفقة لازم يطلع السعر {S['spread_pct'] + S['target_pct']:.1f}% فوق سعر شرائك")
elif cmd == "quote":
    # سعر الدار مع السعر العالمي بنفس الوقت: نسجله ونعاير النسب على متوسط كل الأسعار المسجلة
    buy, sell, usd_oz = map(float, a[:3])
    Q = d.setdefault("quotes", [])
    Q.append({"date": str(date.today()), "spot_usd": usd_oz, "buy": buy, "sell": sell})
    prem = [(q["buy"] / (q["spot_usd"] / OZ * S["usd_kwd"]) - 1) * 100 for q in Q]
    spr = [(q["buy"] - q["sell"]) / q["buy"] * 100 for q in Q]
    S["dealer_premium_pct"] = round(sum(prem) / len(prem), 2); S["spread_pct"] = round(sum(spr) / len(spr), 2)
    save(); print(f"سجلت السعر ({len(Q)} أسعار). نسبة الدار فوق العالمي: {S['dealer_premium_pct']}% | الفرق بين الشراء والبيع: {S['spread_pct']}%")
elif cmd == "buy":
    price = float(a[0]); g = float(a[1]) if len(a) > 1 else next_lot(price)
    T.append({"id": len(T) + 1, "date": str(date.today()), "grams": g, "buy_price": price, "sell_price": None})
    save(); print(f"✅ سجلت شراء #{len(T)}: {g:g} قرام × {price:.3f} | الهدف {target(T[-1]):.3f}")
elif cmd == "sell":
    t = next(t for t in T if t["id"] == int(a[0])); t["sell_price"] = float(a[1]); t["sell_date"] = str(date.today())
    save(); print(f"✅ سجلت بيع #{t['id']}: ربح {(t['sell_price'] - t['buy_price']) * t['grams']:.3f} د.ك")
elif cmd == "status":
    sell_now = float(a[0]) if a else None
    lots = open_lots()
    print(f"صفقات مفتوحة: {len(lots)} / {S['max_open_lots']}")
    for t in lots:
        line = f"#{t['id']} {t['date']}: {t['grams']:g} قرام × {t['buy_price']:.3f} → الهدف {target(t):.3f}"
        if sell_now:
            pnl = (sell_now - t["buy_price"]) * t["grams"]
            line += f" | الحين {pnl:+.3f} د.ك" + (" 🔔 بيع" if sell_now >= target(t) else "")
        print(line)
    if lots:
        floor = min(t["buy_price"] for t in lots) * (1 - S["ladder_gap_pct"] / 100)
        print(f"الشراء الجاي بس تحت {floor:.3f} (أقل من آخر سعر بـ {S['ladder_gap_pct']:g}%)")
    print(f"الربح المحقق كله: {realized():.3f} د.ك | حجم الصفقة الجاية: {next_lot(lots[-1]['buy_price'] if lots else 40):g} قرام")
elif cmd == "report":
    month = a[0] if a else str(date.today())[:7]
    done = [t for t in T if t.get("sell_date", "").startswith(month)]
    profit = sum((t["sell_price"] - t["buy_price"]) * t["grams"] for t in done)
    capital = sum(t["buy_price"] * t["grams"] for t in done)
    print(f"شهر {month}: {len(done)} صفقة مباعة | ربح {profit:.3f} د.ك" + (f" | {profit / capital * 100:.2f}% على المبلغ المستخدم" if capital else ""))
