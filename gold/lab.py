# مختبر استراتيجيات الذهب عيار 24: يجرب عائلات استراتيجيات على 3 أنواع اختبار
#  1) التاريخ: محاولات حقيقية 2005–2023
#  2) مسارات وهمية: خلط أسابيع حقيقية بترتيب جديد (ما نعتمد على الماضي بنفس ترتيبه)
#  3) المستقبل: من تاريخ بداية الورق (paper_start بالسجل) لين اليوم، بأسعار ما شافها أي اختيار
# python3 gold/lab.py [عدد المسارات الوهمية، الافتراضي 300]
import csv, os, sys, math, random, json
from datetime import date, timedelta

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import backtest as b

S = b.S
F = S["usd_kwd"] / b.OZ * (1 + S["dealer_premium_pct"] / 100)
SP = 1 - S["spread_pct"] / 100

def history():
    # أسعار الإغلاق اليومية 2004–اليوم
    out, first_new = [], b.rows[0][0]
    for r in csv.DictReader(open(os.path.join(HERE, "data", "xauusd_1d_2004_2025.csv")), delimiter=";"):
        d = date.fromisoformat(r["Date"][:10].replace(".", "-"))
        if d.weekday() < 5 and d < first_new:
            out.append((d, float(r["Close"])))
    return out + [(r[0], r[3]) for r in b.rows]

def indicators(C):
    n = len(C); rsi = [50.0] * n; ag = al = 0.0
    for i in range(1, n):
        ch = C[i] - C[i - 1]; g, l = max(ch, 0), max(-ch, 0)
        if i <= 14: ag += g / 14; al += l / 14
        else: ag = (ag * 13 + g) / 14; al = (al * 13 + l) / 14
        if i >= 14: rsi[i] = 100 - 100 / (1 + ag / al) if al else 100
    def sma(k):
        out, acc = [None] * n, 0.0
        for i in range(n):
            acc += C[i]
            if i >= k: acc -= C[i - k]
            if i >= k - 1: out[i] = acc / k
        return out
    s50, s200 = sma(50), sma(200)
    low20 = [min(C[max(0, i - 19):i + 1]) for i in range(n)]
    hi250 = [max(C[max(0, i - 250):i + 1]) for i in range(n)]
    vol20 = [0.0] * n
    for i in range(21, n):
        rs = [math.log(C[j] / C[j - 1]) for j in range(i - 19, i + 1)]; m = sum(rs) / 20
        vol20[i] = math.sqrt(sum((x - m) ** 2 for x in rs) / 19)
    return dict(rsi=rsi, s50=s50, s200=s200, low20=low20, hi250=hi250, vol20=vol20)

def score(I, C, i):
    s = 0
    if C[i] > I["s200"][i]: s += 3
    if I["s50"][i] > I["s200"][i]: s += 1
    r = I["rsi"][i]; s += 3 if r <= 30 else 2 if r <= 40 else 1 if r <= 50 else 0
    if C[i] <= I["low20"][i] * 1.01: s += 2
    if C[i] > C[i - 1]: s += 1
    return s

def dip(I, C, i):
    return score(I, C, i) >= 5 and (C[i] <= I["low20"][i] * 1.03 or I["rsi"][i] <= 35)

def mult(I, C, i, scale, power=12):
    if scale == "none": return 1
    if scale == "sma": return max(.25, min(4, (I["s200"][i] / C[i]) ** power))
    if scale == "deep":
        dd = 1 - C[i] / I["hi250"][i]; return 3 if dd >= .2 else 2 if dd >= .1 else 1
    if scale == "vol":  # يشتري أكثر وقت التذبذب العالي (خوف السوق) تحت المتوسط
        base = max(.25, min(4, (I["s200"][i] / C[i]) ** power))
        return base * (1.5 if I["vol20"][i] > .015 else 1)
    if scale == "momo":  # عكس: يشتري أكثر لما الاتجاه صاعد (متوسط 50 فوق 200)
        return 2 if I["s50"][i] > I["s200"][i] else .5

def xirr(flows):
    t0 = flows[0][0]
    npv = lambda r: sum(c / (1 + r) ** ((d - t0) / 365.25) for d, c in flows)
    lo, hi = -0.95, 5.0
    for _ in range(60):
        m = (lo + hi) / 2
        lo, hi = (m, hi) if npv(m) > 0 else (lo, m)
    return m

