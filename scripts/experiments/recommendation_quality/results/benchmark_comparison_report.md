# Recommendation Quality Benchmark: Baseline vs Post-Fix

## Summary of Core Changes
1. **Institutional/Private Venue Elimination**: Operator and building context inspection filtered un-tagged campus canteens and facilities (e.g. SVNIT Food Point, Central Campus Dining, IIT Bombay Food Court).
2. **Non-Tourist Commercial Facility Filtering**: Filtered retail bank branches (e.g. HDFC Bank branch) entering via open travel datasets.
3. **Multi-Outlet Brand Capping**: Capped identical chain branches (e.g. 6 Domino's and 3 Burger Kings in Surat) to 1 representative instance, opening slots for diverse authentic local dining.
4. **Phonetic / Typo Deduplication**: Levenshtein token matching merged duplicate attractions (e.g. Jaigarh Fort vs Jaighar Fort).
5. **Mixed-Interest Category Balancing**: Interleaving without prohibitive cross-tier score thresholds preserved secondary interests (e.g. food in Delhi mixed itinerary).

## Quantitative Comparison Table

| Scenario | K | Baseline Restricted | Post-Fix Restricted | Baseline Gold Recall | Post-Fix Gold Recall | Baseline Diversity Entropy | Post-Fix Diversity Entropy |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `ahmedabad_heritage` | 5 | 0 | 0 | 0.75 | 0.75 | 0.00 | 0.72 |
| `ahmedabad_heritage` | 10 | 0 | 0 | 0.75 | 0.75 | 0.00 | 0.88 |
| `ahmedabad_heritage` | 15 | 0 | 0 | 0.75 | 0.75 | 0.92 | 0.92 |
| `ahmedabad_heritage` | 20 | 0 | 0 | 0.75 | 0.75 | 1.00 | 1.00 |
| `ahmedabad_mixed` | 5 | 0 | 0 | 0.80 | 0.80 | 0.97 | 0.97 |
| `ahmedabad_mixed` | 10 | 0 | 0 | 0.71 | 0.71 | 0.97 | 0.97 |
| `ahmedabad_mixed` | 15 | 0 | 0 | 0.71 | 0.71 | 0.92 | 0.97 |
| `ahmedabad_mixed` | 20 | 0 | 0 | 0.71 | 0.86 | 0.81 | 0.97 |
| `delhi_mixed` | 5 | 0 | 0 | 1.00 | 1.00 | 0.72 | 0.72 |
| `delhi_mixed` | 10 | 0 | 0 | 0.75 | 0.75 | 0.72 | 1.16 |
| `delhi_mixed` | 15 | 0 | 0 | 0.75 | 0.75 | 0.57 | 1.24 |
| `delhi_mixed` | 20 | 0 | 0 | 0.75 | 0.75 | 0.47 | 1.16 |
| `jaipur` | 5 | 0 | 0 | 1.00 | 1.00 | 0.00 | 0.72 |
| `jaipur` | 10 | 0 | 0 | 0.88 | 1.00 | 0.72 | 0.88 |
| `jaipur` | 15 | 0 | 0 | 1.00 | 1.00 | 1.00 | 1.00 |
| `jaipur` | 20 | 0 | 0 | 1.00 | 1.00 | 0.97 | 0.97 |
| `mumbai_mixed` | 5 | 0 | 0 | 0.60 | 0.60 | 1.52 | 1.52 |
| `mumbai_mixed` | 10 | 1 | 0 **FIXED** | 0.57 | 0.57 | 1.52 | 1.49 |
| `mumbai_mixed` | 15 | 2 | 0 **FIXED** | 0.57 | 0.71 | 1.34 | 1.24 |
| `mumbai_mixed` | 20 | 2 | 0 **FIXED** | 0.71 | 0.71 | 1.16 | 1.05 |
| `surat` | 5 | 0 | 0 | 1.00 | 0.80 | 0.00 | 0.72 |
| `surat` | 10 | 2 | 0 **FIXED** | 1.00 | 1.00 | 0.00 | 0.72 |
| `surat` | 15 | 2 | 0 **FIXED** | 1.00 | 1.00 | 0.00 | 0.84 |
| `surat` | 20 | 2 | 0 **FIXED** | 1.00 | 1.00 | 0.00 | 0.72 |
| `udaipur` | 5 | 0 | 0 | 0.40 | 0.60 | 0.00 | 0.72 |
| `udaipur` | 10 | 0 | 0 | 0.71 | 0.71 | 0.88 | 0.97 |
| `udaipur` | 15 | 0 | 0 | 1.00 | 1.00 | 1.00 | 1.00 |
| `udaipur` | 20 | 0 | 0 | 1.00 | 1.00 | 1.00 | 1.00 |
| `varanasi` | 5 | 0 | 0 | 0.80 | 0.80 | 0.72 | 0.72 |
| `varanasi` | 10 | 0 | 0 | 0.57 | 0.57 | 1.00 | 1.00 |
| `varanasi` | 15 | 0 | 0 | 0.71 | 0.71 | 0.94 | 0.94 |
| `varanasi` | 20 | 0 | 0 | 0.71 | 0.71 | 0.94 | 0.94 |

## City-Specific Highlights

### Surat (Food)
- **Baseline**: At K=10, 15, 20, 2 institutional venues leaked (`SVNIT Food Point` and `Central Campus Dining`). At K=20, 6 Domino's and 3 Burger Kings dominated recommendations.
- **Post-Fix**: **0 institutional venues leaked**. Chain restaurant duplication eliminated (Burger King and Domino's capped to 1 representative slot). Authentic local speciality venues like `Jay Jalaram Khaman House`, `Gokulam Dairy`, and `dokla cafe` now surface.

### Mumbai (Sightseeing + Food + Cafes)
- **Baseline**: At K=10, 15, 20, `IIT Bombay Campus Food Court` and `Hdfc Bank Malabar Hill Ec Branch` entered top recommendations.
- **Post-Fix**: **0 restricted/non-tourist venues**. `Taj Mahal Palace Hotel` and `Bombay Castle` correctly promoted into recommendation slots.

### Jaipur (Heritage + Sightseeing)
- **Baseline**: Typo duplicate `Jaighar Fort` entered top 10 alongside `Jaigarh Fort` (Recall = 0.88).
- **Post-Fix**: `Jaighar Fort` merged with `Jaigarh Fort`. Top-10 Gold Recall reached **1.00 (8/8)**.

### Delhi (Heritage + Food + Sightseeing)
- **Baseline**: Heritage flooded 18 of 20 slots; secondary interest `food` received only 2 slots (Diversity Entropy = 0.47).
- **Post-Fix**: Diversity interleaving ensured food and cultural landmarks are balanced (Diversity Entropy = **1.16**).
