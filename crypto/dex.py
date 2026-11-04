#!/usr/bin/env python3
"""تحليل عملات DEX على Solana (اللي تنشرى من Phantom): الأمان + الشارت + الحكم.

الاستخدام:
    python3 crypto/dex.py GTA6CAT                 # بالاسم أو الرمز
    python3 crypto/dex.py HsprHx...pump           # بعنوان العقد (أدق)
    python3 crypto/dex.py --trending              # العملات الترند الحين مع فلتر أمان سريع
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
from datetime import datetime, timezone

from analyze import (atr, cluster, ema, fmt, get_json, macd, market_line, market_status,
                     pivots, rsi, stoch_rsi)

DS = "https://api.dexscreener.com"
GT = "https://api.geckoterminal.com/api/v2/networks/solana"


def gt_json(url, tries=4):
    """GeckoTerminal يسمح بعدد قليل من الطلبات بالدقيقة، فنعيد المحاولة إذا رد 429."""
    for i in range(tries):
        try:
            return get_json(url)
        except urllib.error.HTTPError as e:
            if e.code != 429 or i == tries - 1:
                raise
            time.sleep(15 * (i + 1))


def is_address(q):
    return len(q) >= 32 and q.isalnum()


def find_pairs(q):
    if is_address(q):
        pairs = get_json(f"{DS}/latest/dex/tokens/{q}").get("pairs") or []
        pairs = [p for p in pairs if p["baseToken"]["address"] == q]  # مو الحوض اللي عملتنا فيه هي الطرف الثاني
    else:
        pairs = get_json(f"{DS}/latest/dex/search?q={urllib.parse.quote(q)}").get("pairs") or []
        ql = q.lower().replace("usdt", "")
        pairs = [p for p in pairs if p["baseToken"]["symbol"].lower() == ql
                 or p["baseToken"]["name"].lower().replace(" ", "") == ql]
    return [p for p in pairs if p.get("chainId") == "solana"]


def pick_token(pairs):
    """يختار التوكن الأعلى سيولة، ويرجع عدد التوكنات الثانية بنفس الاسم (غالباً مزيفة)."""
    by_token = {}
    for p in pairs:
        a = p["baseToken"]["address"]
        by_token.setdefault(a, []).append(p)
    liq = lambda ps: sum((x.get("liquidity") or {}).get("usd", 0) for x in ps)
    best = max(by_token, key=lambda a: liq(by_token[a]))
    main = max(by_token[best], key=lambda x: (x.get("liquidity") or {}).get("usd", 0))
    return best, main, by_token[best], len(by_token) - 1


def ohlcv(pool, tf, agg, limit, token):
    # token يضمن إن الشموع لسعر عملتنا، مو العملة الثانية في الحوض
    d = gt_json(f"{GT}/pools/{pool}/ohlcv/{tf}?aggregate={agg}&limit={limit}&currency=usd&token={token}")
    rows = d["data"]["attributes"]["ohlcv_list"]
    return sorted((dict(t=int(r[0]), o=float(r[1]), h=float(r[2]), l=float(r[3]),
                        c=float(r[4]), v=float(r[5])) for r in rows), key=lambda x: x["t"])


def to_4h(cs):
    out = []
    for c in cs:
        b = c["t"] - c["t"] % 14400
        if out and out[-1]["t"] == b:
            o = out[-1]
            o["h"], o["l"], o["c"], o["v"] = max(o["h"], c["h"]), min(o["l"], c["l"]), c["c"], o["v"] + c["v"]
        else:
            out.append(dict(c, t=b))
    return out


def tech(cs):
    closes = [c["c"] for c in cs]
    if len(closes) < 30:
        return None
    _, _, h = macd(closes)
    k, _ = stoch_rsi(closes)
    n = len(closes)
    return dict(close=closes[-1], ema7=ema(closes, 7)[-1], ema25=ema(closes, 25)[-1],
                ema99=ema(closes, 99)[-1] if n >= 99 else None, rsi=rsi(closes)[-1],
                stoch_k=k[-1], macd_hist=h[-1], macd_prev=h[-2])


def analyze(q):
    pairs = find_pairs(q)
    if not pairs:
        raise SystemExit(f"ما لقيت {q} على Solana في DexScreener. جرّب بعنوان العقد.")
    addr, main, token_pairs, fakes = pick_token(pairs)
    info = gt_json(f"{GT}/tokens/{addr}/info")["data"]["attributes"]
    pool = main["pairAddress"]
    c1h = ohlcv(pool, "hour", 1, 500, addr)
    c15 = ohlcv(pool, "minute", 15, 300, addr)
    c4h = to_4h(c1h)

    price = float(main.get("priceUsd") or 0)
    liq = sum((p.get("liquidity") or {}).get("usd", 0) for p in token_pairs)
    mcap = main.get("marketCap") or main.get("fdv") or 0
    age_h = (time.time() - main.get("pairCreatedAt", time.time() * 1000) / 1000) / 3600
    if (info.get("launchpad_details") or {}).get("completed_at"):  # عمر العملة من إطلاقها، مو من الحوض
        t0 = datetime.fromisoformat(info["launchpad_details"]["completed_at"].replace("Z", "+00:00"))
        age_h = max(age_h, (datetime.now(timezone.utc) - t0).total_seconds() / 3600)
    tx = main.get("txns", {}).get("h24", {})
    buys, sells = tx.get("buys", 0), tx.get("sells", 0)
    ch = main.get("priceChange", {})
    holders = info.get("holders") or {}
    dist = holders.get("distribution_percentage") or {}
    top10 = float(dist.get("top_10") or 0)
    dev = float(info.get("developer_holding_percentage") or 0)

    hard, warn, good = [], [], []
    if info.get("mint_authority") == "yes":
        hard.append("صلاحية Mint مفتوحة: المطور يقدر يطبع توكنات جديدة")
    else:
        good.append("صلاحية Mint مقفولة")
    if info.get("freeze_authority") == "yes":
        hard.append("صلاحية Freeze مفتوحة: يقدرون يجمّدون محفظتك وما تقدر تبيع")
    else:
        good.append("صلاحية Freeze مقفولة")
    if info.get("is_honeypot") == "yes":
        hard.append("Honeypot: تقدر تشتري بس ما تقدر تبيع")
    if liq < 50_000:
        hard.append(f"السيولة ضعيفة جداً ${liq:,.0f}")
    elif liq < 150_000:
        warn.append(f"السيولة قليلة ${liq:,.0f}")
    else:
        good.append(f"السيولة زينة ${liq:,.0f}")
    if mcap and liq / mcap < 0.03:
        warn.append(f"السيولة {liq / mcap * 100:.1f}% بس من القيمة السوقية (البيع الكبير يطيح السعر)")
    if top10 > 50:
        hard.append(f"أكبر 10 محافظ ماسكين {top10:.0f}%")
    elif top10 > 30:
        warn.append(f"أكبر 10 محافظ ماسكين {top10:.0f}%")
    elif top10:
        good.append(f"المحافظ موزعة (أكبر 10 = {top10:.0f}%، العدد {holders.get('count', 0):,})")
    if dev > 5:
        warn.append(f"المطور ماسك {dev:.1f}%")
    if age_h < 2:
        hard.append(f"عمرها {age_h:.1f} ساعة بس")
    elif age_h < 24:
        warn.append(f"جديدة جداً ({age_h:.0f} ساعة)")
    if fakes:
        warn.append(f"فيه {fakes} توكن ثاني بنفس الاسم: تأكد من العقد")
    if (main.get("boosts") or {}).get("active"):
        warn.append("عليها إعلان مدفوع (Boost) في DexScreener: الترند ممكن يكون مشترى")
    vol24 = main.get("volume", {}).get("h24", 0)
    if buys + sells > 1000 and vol24 / (buys + sells) < 10:
        warn.append(f"متوسط الصفقة ${vol24 / (buys + sells):.1f} بس: بوتات تسوي حركة وهمية (Wash trading)")
    if sells and buys / sells < 0.8:
        warn.append(f"البيع أكثر من الشراء (24h: {buys:,} شراء / {sells:,} بيع)")

    t1, t15, t4 = tech(c1h), tech(c15), tech(c4h)
    score = 0
    plus, minus = [], []
    if t1:
        def add(cond, pts, msg):
            nonlocal score
            if cond:
                score += pts
                (plus if pts > 0 else minus).append(msg)
        add(t1["close"] > t1["ema25"], 1, "فوق EMA25 على 1h")
        add(t1["close"] < t1["ema25"], -1, "تحت EMA25 على 1h")
        add(t1["ema7"] > t1["ema25"], 1, "EMA7 فوق EMA25 على 1h")
        add(t1["ema99"] is not None and t1["close"] > t1["ema99"], 1, "فوق EMA99 على 1h")
        add(t1["rsi"] > 75, -2, f"RSI 1h متشبع ({t1['rsi']:.0f})")
        add(40 <= t1["rsi"] <= 65, 1, f"RSI 1h صحي ({t1['rsi']:.0f})")
        add(t1["stoch_k"] > 90, -1, f"StochRSI 1h فوق 90")
        add(t1["macd_hist"] > 0 and t1["macd_hist"] > t1["macd_prev"], 1, "MACD 1h إيجابي ويقوى")
        add(t1["macd_hist"] < 0 and t1["macd_hist"] < t1["macd_prev"], -1, "MACD 1h سلبي")
        if t4:
            add(t4["close"] > t4["ema25"], 1, "فوق EMA25 على 4h")
            add(t4["close"] < t4["ema25"], -1, "تحت EMA25 على 4h (الاتجاه الأكبر هابط)")
            add(t4["rsi"] > 75, -1, f"RSI 4h متشبع ({t4['rsi']:.0f})")
    if (ch.get("h24") or 0) > 100:
        score -= 2
        minus.append(f"طالعة {ch['h24']:.0f}% في 24 ساعة (ضخ)")
    elif (ch.get("h24") or 0) > 40:
        score -= 1
        minus.append(f"طالعة {ch['h24']:.0f}% في 24 ساعة")

    sup, res = pivots(c1h[-200:], k=4)
    s15, r15 = pivots(c15[-200:], k=4)  # بعد الضخ، الدعوم الحديثة تبين على 15m بس
    sup, res = sup + s15, res + r15
    sups = [s[0] for s in cluster(sup) if s[0] < price * 0.99]
    ress = [r[0] for r in cluster(res) if r[0] > price * 1.02]
    support = max(sups) if sups else min(c["l"] for c in c1h[-48:])
    dist_sup = (price / support - 1) * 100
    if dist_sup > 15:
        score -= 1
        minus.append(f"بعيد {dist_sup:.0f}% عن الدعم (لحاق)")
    elif dist_sup <= 6:
        score += 1
        plus.append(f"قريب من الدعم ({dist_sup:.1f}%)")
    entry = price if dist_sup <= 6 else support * 1.01
    # الوقف تحت الدعم بـ 1.5 ATR على 1h، بين 4% و12% من الدخول (الميم كوينز ذيولها طويلة)
    stop = support - 1.5 * atr(c1h)
    stop = min(max(stop, entry * 0.88), entry * 0.96)
    targets = sorted(r for r in ress if r > entry * 1.02)[:3]
    while len(targets) < 3:
        targets.append(max(targets + [entry]) + (entry - stop))
    targets.sort()
    rr = (targets[0] - entry) / (entry - stop) if entry > stop else 0

    market = market_status()
    if hard:
        verdict = "⛔ خطر: لا تقربها"
    elif not market["ok"]:  # شرط إلزامي: الميم كوينز تنزل أكثر من السوق لما يضعف
        verdict = "❌ لا تدخل (السوق ضعيف)"
    elif score >= 3 and len(warn) <= 2 and rr >= 1.5:
        verdict = "✅ ادخل (بحجم صغير)"
    elif score >= 0:
        verdict = "⏳ انتظر"
    else:
        verdict = "❌ لا تدخل"

    return dict(symbol=main["baseToken"]["symbol"], name=main["baseToken"]["name"], address=addr,
                dex=main["dexId"], url=main["url"], price=price, mcap=mcap, liquidity=liq,
                age_h=age_h, change=ch, buys=buys, sells=sells, vol24=main.get("volume", {}).get("h24", 0),
                gt_score=info.get("gt_score"), verdict=verdict, score=score, market=market,
                hard=hard, warn=warn, good=good, plus=plus, minus=minus, t1h=t1, t15m=t15,
                supports=sorted(sups, reverse=True)[:3], resistances=sorted(ress)[:3],
                plan=dict(entry=entry, stop=stop, targets=targets, rr=rr,
                          stop_pct=(stop / entry - 1) * 100,
                          targets_pct=[(t / entry - 1) * 100 for t in targets]))


def report(a):
    ch, p = a["change"], a["plan"]
    L = [f"## {a['name']} ({a['symbol']}): {a['verdict']}",
         f"العقد: {a['address']}",
         f"السعر ${fmt(a['price'])} | القيمة السوقية ${a['mcap']:,.0f} | السيولة ${a['liquidity']:,.0f} | "
         f"العمر {a['age_h'] / 24:.0f} يوم",
         f"التغير: 5m {ch.get('m5', 0):+.1f}% | 1h {ch.get('h1', 0):+.1f}% | 6h {ch.get('h6', 0):+.1f}% | "
         f"24h {ch.get('h24', 0):+.1f}% | فوليوم 24h ${a['vol24']:,.0f}",
         f"صفقات 24h: {a['buys']:,} شراء / {a['sells']:,} بيع | GT Score {a['gt_score'] or 0:.0f}/100", ""]
    L += ["الأمان:"] + [f"  ⛔ {x}" for x in a["hard"]] + [f"  ⚠️ {x}" for x in a["warn"]] + [f"  ✅ {x}" for x in a["good"]]
    L += ["الشارت:"] + [f"  ✅ {x}" for x in a["plus"]] + [f"  ❌ {x}" for x in a["minus"]]
    if a["t1h"]:
        t = a["t1h"]
        L.append(f"  1h: RSI {t['rsi']:.0f} | StochRSI {t['stoch_k']:.0f} | EMA7 {fmt(t['ema7'])} / "
                 f"EMA25 {fmt(t['ema25'])}" + (f" / EMA99 {fmt(t['ema99'])}" if t["ema99"] else ""))
    if a["t15m"]:
        L.append(f"  15m: RSI {a['t15m']['rsi']:.0f} | StochRSI {a['t15m']['stoch_k']:.0f}")
    L += ["  الدعوم: " + ", ".join(fmt(s) for s in a["supports"]) +
          " | المقاومات: " + ", ".join(fmt(r) for r in a["resistances"]), "",
          "الخطة:",
          f"  الدخول {fmt(p['entry'])} | الوقف {fmt(p['stop'])} ({p['stop_pct']:.0f}%)",
          "  الأهداف: " + " / ".join(f"{fmt(t)} (+{pc:.0f}%)" for t, pc in zip(p["targets"], p["targets_pct"])),
          f"  المخاطرة للعائد: 1:{p['rr']:.1f}",
          market_line(a["market"]),
          f"DexScreener: {a['url']}"]
    return "\n".join(L)


def trending(n=10):
    d = gt_json(f"{GT}/trending_pools?page=1")["data"]
    rows = []
    for p in d[:n]:
        at = p["attributes"]
        ch = at.get("price_change_percentage") or {}
        liq = float(at.get("reserve_in_usd") or 0)
        mcap = float(at.get("market_cap_usd") or at.get("fdv_usd") or 0)
        age_h = (datetime.now(timezone.utc) - datetime.fromisoformat(
            at["pool_created_at"].replace("Z", "+00:00"))).total_seconds() / 3600
        flags = []
        if liq < 50_000:
            flags.append("سيولة ضعيفة")
        if age_h < 24:
            flags.append(f"عمرها {age_h:.0f}h")
        if float(ch.get("h24") or 0) > 100:
            flags.append("ضخ +100%")
        rows.append(f"{at['name']:<28} mcap ${mcap:>12,.0f} | سيولة ${liq:>10,.0f} | "
                    f"24h {float(ch.get('h24') or 0):+7.1f}% | " + (" ⚠️ " + "، ".join(flags) if flags else "✅ يستاهل فحص")
                    + f"\n    {p['relationships']['base_token']['data']['id'].split('_', 1)[1]}")
    return "## الترند على Solana (GeckoTerminal)\n" + "\n".join(rows)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("query", nargs="?")
    ap.add_argument("--trending", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    if args.trending:
        print(trending())
    elif args.query:
        res = analyze(args.query)
        print(json.dumps(res, ensure_ascii=False, indent=1) if args.json else report(res))
    else:
        ap.print_help()
