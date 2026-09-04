# Multi-City Recommendation Quality Benchmark & Hardening

## Overview & Goal
The objective of this benchmark is to evaluate and harden YatraCanvas recommendation quality across diverse Indian cities, user intents, and requested itinerary sizes ($K \in [5, 10, 15, 20]$).
The benchmark operates **100% offline and deterministically**, using local candidate datasets, Audiala seed data, and deterministic fixtures.

---

## 1. Benchmark Cities & Scenarios

| City | Primary Purpose | Secondary Interests | Focus / Target Behavior |
| :--- | :--- | :--- | :--- |
| **Jaipur** | `heritage` | `sightseeing` | Major forts, palaces, and heritage rank strongly; tiny structures and typo variants do not consume slots. |
| **Varanasi** | `religious` | `temples`, `sightseeing`, `ghats` | Major sacred POIs & distinct ghats rank high; cafes/restaurants do not dominate a temple trip. |
| **Surat** | `food` | `food` | Authentic local speciality dining (khaman, locho, thali); institutional canteens and multi-outlet fast food chains do not dominate. |
| **Ahmedabad (Mixed)** | `food` | `heritage` | Mixed intent preserves balance between Gujarati culinary specialities and historic stepwells/mosques. |
| **Ahmedabad (Heritage)**| `heritage` | `sightseeing` | Dedicated heritage inquiry strongly prioritizes major monuments and stepwells. |
| **Udaipur** | `sightseeing` | `heritage` | Prominent lakes and palaces rank at the top without disruption from generic amenities. |
| **Mumbai (Mixed)** | `sightseeing` | `food`, `cafes` | Healthy diversity across icons, dining, and cafes without ten identical coffee shops or commercial bank branches. |
| **Delhi (Mixed)** | `heritage` | `food`, `sightseeing` | Iconic landmarks and rich food scene; secondary category (food) is not starved by landmark heritage scores. |

---

## 2. Evaluation Metrics & Pass/Fail Thresholds

1. **Intent Precision@K**: Fraction of top-$K$ recommendations matching the user's requested categories/purposes.
   - Target: $\ge 0.80$ at $K=5$, $\ge 0.70$ at $K=10$.
2. **Restricted / Unsuitable POI Rate**: Fraction of venues classified as institutional canteens, private, employee-only, student-only, hospital-only, or commercial non-tourist offices.
   - Target: **0** across all normal tourist scenarios.
3. **Duplicate Rate**: Fraction of canonical duplicates or near-duplicate presentation POIs.
   - Target: **0** canonical duplicates.
4. **Major POI (Gold) Recall**: Fraction of curated, essential landmark POIs surfaced within the top-$K$ list.
5. **Category Diversity Entropy**: Shannon entropy $H = -\sum p_c \ln(p_c)$ across represented categories in mixed-interest trips to detect category starvation.
6. **Determinism**: 100% stable ranking across repeated executions for identical inputs.
7. **Pipeline Funnel Tracking**: Counts tracked through raw candidates $\to$ suitability filter $\to$ category filter $\to$ deduplication $\to$ relevance score $\to$ final top-$K$.
8. **Runtime & Scaling**: Pipeline latency measured across $K \in [5, 10, 15, 20]$.

---

## 3. Discovered Failures in Baseline Run

| Scenario | Discovered Failure | Root Cause |
| :--- | :--- | :--- |
| **Surat (Food)** | Institutional dining facilities (`SVNIT Food Point`, `Central Campus Dining`) recommended for tourist food trips. | Lack of inspection for institutional `operator`, `building`, and contextual facility keywords in suitability filtering. |
| **Surat (Food, K=20)** | 6 Domino's Pizza and 3 Burger King branches filled 9 of 20 slots, displacing local speciality cuisine. | Spatial deduplication alone does not collapse distant multiple branches of the same national fast-food brand across a city. |
| **Mumbai (Mixed)** | `IIT Bombay Campus Food Court` and `Hdfc Bank Malabar Hill Ec Branch` surfaced in top recommendations. | Institutional facility leakage and open-dataset non-tourist commercial branch classification. |
| **Jaipur (Heritage)** | `Jaighar Fort` and `Jaigarh Fort` surfaced simultaneously in top 10. | Deduplication only matched exact token equality or single honorific difference; edit-distance typos were not merged. |
| **Delhi (Mixed)** | Heritage dominated 18 of 20 slots; `food` received only 2 slots (Diversity Entropy = 0.47). | Diversity interleaving compared secondary interests against absolute primary purpose scores using a strict 0.70 threshold. Primary purpose multiplier ($2.5\times$) locked out valid secondary candidates. |

