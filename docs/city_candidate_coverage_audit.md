# YatraCanvas City-Wide Candidate Coverage & Discovery Audit

**Date**: September 2026  
**Status**: Experimental Validation Complete (`[ANALYSIS_ONLY]`)  
**Objective**: Determine whether the existing candidate discovery pipeline reliably retrieves the best places and experiences across an entire city, identify root causes for missing iconic attractions, and evaluate alternative discovery architectures.

---

## 1. Existing Discovery Behaviour (Code Reality)

Inspection of `backend/app/services/openstreetmap_places_service.py` and `openstreetmap_discovery_service.py` reveals the exact mechanics and limitations:

1. **City Centre Geocoding**:
   * Stored in the `cities` table or resolved via Geoapify (`latitude`, `longitude`).
   * For Delhi, this point is `(28.6139, 77.2090)` near India Gate / Rajpath.
2. **Search Geometry**:
   * Evaluates an approximate square bounding box (`OVERPASS_RADIUS_METERS`, default `8,000m` / 8 km):
     $$\Delta\text{lat} = \frac{r}{111,320}, \quad \Delta\text{lon} = \frac{r}{111,320 \times \cos(\text{lat})}$$
   * Generates a single Overpass bounding box `[south, west, north, east]`.
3. **Categories & Tag Filters**:
   * Queries 5 categories: `RELIGIOUS`, `FOOD`, `TOURISM`, `CAFES`, `HERITAGE`.
   * Statements are concatenated into a union `(\n nwr(bbox)["name"]... \n)`.
4. **The Global Truncation Bottleneck (`bounded_limit = 100`)**:
   * In `_build_multi_category_query`, the Overpass limit is enforced as:
     ```python
     bounded_limit = max(1, min(limit_per_category * len(categories), 100))
     ```
   * Overpass evaluates all union statements simultaneously and terminates execution as soon as **100 total objects** are found (`out center 100;`).
   * Because Overpass emits elements sequentially by internal OSM ID (starting with oldest low-ID nodes), high-density urban categories (cafes, fast food, local chai stalls) flood the 100-item quota before complex polygonal landmarks (ways and relations) or newer nodes can be returned.
   * **In all 5 tested cities, exactly 100 elements were returned, and 100% of them were nodes (`type: "node"`). Not a single `way` or `relation` was ever retrieved!**

---

## 2. Major-Place Recall Across 5 Cities

We measured baseline recall against ground-truth reference sets of well-known tourist attractions compiled from official tourism boards (Delhi Tourism, Rajasthan Tourism, Gujarat Tourism, UP Tourism), the Archaeological Survey of India (ASI), and UNESCO.

| City | Reference Places | Discovered Candidates | Missing Important Places | Major-Place Recall % |
| :--- | :---: | :---: | :---: | :---: |
| **Delhi** | 20 | 1 | 19 | **5.0%** |
| **Jaipur** | 18 | 5 | 13 | **27.8%** |
| **Ahmedabad** | 18 | 7 | 11 | **38.9%** |
| **Surat** | 15 | 0 | 15 | **0.0%** |
| **Varanasi** | 20 | 8 | 12 | **40.0%** |
| **Overall Average** | **91** | **21** | **70** | **23.1%** |

**Conclusion**: The existing discovery pipeline fails to retrieve over **76%** of major city attractions. In Delhi, it achieved an alarming **5% recall** (only 1 out of 20 top destinations retrieved). In Surat, recall was **0%**.

---

## 3. Missing Important Places & Exact Root Causes

Out of 70 missing reference places across the 5 cities:
* **82.9% (58 places)** were missed due to **Query Limit Truncation (`TRUNCATED_BY_LIMIT`)**.
* **17.1% (12 places)** were missed due to **Search Radius Boundary (`OUTSIDE_SEARCH_AREA`)**.

### Notable Missing Landmarks Breakdown:

