# مسابقة استراتيجيات DCA للذهب عيار 24 على بيانات 2004–2026
# نختار الأفضل على محاولات بدت 2005–2015 (التصميم)، ونختبرها على محاولات بدت 2016–2023 (اختبار ما شافته)
# python3 gold/tournament.py [سنين المحاولة، الافتراضي 3]
import csv, os, sys, itertools
from datetime import date, timedelta

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import backtest as b

# البيانات: القديمة لين بداية الجديدة، وبعدها الجديدة
rows = []
first_new = b.rows[0][0]
for r in csv.DictReader(open(os.path.join(HERE, "data", "xauusd_1d_2004_2025.csv")), delimiter=";"):
    d = date.fromisoformat(r["Date"][:10].replace(".", "-"))
    if d.weekday() < 5 and d < first_new:
        rows.append((d, float(r["High"]), float(r["Low"]), float(r["Close"])))
rows += b.rows
b.rows[:] = rows; b.C[:] = [r[3] for r in rows]; b.R[:] = b.rsi(b.C)
C, R, N = b.C, b.R, len(rows)
S = b.S
F = S["usd_kwd"] / b.OZ * (1 + S["dealer_premium_pct"] / 100)
SP = 1 - S["spread_pct"] / 100

# مؤشرات محسوبة مرة وحدة
SMA200 = [None] * N
acc = 0.0
for i in range(N):
    acc += C[i]
    if i >= 200: acc -= C[i - 200]
    if i >= 199: SMA200[i] = acc / 200
HI = [max(r[1] for r in rows[max(0, i - 250):i + 1]) for i in range(N)]
DIP = [i >= 200 and b.dip_ok(i) for i in range(N)]
EVT = [b.event_soon(r[0]) for r in rows]

def mult(i, scale):
    if scale == "none": return 1
    if scale == "deep":  # الحالية: 2x تحت القمة بـ 10%، 3x بـ 20%
        dd = 1 - C[i] / HI[i]; return 3 if dd >= .2 else 2 if dd >= .1 else 1
    if scale == "deep_cont":  # يزيد بالتدريج مع النزول عن القمة
        return 1 + min(3, (1 - C[i] / HI[i]) / .1)
    if scale == "sma":  # أكثر تحت متوسط 200، أقل فوقه
        return max(.25, min(4, (SMA200[i] / C[i]) ** 6))
    if scale == "rsi":
        return 3 if R[i] <= 30 else 2 if R[i] <= 40 else .5 if R[i] >= 70 else 1

def run(i0, i1, every=14, scale="deep", dip=True, skip_hot=True, trim=(80, 20, .25)):
    g = cost = paid = got = 0.0; last = lastpx = lastsell = None
    for i in range(i0, i1):
        d = rows[i][0]; px = C[i] * F; spx = px * SP
        if trim and g > 0:
            avg = cost / g
            if R[i] >= trim[0] and spx >= avg * (1 + trim[1] / 100) and (lastsell is None or (d - lastsell).days >= 30):
                q = g * trim[2]; cost -= avg * q; g -= q; got += spx * q; lastsell = d
        q = 0
        if (last is None or (d - last).days >= every) and not EVT[i]:
            last = d
            q = 0 if (skip_hot and R[i] >= 70) else (2 if DIP[i] else 1) * every / 14
        elif dip and DIP[i] and not EVT[i] and lastpx and px <= lastpx * .985:
            q = 1
        if q:
            q *= mult(i, scale); g += q; cost += q * px; paid += q * px; lastpx = px
    return (g * C[i1 - 1] * F * SP + got) / paid - 1 if paid else 0

def windows(y0, y1, years):
    out = []
    for i in range(201, N):
        d = rows[i][0]
        if y0 <= d.year <= y1 and d.day <= 3 and rows[i - 1][0].month != d.month and d.month % 2 == 1:
            end = d.replace(year=d.year + years)
            if end <= rows[-1][0]:
                out.append((i, next(j for j in range(i, N) if rows[j][0] >= end)))
    return out

def stats(rs):
    rs = sorted(rs); n = len(rs)
    return dict(win=sum(r > 0 for r in rs) / n, med=rs[n // 2], p10=rs[n // 10], worst=rs[0], mean=sum(rs) / n)

GRID = dict(every=[7, 14, 30], scale=["none", "deep", "deep_cont", "sma", "rsi"], dip=[False, True],
            skip_hot=[False, True], trim=[None, (80, 20, .25), (75, 30, .25), (85, 40, .5)])

if __name__ == "__main__":
    years = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    design, hold = windows(2005, 2015, years), windows(2016, 2023, years)
    print(f"محاولات {years} سنين: تصميم {len(design)}، اختبار {len(hold)}")
    res = []
    for combo in itertools.product(*GRID.values()):
        kw = dict(zip(GRID, combo))
        dz = stats([run(a, e, **kw) for a, e in design])
        res.append((dz["med"] + dz["p10"], kw, dz))  # الترتيب: الوسط + أسوأ 10% (ربح بدون مخاطرة زايدة)
    res.sort(key=lambda x: -x[0])
    fmt = lambda s: f"ربح {s['win']*100:3.0f}% | وسط {s['med']*100:+6.1f}% | أسوأ10% {s['p10']*100:+6.1f}% | أسوأ {s['worst']*100:+6.1f}%"
    cur = dict(every=14, scale="deep", dip=True, skip_hot=True, trim=(80, 20, .25))
    plain = dict(every=14, scale="none", dip=False, skip_hot=False, trim=None)
    print("\nأفضل 10 على فترة التصميم، ونتيجتهم على الاختبار:")
    for sc, kw, dz in res[:10]:
        hz = stats([run(a, e, **kw) for a, e in hold])
        print(f"{kw}\n   تصميم: {fmt(dz)}\n   اختبار: {fmt(hz)}")
    for name, kw in (("الحالية", cur), ("DCA عادي", plain)):
        rank = next(n for n, (_, k, _) in enumerate(res, 1) if k == kw)
        print(f"\n{name} (ترتيبها {rank} من {len(res)}):\n   تصميم: {fmt(stats([run(a, e, **kw) for a, e in design]))}"
              f"\n   اختبار: {fmt(stats([run(a, e, **kw) for a, e in hold]))}")
