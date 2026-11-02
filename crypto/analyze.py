#!/usr/bin/env python3
"""تحليل فني لعملة من اسمها: يسحب الشموع من Gate / Bitget / MEXC ويعطي حكم على صفقة Long.

الاستخدام:
    python3 crypto/analyze.py TRIA
    python3 crypto/analyze.py BEAT --json
"""
import argparse
import json
import os
import ssl
import sys
import urllib.request

BTC_KEY_LEVEL = 79450  # دعم BTC اللي اتفقنا عليه؛ تحته ما ناخذ Long

_ctx = ssl.create_default_context()
if os.path.exists("/root/.ccr/ca-bundle.crt"):
    _ctx.load_verify_locations("/root/.ccr/ca-bundle.crt")


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15, context=_ctx) as r:
        return json.loads(r.read().decode())


# ---------- مصادر الشموع (كلها ترجع قائمة مرتبة من الأقدم للأحدث) ----------

def candles_gate(sym, tf, limit=300):
    iv = {"1h": "1h", "4h": "4h", "1d": "1d"}[tf]
    rows = get_json(f"https://api.gateio.ws/api/v4/futures/usdt/candlesticks"
                    f"?contract={sym}_USDT&interval={iv}&limit={limit}")
    return [dict(t=int(r["t"]), o=float(r["o"]), h=float(r["h"]), l=float(r["l"]),
                 c=float(r["c"]), v=float(r.get("sum") or 0)) for r in rows]


def candles_bitget(sym, tf, limit=300):
    iv = {"1h": "1H", "4h": "4H", "1d": "1D"}[tf]
    d = get_json(f"https://api.bitget.com/api/v2/mix/market/candles?symbol={sym}USDT"
                 f"&productType=usdt-futures&granularity={iv}&limit={limit}")["data"]
    rows = [dict(t=int(r[0]) // 1000, o=float(r[1]), h=float(r[2]), l=float(r[3]),
                 c=float(r[4]), v=float(r[6])) for r in d]
    return sorted(rows, key=lambda x: x["t"])


def candles_mexc(sym, tf, limit=300):
    iv = {"1h": "60m", "4h": "4h", "1d": "1d"}[tf]
    d = get_json(f"https://api.mexc.com/api/v3/klines?symbol={sym}USDT&interval={iv}&limit={limit}")
    return [dict(t=int(r[0]) // 1000, o=float(r[1]), h=float(r[2]), l=float(r[3]),
                 c=float(r[4]), v=float(r[7])) for r in d]


SOURCES = [("Gate Futures", candles_gate), ("Bitget Futures", candles_bitget), ("MEXC Spot", candles_mexc)]


def load_candles(sym):
    errors = []
    for name, fn in SOURCES:
        try:
            data = {tf: fn(sym, tf) for tf in ("1h", "4h", "1d")}
            if all(len(v) >= 30 for v in data.values()):
                return name, data
            errors.append(f"{name}: بيانات قليلة")
        except Exception as e:  # العملة مو مدرجة في هالمنصة، نجرب اللي بعدها
            errors.append(f"{name}: {e}")
    raise SystemExit(f"ما لقيت شموع للعملة {sym}:\n  " + "\n  ".join(errors))


def futures_stats(sym):
    """التمويل والـ Open Interest من Gate (إذا العملة عندها فيوتشر هناك)."""
    out = {}
    try:
        c = get_json(f"https://api.gateio.ws/api/v4/futures/usdt/contracts/{sym}_USDT")
        out["funding"] = float(c["funding_rate"])
        out["funding_hours"] = int(c.get("funding_interval", 28800)) / 3600
    except Exception:
        pass
    try:
        s = get_json(f"https://api.gateio.ws/api/v4/futures/usdt/contract_stats"
                     f"?contract={sym}_USDT&interval=1h&limit=25")
        if len(s) >= 2:
            first, last = float(s[0]["open_interest_usd"]), float(s[-1]["open_interest_usd"])
            out["oi_usd"] = last
            out["oi_change_24h"] = (last / first - 1) * 100 if first else 0
            out["long_short"] = float(s[-1].get("lsr_account") or 0)
    except Exception:
        pass
    return out


