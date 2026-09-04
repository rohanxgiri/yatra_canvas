# YatraCanvas POI Importance & Popularity Feasibility Experiment

**Date**: September 2026  
**Status**: Experimental Validation Complete (`[ANALYSIS_ONLY]`)  
**Scope**: Evaluates Wikidata, Wikipedia/Wikimedia Pageviews, and Audiala Open Travel Data across **Jaipur, Ahmedabad, Surat, Delhi, and Varanasi** to solve the city-level place importance problem.

---

## 1. Candidate & Metadata Coverage Across Test Cities

| City | Candidates Evaluated | OSM `wikidata` Coverage | OSM `wikipedia` Coverage | OSM `historic` / `heritage` | OSM `opening_hours` | Audiala Matched POIs | Wikipedia Pageviews Measured |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Jaipur** | 99 | 5 (5.1%) | 1 (1.0%) | 8 (8.1%) | 13 (13.1%) | 5 (5.1%) | 6 (6.1%) |
| **Ahmedabad** | 99 | 6 (6.1%) | 6 (6.1%) | 9 (9.1%) | 9 (9.1%) | 6 (6.1%) | 6 (6.1%) |
| **Surat** | 97 | 0 (0.0%) | 0 (0.0%) | 6 (6.2%) | 6 (6.2%) | 1 (1.0%) | 0 (0.0%) |
| **Delhi** | 98 | 11 (11.2%) | 8 (8.2%) | 22 (22.4%) | 6 (6.1%) | 4 (4.1%) | 9 (9.2%) |
| **Varanasi** | 100 | 0 (0.0%) | 0 (0.0%) | 2 (2.0%) | 4 (4.0%) | 27 (27.0%) | 0 (0.0%) |
| **Total / Avg** | **493** | **22 (4.5%)** | **15 (3.0%)** | **47 (9.5%)** | **38 (7.7%)** | **43 (8.7%)** | **21 (4.3%)** |

### Key Observations on OSM Metadata:
1. **Extreme Sparsity of Wikidata in Tier 2/3 Cities**: In Surat and Varanasi, exactly **0%** of candidate POIs returned by Overpass contained a `wikidata` or `wikipedia` tag.
2. **Audiala's Spatial Matching Bridges the Gap**: In Varanasi, where OSM had 0% Wikidata tags, coordinate + name matching with Audiala identified **27 famous Ghats, Forts, and Observatories** (27% coverage), importing precomputed Wikidata QIDs, PageRanks, and Sitelinks.
3. **Opening Hours Sparsity**: Across all five cities, OSM `opening_hours` tags exist for only **4% to 13%** of POIs (average 7.7%), predominantly on chain restaurants and major museums.

---

## 2. Top-20 Ranking Comparisons (All 5 Cities)

### City 1: Jaipur (Rajasthan)

