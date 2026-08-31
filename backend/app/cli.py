"""Project-native backend management commands."""

import argparse
import json
from pathlib import Path

from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_engine
from app.importers import FSQPlacesImporter


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    commands = parser.add_subparsers(dest="command", required=True)
    fsq = commands.add_parser(
        "import-fsq-places",
        help="Import a filtered local FSQ OS Places CSV or JSONL export.",
    )
    fsq.add_argument("--city", required=True)
    fsq.add_argument("--source", type=Path)
    fsq.add_argument("--dry-run", action="store_true")
    fsq.add_argument("--limit", type=int)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command != "import-fsq-places":
        return 2
    settings = get_settings()
    source = args.source or (
        Path(settings.fsq_os_places_path) if settings.fsq_os_places_path else None
    )
    if source is None:
        raise SystemExit(
            "Provide --source or configure FSQ_OS_PLACES_PATH in backend/.env."
        )
    importer = FSQPlacesImporter(
        distance_threshold_meters=settings.fsq_dedupe_distance_meters,
        batch_size=settings.fsq_import_batch_size,
    )
    with Session(get_engine()) as session:
        summary = importer.run(
            session,
            source=source,
            city_slug=args.city,
            dry_run=args.dry_run,
            limit=args.limit,
        )
    mode = "dry-run" if args.dry_run else "import"
    print(json.dumps({"mode": mode, "city": args.city, **summary.as_dict()}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
