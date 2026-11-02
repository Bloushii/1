# مسابقة "1,000 د.ك لكل استراتيجية": كل وحدة تبدأ بنفس المبلغ، والكاش اللي ما ينصرف يقعد كاش (بدون فايدة)
# كل شراء بسعر شراء الدار وكل بيع بسعر بيعها (فرق 0.75%). نقيس قيمة المحفظة بالنهاية والعائد السنوي
# python3 gold/budget_lab.py [عدد المسارات الوهمية لكل بذرة، الافتراضي 200]
import math, os, sys, random, itertools
from datetime import date

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
import lab

SP = lab.SP  # بيع للدار = شراء × SP
BUDGET = 1000.0
CASH_RATE = 0.0  # فايدة الكاش السنوية (وديعة بنك)، تنضبط بـ --cash 0.035

def ind(C):
    I = lab.indicators(C); n = len(C)
    def sma(k):
        out, acc = [None] * n, 0.0
        for i in range(n):
            acc += C[i]
            if i >= k: acc -= C[i - k]
            if i >= k - 1: out[i] = acc / k
        return out
    I["s20"], I["s100"] = sma(20), sma(100)
    I["ret252"] = [C[i] / C[i - 252] - 1 if i >= 252 else 0 for i in range(n)]
    I["ret126"] = [C[i] / C[i - 126] - 1 if i >= 126 else 0 for i in range(n)]
    sd20 = [0.0] * n
    for i in range(19, n):
        m = I["s20"][i]; sd20[i] = math.sqrt(sum((C[j] - m) ** 2 for j in range(i - 19, i + 1)) / 20)
    I["sd20"] = sd20
    return I

# ---------- محرك 1: الوزن المستهدف (كم % من المحفظة ذهب)، يتداول بس لما الفرق أكثر من band ----------
def run_weight(C, I, i0, i1, wfun, band=.1):
    cash, g, w_prev = BUDGET, 0.0, None; dr = CASH_RATE / 252
    for i in range(i0, i1):
        cash *= 1 + dr
        px = C[i]; sell = px * SP; V = cash + g * sell
        w = wfun(I, C, i, w_prev)
        if w is None: continue
        cur = g * sell / V if V else 0
        if abs(w - cur) >= band or (w == 0 and g > 0) or (w == 1 and cash > 1):
            if w > cur:
                spend = min(cash, (w - cur) * V); g += spend / px; cash -= spend
            else:
                q = min(g, (cur - w) * V / sell); g -= q; cash += q * sell
        w_prev = w
    return cash + g * C[i1 - 1] * SP

# ---------- محرك 2: التجميع (شراء من الكاش بس، وبيع اختياري) ----------
def run_accum(C, I, i0, i1, plan):
    cash, g, cost = BUDGET, 0.0, 0.0
    st = {"last": None, "lastpx": None, "lastsell": None, "k": 0}; dr = CASH_RATE / 252
    for i in range(i0, i1):
        cash *= 1 + dr
        px = C[i]; sell = px * SP
        sp, bp = plan(I, C, i, i - i0, st, cash, g, cost)
        if sp and g > 0:
            q = g * sp; cost *= (1 - sp); g -= q; cash += q * sell
        if bp and cash > 0:
            spend = min(cash, bp); g += spend / px; cash -= spend; cost += spend; st["lastpx"] = px
    return cash + g * C[i1 - 1] * SP

# ---------- العائلات ----------
def S_lump(): return ("acc", lambda I, C, i, t, st, cash, g, cost: (0, BUDGET if t == 0 else 0))

def S_dca(months):
    n = max(1, int(months * 21 / 10))  # شروة كل 10 أيام تداول (أسبوعين)
    return ("acc", lambda I, C, i, t, st, cash, g, cost: (0, BUDGET / n if t % 10 == 0 and t < n * 10 else 0))

def S_smartdca(months, power, trim=None, dip=True):
    # استراتيجيتنا بميزانية: الحصة الأساسية × المضاعف، وشراء زيادة وقت الفرص، ونخلص الكاش خلال المدة تقريباً
    n = max(1, int(months * 21 / 10)); base = BUDGET / n
    def plan(I, C, i, t, st, cash, g, cost):
        sp = 0
        if trim and g > 0 and I["rsi"][i] >= trim[0] and C[i] * SP >= cost / g * (1 + trim[1] / 100) \
                and (st["lastsell"] is None or t - st["lastsell"] >= 21):
            sp = trim[2]; st["lastsell"] = t
        bp = 0
        m = max(.25, min(4, (I["s200"][i] / C[i]) ** power))
        if t % 10 == 0:
            bp = 0 if I["rsi"][i] >= 70 else base * m * (2 if lab.dip(I, C, i) else 1)
        elif dip and lab.dip(I, C, i) and st["lastpx"] and C[i] <= st["lastpx"] * .985:
            bp = base * m
        if t >= n * 10 * 2: bp = cash  # بعد ضعف المدة: اللي باقي ينحط كله
        return sp, bp
    return ("acc", plan)

