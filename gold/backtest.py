# محاكاة الاستراتيجية على أسعار الذهب اليومية (gold/data/xauusd_1d.csv من سبتمبر 2021)
# الجزء الفني وفلتر مواعيد الفيدرالي والوظائف ينحسبون بالضبط. تقييم الأخبار والمحللين ما ينعاد تاريخياً،
# فالمعدل هنا مبني على الشارت بس.
import csv, os, sys, json
from datetime import date, timedelta
from collections import defaultdict

OZ = 31.1035
HERE = os.path.dirname(__file__)
S = json.load(open(os.path.join(HERE, "ledger.json")))["settings"]

FOMC = """2021-11-03 2021-12-15 2022-01-26 2022-03-16 2022-05-04 2022-06-15 2022-07-27 2022-09-21 2022-11-02 2022-12-14
2023-02-01 2023-03-22 2023-05-03 2023-06-14 2023-07-26 2023-09-20 2023-11-01 2023-12-13
2024-01-31 2024-03-20 2024-05-01 2024-06-12 2024-07-31 2024-09-18 2024-11-07 2024-12-18
2025-01-29 2025-03-19 2025-05-07 2025-06-18 2025-07-30 2025-09-17 2025-10-29 2025-12-10
2026-01-28 2026-03-18 2026-04-29 2026-06-17 2026-07-29 2026-09-16 2026-10-28 2026-12-09""".split()
FOMC = {date.fromisoformat(x) for x in FOMC}

def event_soon(d):
    # قرار الفيدرالي (يطلع بالليل بتوقيت الكويت) أو الوظائف (أول جمعة بالشهر) خلال 24 ساعة
    nfp = d.day <= 7 and d.weekday() == 4
    return d in FOMC or (d + timedelta(1)) in FOMC or nfp or (d.weekday() == 3 and (d + timedelta(1)).day <= 7)

rows = []
for r in csv.DictReader(open(os.path.join(HERE, "data", "xauusd_1d.csv"))):
    d = date.fromisoformat(r["Datetime"][:10])
    if d.weekday() >= 5:  # شمعة الأحد القصيرة
        continue
    rows.append((d, float(r["High"]), float(r["Low"]), float(r["Close"])))

def rsi(closes, n=14):
    out, ag, al = [None] * len(closes), 0, 0
    for i in range(1, len(closes)):
        ch = closes[i] - closes[i - 1]
        g, l = max(ch, 0), max(-ch, 0)
        if i <= n:
            ag += g / n; al += l / n
        else:
            ag = (ag * (n - 1) + g) / n; al = (al * (n - 1) + l) / n
        if i >= n:
            out[i] = 100 - 100 / (1 + ag / al) if al else 100
    return out

C = [r[3] for r in rows]
R = rsi(C)
sma = lambda i, n: sum(C[i - n + 1:i + 1]) / n

def score(i):
    s, c = 0, C[i]
    if c > sma(i, 200): s += 3
    if sma(i, 50) > sma(i, 200): s += 1
    s += 3 if R[i] <= 30 else 2 if R[i] <= 40 else 1 if R[i] <= 50 else 0
    if c <= min(r[2] for r in rows[i - 19:i + 1]) * 1.01: s += 2
    if c > rows[i - 1][1]: s += 1
    return s

def size(sc):
    return max([g for k, g in S["size_by_score"].items() if sc >= float(k)], default=0)

def buy_ok(i, min_score=S["min_score"], rsi_trig=S["rsi_trigger"], sup=S["support_pct"]):
    c = C[i]
    trig = c <= min(r[2] for r in rows[i - 19:i + 1]) * (1 + sup / 100) or R[i] <= rsi_trig
    confirm = c > sma(i, 200) or c > rows[i - 1][1]
    return score(i) >= min_score and trig and confirm

def today():
    # إشارة آخر يوم بالبيانات، بنفس قواعد المحاكاة
    i = len(rows) - 1
    return dict(date=rows[i][0], close=C[i], score=score(i), rsi=R[i], sma50=sma(i, 50), sma200=sma(i, 200),
                low20=min(r[2] for r in rows[i - 19:i + 1]), high20=max(r[1] for r in rows[i - 19:i + 1]),
                prev_high=rows[i - 1][1], buy_ok=buy_ok(i), size=size(score(i)))

