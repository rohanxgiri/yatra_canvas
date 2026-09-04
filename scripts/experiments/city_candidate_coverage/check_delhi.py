import httpx

lat, lon = 28.6139, 77.2090
bbox = "28.542035,77.127137,28.685765,77.290863"

query = f"""[out:json][timeout:45];
(
  nwr({bbox})["name"="India Gate"];
  nwr({bbox})["name"="Red Fort"];
  nwr({bbox})["name"="Humayun's Tomb"];
  nwr({bbox})["name"="Jama Masjid"];
);
out tags center 20;
"""

for endpoint in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter", "https://lz4.overpass-api.de/api/interpreter"]:
    try:
        print(f"Trying {endpoint}...")
        r = httpx.post(endpoint, data={"data": query}, headers={"User-Agent": "YatraCanvas/0.1"}, timeout=45.0)
        if r.status_code == 200:
            data = r.json()
            print("Found elements:", len(data.get("elements", [])))
            for el in data.get("elements", []):
                tags = el.get("tags", {})
                print(f"- {el['type']}/{el['id']}: {tags.get('name')} | tourism={tags.get('tourism')} | historic={tags.get('historic')} | amenity={tags.get('amenity')} | wikidata={tags.get('wikidata')}")
            break
        else:
            print("Status:", r.status_code)
    except Exception as e:
        print("Error:", e)

