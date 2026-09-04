"""Generate a detailed text summary of experiment results across all 5 cities."""

import json
import os

CITIES = ["jaipur", "ahmedabad", "surat", "delhi", "varanasi"]
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")
OUTPUT_MD = os.path.join(RESULTS_DIR, "experiment_summary.md")


def generate_summary():
    lines = []
    lines.append("# YatraCanvas POI Importance Feasibility Experiment Summary\n")
    lines.append("Evaluated across 5 Indian cities: Jaipur, Ahmedabad, Surat, Delhi, Varanasi.\n")

    for city_key in CITIES:
        path = os.path.join(RESULTS_DIR, f"{city_key}.json")
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        city_name = data["city_name"]
        lines.append(f"\n## City: {city_name} (Candidates: {data['candidates_count']})\n")
        lines.append("### OSM Metadata Coverage")
        lines.append("| Field | Count (%) |")
        lines.append("|---|---|")
        for k, v in data["metadata_stats"]["percentages"].items():
            lines.append(f"| `{k}` | {v} |")
        lines.append(f"| **Audiala Match** | {data['audiala_matched_count']} ({data['audiala_matched_count']/data['candidates_count']*100:.1f}%) |\n")

        lines.append("### Category Distribution")
        lines.append("| Category | Count |")
        lines.append("|---|---|")
        for cat, cnt in data["metadata_stats"]["category_distribution"].items():
            lines.append(f"| `{cat}` | {cnt} |")

        # Top 20 Comparison: Variant A vs Variant C vs Variant D
        lines.append("\n### Top 20 Ranking Comparison")
        lines.append("| Rank | Variant A (Current YatraCanvas) | Variant C (Wikidata + Wikipedia) | Variant D (Wikidata + Wiki + Audiala) |")
        lines.append("|---|---|---|---|")

        top_a = data["top_20_variant_a"]
        top_c = data["top_20_variant_c"]
        top_d = data["top_20_variant_d"]

        for r in range(20):
            pa = top_a[r] if r < len(top_a) else None
            pc = top_c[r] if r < len(top_c) else None
            pd = top_d[r] if r < len(top_d) else None

            str_a = f"**{pa['name']}** ({pa['category']}, {pa['score_a']})" if pa else "-"
            str_c = f"**{pc['name']}** ({pc['category']}, sc:{pc['score_c']:.1f}, sl:{pc['sitelinks']}, pv:{pc['pageviews_90d']:,})" if pc else "-"
            aud_str = f"PR:{pd['audiala_pagerank']:.2f}" if pd and pd.get('audiala_pagerank') is not None else ("Aud:Yes" if pd and pd.get('audiala_match') else "Aud:No")
            str_d = f"**{pd['name']}** ({pd['category']}, sc:{pd['score_d']:.1f}, {aud_str})" if pd else "-"

            lines.append(f"| {r+1} | {str_a} | {str_c} | {str_d} |")

    with open(OUTPUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Summary written to {OUTPUT_MD}")


if __name__ == "__main__":
    generate_summary()