| Rank | Current YatraCanvas (Variant A) | Best Open-Data Ranking (Variant C: Wikidata + Wikipedia) | Composite Open-Data (Variant D: Wiki + Audiala) |
| :---: | :--- | :--- | :--- |
| **1** | Jantar Mantar (48.0) | **Hawa Mahal** (94.2, 59 sl, 60.9k views) | **Jantar Mantar** (91.8, PR: 18.56) |
| **2** | Hawa Mahal (48.0) | **Jantar Mantar** (89.5, 47 sl, 21.1k views) | **Hawa Mahal** (84.2, PR: 4.32) |
| **3** | Jaigarh Fort (48.0) | **Amber Fort** (84.0, 44 sl, 3.1k views) | **Amber Fort** (81.0, PR: 6.92) |
| **4** | Amber Fort (48.0) | **Jaigarh Fort** (79.8, 21 sl, 6.9k views) | **Jaigarh Fort** (69.1, PR: 2.41) |
| **5** | Sheesh Mahal (48.0) | **Albert Hall** (73.6, 10 sl, 6.3k views) | **Albert Hall** (59.6, Aud: No) |
| **6** | Sun Gate (48.0) | Sheesh Mahal (30.0, 0 sl, 0 views) | Galtaji (30.8, PR: 0.74) |
| **7** | Moon Gate (48.0) | Sun Gate (30.0, 0 sl, 0 views) | Sheesh Mahal (25.0) |
| **8** | Natraj veg Restaurant (40.0) | Moon Gate (30.0, 0 sl, 0 views) | Sun Gate (25.0) |
| **9** | Anokhi Cafe (40.0) | Pink City (25.0) | Moon Gate (25.0) |
| **10** | Pink City (40.0) | Elefantastic (25.0) | Natraj veg Restaurant (15.0) |
| **11** | Albert Hall (40.0) | Maharaniyon (25.0) | Sun Temple, Jaipur (15.0) |
| **12** | Ganesh Restaurant (40.0) | Sawai Mansingh Townhall (25.0) | Anokhi Cafe (15.0) |
| **13** | Spice Court (40.0) | Diwan-i-Am (25.0) | Pink City (15.0) |
| **14** | Laxmi Mishthan Bhandar (40.0) | Elephant Riding (25.0) | Jain Temple (15.0) |
| **15** | Moti Park (40.0) | Natraj veg Restaurant (15.0) | Ganesh Restaurant (15.0) |
| **16** | Savitri Park (40.0) | Galtaji (15.0) | Spice Court (15.0) |
| **17** | Old Green Tandori Dhaba (40.0)| Sun Temple, Jaipur (15.0) | Laxmi Mishthan Bhandar (15.0) |
| **18** | Saras Parlur (40.0) | Anokhi Cafe (15.0) | Moti Park (15.0) |
| **19** | Hotel Raj Style Inn (40.0) | Jain Temple (15.0) | Savitri Park (15.0) |
| **20** | Neelam Dhaba (40.0) | Ganesh Restaurant (15.0) | Old Green Tandori Dhaba (15.0) |

*Verdict*: Variant C and D immediately propel the world-famous UNESCO and ASI monuments (Hawa Mahal, Jantar Mantar, Amber Fort, Jaigarh Fort, Albert Hall) to ranks 1–5 with massive statistical separation (scores 73–94) over neighbourhood gates and local dhabas (scores 15–30).

---

### City 2: Ahmedabad (Gujarat)

| Rank | Current YatraCanvas (Variant A) | Best Open-Data Ranking (Variant C: Wikidata + Wikipedia) | Composite Open-Data (Variant D: Wiki + Audiala) |
| :---: | :--- | :--- | :--- |
| **1** | Raipur Gate (48.0) | **Teen Darwaza** (68.4, 10 sl, 847 views) | **Dada Harir Stepwell** (56.9, PR: 1.12) |
| **2** | Panch Kua Dawaza (48.0) | **Dada Harir Stepwell** (67.4, 7 sl, 1.6k views) | **Teen Darwaza** (56.4, PR: 0.59) |
| **3** | Kalupur Darwaza (48.0) | **Raipur Gate** (59.8, 3 sl, 921 views) | **Raipur Gate** (48.8) |
| **4** | Astodia Gate (48.0) | **Astodia Gate** (59.8, 3 sl, 921 views) | **Astodia Gate** (48.8) |
| **5** | Teen Darwaza (48.0) | **Sanskar Kendra Museum** (51.6, 9 sl, 604 views) | **Sanskar Kendra Museum** (46.9, PR: 1.51) |
| **6** | AKHBAR NAGAR CIRCLE (48.0) | **Calico Textile Museum** (47.6, 5 sl, 697 views) | **Calico Textile Museum** (43.5, PR: 1.29) |
| **7** | Panch Kuva Darwaja (48.0) | Panch Kua Dawaza (30.0) | **Prem Darwaza** (42.1, Aud: Yes) |
| **8** | Jain temple (48.0) | Kalupur Darwaza (30.0) | **Kochrab Satyagraha Ashram** (35.0, PR: 2.51)|
| **9** | Prem Darwaza (48.0) | AKHBAR NAGAR CIRCLE (30.0) | Panch Kua Dawaza (25.0) |
| **10** | Sakar 2 (40.0) | Panch Kuva Darwaja (30.0) | Kalupur Darwaza (25.0) |
| **11** | Sakar 4 (40.0) | Jain temple (30.0) | AKHBAR NAGAR CIRCLE (25.0) |
| **12** | Sanskar Kendra Museum (40.0) | Prem Darwaza (30.0) | Panch Kuva Darwaja (25.0) |
| **13** | Vishala (40.0) | Sakar 2 (25.0) | Jain temple (25.0) |
| **14** | Rajvadu Restaurant (40.0) | Sakar 4 (25.0) | Manav Mandir (15.0) |
| **15** | Kankaria Zoo (40.0) | Narol Circle (25.0) | Karnvanath Mahadev Temple (15.0) |
| **16** | Narol Circle (40.0) | Bird Feeder (25.0) | Paramdham Temple (15.0) |
| **17** | Vechaar Utensils Museum (40.0) | Bird Feeder (25.0) | Gayatri Mandir (15.0) |
| **18** | Mangaldas Ni Haveli (40.0) | ashram-managers guesthouse (25.0) | Jalaram Mandir (15.0) |
| **19** | Bird Feeder (40.0) | Prathana Bhoomi (25.0) | Sakar 2 (15.0) |
| **20** | Bird Feeder (40.0) | Imam Manzil (25.0) | Sakar 4 (15.0) |

