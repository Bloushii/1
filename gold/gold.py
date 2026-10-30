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
    # الحجم حسب قوة الإشارة × وحدة القرامات
    return max([g for s, g in S["size_by_score"].items() if score >= float(s)], default=0) * S["unit_grams"]

CORE = d.setdefault("core", [])  # المحفظة الدائمة: قرامات ما تنباع. source: "profit" من الأرباح، "hold" تخزين على الإشارات

def profit_pool():
    # الأرباح اللي ما انشرى فيها ذهب للحين
    return realized() - sum(c["price"] * c["grams"] for c in CORE if c.get("source", "profit") == "profit")

SALES = d.setdefault("core_sales", [])  # بيع من الذهب المحفوظ، بمتوسط التكلفة وقت البيع

def core_grams():
    return sum(c["grams"] for c in CORE) - sum(x["grams"] for x in SALES)

def core_cost():
    # تكلفة الذهب المحفوظ اللي باقي (متوسط تكلفة)
    return sum(c["grams"] * c["price"] for c in CORE) - sum(x["grams"] * x["avg"] for x in SALES)

def core_realized():
    return sum((x["price"] - x["avg"]) * x["grams"] for x in SALES)

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
    holds = [c for c in CORE if c.get("source") == "hold"]
    last = holds[-1] if holds else None
    spaced = not last or (date.today() - date.fromisoformat(last["date"])).days >= S["hold_days"] \
        or buy_px <= last["price"] * (1 - S["ladder_gap_pct"] / 100)
    hold = next_lot(buy_px, x["score"]) if x["buy_ok"] and not event and spaced else 0
    if S.get("mode") == "dca":
        # DCA: كل dca_every_days نشتري كمية ثابتة، ضعفها أو 3 أضعافها وقت الضعف، ولا شي لو السعر مولّع. ما فيه تداول
        import dca
        due = not last or (date.today() - date.fromisoformat(last["date"])).days >= S["dca_every_days"]
        buy, hold = 0, dca.dca_grams(len(b.rows) - 1, S["dca_base_grams"]) if due and not event else 0
        # فرصة بين مواعيد DCA: إشارة شراء والسعر أرخص من آخر شراء بـ 1.5%
        latest = max(CORE, key=lambda c: c["date"]) if CORE else None
        if not hold and not event and x["buy_ok"] and latest and buy_px <= latest["price"] * (1 - S["ladder_gap_pct"] / 100):
            hold = S["dca_base_grams"] * (2 if x["score"] >= 7 else 1)
        # ربح زين: نبيع ربع الذهب لما السعر مولّع (RSI عالي) وربحك على متوسط التكلفة عالي، مرة كل 30 يوم كحد أقصى
        g = core_grams(); avg = core_cost() / g if g else 0; trim = 0
        recent = SALES and (date.today() - date.fromisoformat(SALES[-1]["date"])).days < S["trim_cooldown_days"]
        if g and not recent and x["rsi"] >= S["trim_rsi"] and sell_px >= avg * (1 + S["trim_profit_pct"] / 100):
            trim = max(1, round(g * S["trim_frac"])); hold = 0
        nxt = date.fromordinal(date.fromisoformat(last["date"]).toordinal() + S["dca_every_days"]) if last else date.today()
        why = ("خبر كبير خلال 24 ساعة، نشتري أول يوم بعده" if due and event else
               "السعر مرتفع بقوة (RSI فوق 70)، نفوّت هالمرة" if due else f"الشراء الجاي يوم {nxt}")
        return dict(x, event=event, buy_px=buy_px, sell_px=sell_px, sells=sells, buy_grams=0, hold_grams=hold, why=why,
                    core_buy=0, pool=profit_pool(), buy_target=0, trim_grams=trim, avg_cost=avg)
    why = "خبر كبير خلال 24 ساعة" if event and x["buy_ok"] else "ما فيه إشارة شراء" if not x["buy_ok"] else "الصفقات المفتوحة ما تسمح"
    pool = profit_pool() + sum((sell_px - t["buy_price"]) * t["grams"] for t in sells)
    return dict(x, event=event, buy_px=buy_px, sell_px=sell_px, sells=sells, buy_grams=buy, hold_grams=hold, why=why,
                core_buy=math.floor(pool / buy_px), pool=pool,
                buy_target=buy_px * (1 + (S["spread_pct"] + S["target_pct"]) / 100))

cmd, a = (sys.argv[1] if len(sys.argv) > 1 else "status") if __name__ == "__main__" else None, sys.argv[2:]

