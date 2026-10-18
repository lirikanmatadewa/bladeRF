#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
manifest="$script_dir/firmware-manifest.json"
destination=${1:?Usage: prepare-firmware.sh destination}
cache=${BLADERF_FIRMWARE_CACHE:-/workspace/firmware-cache}
mkdir -p "$destination" "$cache"

jq -e '.schema == 1 and (.firmware | length == 6) and all(.firmware[]; (.sha256 | type == "string" and test("^[0-9a-f]{64}$")))' "$manifest" >/dev/null
resolved_manifest="$destination/firmware-manifest.json"
cp "$manifest" "$resolved_manifest"
while IFS=$'\t' read -r name filename url md5 sha256; do
    cached="$cache/$sha256"
    if [[ ! -f "$cached" ]]; then
        temporary="$cached.part"
        rm -f "$temporary"
        curl --fail --location --retry 3 --silent --show-error "$url" -o "$temporary"
        printf '%s  %s\n' "$sha256" "$temporary" | sha256sum --check --status || {
            rm -f "$temporary"
            printf 'SHA-256 verification failed for %s\n' "$name" >&2
            exit 1
        }
        printf '%s  %s\n' "$md5" "$temporary" | md5sum --check --status || {
            rm -f "$temporary"
            printf 'Upstream Debian checksum verification failed for %s\n' "$name" >&2
            exit 1
        }
        mv "$temporary" "$cached"
    fi
    printf '%s  %s\n' "$sha256" "$cached" | sha256sum --check --status || {
        rm -f "$cached"
        printf 'Cached firmware SHA-256 verification failed for %s\n' "$name" >&2
        exit 1
    }
    printf '%s  %s\n' "$md5" "$cached" | md5sum --check --status || {
        rm -f "$cached"
        printf 'Cached firmware MD5 verification failed for %s\n' "$name" >&2
        exit 1
    }
    install -m 0644 "$cached" "$destination/$filename"
    printf 'Prepared %s as %s\n' "$name" "$filename"
done < <(jq -r '.firmware[] | [.name, .filename, .url, .md5, .sha256] | @tsv' "$manifest")