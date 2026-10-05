"""Export the selected canonical head and atomically bundle its Flutter projection."""
import argparse
import json
import os
import shutil
import sys
import uuid
from pathlib import Path


def sync(city, factory, *, version=None, dry_run=False, allow_test_media=False, target=None):
    factory = Path(factory).resolve()
    sys.path.insert(0, str(factory))
    from datafactory.app_pack import export_app_pack, validate_app_pack
    from datafactory.config.settings import Settings
    root = Path(__file__).resolve().parent.parent
    # Settings defaults are relative; anchor all factory paths to its checkout.
    settings = Settings(project_root=factory)
    result = export_app_pack(city, version=version, dry_run=dry_run, allow_test_media=allow_test_media, settings=settings)
    target_base = Path(target).resolve() if target else root / 'assets/citypacks'
    destination = target_base / result['city_id']
    if destination.parent.resolve() != target_base.resolve():
        raise ValueError('Invalid city destination')
    old = json.loads((destination / 'manifest.json').read_text(encoding='utf-8')) if (destination / 'manifest.json').exists() else {}
    summary = {'city_id': result['city_id'], 'before': old.get('pack_version'),
               'after': result.get('pack_version') or result['source_release'], 'target': str(destination), 'dry_run': dry_run}
    if dry_run:
        print(json.dumps(summary, indent=2)); return summary
    source = Path(result['output'])
    manifest = validate_app_pack(source)
    target_base.mkdir(parents=True, exist_ok=True)
    staging = target_base / ('.sync-' + uuid.uuid4().hex)
    backup = target_base / ('.previous-' + uuid.uuid4().hex)
    index_path = target_base / 'index.json'
    pubspec_path = root / 'pubspec.yaml'
    old_index = index_path.read_bytes() if index_path.exists() else None
    old_pubspec = pubspec_path.read_bytes() if target is None else None
    swapped = False
    try:
        shutil.copytree(source, staging)
        validate_app_pack(staging)
        if destination.exists():
            destination.rename(backup)
        staging.rename(destination)
        swapped = True
        validate_app_pack(destination)
        index = json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {}
        index[manifest['city_id']] = {k: manifest[k] for k in ('city_id', 'name', 'state', 'country', 'latitude', 'longitude', 'pack_version')}
        index_temp = target_base / '.index.tmp'
        index_temp.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        os.replace(index_temp, index_path)
        if target is None:
            update_assets(root, target_base)
        summary.update(place_count=manifest['place_count'], media_count=manifest['media_count'], database_bytes=manifest['database_bytes'], media_bytes=manifest['media_bytes'])
    except Exception:
        if swapped or backup.exists():
            if swapped and destination.exists():
                shutil.rmtree(destination)
            if backup.exists():
                backup.rename(destination)
            if old_index is None:
                index_path.unlink(missing_ok=True)
            else:
                index_path.write_bytes(old_index)
            if old_pubspec is not None:
                pubspec_path.write_bytes(old_pubspec)
        raise
    finally:
        for path in (staging, backup):
            if path.exists() and path.parent.resolve() == target_base.resolve():
                shutil.rmtree(path)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def update_assets(root, base):
    pubspec = root / 'pubspec.yaml'
    text = pubspec.read_text(encoding='utf-8')
    start, end = '    # CITYPACK ASSETS BEGIN', '    # CITYPACK ASSETS END'
    # List directories because Flutter asset declarations are not recursive.
    directories = {p.parent.relative_to(root).as_posix() + '/' for p in base.rglob('*') if p.is_file() and not any(part.startswith('.') for part in p.relative_to(base).parts)}
    block = start + '\n' + '\n'.join('    - ' + d for d in sorted(directories)) + '\n' + end
    if start in text:
        a, b = text.index(start), text.index(end) + len(end)
        text = text[:a] + block + text[b:]
    else:
        text = text.replace('  assets:\n', '  assets:\n' + block + '\n', 1)
    pubspec.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--city', required=True)
    parser.add_argument('--factory', type=Path, default=Path(__file__).resolve().parent.parent.parent / 'YatraCanvas-DataFactory')
    parser.add_argument('--version')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--allow-test-media', action='store_true')
    args = parser.parse_args()
    sync(args.city, args.factory, version=args.version, dry_run=args.dry_run, allow_test_media=args.allow_test_media)