# ---------- المؤشرات ----------

def ema(vals, n):
    k, out = 2 / (n + 1), []
    e = sum(vals[:n]) / n if len(vals) >= n else vals[0]
    for i, v in enumerate(vals):
        e = e if i < n - 1 else v * k + e * (1 - k)
        out.append(e)
    return out


def rsi(vals, n=14):
    out, gain, loss = [50.0] * len(vals), 0.0, 0.0
    for i in range(1, len(vals)):
        d = vals[i] - vals[i - 1]
        g, l_ = max(d, 0), max(-d, 0)
        if i <= n:
            gain += g / n
            loss += l_ / n
        else:
            gain = (gain * (n - 1) + g) / n
            loss = (loss * (n - 1) + l_) / n
        if i >= n:
            out[i] = 100.0 if loss == 0 else 100 - 100 / (1 + gain / loss)
    return out


def sma(vals, n):
    return [sum(vals[max(0, i - n + 1):i + 1]) / len(vals[max(0, i - n + 1):i + 1]) for i in range(len(vals))]


def stoch_rsi(vals, n=14):
    r = rsi(vals, n)
    raw = []
    for i in range(len(r)):
        w = r[max(0, i - n + 1):i + 1]
        hi, lo = max(w), min(w)
        raw.append(50.0 if hi == lo else (r[i] - lo) / (hi - lo) * 100)
    k = sma(raw, 3)
    return k, sma(k, 3)


def macd(vals):
    m = [a - b for a, b in zip(ema(vals, 12), ema(vals, 26))]
    s = ema(m, 9)
    return m, s, [a - b for a, b in zip(m, s)]


def atr(cs, n=14):
    trs = [cs[0]["h"] - cs[0]["l"]]
    for p, c in zip(cs, cs[1:]):
        trs.append(max(c["h"] - c["l"], abs(c["h"] - p["c"]), abs(c["l"] - p["c"])))
    a = sum(trs[:n]) / n
    for t in trs[n:]:
        a = (a * (n - 1) + t) / n
    return a


def pivots(cs, k=3):
    sup, res = [], []
    for i in range(k, len(cs) - k):
        w = cs[i - k:i + k + 1]
        if cs[i]["l"] == min(x["l"] for x in w):
            sup.append(cs[i]["l"])
        if cs[i]["h"] == max(x["h"] for x in w):
            res.append(cs[i]["h"])
    return sup, res


def cluster(levels, tol=0.015):
    """يجمع المستويات القريبة من بعض (1.5%) في مستوى واحد مع عدد اللمسات."""
    out = []
    for lv in sorted(levels):
        if out and lv <= out[-1][0] * (1 + tol):
            p, n = out[-1]
            out[-1] = ((p * n + lv) / (n + 1), n + 1)
        else:
            out.append((lv, 1))
    return out


def frame(cs):
    closes = [c["c"] for c in cs]
    m, s, h = macd(closes)
    k, d = stoch_rsi(closes)
    vol = [c["v"] for c in cs]
    return dict(
        close=closes[-1],
        ema7=ema(closes, 7)[-1], ema25=ema(closes, 25)[-1], ema99=ema(closes, 99)[-1],
        rsi=rsi(closes)[-1], macd_hist=h[-1], macd_hist_prev=h[-2],
        stoch_k=k[-1], stoch_d=d[-1], atr=atr(cs),
        vol_ratio=(sum(vol[-6:]) / 6) / (sum(vol[-36:-6]) / 30 or 1),
    )


# ---------- التحليل ----------

def btc_status():
    cs = candles_gate("BTC", "4h", 200)
    f = frame(cs)
    ok = f["close"] > BTC_KEY_LEVEL and f["close"] > f["ema99"]
    weak = f["close"] < f["ema25"]
    return dict(price=f["close"], ema25=f["ema25"], ema99=f["ema99"], rsi=f["rsi"],
                ok=ok and not weak, bad=not ok)