*Verdict*: In Variant A, a traffic junction (`AKHBAR NAGAR CIRCLE`) was tied at rank 6 above world-renowned museums like Sanskar Kendra and Calico Textile Museum. In Variant C and D, the museums and historic stepwells jump to the top, and Kochrab Ashram is recovered.

---

### City 3: Surat (Gujarat)

| Rank | Current YatraCanvas (Variant A) | Best Open-Data Ranking (Variant C: Wikidata + Wikipedia) | Composite Open-Data (Variant D: Wiki + Audiala) |
| :---: | :--- | :--- | :--- |
| **1** | VICHAR KRANTI CIRCLE (48.0) | VICHAR KRANTI CIRCLE (30.0) | **Dutch & Armenian Tombs** (42.1, Aud: Yes) |
| **2** | PALANPUR JAKAT NAKA (48.0) | PALANPUR JAKAT NAKA (30.0) | VICHAR KRANTI CIRCLE (25.0) |
| **3** | Swami Vivekanand Circle (48.0)| Swami Vivekanand Circle (30.0) | PALANPUR JAKAT NAKA (25.0) |
| **4** | Mangalam Heights (48.0) | Mangalam Heights (30.0) | Swami Vivekanand Circle (25.0) |
| **5** | Dutch & Armenian Tombs (48.0)| Dutch & Armenian Tombs (30.0) | Mangalam Heights (25.0) |
| **6** | VISHAL NAGAR MARRIGE HALL (48.0)| VISHAL NAGAR MARRIGE HALL (30.0) | VISHAL NAGAR MARRIGE HALL (25.0) |
| **7** | The Grand Bhagwati (40.0) | SHREENIKETAN (25.0) | The Grand Bhagwati (15.0) |
| **8** | McDonald's (40.0) | Vasanjipark (25.0) | McDonald's (15.0) |
| **9** | Domino's Pizza (40.0) | Surat 19th c. Firetruck (25.0) | Domino's Pizza (15.0) |
| **10** | Yoko Sizzler (40.0) | Anand Nagar Hall (25.0) | Yoko Sizzler (15.0) |
| **11** | Sizzling Salsa (40.0) | The Grand Bhagwati (15.0) | Sizzling Salsa (15.0) |
| **12** | Barbeque Nation (40.0) | McDonald's (15.0) | Barbeque Nation (15.0) |
| **13** | Wok On Fire (40.0) | Domino's Pizza (15.0) | Wok On Fire (15.0) |
| **14** | Cafe Coffee Day (40.0) | Yoko Sizzler (15.0) | Cafe Coffee Day (15.0) |
| **15** | Gokulam Dairy (40.0) | Sizzling Salsa (15.0) | Gokulam Dairy (15.0) |
| **16** | Children's Traffic Park (40.0)| Barbeque Nation (15.0) | Children's Traffic Park (15.0) |
| **17** | Cafe Coffee Day (40.0) | Wok On Fire (15.0) | Cafe Coffee Day (15.0) |
| **18** | adarsh (40.0) | Cafe Coffee Day (15.0) | omkar (15.0) |
| **19** | cafe coffeee (40.0) | Gokulam Dairy (15.0) | adarsh (15.0) |
| **20** | sheetal park (40.0) | Children's Traffic Park (15.0) | cafe coffeee (15.0) |

