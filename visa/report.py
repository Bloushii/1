import json, sys, os
d = json.load(open(os.path.join(os.path.dirname(__file__), "ledger.json")))
month = sys.argv[1] if len(sys.argv) > 1 else d["start_month"]
L, R = d["limit_per_card"], d["cashback_rate"]
ps = [p for p in d["purchases"] if p["month"] == month]
tot_spent = tot_cb = tot_sold = 0
print(f"شهر {month}")
for c in d["cards"]:
    mine = [p for p in ps if p["card"] == c["last4"]]
    spent = sum(p["qty"] * p["buy_price"] for p in mine)
    sold = sum(p["qty"] * p["sell_price"] for p in mine if p.get("sell_price") is not None)
    cb = min(spent, L) * R
    tot_spent += spent; tot_cb += cb; tot_sold += sold
    print(f"{c['last4']} {c['name']}: صرف {spent:g} | باقي {max(L-spent,0):g} | كاش باك {cb:g}" + (" ⚠️ تجاوز الحد" if spent > L else ""))
print(f"المجموع: صرف {tot_spent:g} / {L*len(d['cards'])} | باقي {max(L*len(d['cards'])-tot_spent,0):g}")
print(f"المبيع {tot_sold:g} | كاش باك {tot_cb:g} | صافي الربح (للمباع) {tot_sold + tot_cb - tot_spent:g}")