def analyze(sym):
    src, data = load_candles(sym)
    f1, f4, fd = frame(data["1h"]), frame(data["4h"]), frame(data["1d"])
    price = f1["close"]
    day = data["1d"]
    chg24 = (price / data["1h"][-25]["c"] - 1) * 100 if len(data["1h"]) > 25 else 0
    chg7d = (price / day[-8]["c"] - 1) * 100 if len(day) > 8 else 0
    ath_drop = (price / max(c["h"] for c in day) - 1) * 100

    s4, r4 = pivots(data["4h"])
    sd, rd = pivots(day)
    sup = [lv for lv in cluster(s4 + sd) if lv[0] < price * 0.997]
    res = [lv for lv in cluster(r4 + rd) if lv[0] > price * 1.01]
    support = max(sup, key=lambda x: x[0])[0] if sup else min(c["l"] for c in data["4h"][-30:])
    dist_sup = (price / support - 1) * 100

    # الخطة: الدخول عند السعر إذا قريب من الدعم، وإلا أمر Limit فوق الدعم
    entry = price if dist_sup <= 4 else support * 1.005
    stop = support - 0.5 * f4["atr"]
    risk = entry - stop
    targets = [lv[0] for lv in sorted(res, key=lambda x: x[0]) if lv[0] > entry * 1.02][:3]
    while len(targets) < 3:  # ما فيه مقاومات كفاية فوق، نكمل بمضاعفات المخاطرة
        targets.append(entry + risk * (2 + len(targets)))
    rr = (targets[0] - entry) / risk if risk > 0 else 0

    fut = futures_stats(sym)
    btc = btc_status()

    score, plus, minus = 0, [], []

    def add(cond, pts, good, bad=None):
        nonlocal score
        if cond:
            score += pts
            (plus if pts > 0 else minus).append(good)
        elif bad:
            minus.append(bad)

    add(f4["close"] > f4["ema25"], 1, "السعر فوق EMA25 على 4h", "السعر تحت EMA25 على 4h")
    add(f4["ema7"] > f4["ema25"], 1, "EMA7 فوق EMA25 على 4h (زخم صاعد)")
    add(f4["close"] > f4["ema99"], 1, "فوق EMA99 على 4h (اتجاه متوسط صاعد)")
    add(f4["close"] < f4["ema99"], -1, "تحت EMA99 على 4h (اتجاه متوسط هابط)")
    add(fd["close"] > fd["ema25"], 1, "فوق EMA25 على اليومي")
    add(fd["close"] < fd["ema25"], -1, "تحت EMA25 على اليومي (الاتجاه اليومي هابط)")
    add(45 <= f4["rsi"] <= 65, 1, f"RSI 4h صحي ({f4['rsi']:.0f})")
    add(f4["rsi"] > 75, -2, f"RSI 4h متشبع شراء ({f4['rsi']:.0f})")
    add(f4["stoch_k"] > 90, -1, f"StochRSI 4h فوق 90 ({f4['stoch_k']:.0f}) = لحاق بالسعر")
    add(f4["macd_hist"] > 0 and f4["macd_hist"] > f4["macd_hist_prev"], 1, "MACD 4h إيجابي ويقوى")
    add(f4["macd_hist"] < 0 and f4["macd_hist"] < f4["macd_hist_prev"], -1, "MACD 4h سلبي ويضعف")
    add(f4["vol_ratio"] > 1.3, 1, f"الفوليوم أعلى من المعدل ×{f4['vol_ratio']:.1f}")
    add(dist_sup <= 4, 1, f"قريب من الدعم ({dist_sup:.1f}% فوقه)")
    add(dist_sup > 10, -1, f"بعيد عن الدعم ({dist_sup:.1f}%)، الدخول الحين لحاق")
    add(rr >= 2, 1, f"المخاطرة للعائد ممتازة 1:{rr:.1f}")
    add(rr < 1.2, -2, f"المخاطرة للعائد ضعيفة 1:{rr:.1f}")
    add(chg24 > 25, -1, f"طالعة {chg24:.0f}% في 24 ساعة (مضخوخة)")
    if "funding" in fut:
        add(fut["funding"] > 0.0005, -1, f"التمويل عالي {fut['funding']*100:.3f}% (الكل داخل Long)")
    add(btc["bad"], -2, f"BTC ضعيف ({btc['price']:,.0f} تحت {BTC_KEY_LEVEL:,} أو تحت EMA99 على 4h)")
    add(btc["ok"], 1, f"BTC إيجابي ({btc['price']:,.0f})")

    if score >= 4 and rr >= 1.5 and not btc["bad"]:
        verdict = "✅ ادخل"
    elif score >= 1 or (score >= 0 and dist_sup > 4):
        verdict = "⏳ انتظر"
    else:
        verdict = "❌ لا تدخل"

    return dict(
        symbol=sym, source=src, price=price, chg24=chg24, chg7d=chg7d, ath_drop=ath_drop,
        verdict=verdict, score=score, plus=plus, minus=minus,
        plan=dict(entry=entry, stop=stop, stop_pct=(stop / entry - 1) * 100,
                  targets=targets, targets_pct=[(t / entry - 1) * 100 for t in targets], rr=rr),
        supports=[round(s[0], 10) for s in sorted(sup, key=lambda x: -x[0])[:3]],
        resistances=[round(r[0], 10) for r in sorted(res, key=lambda x: x[0])[:3]],
        frames={"1h": f1, "4h": f4, "1d": fd}, futures=fut, btc=btc,
    )