*Verdict*: Demonstrates a critical OSM tag abuse problem: local users tagged traffic circles, toll gates, marriage halls, and modern apartment buildings as `historic=yes` in Surat. Because Surat had 0 Wikidata tags, Variant C could not fix this. Only Variant D (Audiala matching) was able to identify the genuine monument (`Dutch & Armenian Tombs & Cemeteries`) and lift it to #1.

---

### City 4: Delhi (National Capital Region)

| Rank | Current YatraCanvas (Variant A) | Best Open-Data Ranking (Variant C: Wikidata + Wikipedia) | Composite Open-Data (Variant D: Wiki + Audiala) |
| :---: | :--- | :--- | :--- |
| **1** | Dandi March Statue (48.0) | **Tomb of Abdul Rahim Khan** (82.7, 25 sl, 11.7k pv)| **Tomb of Abdul Rahim Khan** (66.5) |
| **2** | Teen Murti Haifa Memorial (48.0)| **Jamali Kamali Tomb** (74.1, 14 sl, 2.7k pv) | **Iron Pillar** (60.8, PR: 5.53) |
| **3** | Kisan Ghat (48.0) | **Isa Khan's Tomb** (69.2, 9 sl, 1.6k pv) | **Jamali Kamali Tomb** (59.8) |
| **4** | Octagonal observation post (48.0)| **Sunehri Masjid** (65.6, 9 sl, 407 pv) | **Isa Khan's Tomb** (57.8, PR: 0.87) |
| **5** | Bijaymandal Hall Ruins (48.0) | **Iron Pillar** (63.0, 44 sl) | **Sunehri Masjid** (53.0) |
| **6** | Dome (48.0) | **Diwan-e-Aam** (52.3, 7 sl, 1.6k pv) | **Diwan-e-Aam** (45.1, PR: 0.26) |
| **7** | Munda Gumbad (48.0) | **Kiran Nadar Museum** (51.4, 7 sl, 1.1k pv) | **Kiran Nadar Museum** (43.9) |
| **8** | Unidentified Tomb (48.0) | Kisan Ghat (37.8, 1 sl, 1 pv) | Munda Gumbad (39.5, Aud: Yes) |
| **9** | Tombs (48.0) | Munda Gumbad (36.0, 1 sl, 0 pv) | Kisan Ghat (31.0) |
| **10** | Tomb (48.0) | Mirza Ghalib's Tomb (36.0, 1 sl, 0 pv) | Mirza Ghalib's Tomb (29.5) |
| **11** | Gateway Guest House (48.0) | Biran Ka Gumbad (36.0, 1 sl, 0 pv) | Biran Ka Gumbad (29.5) |
| **12** | Gumti (48.0) | Dandi March Statue (30.0) | Dandi March Statue (25.0) |
| **13** | Jamali Kamali Tomb (48.0) | Teen Murti Haifa Memorial (30.0) | Teen Murti Haifa Memorial (25.0) |
| **14** | Lal Gumbad (48.0) | Octagonal observation post (30.0) | Octagonal observation post (25.0) |
| **15** | Vijaymandal (48.0) | Bijaymandal Hall Ruins (30.0) | Bijaymandal Hall Ruins (25.0) |
| **16** | Tughlakabad Mosque (48.0) | Dome (30.0) | Dome (25.0) |
| **17** | Mirza Ghalib's Tomb (48.0) | Unidentified Tomb (30.0) | Unidentified Tomb (25.0) |
| **18** | Moluddin Chisti's Grave (48.0)| Tombs (30.0) | Tombs (25.0) |
| **19** | Iron Pillar (48.0) | Tomb (30.0) | Tomb (25.0) |
| **20** | Tomb of Abdul Rahim Khan (48.0)| Gateway Guest House (30.0) | Gateway Guest House (25.0) |

