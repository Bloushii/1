# يطلع ملفات صفحة "قرار الذهب اليومي": القرار، والأسعار، والصفقات
# python3 gold/export.py "ملخص الأخبار" "تنبيه خبر (أو فاضي)" [سعر بيعك للدار]
import json, os, sys
from datetime import datetime, timezone
import gold as g, backtest as b

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)
note = sys.argv[1] if len(sys.argv) > 1 else ""
alert = sys.argv[2] if len(sys.argv) > 2 else ""
x = g.decide(float(sys.argv[3]) if len(sys.argv) > 3 else None)

if x["sells"]:
    grams = sum(t["grams"] for t in x["sells"])
    action, text = "sell", f"بيع {grams:g} قرام"
    detail = "، ".join(f"صفقة #{t['id']} ربح {(x['sell_px'] - t['buy_price']) * t['grams']:+.3f} د.ك" for t in x["sells"])
elif x["buy_grams"]:
    action, text = "buy", f"اشتر {x['buy_grams']:g} قرام"
    detail = f"بحدود {x['buy_px']:.3f} د.ك، وتبيع لما سعر بيعك للدار يوصل {x['buy_target']:.3f}"
else:
    action, text, detail = "hold", "لا تسوي شي اليوم", x["why"]

decision = [{
    "checked_at": datetime.now(timezone.utc).isoformat(timespec="minutes"), "price_date": str(x["date"]),
    "action": action, "headline": text, "detail": detail, "news": note, "alert": alert,
    "score": x["score"], "rsi": round(x["rsi"], 1), "event_24h": "نعم" if x["event"] else "لا",
    "spot_usd": round(x["close"], 1), "dealer_buy_kwd": round(x["buy_px"], 3), "dealer_sell_kwd": round(x["sell_px"], 3),
    "sma200_usd": round(x["sma200"]), "support_usd": round(x["low20"]), "resistance_usd": round(x["high20"]),
}]
f = g.S["usd_kwd"] / g.OZ * (1 + g.S["dealer_premium_pct"] / 100)
prices = [{"day": str(r[0]), "spot_usd": round(r[3], 1), "dealer_buy_kwd": round(r[3] * f, 3)} for r in b.rows[-130:]]
trades = [{"id": t["id"], "bought": t["date"], "grams": t["grams"], "buy_kwd": t["buy_price"],
           "target_kwd": round(g.target(t), 3), "sold": t.get("sell_date", ""), "sell_kwd": t.get("sell_price"),
           "profit_kwd": round((t["sell_price"] if t.get("sell_price") is not None else x["sell_px"]) - t["buy_price"], 3) * t["grams"],
           "status": "مفتوحة" if t.get("sell_price") is None else "مباعة"} for t in g.T]
for name, rows in (("decision", decision), ("prices", prices)):
    json.dump(rows, open(os.path.join(OUT, f"{name}.json"), "w"), ensure_ascii=False)
# الصفقات CSV عشان العناوين تبقى حتى لو ما فيه صفقات
import csv
cols = ["id", "bought", "grams", "buy_kwd", "target_kwd", "sold", "sell_kwd", "profit_kwd", "status"]
with open(os.path.join(OUT, "trades.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, cols); w.writeheader(); w.writerows(trades)
print(text, "|", detail)