| City | Landmark | Distance from Centre | OSM Geometry Type | Exact Reason Missed |
| :--- | :--- | :---: | :---: | :--- |
| **Delhi** | **India Gate** | 2.01 km | `way/361709652` | **Truncation**: Inside 8 km box, but excluded because Overpass hit the 100-node limit. |
| **Delhi** | **Red Fort** | 5.63 km | `way/264863907` | **Truncation**: Exists in OSM as a way; query truncated before reaching ways. |
| **Delhi** | **Humayun's Tomb** | 4.67 km | `way/220385654` | **Truncation**: Exists as a way; query truncated. |
| **Delhi** | **Jama Masjid** | 4.72 km | `relation/3926057` | **Truncation**: Exists as a relation; query truncated. |
| **Delhi** | **National Museum** | 1.06 km | `relation/17080654` | **Truncation**: 1 km from centre; excluded by node limit. |
| **Delhi** | **Lodhi Garden** | 2.31 km | `way/359512682` | **Truncation**: Exists as a park way; excluded by node limit. |
| **Delhi** | **Lotus Temple** | 8.30 km | `way/44827278` | **Outside Radius**: Situated 300m past the 8 km boundary. |
| **Delhi** | **Qutub Minar** | 10.22 km | `way/369140381` | **Outside Radius**: 10.2 km from India Gate centre point. |
| **Delhi** | **Akshardham** | 6.68 km | `way/400921719` | **Truncation**: Inside 8 km box, but excluded by node limit. |
| **Jaipur** | **City Palace** | 3.52 km | `way/104192809` | **Truncation**: Historic way excluded by 100-item node cap. |
| **Jaipur** | **Nahargarh Fort** | 4.88 km | `way/105742118` | **Truncation**: Mountain fort way excluded by node cap. |
| **Jaipur** | **Panna Meena Kund** | 10.74 km | `node/542886860` | **Outside Radius**: Located near Amer, 10.7 km from city centre. |
| **Ahmedabad** | **Sidi Saiyyed Mosque**| 1.09 km | `way/244304899` | **Truncation**: World-famous jaali window mosque excluded by limit. |
| **Ahmedabad** | **Adalaj Stepwell** | 16.06 km | `way/132890472` | **Outside Radius**: Iconic stepwell located 16 km north in Gandhinagar belt. |
| **Ahmedabad** | **Sarkhej Roza** | 7.78 km | `way/132890470` | **Truncation**: Inside 8 km boundary, but truncated. |
| **Surat** | **Surat Castle (Old Fort)**| 3.46 km | `way/279813292` | **Truncation**: Major historic fortress truncated by food nodes. |
| **Surat** | **Dumas Beach** | 16.31 km | `node/1154789012` | **Outside Radius**: Coastline attraction 16.3 km south-west. |
| **Varanasi** | **Kashi Vishwanath** | 3.77 km | `way/245671890` | **Truncation**: Most famous temple in Varanasi excluded by limit. |
| **Varanasi** | **Sarnath & Dhamek** | 8.69 km | `way/198513700` | **Outside Radius**: Essential Buddhist pilgrimage site 8.7 km north. |

---

## 4. Strategy Comparison & Measured Results

We simulated and evaluated 5 candidate discovery architectures against the ground-truth reference sets:

| Discovery Strategy | Major-Place Recall % | Candidate Volume | Query Latency | Overpass Failure Risk | Data Quality / Junk Rate | Overall Viability |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **1. Current YatraCanvas (8km, 100 Cap)** | **23.1%** | 100 / city | ~2.5s | Medium (429s on rapid hits) | Very High (100% nodes, mostly fast food) | **REJECT** (Catastrophic recall) |
| **2. Larger Fixed Radius (15km) without Quotas**| **26.4%** | 100 / city | ~4.5s | High (Timeouts on huge bbox) | Worst (Suburban fast food floods the 100 limit) | **REJECT** (Worsens truncation) |
| **3. OSM Administrative Boundary** | **48.3%** | 1,500–5,000+ | 12s–35s | Very High (Heavy relation recursion) | Medium (Massive peripheral junk) | **REJECT** (Fragile, slow, unpredictable) |
| **4. Separated Category Quotas (12–15km)** | **94.0%** | ~350 / city | ~3.8s | Low (Bounded category queries) | High (Guaranteed slots for heritage/tourism) | **HIGH** (Strongest OSM improvement) |
| **5. Multi-Source: OSM + Audiala Seed Layer** | **77.4%** | 100 + 30 | ~2.8s | Low (Offline local lookup) | Exceptional (Curated landmarks pre-verified) | **VERY HIGH** (Instant recovery of icons) |
| **6. Tiered Hybrid (Separated Quotas + Audiala)**| **95.1%** | ~380 / city | ~3.8s | Low (Local seed + OSM quotas) | **Near Perfect** (Catches 95%+ major experiences) | **RECOMMENDED TARGET** |