def fmt(x):
    return f"{x:,.2f}" if x >= 100 else f"{x:.4f}" if x >= 1 else f"{x:.6g}"


def report(a):
    p, f4, fd = a["plan"], a["frames"]["4h"], a["frames"]["1d"]
    L = [f"## {a['symbol']}USDT: {a['verdict']}  (النقاط {a['score']:+d})",
         f"السعر {fmt(a['price'])} | 24 ساعة {a['chg24']:+.1f}% | 7 أيام {a['chg7d']:+.1f}% | "
         f"من أعلى سعر {a['ath_drop']:.0f}% | المصدر: {a['source']}", ""]
    L += ["الإيجابي:"] + ([f"  ✅ {x}" for x in a["plus"]] or ["  —"])
    L += ["السلبي:"] + ([f"  ❌ {x}" for x in a["minus"]] or ["  —"])
    L += ["", f"4h: RSI {f4['rsi']:.0f} | StochRSI {f4['stoch_k']:.0f} | MACD hist {f4['macd_hist']:+.3g} | "
              f"EMA7 {fmt(f4['ema7'])} / EMA25 {fmt(f4['ema25'])} / EMA99 {fmt(f4['ema99'])}",
          f"1d: RSI {fd['rsi']:.0f} | EMA25 {fmt(fd['ema25'])} | EMA99 {fmt(fd['ema99'])}",
          "الدعوم: " + ", ".join(fmt(s) for s in a["supports"]) +
          " | المقاومات: " + ", ".join(fmt(r) for r in a["resistances"])]
    fu = a["futures"]
    if fu:
        L.append(f"التمويل: {fu.get('funding', 0)*100:.4f}% | OI: ${fu.get('oi_usd', 0):,.0f} "
                 f"({fu.get('oi_change_24h', 0):+.1f}% 24h)")
    L += ["", "الخطة (من الشارت):",
          f"  الدخول {fmt(p['entry'])} | الوقف {fmt(p['stop'])} ({p['stop_pct']:.1f}%)",
          "  الأهداف: " + " / ".join(f"{fmt(t)} (+{pc:.0f}%)" for t, pc in zip(p["targets"], p["targets_pct"])),
          f"  المخاطرة للعائد على الهدف الأول: 1:{p['rr']:.1f}",
          f"BTC: {fmt(a['btc']['price'])} | RSI 4h {a['btc']['rsi']:.0f}"]
    return "\n".join(L)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("symbol")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    sym = args.symbol.upper().replace("USDT", "").replace("/", "").replace("_", "")
    res = analyze(sym)
    print(json.dumps(res, ensure_ascii=False, indent=1) if args.json else report(res))