def S_dipreserve(first, steps, cap_months):
    # نحط جزء على طول، والباقي على درجات كل ما نزل السعر عن قمة سنة (مثلاً −5% −10% −15%)، وبعد مدة نحط الباقي
    def plan(I, C, i, t, st, cash, g, cost):
        if t == 0: return 0, BUDGET * first
        dd = 1 - C[i] / I["hi250"][i]; bp = 0
        while st["k"] < len(steps) and dd >= steps[st["k"]]:
            bp += BUDGET * (1 - first) / len(steps); st["k"] += 1
        if t >= cap_months * 21: bp = cash
        return 0, bp
    return ("acc", plan)

def S_trend(k):  # ذهب كامل فوق متوسط k يوم، كاش تحته
    key = {20: "s20", 50: "s50", 100: "s100", 200: "s200"}[k]
    return ("w", lambda I, C, i, w: (1 if C[i] > I[key][i] else 0) if I[key][i] else None)

def S_cross():  # متوسط 50 فوق 200
    return ("w", lambda I, C, i, w: (1 if I["s50"][i] > I["s200"][i] else 0) if I["s200"][i] else None)

def S_momo(look):  # عائد آخر 6 أو 12 شهر موجب = ذهب
    key = "ret252" if look == 12 else "ret126"
    return ("w", lambda I, C, i, w: 1 if I[key][i] > 0 else 0)

def S_rsiswing(lo, hi):  # يشتري كله تحت RSI lo، ويبيع كله فوق hi
    def f(I, C, i, w):
        r = I["rsi"][i]
        if r <= lo: return 1
        if r >= hi: return 0
        return w if w is not None else 0
    return ("w", f)

def S_boll(z):  # يشتري لما السعر تحت متوسط 20 بـ z انحراف، ويبيع لما يرجع فوقه
    def f(I, C, i, w):
        m, sd = I["s20"][i], I["sd20"][i]
        if not m or not sd: return None
        if C[i] < m - z * sd: return 1
        if C[i] > m + z * sd: return 0
        return w if w is not None else 0
    return ("w", f)

def S_core(core, sat):  # نسبة ثابتة ذهب دايماً + الباقي يمشي مع الاتجاه
    _, tf = sat
    return ("w", lambda I, C, i, w: (lambda x: None if x is None else core + (1 - core) * x)(tf(I, C, i, None)))

def S_voltarget(target):  # الوزن = التذبذب المستهدف ÷ تذبذب آخر 20 يوم
    return ("w", lambda I, C, i, w: min(1, target / (I["vol20"][i] * math.sqrt(252))) if I["vol20"][i] else None)

def S_valuetilt(power):  # وزن الذهب يكبر كل ما نزل تحت متوسط 200 (نفس فكرة استراتيجيتنا بس على المحفظة كلها)
    return ("w", lambda I, C, i, w: max(0, min(1, .5 * (I["s200"][i] / C[i]) ** power)) if I["s200"][i] else None)

STRATS = {"شراء مرة وحدة": S_lump()}
for m in (6, 12, 24): STRATS[f"DCA عادي {m} شهر"] = S_dca(m)
for m, p in itertools.product((6, 12, 24), (6, 12)):
    STRATS[f"DCA ذكي {m} شهر قوة {p}"] = S_smartdca(m, p)
    STRATS[f"DCA ذكي {m} شهر قوة {p} + بيع 85/40"] = S_smartdca(m, p, trim=(85, 40, .5))
for f, steps, cap in ((.5, (.05, .10, .15), 12), (.34, (.05, .10), 6), (.25, (.07, .14, .21), 12), (.5, (.03, .06, .09), 6)):
    STRATS[f"احتياطي النزول {int(f*100)}% + {'/'.join(str(int(s*100)) for s in steps)} (حد {cap} شهر)"] = S_dipreserve(f, steps, cap)
for k in (20, 50, 100, 200): STRATS[f"اتجاه فوق متوسط {k}"] = S_trend(k)
STRATS["تقاطع 50/200"] = S_cross()
for l in (6, 12): STRATS[f"زخم {l} شهر"] = S_momo(l)
for lo, hi in ((30, 70), (25, 75), (35, 65)): STRATS[f"RSI تأرجح {lo}/{hi}"] = S_rsiswing(lo, hi)
for z in (1.5, 2.0): STRATS[f"بولنجر {z}"] = S_boll(z)
for c in (.5, .7): STRATS[f"أساس {int(c*100)}% + اتجاه 100"] = S_core(c, S_trend(100))
for t in (.10, .15): STRATS[f"تذبذب مستهدف {int(t*100)}%"] = S_voltarget(t)
for p in (3, 6): STRATS[f"وزن حسب المتوسط قوة {p}"] = S_valuetilt(p)