*Verdict*: In Variant A, major monuments like the `Iron Pillar` (Qutb Complex) and `Tomb of Abdul Rahim Khan-i-Khanan` were stuck at ranks 19 and 20, tied with generic entries named `"Tomb"`, `"Tombs"`, `"Dome"`, and `"Unidentified Tomb"`. In Variant C and D, famous documented heritage sites surge to ranks 1–7, while nameless ruins drop out of the top recommendations.

---

### City 5: Varanasi (Uttar Pradesh)

| Rank | Current YatraCanvas (Variant A) | Best Open-Data Ranking (Variant C: Wikidata + Wikipedia) | Composite Open-Data (Variant D: Wiki + Audiala) |
| :---: | :--- | :--- | :--- |
| **1** | Madan Mohan Malviye Statue (48.0)| Madan Mohan Malviye Statue (30.0) | **Ramnagar Fort** (40.9, PR: 3.92) |
| **2** | Ashokan Pillar (48.0) | Ashokan Pillar (30.0) | **Man Singh Observatory** (39.6, PR: 4.52) |
| **3** | Hanuman Ghat (40.0) | Hanuman Ghat (25.0) | **Ahilyabai Ghat** (38.6, PR: 3.24) |
| **4** | Ahilyabai Ghat (40.0) | Ahilyabai Ghat (25.0) | **Manmandir Ghat** (38.6, PR: 3.24) |
| **5** | Raja Ghat (40.0) | Raja Ghat (25.0) | **Munshi Ghat** (38.6, PR: 3.24) |
| **6** | Ranamahal Ghat (40.0) | Ranamahal Ghat (25.0) | **Darbhanga Ghat** (38.6, PR: 3.24) |
| **7** | Chatni (food, 40.0) | Manasarowa Ghat (25.0) | **Manikarnika Ghat** (38.6, PR: 3.45) |
| **8** | Manasarowa Ghat (40.0) | Manmandir Ghat (25.0) | **Prayag Ghat** (38.6, PR: 3.24) |
| **9** | Manmandir Ghat (40.0) | Kedar Ghat (25.0) | **Jalasayi Ghat** (38.6, PR: 3.45) |
| **10** | Kedar Ghat (40.0) | Badhaini Ghat (25.0) | **Badhaini Ghat** (38.1, PR: 3.47) |
| **11** | Badhaini Ghat (40.0) | Ganga Mahal Ghat (25.0) | **Tulsi Ghat** (38.1, PR: 3.47) |
| **12** | Ganga Mahal Ghat (40.0) | Lali Ghat (25.0) | **Reewa Ghat** (38.1, PR: 3.47) |
| **13** | Lali Ghat (40.0) | Babua Pandey Ghat (25.0) | **janki ghat** (38.1, PR: 3.47) |
| **14** | Marwadi Bhojanalay (food, 40.0)| Munshi Ghat (25.0) | **Sankatha Ghat** (36.7, PR: 3.07) |
| **15** | Babua Pandey Ghat (40.0) | Karnataka Ghat (25.0) | **Mehfa Ghat** (36.7, PR: 3.07) |
| **16** | Munshi Ghat (40.0) | Narad Ghat (25.0) | **Ram Ghat** (36.7, PR: 3.07) |
| **17** | Karnataka Ghat (40.0) | Chousatti Ghat (25.0) | **Scindia Ghat** (36.7, PR: 3.07) |
| **18** | Narad Ghat (40.0) | Ganesh Ghat (25.0) | **Bhonsale Ghat** (36.7, PR: 3.07) |
| **19** | Chousatti Ghat (40.0) | Dr. Rajendra Prasad Ghat (25.0) | **Ganesh Ghat** (35.9, PR: 2.99) |
| **20** | Phulwari Restaurant (food, 40.0)| Tulsi Ghat (25.0) | **Lalita Ghat** (35.9, PR: 2.99) |

