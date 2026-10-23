#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
for tool in helm yq jq; do
  command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 1; }
done

tmp=$(mktemp -d "$PWD/.psk-test.XXXXXX")
trap 'rm -r "$tmp"' EXIT
cp -R packages/apps/site-router "$tmp/chart"
mkdir -p "$tmp/chart/charts"
cp -R packages/library/cozy-lib "$tmp/chart/charts/cozy-lib"

render() {
  local output=$1 release=$2
  shift 2
  helm template "$release" "$tmp/chart" --namespace tenant-test "$@" |
    yq -o=json '.' | jq -s '.' >"$tmp/$output.json"
}

assert_generated() {
  jq -e '
    ([.[] | select(.kind == "Secret")] | length) == 0 and
    ([.[] | select(.kind == "SiteRouter")] | length) == 1 and
    ([.[] | select(.kind == "SiteRouter")][0].spec.peer | has("auth") | not)
  ' "$tmp/$1.json" >/dev/null
}

assert_custom() {
  local output=$1 instance=$2 key=$3
  jq -e --arg instance "$instance" --arg key "$key" '
    [.[] | select(.kind == "Secret")] as $secrets |
    [.[] | select(.kind == "SiteRouter")][0] as $router |
    ($secrets | length) == 1 and
    $secrets[0].metadata.name == ("site-router-" + $instance + "-psk-custom") and
    $secrets[0].metadata.namespace == "tenant-test" and
    $secrets[0].type == "Opaque" and
    ($secrets[0].data.psk | @base64d) == $key and
    ($secrets[0].metadata.ownerReferences // [] | length) == 0 and
    $router.metadata.name == $instance and
    $router.spec.peer.auth.secretRef == {name: $secrets[0].metadata.name}
  ' "$tmp/$output.json" >/dev/null
}

render default site-router-office
render empty site-router-office --set-string peer.psk=
assert_generated default
assert_generated empty
cmp "$tmp/default.json" "$tmp/empty.json"

# Template-like text and YAML punctuation must reach the Secret unchanged.
key=$'test-only: "quotes" \\ slash\n{{ .Release.Name }}\n'
jq -n --arg key "$key" '{peer: {psk: $key}}' >"$tmp/custom-values.json"
render custom site-router-office --values "$tmp/custom-values.json"
assert_custom custom office "$key"
# Every operator-generated PSK ends in -psk, including office-custom's key.
jq -e '[.[] | select(.kind == "Secret")][0].metadata.name | endswith("-psk") | not' "$tmp/custom.json" >/dev/null
jq -e '([.[] | select(.kind == "SiteRouter")][0].spec.peer.address // "") == ""' "$tmp/custom.json" >/dev/null

jq -n --arg key "$key" '{peer: {address: "203.0.113.10", psk: $key}}' >"$tmp/peer.json"
render addressed site-router-office --values "$tmp/peer.json"
assert_custom addressed office "$key"
jq -e '[.[] | select(.kind == "SiteRouter")][0].spec.peer.address == "203.0.113.10"' "$tmp/addressed.json" >/dev/null
render other site-router-branch --values "$tmp/peer.json"
assert_custom other branch "$key"

render rotated site-router-office --is-upgrade --set-string peer.psk=test-only-rotated
assert_custom rotated office test-only-rotated
render restored site-router-office --is-upgrade --set-string peer.psk=
assert_generated restored
cmp "$tmp/default.json" "$tmp/restored.json"

render arbitrary site-router-office --set-string peer.auth.secretRef.name=another-secret
assert_generated arbitrary

if helm template site-router-office "$tmp/chart" --set peer.psk=123 >"$tmp/invalid.log" 2>&1; then
  echo "numeric peer.psk was accepted" >&2
  exit 1
fi
grep -q 'psk' "$tmp/invalid.log"

yq -r '.spec.application.openAPISchema' packages/system/site-router-rd/cozyrds/site-router.yaml >"$tmp/app-schema.json"
cmp <(jq -S . packages/apps/site-router/values.schema.json) <(jq -S . "$tmp/app-schema.json")
jq -e '
  .properties.peer.properties.psk.type == "string" and
  (.properties.peer.required | index("psk") | not)
' "$tmp/app-schema.json" >/dev/null
yq -o=json '.spec.secrets.include' packages/system/site-router-rd/cozyrds/site-router.yaml |
  jq -e '[.[].resourceNames[]] | index("site-router-{{ .name }}-psk-custom") != null' >/dev/null

echo "PSK rendering: generated, custom, rotation, transitions, isolation and schema passed"
