"""Create deterministic app-ready WebP place fallbacks from preserved PNG masters."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

SOURCE_TO_LOGICAL = {
    "ChatGPT Image Sep 17, 2026, 10_22_20 PM (1).png": "cafe.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_21 PM (2).png": "temple.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_21 PM (3).png": "museum.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_22 PM (4).png": "park_garden.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_22 PM (5).png": "fort_palace.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_23 PM (6).png": "lake_riverfront.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_24 PM (7).png": "generic_place.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_25 PM (8).png": "hill_viewpoint.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_25 PM (9).png": "mountain.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_26 PM (10).png": "market.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_33 PM (1).png": "beach.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_34 PM (2).png": "desert.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_34 PM (3).png": "waterfall.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_35 PM (4).png": "forest.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_35 PM (5).png": "restaurant.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_36 PM (6).png": "shopping.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_36 PM (7).png": "viewpoint.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_36 PM (8).png": "wildlife.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_37 PM (9).png": "art_gallery.webp",
    "ChatGPT Image Sep 17, 2026, 10_22_37 PM (10).png": "hotel.webp",
}

COMPARISON_ASSETS = ("cafe", "temple", "mountain", "market", "waterfall")
QUALITY_OVERRIDES = {
    "market.webp": 88,
    "shopping.webp": 88,
}


def target_size(width: int, height: int, max_width: int) -> tuple[int, int]:
    if width <= max_width:
        return width, height
    scale = max_width / width
    return max_width, round(height * scale)


def convert(source_dir: Path, output_dir: Path, *, width: int, quality: int) -> list[dict]:
    source_names = {path.name for path in source_dir.glob("*.png")}
    expected_names = set(SOURCE_TO_LOGICAL)
    if source_names != expected_names:
        missing = sorted(expected_names - source_names)
        unexpected = sorted(source_names - expected_names)
        raise ValueError(f"Master set mismatch; missing={missing}, unexpected={unexpected}")

    output_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    for source_name, output_name in SOURCE_TO_LOGICAL.items():
        source_path = source_dir / source_name
        output_path = output_dir / output_name
        asset_quality = QUALITY_OVERRIDES.get(output_name, quality)
        with Image.open(source_path) as opened:
            image = ImageOps.exif_transpose(opened)
            original_size = image.size
            resized_size = target_size(*original_size, width)
            if resized_size != original_size:
                image = image.resize(resized_size, Image.Resampling.LANCZOS)
            if image.mode not in ("RGB", "RGBA"):
                image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
            save_options = {
                "format": "WEBP",
                "quality": asset_quality,
                "method": 6,
                "exact": True,
            }
            icc_profile = opened.info.get("icc_profile")
            if icc_profile:
                save_options["icc_profile"] = icc_profile
            image.save(output_path, **save_options)

        with Image.open(source_path) as master, Image.open(output_path) as verified:
            verified.load()
            if verified.format != "WEBP" or verified.size != resized_size:
                raise ValueError(f"Invalid output: {output_path}")
            mae, psnr = quality_metrics(master, verified)
        records.append(
            {
                "master": source_name,
                "asset": output_name,
                "original_dimensions": f"{original_size[0]}x{original_size[1]}",
                "optimized_dimensions": f"{resized_size[0]}x{resized_size[1]}",
                "original_bytes": source_path.stat().st_size,
                "optimized_bytes": output_path.stat().st_size,
                "quality": asset_quality,
                "mean_absolute_error": round(mae, 3),
                "psnr_db": round(psnr, 3),
            }
        )
    return records


def quality_metrics(master: Image.Image, optimized: Image.Image) -> tuple[float, float]:
    reference = master.convert("RGB").resize(optimized.size, Image.Resampling.LANCZOS)
    candidate = optimized.convert("RGB")
    difference = ImageChops.difference(reference, candidate)
    stats = ImageStat.Stat(difference)
    mae = sum(stats.mean) / len(stats.mean)
    mse = sum(value**2 for value in stats.rms) / len(stats.rms)
    psnr = float("inf") if mse == 0 else 20 * math.log10(255 / math.sqrt(mse))
    return mae, psnr


def build_comparison(source_dir: Path, output_dir: Path, destination: Path) -> None:
    display_width, display_height = 360, 270
    label_height = 32
    margin = 16
    sheet = Image.new(
        "RGB",
        (
            margin * 3 + display_width * 2,
            margin + len(COMPARISON_ASSETS) * (display_height + label_height + margin),
        ),
        "white",
    )
    draw = ImageDraw.Draw(sheet)
    reverse_mapping = {
        Path(output_name).stem: source_name
        for source_name, output_name in SOURCE_TO_LOGICAL.items()
    }
    for index, logical_name in enumerate(COMPARISON_ASSETS):
        source_path = source_dir / reverse_mapping[logical_name]
        optimized_path = output_dir / f"{logical_name}.webp"
        with Image.open(source_path) as original, Image.open(optimized_path) as optimized:
            original_display = original.convert("RGB").resize(
                (display_width, display_height), Image.Resampling.LANCZOS
            )
            optimized_display = optimized.convert("RGB").resize(
                (display_width, display_height), Image.Resampling.LANCZOS
            )
            mae, psnr = quality_metrics(original, optimized)
        y = margin + index * (display_height + label_height + margin)
        sheet.paste(original_display, (margin, y + label_height))
        sheet.paste(optimized_display, (margin * 2 + display_width, y + label_height))
        draw.text((margin, y), f"{logical_name}: original PNG", fill="black")
        draw.text(
            (margin * 2 + display_width, y),
            f"optimized WebP | MAE {mae:.2f} | PSNR {psnr:.2f} dB",
            fill="black",
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, format="PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("design_reference/place_fallback_masters"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/images/place_fallbacks"),
    )
    parser.add_argument(
        "--comparison",
        type=Path,
        default=Path("design_reference/place_fallback_comparison.png"),
    )
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--quality", type=int, default=86)
    args = parser.parse_args()

    records = convert(args.source, args.output, width=args.width, quality=args.quality)
    build_comparison(args.source, args.output, args.comparison)
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
