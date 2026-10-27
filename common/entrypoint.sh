#!/bin/sh

for file in /run/secrets/*; do
    [ -f "$file" ] || continue

    name=$(basename "$file")
    export "$name=$(cat "$file")"
done

exec /docker-entrypoint.sh docker-start