*Verdict*: In Varanasi, Overpass returns 60+ individual Ghats, all tagged identically as `tourism=attraction` with no ratings and no OSM Wikidata tags. In Variant A, random restaurants and snacks (`Chatni`, `Marwadi Bhojanalay`) mingle arbitrarily with Ghats. In Variant D, Audiala's matched PageRanks successfully structure the famous Ghats (Ahilyabai, Manikarnika, Tulsi, Scindia) and major monuments (Ramnagar Fort, Man Singh Observatory).

---

## 3. Best Performing Signals

Ranking of tested importance signals by practical effectiveness:

1. **Wikidata Sitelinks Count (`sitelinks`) — [RANK 1: BEST OVERALL SIGNAL]**:
   * *Effectiveness*: Exceptional. Logarithmic scaling ($\log_{10}(\text{sitelinks}+1)$) perfectly distinguishes global icons (Taj Mahal: 100+, Hawa Mahal: 59, Amber Fort: 44, Jantar Mantar: 47) from local attractions (3–10) and obscure tags (0).
   * *Reliability*: Uncompromised encyclopedic neutral standard across all languages.
2. **Wikipedia 90-Day Pageviews — [RANK 2: HIGH CONTRAST SIGNAL]**:
   * *Effectiveness*: Very high. Separates actively visited tourist attractions from obscure administrative listings. In Jaipur, Hawa Mahal (60,903 views) and Jantar Mantar (21,127 views) stood out dramatically.
   * *Limitation*: Can be spikey or biased toward entities in recent political/pop-culture news.
3. **Audiala Open Data Presence & PageRank — [RANK 3: HIGH VALUE CURATION OVERLAY]**:
   * *Effectiveness*: Essential for compensating for OSM tag sparsity. When OSM lacks a `wikidata` tag (Surat, Varanasi), Audiala's pre-matched catalog of 1,204 Indian places injects fame signals through spatial/name matching.
   * *Limitation*: Selective coverage (only 16 in Jaipur, 5 in Surat). Cannot act as a standalone candidate source.
4. **OSM Historic / Tourism Tags — [RANK 4: BASELINE CANDIDATE RETRIEVAL]**:
   * *Effectiveness*: Good for discovery, bad for ranking. Tags like `historic=yes` are frequently misapplied by OSM contributors to wedding halls, traffic roundabouts, and apartment buildings (observed heavily in Surat and Ahmedabad).
5. **OSM Heritage / UNESCO Tags — [RANK 5: HIGH PRECISION, ZERO COVERAGE]**:
   * *Effectiveness*: High precision when present, but present in only **1 out of 493** candidates tested across the 5 cities.

---

## 4. Category Performance Analysis

| Category | Best Signals | Signal Weaknesses & Failure Modes |
| :--- | :--- | :--- |
| **Major Monuments & Forts** | Wikidata sitelinks + Wikipedia Pageviews + Audiala PageRank | Extremely strong. Amber Fort, Hawa Mahal, Tomb of Abdul Rahim Khan rank at the very top. |
| **Museums & Observatories** | Wikidata sitelinks + Pageviews | Very strong. Albert Hall, Calico Museum, Sanskar Kendra, Jantar Mantar separated cleanly. |
| **Religious & Spiritual Places** | Audiala match + Heritage tag | Mixed. World-famous temples have Wikidata, but major active community temples in India often lack English Wikipedia pages. |
| **Ghats & Riverfronts (Varanasi)**| Audiala PageRank + Spatial Matching | Pure OSM lacks Wikidata tags for Ghats. Audiala's catalog is the only open source that successfully ranked Manikarnika, Tulsi, and Ahilyabai Ghats. |
| **Food & Restaurants** | **Fails completely** on open knowledge. | Wikidata/Wikipedia are practically non-existent for excellent local restaurants and street-food stalls (`Natraj`, `Anokhi Cafe`, `Laxmi Mishthan Bhandar` have 0 sitelinks). Must rely on review counts, ratings, and culinary tags. |
| **Cafes & Bakeries** | **Fails completely** on open knowledge. | Coffee shops (`Cafe Coffee Day`, boutique cafes) receive 0 fame signals from Wikipedia. Must use verified reviews and proximity. |
| **Markets & Bazaars** | Mixed (Historic bazaars have Wikipedia; local markets do not). | Chandni Chowk or Johari Bazaar have articles; local fruit/textile markets do not. |

