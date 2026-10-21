#!/usr/bin/env bash
# Puts into the ApplicationDefinition of the application what the chart says of
# itself: the schema of the values, as the API validates against it, and the order
# of the keys the dashboard shows. Run it by `make generate`, after cozyvalues-gen
# has made values.schema.json.
set -euo pipefail

cd "$(dirname "$0")/.."
CHART=packages/apps/site-router
OUT=packages/system/site-router-rd/cozyrds/site-router.yaml

for tool in yq jq; do
  command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 1; }
done
[[ -f $CHART/values.schema.json ]] || { echo "no $CHART/values.schema.json: run cozyvalues-gen first" >&2; exit 1; }

SCHEMA_JSON_MIN="$(jq -c . "$CHART/values.schema.json")"
# Every path of values.yaml, in the order of the file, under spec.
KEYS_ORDER="$(
  yq -o=json '.' "$CHART/values.yaml" | jq -c '
    def paths_of(obj; path):
      obj | to_entries | map(
        .key as $key | .value as $value |
        if ($value | type) == "object" then
          [path + [$key]] + paths_of($value; path + [$key])
        else
          [path + [$key]]
        end
      ) | flatten(1);
    [ ["apiVersion"], ["appVersion"], ["kind"], ["metadata"], ["metadata", "name"] ]
    + ( paths_of(.; []) | map(["spec"] + .) )
  '
)"
export SCHEMA_JSON_MIN KEYS_ORDER

yq -i '
  .spec.application.openAPISchema = strenv(SCHEMA_JSON_MIN) |
  (.spec.application.openAPISchema style="literal") |
  .spec.dashboard.keysOrder = (strenv(KEYS_ORDER) | from_json)
' "$OUT"
echo "updated $OUT"