def S_lump_trim(trim, rebuy):
    # كله مرة وحدة، نبيع جزء وقت الربح الكبير، ونرجع نشتري بالكاش لما ينزل rebuy% عن سعر البيع
    def plan(I, C, i, t, st, cash, g, cost):
        if t == 0: return 0, BUDGET
        sp = bp = 0
        if g > 0 and I["rsi"][i] >= trim[0] and C[i] * SP >= cost / g * (1 + trim[1] / 100) \
                and (st["lastsell"] is None or t - st["lastsell"] >= 21):
            sp = trim[2]; st["lastsell"] = t; st["sellpx"] = C[i]
        if cash > 1 and st.get("sellpx") and C[i] <= st["sellpx"] * (1 - rebuy / 100):
            bp = cash; st["sellpx"] = None
        return sp, bp
    return ("acc", plan)

for f, steps, cap in ((.5, (.02, .04, .06), 6), (.6, (.03, .06, .09), 6), (.7, (.03, .06), 4), (.5, (.03, .06, .09), 3), (.4, (.03, .06, .09, .12), 6)):
    STRATS[f"احتياطي النزول {int(f*100)}% + {'/'.join(str(int(s*100)) for s in steps)} (حد {cap} شهر)"] = S_dipreserve(f, steps, cap)
for m, p in itertools.product((3, 6), (3, 9)):
    STRATS[f"DCA ذكي {m} شهر قوة {p}"] = S_smartdca(m, p)
STRATS["DCA ذكي 3 شهر قوة 6"] = S_smartdca(3, 6)
STRATS["DCA عادي 3 شهر"] = S_dca(3)
for trim, rb in (((85, 40, .5), 10), ((80, 30, .25), 8), ((85, 50, .5), 15)):
    STRATS[f"مرة وحدة + بيع {trim[0]}/{trim[1]}/{int(trim[2]*100)}% ورجوع -{rb}%"] = S_lump_trim(trim, rb)

def run(name, C, I, i0, i1):
    kind, f = STRATS[name]
    return run_weight(C, I, i0, i1, f) if kind == "w" else run_accum(C, I, i0, i1, f)

def cagr(v, days): return (v / BUDGET) ** (252 / days) - 1

def stats(rs):
    rs = sorted(rs); n = len(rs)
    return dict(med=rs[n // 2], p10=rs[max(0, n // 10)], win=sum(r > 0 for r in rs) / n, mean=sum(rs) / n)

def evaluate(n_paths=200):
    H = lab.history(); D = [d for d, _ in H]; C = [c for _, c in H]; I = ind(C); N = len(C)
    starts = [i for i in range(260, N) if D[i].day <= 3 and D[i - 1].month != D[i].month]
    tests = {}
    for yrs in (1, 2, 3, 5):
        L = yrs * 252
        tests[f"تاريخ {yrs}س"] = [(C, I, s, s + L) for s in starts if s + L <= N]
    for a, b_ in ((2005, 2012), (2013, 2019), (2020, 2026)):
        tests[f"فترة {a}-{b_}"] = [(C, I, s, min(s + 504, N)) for s in starts if a <= D[s].year <= b_ and s + 252 <= N]
    for seed in (5, 29):
        paths = lab.synthetic(C, n_paths, 3, seed=seed, block=60)
        tests[f"وهمي بذرة {seed}"] = [(p, ind(p), 260, len(p)) for p in paths]
    res = {}
    for name in STRATS:
        res[name] = {}
        for t, W in tests.items():
            res[name][t] = stats([cagr(run(name, c, ii, a, e), e - a) for c, ii, a, e in W])
    return res, list(tests)

if __name__ == "__main__":
    n_paths = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else 200
    if "--cash" in sys.argv: CASH_RATE = float(sys.argv[sys.argv.index("--cash") + 1])
    res, tests = evaluate(n_paths)
    # الترتيب: متوسط الرتبة على كل الاختبارات (الوسط + أسوأ 10%)، عشان ما نختار وحدة فازت باختبار واحد بالصدفة
    ranks = {n: [] for n in res}
    for t in tests:
        order = sorted(res, key=lambda n: -(res[n][t]["med"] + res[n][t]["p10"]))
        for r, n in enumerate(order, 1): ranks[n].append(r)
    final = sorted(res, key=lambda n: sum(ranks[n]) / len(ranks[n]))
    print("الترتيب حسب متوسط الرتبة على كل الاختبارات (العائد السنوي بالوسط / أسوأ 10%):")
    for n in final:
        r = res[n]
        print(f"{sum(ranks[n])/len(ranks[n]):5.1f} | {n:<46} | " + " | ".join(
            f"{t}: {r[t]['med']*100:+.1f}/{r[t]['p10']*100:+.1f}" for t in tests))
