#!/usr/bin/env bash
# Stages a section of the repository, free or contrib, as the one repository that cozypkg
# pushes: the packages/ of every application of the section merged into one tree under
# <out-dir>/packages. An application is a directory of the section that has a packages/.
#
#   hack/stage-section.sh <free|contrib> <out-dir>
#
# <out-dir> must not exist. A file that two applications both carry is taken once when the
# two are the same, which is how the copy of cozy-lib is shared, and is an error when they
# differ. Exit 3 when the section has no application yet.
set -euo pipefail

section=${1:?section: free or contrib}
out=${2:?output directory}
case "$section" in
  free | contrib) ;;
  *) echo "unknown section: $section" >&2; exit 2 ;;
esac
[ ! -e "$out" ] || { echo "$out exists" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
apps=()
for dir in "$root/$section"/*/; do
  [ -d "${dir}packages" ] && apps+=("${dir%/}")
done
[ ${#apps[@]} -gt 0 ] || { echo "no application with packages/ in $section" >&2; exit 3; }

mkdir -p "$out/packages"
for app in "${apps[@]}"; do
  while read -r file; do
    dst="$out/packages/$file"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      cmp -s "$app/packages/$file" "$dst" || {
        echo "conflict: $file of $(basename "$app") differs from the same file of another application" >&2
        exit 1
      }
    else
      mkdir -p "$(dirname "$dst")"
      cp -P "$app/packages/$file" "$dst"
    fi
  done < <(cd "$app/packages" && find . \( -type f -o -type l \) | sed 's|^\./||' | sort)
  echo "staged $section/$(basename "$app")"
done
