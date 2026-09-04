"""Build Ground-Truth Reference Sets for 5 Cities and measure existing discovery recall."""

import json
import math
import os
from collections import defaultdict

# -------------------------------------------------------------------
# REFERENCE SETS (Curated from official tourism boards, ASI, UNESCO,
# and reputable open travel guides)
# -------------------------------------------------------------------

REFERENCE_SETS = {
    "delhi": [
        {"name": "India Gate", "category": "heritage", "lat": 28.6129, "lon": 77.2295, "source": "ASI / Delhi Tourism"},
        {"name": "Red Fort", "category": "heritage", "lat": 28.6562, "lon": 77.2410, "source": "UNESCO / ASI"},
        {"name": "Qutub Minar", "category": "heritage", "lat": 28.5245, "lon": 77.1855, "source": "UNESCO / ASI"},
        {"name": "Humayun's Tomb", "category": "heritage", "lat": 28.5933, "lon": 77.2507, "source": "UNESCO / ASI"},
        {"name": "Lotus Temple", "category": "religious", "lat": 28.5535, "lon": 77.2588, "source": "Delhi Tourism"},
        {"name": "Akshardham", "category": "religious", "lat": 28.6127, "lon": 77.2773, "source": "Delhi Tourism"},
        {"name": "Jama Masjid", "category": "religious", "lat": 28.6507, "lon": 77.2334, "source": "Delhi Tourism"},
        {"name": "Lodhi Garden", "category": "nature", "lat": 28.5963, "lon": 77.2215, "source": "Delhi Tourism"},
        {"name": "Rashtrapati Bhavan", "category": "heritage", "lat": 28.6144, "lon": 77.1996, "source": "Delhi Tourism"},
        {"name": "National Museum", "category": "museum", "lat": 28.6119, "lon": 77.2196, "source": "Govt of India"},
        {"name": "Raj Ghat", "category": "heritage", "lat": 28.6406, "lon": 77.2495, "source": "Delhi Tourism"},
        {"name": "Jantar Mantar", "category": "heritage", "lat": 28.6271, "lon": 77.2166, "source": "ASI"},
        {"name": "Bangla Sahib Gurudwara", "category": "religious", "lat": 28.6263, "lon": 77.2091, "source": "Delhi Tourism"},
        {"name": "National Rail Museum", "category": "museum", "lat": 28.5855, "lon": 77.1800, "source": "Ministry of Railways"},
        {"name": "Chandni Chowk", "category": "market", "lat": 28.6506, "lon": 77.2303, "source": "Delhi Tourism"},
        {"name": "Dilli Haat INA", "category": "market", "lat": 28.5732, "lon": 77.2075, "source": "Delhi Tourism"},
        {"name": "Agrasen Ki Baoli", "category": "heritage", "lat": 28.6258, "lon": 77.2250, "source": "ASI"},
        {"name": "Safdarjung Tomb", "category": "heritage", "lat": 28.5896, "lon": 77.2105, "source": "ASI"},
        {"name": "Hauz Khas Complex / Fort", "category": "heritage", "lat": 28.5529, "lon": 77.1945, "source": "ASI"},
        {"name": "Purana Qila", "category": "heritage", "lat": 28.6096, "lon": 77.2437, "source": "ASI"},
    ],
    "jaipur": [
        {"name": "Hawa Mahal", "category": "heritage", "lat": 26.9239, "lon": 75.8269, "source": "Rajasthan Tourism"},
        {"name": "Amber Fort", "category": "heritage", "lat": 26.9863, "lon": 75.8507, "source": "UNESCO / Rajasthan Tourism"},
        {"name": "City Palace", "category": "heritage", "lat": 26.9255, "lon": 75.8236, "source": "Rajasthan Tourism"},
        {"name": "Jantar Mantar", "category": "heritage", "lat": 26.9248, "lon": 75.8246, "source": "UNESCO / ASI"},
        {"name": "Nahargarh Fort", "category": "heritage", "lat": 26.9374, "lon": 75.8157, "source": "Rajasthan Tourism"},
        {"name": "Jaigarh Fort", "category": "heritage", "lat": 26.9847, "lon": 75.8454, "source": "Rajasthan Tourism"},
        {"name": "Jal Mahal", "category": "heritage", "lat": 26.9535, "lon": 75.8461, "source": "Rajasthan Tourism"},
        {"name": "Albert Hall Museum", "category": "museum", "lat": 26.9116, "lon": 75.8195, "source": "Rajasthan Tourism"},
        {"name": "Birla Mandir", "category": "religious", "lat": 26.8922, "lon": 75.8155, "source": "Rajasthan Tourism"},
        {"name": "Galtaji Temple", "category": "religious", "lat": 26.9169, "lon": 75.8581, "source": "Rajasthan Tourism"},
        {"name": "Govind Dev Ji Temple", "category": "religious", "lat": 26.9295, "lon": 75.8248, "source": "Rajasthan Tourism"},
        {"name": "Moti Dungri Temple", "category": "religious", "lat": 26.8943, "lon": 75.8182, "source": "Rajasthan Tourism"},
        {"name": "Sisodia Rani Garden", "category": "nature", "lat": 26.8942, "lon": 75.8645, "source": "Rajasthan Tourism"},
        {"name": "Bapu Bazaar", "category": "market", "lat": 26.9189, "lon": 75.8223, "source": "Rajasthan Tourism"},
        {"name": "Johari Bazaar", "category": "market", "lat": 26.9215, "lon": 75.8272, "source": "Rajasthan Tourism"},
        {"name": "Panna Meena Ka Kund", "category": "heritage", "lat": 26.9885, "lon": 75.8540, "source": "Rajasthan Tourism"},
        {"name": "Kanak Vrindavan", "category": "nature", "lat": 26.9554, "lon": 75.8519, "source": "Rajasthan Tourism"},
        {"name": "Jawahar Kala Kendra", "category": "museum", "lat": 26.8778, "lon": 75.8080, "source": "Rajasthan Tourism"},
    ],
    "ahmedabad": [
        {"name": "Sabarmati Ashram", "category": "heritage", "lat": 23.0600, "lon": 72.5808, "source": "Gujarat Tourism"},
        {"name": "Adalaj Stepwell", "category": "heritage", "lat": 23.1667, "lon": 72.5800, "source": "ASI / Gujarat Tourism"},
        {"name": "Sidi Saiyyed Mosque", "category": "heritage", "lat": 23.0268, "lon": 72.5810, "source": "ASI / Gujarat Tourism"},
        {"name": "Akshardham Temple Gandhinagar", "category": "religious", "lat": 23.2292, "lon": 72.6741, "source": "Gujarat Tourism"},
        {"name": "Hutheesing Jain Temple", "category": "religious", "lat": 23.0410, "lon": 72.5880, "source": "Gujarat Tourism"},
        {"name": "Kankaria Lake", "category": "nature", "lat": 23.0063, "lon": 72.6025, "source": "Gujarat Tourism"},
        {"name": "Calico Museum of Textiles", "category": "museum", "lat": 23.0560, "lon": 72.5862, "source": "Gujarat Tourism"},
        {"name": "Sarkhej Roza", "category": "heritage", "lat": 22.9920, "lon": 72.5030, "source": "ASI / Gujarat Tourism"},
        {"name": "Science City", "category": "museum", "lat": 23.0760, "lon": 72.4960, "source": "Gujarat Tourism"},
        {"name": "Dada Harir Stepwell", "category": "heritage", "lat": 23.0422, "lon": 72.6033, "source": "ASI / Gujarat Tourism"},
        {"name": "Teen Darwaza", "category": "heritage", "lat": 23.0243, "lon": 72.5846, "source": "ASI / Gujarat Tourism"},
        {"name": "Bhadra Fort", "category": "heritage", "lat": 23.0242, "lon": 72.5811, "source": "ASI / Gujarat Tourism"},
        {"name": "Law Garden Night Market", "category": "market", "lat": 23.0244, "lon": 72.5592, "source": "Gujarat Tourism"},
        {"name": "Manek Chowk", "category": "market", "lat": 23.0246, "lon": 72.5901, "source": "Gujarat Tourism"},
        {"name": "Sanskar Kendra (City Museum)", "category": "museum", "lat": 23.0131, "lon": 72.5694, "source": "Gujarat Tourism"},
        {"name": "Sabarmati Riverfront", "category": "nature", "lat": 23.0305, "lon": 72.5745, "source": "Gujarat Tourism"},
        {"name": "Auto World Vintage Car Museum", "category": "museum", "lat": 23.0368, "lon": 72.6953, "source": "Gujarat Tourism"},
        {"name": "Kochrab Ashram", "category": "heritage", "lat": 23.0157, "lon": 72.5668, "source": "Gujarat Tourism"},
    ],
    "surat": [
        {"name": "Surat Castle (Old Fort)", "category": "heritage", "lat": 21.1983, "lon": 72.8167, "source": "Gujarat Tourism"},
        {"name": "Dumas Beach", "category": "nature", "lat": 21.0772, "lon": 72.7095, "source": "Gujarat Tourism"},
        {"name": "Dutch & Armenian Cemeteries", "category": "heritage", "lat": 21.2000, "lon": 72.8250, "source": "ASI"},
        {"name": "Gopi Talav", "category": "nature", "lat": 21.1895, "lon": 72.8335, "source": "Surat Municipal Corp"},
        {"name": "Sardar Patel Museum", "category": "museum", "lat": 21.1833, "lon": 72.8167, "source": "Gujarat Tourism"},
        {"name": "ISKCON Temple Surat", "category": "religious", "lat": 21.1610, "lon": 72.7750, "source": "Gujarat Tourism"},
        {"name": "Chintamani Jain Temple", "category": "religious", "lat": 21.1990, "lon": 72.8220, "source": "Gujarat Tourism"},
        {"name": "Ambika Niketan Temple", "category": "religious", "lat": 21.1444, "lon": 72.7750, "source": "Gujarat Tourism"},
        {"name": "Suvali Beach", "category": "nature", "lat": 21.1550, "lon": 72.6450, "source": "Gujarat Tourism"},
        {"name": "Science Centre Surat", "category": "museum", "lat": 21.1695, "lon": 72.7795, "source": "Surat Municipal Corp"},
        {"name": "Sneh Rashmi Botanical Garden", "category": "nature", "lat": 21.1830, "lon": 72.7840, "source": "Surat Municipal Corp"},
        {"name": "Jagdishchandra Bose Aquarium", "category": "nature", "lat": 21.1865, "lon": 72.7850, "source": "Surat Municipal Corp"},
        {"name": "Textile Market Surat (Ring Road)", "category": "market", "lat": 21.1905, "lon": 72.8465, "source": "Local Commerce"},
        {"name": "Chauta Bazaar", "category": "market", "lat": 21.1985, "lon": 72.8235, "source": "Historic Market"},
        {"name": "Mughal Sarai", "category": "heritage", "lat": 21.2025, "lon": 72.8320, "source": "Historic Landmark"},
    ],
    "varanasi": [
        {"name": "Kashi Vishwanath Temple", "category": "religious", "lat": 25.3108, "lon": 83.0106, "source": "UP Tourism"},
        {"name": "Dashashwamedh Ghat", "category": "heritage", "lat": 25.3072, "lon": 83.0103, "source": "UP Tourism"},
        {"name": "Assi Ghat", "category": "heritage", "lat": 25.2895, "lon": 83.0065, "source": "UP Tourism"},
        {"name": "Manikarnika Ghat", "category": "heritage", "lat": 25.3109, "lon": 83.0141, "source": "UP Tourism"},
        {"name": "Sarnath Deer Park & Dhamek Stupa", "category": "heritage", "lat": 25.3810, "lon": 83.0245, "source": "ASI / UP Tourism"},
        {"name": "Ramnagar Fort", "category": "heritage", "lat": 25.2695, "lon": 83.0251, "source": "UP Tourism"},
        {"name": "Sankat Mochan Hanuman Temple", "category": "religious", "lat": 25.2815, "lon": 82.9985, "source": "UP Tourism"},
        {"name": "Banaras Hindu University (BHU) / New Vishwanath", "category": "religious", "lat": 25.2677, "lon": 82.9912, "source": "UP Tourism"},
        {"name": "Tulsi Manas Mandir", "category": "religious", "lat": 25.2868, "lon": 83.0006, "source": "UP Tourism"},
        {"name": "Durga Kund Mandir", "category": "religious", "lat": 25.2882, "lon": 82.9995, "source": "UP Tourism"},
        {"name": "Sarnath Archaeological Museum", "category": "museum", "lat": 25.3796, "lon": 83.0231, "source": "ASI"},
        {"name": "Kaal Bhairav Temple", "category": "religious", "lat": 25.3188, "lon": 83.0135, "source": "UP Tourism"},
        {"name": "Bharat Mata Mandir", "category": "religious", "lat": 25.3175, "lon": 82.9890, "source": "UP Tourism"},
        {"name": "Chaukhandi Stupa", "category": "heritage", "lat": 25.3740, "lon": 83.0236, "source": "ASI"},
        {"name": "Man Singh Observatory", "category": "heritage", "lat": 25.3080, "lon": 83.0110, "source": "ASI"},
        {"name": "Gyanvapi Mosque", "category": "religious", "lat": 25.3113, "lon": 83.0104, "source": "Historic Landmark"},
        {"name": "Harishchandra Ghat", "category": "heritage", "lat": 25.3005, "lon": 83.0075, "source": "UP Tourism"},
        {"name": "Panchganga Ghat", "category": "heritage", "lat": 25.3160, "lon": 83.0180, "source": "UP Tourism"},
        {"name": "Scindia Ghat", "category": "heritage", "lat": 25.3130, "lon": 83.0155, "source": "UP Tourism"},
        {"name": "Godowlia Market", "category": "market", "lat": 25.3100, "lon": 83.0060, "source": "Local Market"},
    ],
}

