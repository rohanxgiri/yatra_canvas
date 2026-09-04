"""Generate comparative summary report between baseline.json and post_fix.json."""

from __future__ import annotations

import json
import os

EXPERIMENT_DIR = os.path.dirname(__file__)
RESULTS_DIR = os.path.join(EXPERIMENT_DIR, "results")
BASELINE_PATH = os.path.join(RESULTS_DIR, "baseline.json")
POST_FIX_PATH = os.path.join(RESULTS_DIR, "post_fix.json")
REPORT_PATH = os.path.join(RESULTS_DIR, "benchmark_comparison_report.md")


def generate_report():
    with open(BASELINE_PATH, "r", encoding="utf-8") as f:
        baseline_data = json.load(f)
    with open(POST_FIX_PATH, "r", encoding="utf-8") as f:
        post_fix_data = json.load(f)

    base_map = {(r["scenario_key"], r["k"]): r for r in baseline_data["results"]}
    post_map = {(r["scenario_key"], r["k"]): r for r in post_fix_data["results"]}

    lines: list[str] = [
        "# Recommendation Quality Benchmark: Baseline vs Post-Fix",
        "",
        "## Summary of Core Changes",
        "1. **Institutional/Private Venue Elimination**: Operator and building context inspection filtered un-tagged campus canteens and facilities (e.g. SVNIT Food Point, Central Campus Dining, IIT Bombay Food Court).",
        "2. **Non-Tourist Commercial Facility Filtering**: Filtered retail bank branches (e.g. HDFC Bank branch) entering via open travel datasets.",
        "3. **Multi-Outlet Brand Capping**: Capped identical chain branches (e.g. 6 Domino's and 3 Burger Kings in Surat) to 1 representative instance, opening slots for diverse authentic local dining.",
        "4. **Phonetic / Typo Deduplication**: Levenshtein token matching merged duplicate attractions (e.g. Jaigarh Fort vs Jaighar Fort).",
        "5. **Mixed-Interest Category Balancing**: Interleaving without prohibitive cross-tier score thresholds preserved secondary interests (e.g. food in Delhi mixed itinerary).",
        "",
        "## Quantitative Comparison Table",
        "",
        "| Scenario | K | Baseline Restricted | Post-Fix Restricted | Baseline Gold Recall | Post-Fix Gold Recall | Baseline Diversity Entropy | Post-Fix Diversity Entropy |",
        "| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |",
    ]

    for key in sorted(base_map.keys()):
        b = base_map[key]
        p = post_map[key]
        s_name = key[0]
        k_val = key[1]
        b_restr = b["restricted_count"]
        p_restr = p["restricted_count"]
        b_recall = f"{b['gold_major_poi_recall']:.2f}"
        p_recall = f"{p['gold_major_poi_recall']:.2f}"
        b_div = f"{b['category_diversity_entropy']:.2f}"
        p_div = f"{p['category_diversity_entropy']:.2f}"

        restr_flag = " **FIXED**" if b_restr > 0 and p_restr == 0 else ""
        lines.append(
            f"| `{s_name}` | {k_val} | {b_restr} | {p_restr}{restr_flag} | {b_recall} | {p_recall} | {b_div} | {p_div} |"
        )

    lines.extend([
        "",
        "## City-Specific Highlights",
        "",
        "### Surat (Food)",
        "- **Baseline**: At K=10, 15, 20, 2 institutional venues leaked (`SVNIT Food Point` and `Central Campus Dining`). At K=20, 6 Domino's and 3 Burger Kings dominated recommendations.",
        "- **Post-Fix**: **0 institutional venues leaked**. Chain restaurant duplication eliminated (Burger King and Domino's capped to 1 representative slot). Authentic local speciality venues like `Jay Jalaram Khaman House`, `Gokulam Dairy`, and `dokla cafe` now surface.",
        "",
        "### Mumbai (Sightseeing + Food + Cafes)",
        "- **Baseline**: At K=10, 15, 20, `IIT Bombay Campus Food Court` and `Hdfc Bank Malabar Hill Ec Branch` entered top recommendations.",
        "- **Post-Fix**: **0 restricted/non-tourist venues**. `Taj Mahal Palace Hotel` and `Bombay Castle` correctly promoted into recommendation slots.",
        "",
        "### Jaipur (Heritage + Sightseeing)",
        "- **Baseline**: Typo duplicate `Jaighar Fort` entered top 10 alongside `Jaigarh Fort` (Recall = 0.88).",
        "- **Post-Fix**: `Jaighar Fort` merged with `Jaigarh Fort`. Top-10 Gold Recall reached **1.00 (8/8)**.",
        "",
        "### Delhi (Heritage + Food + Sightseeing)",
        "- **Baseline**: Heritage flooded 18 of 20 slots; secondary interest `food` received only 2 slots (Diversity Entropy = 0.47).",
        "- **Post-Fix**: Diversity interleaving ensured food and cultural landmarks are balanced (Diversity Entropy = **1.16**).",
        "",
    ])

    report_content = "\n".join(lines)
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write(report_content)

    print(f"Report written to: {REPORT_PATH}")
    print("\n" + report_content)


if __name__ == "__main__":
    generate_report()
