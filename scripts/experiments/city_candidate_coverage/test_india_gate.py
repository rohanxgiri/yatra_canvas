import httpx

query = """[out:json][timeout:20];
(
  node(around:1000, 28.6129, 77.2295)["name"];
  way(around:1000, 28.6129, 77.2295)["name"];
  relation(around:1000, 28.6129, 77.2295)["name"];
);
out tags center 30;
"""

r = httpx.post(
    "https://overpass.kumi.systems/api/interpreter",
    data={"data": query},
    headers={"User-Agent": "YatraCanvas/0.1"},
    timeout=20.0
)
print("Status:", r.status_code)
for el in r.json().get("elements", []):
    tags = el.get("tags", {})
    name = tags.get("name")
    if name and "India Gate" in name:
        print("FOUND:", el["type"], el["id"], name, "tags:", tags)
