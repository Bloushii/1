# سعر دار السبائك الفعلي للذهب عيار 24 بالدينار (purchaseGoldPrice و sellGoldPrice هم عيار 24؛ الباقي 22 و21 و18 ما نستخدمه) (نفس الرابط اللي يقرا منه موقعهم)
import json, time, urllib.request

URL = "https://api.daralsabaek.com/api/goldAndFundBalance/getMetalSellAndBuyPrices"

def fetch():
    # يرجع {"buy": سعر شرائك من الدار, "sell": سعر بيعك للدار, "ounce": سعر الأونصة بالدولار} أو None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(URL, timeout=15) as r:
                x = json.load(r)["result"]
            return {"buy": float(x["purchaseGoldPrice"]), "sell": float(x["sellGoldPrice"]), "ounce": float(x["goldOuncePrice"])}
        except Exception:
            time.sleep(2 * (attempt + 1))
    return None