def run(target=S["target_pct"], spread=S["spread_pct"], prem=S["dealer_premium_pct"], fx=S["usd_kwd"],
        max_lots=S["max_open_lots"], gap=S["ladder_gap_pct"], min_score=S["min_score"], use_events=True, compound=True, start=200, end=None, log=False,
        rsi_trig=S["rsi_trigger"], sup=S["support_pct"], unit=S["unit_grams"]):
    lots, done, realized, peak_cap, trades, worst = [], [], 0.0, 0.0, [], 0.0
    end = end or len(rows)
    monthly = defaultdict(float)
    for i in range(start, end):
        d, hi, lo, c = rows[i]
        buy_px = c / OZ * fx * (1 + prem / 100)
        sell_px = buy_px * (1 - spread / 100)
        sc = score(i)
        resist = c >= max(r[1] for r in rows[i - 19:i + 1]) * 0.99
        # البيع
        for L in list(lots):
            p = (sell_px / L["px"] - 1) * 100
            early = p >= spread + 0.75 and (R[i] >= 70 or resist or (use_events and event_soon(d)))
            if sell_px >= L["px"] * (1 + (spread + target) / 100) or early:
                gain = (sell_px - L["px"]) * L["g"]
                realized += gain; monthly[d.strftime("%Y-%m")] += gain
                lots.remove(L); done.append({**L, "out": d, "sell": sell_px, "gain": gain})
                if log: trades.append(f"{d} بيع  {L['g']:g}g @ {sell_px:.3f} (شراء {L['px']:.3f} يوم {L['d']}) ربح {gain:+.3f}")
        # الشراء
        ladder = not lots or buy_px <= min(L["px"] for L in lots) * (1 - gap / 100)
        if buy_ok(i, min_score, rsi_trig, sup) and len(lots) < max_lots and ladder and not (use_events and event_soon(d)):
            g = size(sc) * unit + (int(realized // buy_px) if compound else 0)
            lots.append({"d": d, "px": buy_px, "g": g})
            if log: trades.append(f"{d} شراء {g:g}g @ {buy_px:.3f} (معدل {sc}, RSI {R[i]:.0f})")
        peak_cap = max(peak_cap, sum(L["px"] * L["g"] for L in lots))
        worst = min(worst, sum((sell_px - L["px"]) * L["g"] for L in lots))
    last_sell = rows[end - 1][3] / OZ * fx * (1 + prem / 100) * (1 - spread / 100)
    unreal = sum((last_sell - L["px"]) * L["g"] for L in lots)
    return dict(done=done, lots=lots, realized=realized, unreal=unreal, peak_cap=peak_cap, monthly=monthly,
                trades=trades, worst=worst, months=len({r[0].strftime("%Y-%m") for r in rows[start:end]}))

def summary(name, x):
    hold = [(t["out"] - t["d"]).days for t in x["done"]]
    pos = sum(1 for v in x["monthly"].values() if v > 0)
    pct = x["realized"] / x["peak_cap"] * 100 if x["peak_cap"] else 0
    print(f"{name}: {len(x['done'])} صفقة | ربح محقق {x['realized']:.2f} د.ك | أعلى مبلغ مستخدم {x['peak_cap']:.0f} د.ك "
          f"({pct:.1f}% كله، {pct / x['months']:.2f}% بالشهر) | شهور فيها ربح {pos}/{x['months']} | "
          f"متوسط المسكة {sum(hold) / len(hold) if hold else 0:.0f} يوم، أطول {max(hold, default=0)} | "
          f"أسوأ خسارة مؤقتة {x['worst']:.2f} | مفتوح {sum(L['g'] for L in x['lots']):g}g بـ {x['unreal']:+.2f} د.ك")

if __name__ == "__main__":
    base = run(log=True)
    if "-v" in sys.argv:
        print("\n".join(base["trades"]))
    summary("الأساسية", base)
    print("\nحسب السنة (ربح محقق):", {y: round(sum(v for m, v in base["monthly"].items() if m.startswith(y)), 2) for y in "2022 2023 2024 2025 2026".split()})
    print("\nمقارنات:")
    for t in (0.75, 1.0, 1.5, 2.5, 4.0):
        summary(f"  هدف {t}%", run(target=t))
    summary("  بدون فلتر الأخبار", run(use_events=False))
    summary("  بدون تراكم", run(compound=False))
    summary("  فرق 3% بين الشراء والبيع", run(spread=3.0))
    summary("  أقصى 5 صفقات", run(max_lots=5))
    for s in (5, 7):
        summary(f"  أقل معدل {s}", run(min_score=s))
    first = rows[200][3] / OZ * S["usd_kwd"] * (1 + S["dealer_premium_pct"] / 100)
    now = rows[-1][3] / OZ * S["usd_kwd"] * (1 + S["dealer_premium_pct"] / 100) * (1 - S["spread_pct"] / 100)
    print(f"\nللمقارنة، شراء وتخزين من {rows[200][0]}: {first:.3f} → {now:.3f} = {(now / first - 1) * 100:+.1f}%")