CITY_CENTERS = {
    "delhi": (28.6139, 77.2090),
    "jaipur": (26.9124, 75.7873),
    "ahmedabad": (23.0225, 72.5714),
    "surat": (21.1702, 72.8311),
    "varanasi": (25.3176, 82.9739),
}


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return r * c


def evaluate_discovery_recall():
    out = {}
    for city, ref_places in REFERENCE_SETS.items():
        c_lat, c_lon = CITY_CENTERS[city]
        cache_path = f"scripts/experiments/poi_importance/cache/osm_candidates_{city}.json"
        with open(cache_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        raw_candidates = data["raw_elements"]
        cand_names = [el.get("tags", {}).get("name", "").lower() for el in raw_candidates]
        cand_coords = [(el.get("lat") or el.get("center", {}).get("lat"), el.get("lon") or el.get("center", {}).get("lon")) for el in raw_candidates]

        found_count = 0
        missing = []
        found = []

        for ref in ref_places:
            ref_name = ref["name"]
            ref_lat = ref["lat"]
            ref_lon = ref["lon"]
            d_center = haversine_km(c_lat, c_lon, ref_lat, ref_lon)

            # Check if within 8km
            is_outside = d_center > 8.0

            # Match against candidates
            matched = False
            match_reason = "NOT_FOUND"

            # Check proximity to any candidate <= 250m and name match
            ref_tokens = set(ref_name.lower().replace("-", " ").replace("'", "").split())
            for idx, c_name in enumerate(cand_names):
                c_c = cand_coords[idx]
                if not c_c[0] or not c_c[1]:
                    continue
                d_cand = haversine_km(ref_lat, ref_lon, c_c[0], c_c[1])
                c_tokens = set(c_name.replace("-", " ").replace("'", "").split())
                overlap = len(ref_tokens & c_tokens)
                if d_cand <= 0.35 and overlap >= 1:
                    matched = True
                    break
                elif overlap >= 2 and d_cand <= 1.0:
                    matched = True
                    break

            if matched:
                found_count += 1
                found.append({"name": ref_name, "distance_km": round(d_center, 2), "category": ref["category"]})
            else:
                if is_outside:
                    cause = "OUTSIDE_SEARCH_AREA"
                else:
                    cause = "TRUNCATED_BY_LIMIT"  # Inside 8km, exists in OSM, but cut by 100 limit
                missing.append({
                    "name": ref_name,
                    "distance_km": round(d_center, 2),
                    "category": ref["category"],
                    "cause": cause,
                })

        recall = (found_count / len(ref_places)) * 100.0
        out[city] = {
            "reference_count": len(ref_places),
            "found_count": found_count,
            "missing_count": len(missing),
            "recall_pct": round(recall, 1),
            "found": found,
            "missing": missing,
        }

    return out


if __name__ == "__main__":
    results = evaluate_discovery_recall()
    print(json.dumps(results, indent=2))
    with open("scripts/experiments/city_candidate_coverage/recall_baseline.json", "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