def run(C, I, i0, i1, every=14, scale="sma", power=12, dipbuy=True, skip_hot=True, trim=(85, 40, .5), trail=None):
    # يرجع العائد السنوي. الأيام أرقام تداول (كل يوم تداول = 1.4 يوم تقويم تقريباً)
    g = cost = 0.0; last = lastpx = lastsell = None; flows = []; peak = 0
    for i in range(i0, i1):
        day = i * 1.4; px = C[i] * F; spx = px * SP
        if g > 0:
            avg = cost / g; peak = max(peak, spx)
            sell = 0
            if trim and I["rsi"][i] >= trim[0] and spx >= avg * (1 + trim[1] / 100):
                sell = trim[2]
            if trail and spx >= avg * (1 + trail[0] / 100) and spx <= peak * (1 - trail[1] / 100):
                sell = max(sell, trail[2])  # وقف ربح متحرك: نزل من القمة بعد ربح واضح
            if sell and (lastsell is None or day - lastsell >= 30):
                q = g * sell; cost -= avg * q; g -= q; flows.append((day, spx * q)); lastsell = day; peak = spx
        q = 0
        if last is None or day - last >= every:
            last = day; q = 0 if (skip_hot and I["rsi"][i] >= 70) else (2 if dip(I, C, i) else 1)
        elif dipbuy and dip(I, C, i) and lastpx and px <= lastpx * .985:
            q = 1
        if q:
            q *= mult(I, C, i, scale, power); g += q; cost += q * px; lastpx = px; flows.append((day, -q * px))
    if not flows: return 0.0
    return xirr(flows + [((i1 - 1) * 1.4, g * C[i1 - 1] * F * SP)])

def synthetic(C, n_paths, years, seed=7, block=20):
    # مسارات وهمية: نلصق قطع 20 يوم من عوائد حقيقية بترتيب عشوائي، ونبدأها من آخر سعر
    rets = [math.log(C[i] / C[i - 1]) for i in range(1, len(C))]
    rnd = random.Random(seed); L = int(years * 252) + 260; paths = []
    for _ in range(n_paths):
        p = [C[-1]]
        while len(p) < L:
            k = rnd.randrange(0, len(rets) - block)
            for r in rets[k:k + block]: p.append(p[-1] * math.exp(r))
        paths.append(p[:L])
    return paths

CANDIDATES = {
    "الحالية": dict(),
    "DCA عادي": dict(scale="none", dipbuy=False, skip_hot=False, trim=None),
    "قوة 6 (السابقة)": dict(power=6),
    "قوة 9": dict(power=9),
    "قوة 12 + بيع 75/30/ربع": dict(trim=(75, 30, .25)),
    "قوة 12 + وقف متحرك 30/10/نص": dict(trail=(30, 10, .5)),
    "تذبذب": dict(scale="vol"),
    "مع الاتجاه": dict(scale="momo"),
    "وقف ربح متحرك 30/10/نص": dict(trail=(30, 10, .5)),
    "وقف ربح متحرك 20/8/ربع": dict(trail=(20, 8, .25)),
    "بيع 75/30/ربع": dict(trim=(75, 30, .25)),
    "بدون بيع": dict(trim=None),
    "أسبوعي": dict(every=7),
    "شهري": dict(every=30),
}

def stats(rs):
    rs = sorted(rs); n = len(rs)
    return dict(med=rs[n // 2], p10=rs[n // 10], win=sum(r > 0 for r in rs) / n)

if __name__ == "__main__":
    n_paths = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    H = history(); C = [c for _, c in H]; I = indicators(C)
    # 1) التاريخ: كل شهرين من 2005 لين 2023، مدة سنتين
    starts = [i for i in range(260, len(H)) if H[i][0].day <= 3 and H[i - 1][0].month != H[i][0].month
              and H[i][0].month % 2 == 1 and H[i][0].year <= 2023]
    hist = {n: stats([run(C, I, s, min(s + 504, len(C)), **kw) for s in starts if s + 504 <= len(C)]) for n, kw in CANDIDATES.items()}
    # 2) مسارات وهمية، 3 سنين
    paths = synthetic(C, n_paths, 3)
    syn = {}
    for n, kw in CANDIDATES.items():
        rs = []
        for p in paths:
            Ip = indicators(p); rs.append(run(p, Ip, 260, len(p), **kw))
        syn[n] = stats(rs)
    # 3) المستقبل: من paper_start
    ledger = json.load(open(os.path.join(HERE, "ledger.json")))
    ps = date.fromisoformat(ledger["settings"].get("paper_start", str(date.today())))
    i_ps = next((i for i, (d, _) in enumerate(H) if d >= ps), len(H))
    fwd = {n: (run(C, I, i_ps, len(C), **kw) if len(C) - i_ps >= 5 else None) for n, kw in CANDIDATES.items()}
    print(f"{'الاستراتيجية':<26} | تاريخ سنتين: وسط/أسوأ10 | وهمي 3 سنين ({n_paths}): وسط/أسوأ10/ربح | مستقبل من {ps}")
    rank = sorted(CANDIDATES, key=lambda n: -(hist[n]["med"] + hist[n]["p10"] + syn[n]["med"] + syn[n]["p10"]))
    for n in rank:
        h, s, f = hist[n], syn[n], fwd[n]
        print(f"{n:<26} | {h['med']*100:+6.1f}% / {h['p10']*100:+6.1f}% | {s['med']*100:+6.1f}% / {s['p10']*100:+6.1f}% / {s['win']*100:3.0f}% | "
              + (f"{f*100:+.1f}%/سنة" if f is not None else "ينتظر أيام كفاية"))