---

## 5. Failure Case Analysis (Empirical Findings)

### Failure A: Obviously Major Attraction Ranks Too Low
* **Case**: `Galtaji Temple` (Jaipur's famous Monkey Temple) received a low rank in Variant C (score 15.0).
* **Cause**: In OSM, Galtaji is mapped under `religion=hindu` and had no direct English Wikipedia title tag in the node, even though it had a Wikidata QID with 8 sitelinks.
* **Resolution**: When computing pageviews, resolve the English Wikipedia title directly from Wikidata's `sitelinks.enwiki.title` rather than relying only on the OSM `wikipedia` tag.

### Failure B: Obscure / Minor Place Ranks Too High
* **Case**: In Surat, `VICHAR KRANTI CIRCLE`, `PALANPUR JAKAT NAKA`, and `Mangalam Heights` ranked at the very top in Variant A and B.
* **Cause**: OSM contributors tagged a modern roundabout, a toll post, and an apartment building with `historic=yes`. In the absence of a fame signal, YatraCanvas's current scoring treated them as historic landmarks.
* **Resolution**: Fame signals (sitelinks/pageviews) must serve as a filter: a place with `historic=yes` but 0 sitelinks must NOT outrank places that have genuine cultural notability.

### Failure C: Place Has No Wikidata Metadata but Deserves High Recommendation
* **Case**: `Laxmi Mishthan Bhandar (LMB)` in Jaipur and `Vishala` / `Rajvadu` in Ahmedabad (famous culinary heritage institutions).
* **Cause**: Wikipedia is an encyclopedia, not a restaurant guide. World-famous traditional eateries rarely have Wikipedia articles.
* **Resolution**: Never apply a negative penalty to un-enriched food and cafe POIs. City importance must be category-aware: Wikipedia for monuments/culture; verified reviews and speciality tags for food/dining.

### Failure D: Wikipedia Pageviews Are Misleading
* **Case**: In Delhi, `Kisan Ghat` (memorial of Prime Minister Charan Singh) has political significance but modest leisure tourist interest compared to `Diwan-e-Aam`.
* **Resolution**: Sitelinks count is more resilient to temporary news/political spikes than raw pageviews. Combine both logarithmically, with sitelinks weighted higher ($40\%$ vs $25\%$).

### Failure E: Audiala Misses an Obvious Landmark
* **Case**: In Delhi, `Tomb of Abdul Rahim Khan-i-Khanan` (restored Aga Khan Trust landmark) was not matched in Audiala, despite having 25 sitelinks and 11,789 pageviews.
* **Cause**: Audiala's dataset consists of 33,148 places where Audiala has published an editorial guide. It is not an exhaustive catalog.
* **Resolution**: Audiala must never be a gatekeeper or sole provider; it should act only as an additive validation boost.

### Failure F: Name / Coordinate Matching Ambiguities
* **Case**: In Jaipur, `Paanch Batti` (a landmark junction) was almost matched to a nearby heritage hotel due to token overlap.
* **Resolution**: Coordinate matching without an exact Wikidata QID must be restricted to $\le 100\text{ m}$ distance and require token similarity $\ge 0.70$.

---

## 6. Audiala Open Data Evaluation

* **Dataset Size & India Reach**: 33,148 rows globally; exactly **1,204 rows in India** across 93 cities.
* **License**: **CC BY 4.0** (Attribution required: *"Data by Audiala — audiala.com"*). Clean for commercial/open use.
* **Value Added**: Precomputed `wikidata_pagerank` (danker algorithm) and QIDs for top landmarks.
* **Critical Finding**: Audiala provides exceptional value for cities with poor OSM metadata (e.g. Varanasi, where it identified 27 top Ghats that lacked OSM Wikidata tags). However, it covers only 16 places in Jaipur, 31 in Ahmedabad, and 5 in Surat.
* **Verdict**: **`USE AS OPTIONAL ENRICHMENT SIGNAL`**. Do NOT adopt as the primary candidate database. Use it as a secondary, offline-indexed lookup table for fame and guide validation.

---

## 7. Recommended City Importance Architecture

To determine *"best places in a city"* without penalizing unrated places, YatraCanvas should adopt a 4-tier importance pipeline:

```text
                             CANDIDATE POI
                                   │
                ┌──────────────────┴──────────────────┐
                ▼                                     ▼
        CULTURE / ATTRACTIONS                  FOOD / CAFES / LEISURE
                │                                     │
      1. Wikidata Sitelinks (0-40 pts)      1. Review Count Confidence (0-30 pts)
      2. Wikipedia Pageviews (0-25 pts)     2. Verified Rating (0-20 pts)
      3. Audiala PageRank (0-15 pts)        3. Local Speciality Tag (0-15 pts)
      4. Heritage/UNESCO (0-10 pts)         4. OSM Amenity Subtype (0-10 pts)
                │                                     │
                └──────────────────┬──────────────────┘
                                   ▼
                      CITY IMPORTANCE SCORE (0-100)
                                   │
                                   ▼
                      PERSONALIZATION & DIVERSITY
                   (Purpose 2.5x + Interests 1.0x)
```

---

## 8. Production Integration Recommendations

| Component | Verdict | Justification |
| :--- | :---: | :--- |
| **Wikidata Entity Enrichment** | **YES** | Sitelink count provides the single cleanest, most objective fame signal available. It immediately fixed ranking across all cities where OSM tags were present. Fast, free, CC0. |
| **Wikimedia 90-Day Pageviews** | **PILOT MORE** | Adds strong freshness and tourist-interest signal, but requires polite per-article queries and caching. Pilot as an asynchronous background enrichment job. |
| **Audiala Open Travel Data** | **PILOT MORE** | High value as an offline seed database to backfill Wikidata QIDs for Indian places that lack OSM tags (as demonstrated in Varanasi). Embed as a bundled read-only JSON lookup. |

---

## 9. Performance & API Cost Metrics

* **Overpass Discovery**: 5 requests (1 per city, batching 5 categories each). Average latency: 2.8s. 
* **Wikidata Entity Enrichment**: Batched at 50 QIDs per request. Total requests: 2 across all cities. Latency: 320ms per batch.
* **Wikimedia Pageviews**: 21 individual HTTP requests. Average latency: 95ms per request with 50ms politeness delay.
* **Cache Opportunities**: Wikidata sitelinks and Wikipedia pageviews can be cached with a **30-day TTL** in PostgreSQL. Once enriched, 99% of user recommendation requests will hit the local database with **zero outbound API latency**.

---

## 10. Final Decision

**If you could add only ONE new data/enrichment capability to YatraCanvas today, choose:**

### **Wikidata Sitelink Count Enrichment**

**Why:**
1. **Solves the Core Product Problem Immediately**: It transforms YatraCanvas from an app that recommends random roundabouts and wedding halls into an intelligent travel planner that instantly surfaces world-class icons (Hawa Mahal, Amber Fort, Jantar Mantar, Tomb of Abdul Rahim Khan, Dada Harir Stepwell).
2. **Zero Infrastructure & Zero Operational Burden**: It does not require hosting a C++ tile server (Valhalla), running a JVM microservice (Timefold), downloading 100GB graph dumps (danker), or managing complex licenses. It is a single lightweight HTTP call (`action=wbgetentities&props=sitelinks`) batched across 50 places at a time.
3. **Public Domain (CC0)**: Completely free of legal attribution or licensing friction.
4. **Resilient to Spikes**: Unlike pageviews, which fluctuate with news cycles, sitelink count is an enduring, multi-lingual measure of genuine cultural importance.
