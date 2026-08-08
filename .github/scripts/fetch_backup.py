#!/usr/bin/env python3
"""Pull every table and photo out of Supabase into _staging/ for encryption.

Run by .github/workflows/backup-data.yml. Uses the service_role key because
RLS (is_allowed_user()) makes the public anon key return zero rows — see
CLAUDE.md. Nothing written here is safe to commit unencrypted.
"""

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SERVICE_KEY"]

# The archive tables are included on purpose: they are the recovery net for
# rows deleted from the app, so a backup without them loses that history.
TABLES = [
    "play_entries",
    "play_types",
    "child_info",
    "allowed_users",
    "play_entries_deleted",
    "play_types_deleted",
]

PAGE_SIZE = 1000
STAGING = pathlib.Path("_staging")


def get(url, headers, binary=False):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    return raw if binary else json.loads(raw.decode("utf-8"))


def fetch_table(name):
    """PostgREST caps a response at 1000 rows, so page until it runs dry."""
    headers = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Accept": "application/json",
    }
    rows, offset = [], 0
    while True:
        url = f"{SUPABASE_URL}/rest/v1/{name}?select=*&limit={PAGE_SIZE}&offset={offset}"
        try:
            page = get(url, headers)
        except urllib.error.HTTPError as e:
            # A table that doesn't exist yet shouldn't sink the whole backup.
            if e.code in (404, 406):
                print(f"  {name}: 없음 (건너뜀)")
                return None
            raise
        rows.extend(page)
        if len(page) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
    print(f"  {name}: {len(rows)}행")
    return rows


def fetch_photos(entries):
    """Photos live in a public bucket, so no key is needed to read them."""
    out = STAGING / "photos"
    out.mkdir(parents=True, exist_ok=True)

    paths = sorted({e["photo_path"] for e in entries if e.get("photo_path")})
    already = {p.name for p in pathlib.Path("backup/photos").glob("*.gpg")}

    saved = skipped = failed = 0
    for path in paths:
        # Encryption appends .gpg, so that's what an existing backup looks like.
        if f"{path}.gpg" in already:
            skipped += 1
            continue
        url = f"{SUPABASE_URL}/storage/v1/object/public/play-photos/{path}"
        try:
            (out / path).write_bytes(get(url, {}, binary=True))
            saved += 1
        except Exception as e:  # a missing photo shouldn't sink the backup
            print(f"  ⚠️ 사진 실패 {path}: {e}")
            failed += 1
    print(f"  사진: 신규 {saved}개, 기존 {skipped}개, 실패 {failed}개")


def main():
    STAGING.mkdir(exist_ok=True)
    print("Supabase에서 데이터를 가져오는 중...")

    data = {}
    for name in TABLES:
        rows = fetch_table(name)
        if rows is not None:
            data[name] = rows

    if not any(data.values()):
        # Empty across the board almost certainly means the key is wrong and
        # RLS silently filtered everything — committing that would overwrite a
        # good backup with nothing.
        print("::error::모든 테이블이 비어 있습니다. service_role 키를 확인하세요.", file=sys.stderr)
        sys.exit(1)

    payload = {
        "exported_at": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc
        ).isoformat(),
        "source": SUPABASE_URL,
        **data,
    }
    (STAGING / "data.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    fetch_photos(data.get("play_entries", []))
    print("완료.")


if __name__ == "__main__":
    main()
