# DCA ذكي: نشتري كمية ثابتة كل أسبوع، ونزيدها وقت الضعف، ونقللها وقت الغلا. ما نبيع
import backtest as b

def dca_grams(i, base=1, smart=True):
    # كم قرام هالأسبوع حسب حالة السعر
    if not smart:
        return base
    if b.buy_ok(i):
        return base * (3 if b.score(i) >= 7 else 2)
    if b.R[i] >= 70:
        return 0  # السعر مولّع، نفوّت هالأسبوع
    return base

def run(start, end=None, base=1, smart=True, every=7):
    S = b.S; f = S["usd_kwd"] / b.OZ * (1 + S["dealer_premium_pct"] / 100)
    end = end or len(b.rows)
    g = cost = 0.0; last = None; worst = 0.0
    for i in range(start, end):
        d = b.rows[i][0]
        if last is None or (d - last).days >= every:
            if b.event_soon(d):
                continue  # ننطر يعدّي الخبر ونشتري اليوم اللي بعده
            q = dca_grams(i, base, smart); px = b.C[i] * f
            g += q; cost += q * px; last = d
        worst = min(worst, g * b.C[i] * f * (1 - S["spread_pct"] / 100) - cost)
    val = g * b.C[end - 1] * f * (1 - S["spread_pct"] / 100)
    return dict(grams=g, cost=cost, value=val, pct=(val / cost - 1) * 100 if cost else 0, worst=worst)
