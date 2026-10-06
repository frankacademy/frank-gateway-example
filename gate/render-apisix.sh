#!/bin/sh
# Builds apisix.yaml from the template by replacing each @@file:<path>@@ line
# with the contents of <path>, indented like the placeholder.
set -e
awk '
  match($0, /@@file:[^@]+@@/) {
    indent = substr($0, 1, RSTART - 1)
    path = substr($0, RSTART + 7, RLENGTH - 9)
    while ((getline line < path) > 0) print indent line
    close(path)
    next
  }
  { print }
' /templates/apisix.yaml > /usr/local/apisix/conf/apisix.yaml
exec /docker-entrypoint.sh docker-start