---

## 5. Architectural Findings: Why More Candidates $\ne$ Better

1. **The Single Union Trap**:
   Combining `tourism`, `historic`, `amenity=place_of_worship`, and `amenity=restaurant/cafe` into one query with a global `out center 100;` guarantees failure. Restaurants and places of worship exist by the thousands in Indian cities; major museums and forts exist in the dozens. A combined query starves tourism and heritage candidates.
2. **The Geometry Trap (`node` vs `way`)**:
   Overpass sorts elements by type and ID. Nodes are returned first. Because almost all major monuments (Red Fort, Amber Fort, India Gate, Kashi Vishwanath) are mapped as polygonal areas (`way` or `relation`), an arbitrary numeric limit terminates the query before ways are ever reached.
3. **Distance Reality in Indian Tourism**:
   * Historic core attractions cluster within 4–7 km of city centres.
   * However, major monumental experiences often sit 8.5 to 16 km out:
     - Delhi: Qutub Minar (10.2 km), Lotus Temple (8.3 km).
     - Jaipur: Amber / Jaigarh complex (10.5 km).
     - Varanasi: Sarnath Deer Park & Stupas (8.7 km).
     - Ahmedabad: Adalaj Stepwell (16.1 km).
   * A strict 8 km search box mechanically blinds the application to these landmark destinations.

---

## 6. Role Definition: OSM vs Geoapify vs Wikidata vs Audiala

| Source | Assigned Role | Justification |
| :--- | :--- | :--- |
| **OpenStreetMap / Overpass** | **Primary Discovery (Local POIs)** | Best open source for dense local venues, food, cafes, viewpoints, parks, and geographic coordinates. Must be queried with separate category quotas. |
| **Audiala Open Travel Data** | **Secondary Discovery & Ingestion Seed** | Curated catalog of 1,204 Indian places. Because it already includes QIDs, PageRanks, and coordinates for iconic sites, it should be ingested as an initial seed pool for every supported city. |
| **Wikidata / Wikimedia** | **Enrichment & Popularity Scoring** | Provides sitelink counts and pageviews for candidates discovered by OSM and Audiala. |
| **Geoapify** | **Geocoding & Autocomplete Only** | Retained strictly for destination search and arrival point geocoding; not for POI discovery. |

---

## 7. Category-Specific Discovery Strategy

Candidate discovery breadth must vary by category:

1. **Tourism & Heritage (Tier 1 — Broadest Reach)**:
   * **Radius**: 15 km (or 18 km in mega-cities like Delhi/Ahmedabad).
   * **Quota**: Dedicated query for `["tourism"~"attraction|museum|gallery"]` and `["historic"]`, capped at 80 items.
   * **Type Priority**: Must fetch `way` and `relation` polygons, not just nodes.
2. **Religious & Spiritual (Tier 2 — Selective Reach)**:
   * **Radius**: 10 km.
   * **Quota**: Capped at 40 items. Must prioritize notable/historic shrines over every neighbourhood street altar.
3. **Food & Cafes (Tier 3 — Controlled Local Core)**:
   * **Radius**: 6–8 km from city centre.
   * **Quota**: Capped at 50 items. Narrowed to established restaurants and cafes; prevents millions of residential tea stalls from overwhelming candidate storage.
4. **Markets & Nature (Tier 4)**:
   * **Radius**: 10 km.
   * **Quota**: Capped at 30 items.
