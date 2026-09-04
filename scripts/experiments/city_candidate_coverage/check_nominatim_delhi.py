import httpx

targets = [
    "India Gate Delhi",
    "Red Fort Delhi",
    "Qutub Minar Delhi",
    "Humayun's Tomb Delhi",
    "Lotus Temple Delhi",
    "Jama Masjid Delhi",
    "Akshardham Delhi",
    "Lodhi Garden Delhi",
    "National Museum Delhi",
]

for t in targets:
    try:
        r = httpx.get(
            "https://nominatim.openstreetmap.org/search",
            params={"q": t, "format": "json", "limit": 1},
            headers={"User-Agent": "YatraCanvas-Experiment/0.1 (info@yatracanvas.org)"},
            timeout=10.0
        )
        if r.status_code == 200 and r.json():
            item = r.json()[0]
            lat = float(item["lat"])
            lon = float(item["lon"])
            osm_type = item["osm_type"]
            osm_id = item["osm_id"]
            # Distance from Delhi center (28.6139, 77.2090)
            from math import cos, radians, sqrt
            d_km = sqrt(((lat - 28.6139) * 111.32) ** 2 + ((lon - 77.2090) * 111.32 * cos(radians(28.6139))) ** 2)
            print(f"{t:<25}: {osm_type}/{osm_id:<10} | dist: {d_km:5.2f} km | coords: ({lat:.4f}, {lon:.4f})")
    except Exception as e:
        print(t, "Error:", e)
