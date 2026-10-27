#!/bin/sh
set -e

for file in /run/secrets/*; do
    [ -f "$file" ] || continue

    name=$(basename "$file")
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_]*)
            echo "entrypoint: skipping secret '$name': not a valid variable name" >&2
            continue ;;
    esac

    value=$(cat "$file")
    export "$name=$value"
done

exec /docker-entrypoint.sh docker-start