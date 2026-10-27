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

def next_lot(price, score=S["min_score"]):
    # الحجم حسب قوة الإشارة × وحدة القرامات، وفوقه تراكم: كل ما الربح المحقق يغطي قرام، نزيد قرام
    base = max([g for s, g in S["size_by_score"].items() if score >= float(s)], default=0) * S["unit_grams"]
    return base + math.floor(realized() / price) if base else 0

def target(t):
    return t["buy_price"] * (1 + (S["spread_pct"] + S["target_pct"]) / 100)

def early_sell(t, sell_px, x, event):
    # بيع مبكر: الربح يغطي الفرق + 0.75% والسعر عند مقاومة أو RSI عالي أو فيه خبر كبير خلال 24 ساعة
    ok = sell_px >= t["buy_price"] * (1 + (S["spread_pct"] + 0.75) / 100)
    return ok and (x["rsi"] >= 70 or x["close"] >= x["high20"] * 0.99 or event)

def decide(sell_now=None):
    # قرار اليوم بنفس قواعد المحاكاة. sell_now: سعر بيعك للدار الحين لو معروف
    import backtest as b
    x = b.today(); event = b.event_soon(date.today())
    buy_px = x["close"] / OZ * S["usd_kwd"] * (1 + S["dealer_premium_pct"] / 100)
    sell_px = sell_now or buy_px * (1 - S["spread_pct"] / 100)
    sells = [t for t in open_lots() if sell_px >= target(t) or early_sell(t, sell_px, x, event)]
    lots = [t for t in open_lots() if t not in sells]
    ladder = not lots or buy_px <= min(t["buy_price"] for t in lots) * (1 - S["ladder_gap_pct"] / 100)
    g = next_lot(buy_px, x["score"])
    buy = g if x["buy_ok"] and not event and ladder and len(lots) < S["max_open_lots"] else 0
    why = "خبر كبير خلال 24 ساعة" if event and x["buy_ok"] else "ما فيه إشارة شراء" if not x["buy_ok"] else "الصفقات المفتوحة ما تسمح"
    return dict(x, event=event, buy_px=buy_px, sell_px=sell_px, sells=sells, buy_grams=buy, why=why,
                buy_target=buy_px * (1 + (S["spread_pct"] + S["target_pct"]) / 100))

cmd, a = (sys.argv[1] if len(sys.argv) > 1 else "status") if __name__ == "__main__" else None, sys.argv[2:]

if cmd == "signal":
    x = decide(float(a[0]) if a else None)
    print(f"آخر سعر {x['date']}: {x['close']:,.1f}$ | الدار تقديراً: شراء {x['buy_px']:.3f} بيع {x['sell_px']:.3f}")
    print(f"المعدل الفني {x['score']}/10 | RSI {x['rsi']:.0f} | متوسط 50: {x['sma50']:,.0f} | متوسط 200: {x['sma200']:,.0f} | "
          f"دعم 20 يوم {x['low20']:,.0f} | مقاومة {x['high20']:,.0f} | خبر كبير خلال 24 ساعة: {'نعم' if x['event'] else 'لا'}")
    for t in x["sells"]:
        print(f"🔴 بيع {t['grams']:g} قرام (صفقة #{t['id']}، شراء {t['buy_price']:.3f}) ربح {(x['sell_px'] - t['buy_price']) * t['grams']:+.3f} د.ك")
    if x["buy_grams"]:
        print(f"🟢 اشتر {x['buy_grams']:g} قرام بحدود {x['buy_px']:.3f} | تبيع لما سعر بيعك للدار يوصل {x['buy_target']:.3f}")
    elif not x["sells"]:
        print(f"⚪ لا تسوي شي اليوم ({x['why']})")
elif cmd == "price":
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
    price = float(a[0]); g = float(a[1]) if len(a) > 1 else next_lot(price, 10)
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
    p = lots[-1]["buy_price"] if lots else 40
    print(f"الربح المحقق كله: {realized():.3f} د.ك")
    print("حجم الصفقة الجاية: " + " | ".join(f"معدل {s}+ = {next_lot(p, float(s)):g} قرام" for s in S["size_by_score"]))
elif cmd == "report":
    month = a[0] if a else str(date.today())[:7]
    done = [t for t in T if t.get("sell_date", "").startswith(month)]
    profit = sum((t["sell_price"] - t["buy_price"]) * t["grams"] for t in done)
    capital = sum(t["buy_price"] * t["grams"] for t in done)
    print(f"شهر {month}: {len(done)} صفقة مباعة | ربح {profit:.3f} د.ك" + (f" | {profit / capital * 100:.2f}% على المبلغ المستخدم" if capital else ""))