---

## 4. Production Fixes Implemented

1. **Generalizable Institutional & Non-Tourist Suitability Filtering** (`place_suitability_service.py`):
   - Expanded `evaluate_access_confidence` to inspect `operator` (detecting universities, colleges, research institutes, hospitals, military establishments, etc.).
   - Added `building` tag inspection (`university`, `college`, `school`, `hospital`, `dormitory`, `hostel`, `barracks`, `office`).
   - Added `_NON_TOURIST_FACILITY_PATTERNS` to filter commercial retail bank branches, ATMs, and corporate/zonal offices without hardcoding place names.
   - Added generalized institutional dining and campus patterns (e.g. `campus food court`, `faculty dining`, `institute mess`) without hardcoding city/venue identifiers.
2. **Brand / Multi-Outlet Deduplication** (`recommendation_service.py`):
   - In Stage 5, multi-outlet chain brands (e.g. Domino's, Burger King, Starbucks) are capped to at most 1 representative instance per itinerary, preserving slots for authentic local dining and cultural venues.
3. **Phonetic & Typo Deduplication** (`place_deduplication_service.py`):
   - Added Levenshtein edit-distance token comparison ($\le 2$ edit distance for tokens $\ge 6$ chars) to `are_names_similar` to merge variants like `Jaigarh Fort` and `Jaighar Fort` while preserving distinct nearby entities (e.g. `Ajmeri Gate` vs `Sanganeri Gate`).
4. **Mixed-Interest Category Balancing** (`recommendation_service.py`):
   - In Stage 4b, eliminated the prohibitive cross-tier absolute score ratio threshold that caused category starvation in mixed itineraries. The interleaving loop now guarantees rotating representation for each strongly requested category while preserving primary purpose dominance.

---

## 5. Comparative Results: Baseline vs Post-Fix

| Scenario | K | Baseline Restricted | Post-Fix Restricted | Baseline Gold Recall | Post-Fix Gold Recall | Baseline Diversity Entropy | Post-Fix Diversity Entropy |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `surat` (Food) | 10 | 2 | **0 (FIXED)** | 1.00 | 1.00 | 0.00 | 0.72 |
| `surat` (Food) | 20 | 2 | **0 (FIXED)** | 1.00 | 1.00 | 0.00 | 0.72 |
| `mumbai_mixed` | 10 | 1 | **0 (FIXED)** | 0.57 | 0.57 | 1.52 | 1.49 |
| `mumbai_mixed` | 15 | 2 | **0 (FIXED)** | 0.57 | 0.71 | 1.34 | 1.24 |
| `mumbai_mixed` | 20 | 2 | **0 (FIXED)** | 0.71 | 0.71 | 1.16 | 1.05 |
| `jaipur` | 10 | 0 | 0 | 0.88 | **1.00 (FIXED)** | 0.72 | 0.88 |
| `delhi_mixed` | 10 | 0 | 0 | 0.75 | 0.75 | 0.72 | **1.16 (BALANCED)** |
| `delhi_mixed` | 20 | 0 | 0 | 0.75 | 0.75 | 0.47 | **1.16 (BALANCED)** |

---

## 6. How to Run the Benchmark

```powershell
# Run benchmark offline and generate post_fix.json
$env:PYTHONPATH="backend"; .\venv\Scripts\python scripts/experiments/recommendation_quality/run_benchmark.py --output scripts/experiments/recommendation_quality/results/post_fix.json

# Generate comparison report
$env:PYTHONPATH="backend"; .\venv\Scripts\python scripts/experiments/recommendation_quality/generate_report.py

# Run benchmark regression test suite
$env:PYTHONPATH="backend"; .\venv\Scripts\pytest backend/tests/test_recommendation_quality_benchmark.py -v
```

---

## 7. Remaining Weaknesses & Next Frontier
- **Sparse Metadata Food Venues**: Small local street-food stalls in tier-2/3 cities often lack `cuisine`, `description`, or website details in OSM. While permissive fallback ensures they are not rejected, fine-grained subcategory ranking (e.g. dessert vs street food) remains coarse without additional semantic tags.
- **Audiala Boundary Overlap**: In dense tourist hubs (e.g. Old Delhi, Varanasi Ghats), Audiala POIs and OSM nodes with slightly different English transliterations rely on fallback coordinate clustering ($\le 100$m) when Wikidata QIDs are missing.