if cmd == "signal":
    x = decide(float(a[0]) if a else None)
    print(f"آخر سعر {x['date']}: {x['close']:,.1f}$ | الدار تقديراً: شراء {x['buy_px']:.3f} بيع {x['sell_px']:.3f}")
    print(f"المعدل الفني {x['score']}/10 | RSI {x['rsi']:.0f} | متوسط 50: {x['sma50']:,.0f} | متوسط 200: {x['sma200']:,.0f} | "
          f"دعم 20 يوم {x['low20']:,.0f} | مقاومة {x['high20']:,.0f} | خبر كبير خلال 24 ساعة: {'نعم' if x['event'] else 'لا'}")
    for t in x["sells"]:
        print(f"🔴 بيع {t['grams']:g} قرام (صفقة #{t['id']}، شراء {t['buy_price']:.3f}) ربح {(x['sell_px'] - t['buy_price']) * t['grams']:+.3f} د.ك")
    if x.get("trim_grams"):
        print(f"🔴 بيع {x['trim_grams']:g} قرام بحدود {x['sell_px']:.3f} (متوسط تكلفتك {x['avg_cost']:.3f}) ربح {(x['sell_px'] - x['avg_cost']) * x['trim_grams']:+.3f} د.ك")
    total = x["buy_grams"] + x["hold_grams"] + x["core_buy"]
    if total:
        print(f"🟢 اشتر {total:g} قرام بحدود {x['buy_px']:.3f} د.ك  [داخلياً: تداول {x['buy_grams']:g}، تخزين {x['hold_grams']:g}، أرباح {x['core_buy']:g}]")
    if not x["sells"] and not x["core_buy"] and not x["buy_grams"] and not x["hold_grams"] and not x.get("trim_grams"):
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
elif cmd == "bought":
    # المستخدم يقول بس "شريت X قرام بسعر Y". نوزعها على حسب قرار اليوم: تداول، بعدين أرباح، بعدين تخزين
    price = float(a[0]); x = decide(); left = float(a[1]) if len(a) > 1 else x["buy_grams"] + x["hold_grams"] + x["core_buy"]
    for kind, n in (("buy", x["buy_grams"]), ("core", x["core_buy"]), ("hold", x["hold_grams"] + left)):
        n = min(n, left); left -= n
        if not n: continue
        if kind == "buy":
            T.append({"id": len(T) + 1, "date": str(date.today()), "grams": n, "buy_price": price, "sell_price": None})
        else:
            CORE.append({"date": str(date.today()), "grams": n, "price": price, "source": "profit" if kind == "core" else "hold"})
        print(f"✅ {kind}: {n:g} قرام × {price:.3f}")
    save()
elif cmd == "sold":
    # بيع من الذهب المحفوظ: python3 gold/gold.py sold <السعر> <القرامات>
    price, g = float(a[0]), float(a[1]); avg = core_cost() / core_grams()
    SALES.append({"date": str(date.today()), "grams": g, "price": price, "avg": round(avg, 4)})
    save(); print(f"✅ بعت {g:g} قرام × {price:.3f} | متوسط التكلفة {avg:.3f} | الربح {(price - avg) * g:+.3f} د.ك | باقي {core_grams():g} قرام")
elif cmd in ("core", "hold"):
    # core: قرام من الأرباح، hold: تخزين على الإشارة. الاثنين ما ينباعون
    price = float(a[0]); g = float(a[1]) if len(a) > 1 else 1
    CORE.append({"date": str(date.today()), "grams": g, "price": price, "source": "profit" if cmd == "core" else "hold"})
    save(); print(f"✅ سجلت {g:g} قرام {'من الأرباح' if cmd == 'core' else 'للتخزين'} × {price:.3f} | المحفظة الدائمة صارت {core_grams():g} قرام")
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
    print(f"الربح المحقق كله: {realized():.3f} د.ك | المحفظة الدائمة {core_grams():g} قرام | أرباح تنتظر قرام: {profit_pool():.3f} د.ك")
    print("حجم الصفقة الجاية: " + " | ".join(f"معدل {s}+ = {next_lot(p, float(s)):g} قرام" for s in S["size_by_score"]))
elif cmd == "report":
    # تقرير الشهر: كل الشراء والبيع فيه (التداول والذهب المحفوظ)، وقيمة المحفظة. اختياري: سعر بيعك للدار الحين
    month = a[0] if a else str(date.today())[:7]
    sell_now = float(a[1]) if len(a) > 1 else None
    buys = [(t["grams"], t["buy_price"]) for t in T if t["date"].startswith(month)] + \
           [(c["grams"], c["price"]) for c in CORE if c["date"].startswith(month)]
    sells = [((t["sell_price"] - t["buy_price"]) * t["grams"], t["buy_price"] * t["grams"]) for t in T if t.get("sell_date", "").startswith(month)] + \
            [((x["price"] - x["avg"]) * x["grams"], x["avg"] * x["grams"]) for x in SALES if x["date"].startswith(month)]
    print(f"تقرير شهر {month}")
    if buys:
        g = sum(q for q, _ in buys); spent = sum(q * p for q, p in buys)
        print(f"اشتريت: {len(buys)} مرة، {g:g} قرام بـ {spent:.3f} د.ك (متوسط {spent / g:.3f})")
    else:
        print("اشتريت: ولا مرة")
    if sells:
        gains = [x for x, _ in sells]
        print(f"بعت: {len(sells)} مرة | رابحة {sum(1 for x in gains if x > 0)} | خاسرة {sum(1 for x in gains if x < 0)} | "
              f"الربح {sum(gains):.3f} د.ك ({sum(gains) / sum(c for _, c in sells) * 100:.2f}%) | أفضل {max(gains):+.3f} | أقل {min(gains):+.3f}")
    else:
        print("بعت: ولا مرة")
    lots = open_lots()
    held = core_grams() + sum(t["grams"] for t in lots)
    cost = core_cost() + sum(t["buy_price"] * t["grams"] for t in lots)
    line = f"ذهبك كله الحين: {held:g} قرام بتكلفة {cost:.3f} د.ك (متوسط {cost / held:.3f})" if held else "ذهبك كله الحين: 0"
    if sell_now and held:
        line += f" | قيمته لو تبيعه {held * sell_now:.3f} د.ك ({held * sell_now - cost:+.3f}، {(held * sell_now / cost - 1) * 100:+.2f}%)"
    print(line)
    real = realized() + core_realized()
    if real:
        print(f"الربح اللي قبضته من البداية: {real:.3f} د.ك")
