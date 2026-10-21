#!/usr/bin/env bash
# Stages a section of the repository, free or contrib, as the one repository that cozypkg
# pushes: the packages/ of every application of the section merged into one tree under
# <out-dir>/packages. An application is a directory of the section that has a packages/.
#
#   hack/stage-section.sh <free|contrib> <out-dir>
#
# <out-dir> must not exist. A file that two applications both carry is taken once when the
# two are the same, which is how the copy of cozy-lib is shared, and is an error when they
# differ. Only regular files are staged. A symbolic link anywhere in the way, in a
# packages/, or as the section, an application or its packages/, is an error: a link could
# take a file of another application outside the staged tree, or a file of the runner into
# the artifact. The paths of the files are read as NUL-separated, so that a name with a
# space is one name, and a path that leaves its packages/, or has a control character such
# as a newline, is an error.
# Exit 3 when the section has no application yet.
set -euo pipefail

section=${1:?section: free or contrib}
out=${2:?output directory}
case "$section" in
  free | contrib) ;;
  *) echo "unknown section: $section" >&2; exit 2 ;;
esac
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo "$out exists" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd -P)
sec="$root/$section"
[ -d "$sec" ] && [ ! -L "$sec" ] || { echo "$section is missing or is a symbolic link" >&2; exit 1; }

apps=()
for dir in "$sec"/*/; do
  app=${dir%/}
  [ -d "$app/packages" ] || continue
  if [ -L "$app" ] || [ -L "$app/packages" ]; then
    echo "$section/$(basename "$app") is a symbolic link or has one for packages/" >&2
    exit 1
  fi
  apps+=("$app")
done
[ ${#apps[@]} -gt 0 ] || { echo "no application with packages/ in $section" >&2; exit 3; }

for app in "${apps[@]}"; do
  link=$(find "$app/packages" -type l -print -quit)
  [ -z "$link" ] || { echo "symbolic link in $section: ${link#"$root"/}" >&2; exit 1; }
done

mkdir -p "$out/packages"
for app in "${apps[@]}"; do
  while IFS= read -r -d '' file; do
    case "$file" in
      /* | .. | ../* | */.. | */../*)
        echo "a path that leaves packages/ in $section/$(basename "$app"): $file" >&2
        exit 1 ;;
    esac
    if [[ "$file" =~ [[:cntrl:]] ]]; then
      echo "a path with a control character in $section/$(basename "$app"): ${file//[[:cntrl:]]/?}" >&2
      exit 1
    fi
    dst="$out/packages/$file"
    if [ -e "$dst" ]; then
      cmp -s "$app/packages/$file" "$dst" || {
        echo "conflict: $file of $(basename "$app") differs from the same file of another application" >&2
        exit 1
      }
    else
      mkdir -p "$(dirname "$dst")"
      cp "$app/packages/$file" "$dst"
    fi
  done < <(cd "$app/packages" && find . -type f -print0 | sed -z 's|^\./||' | sort -z)
  echo "staged $section/$(basename "$app")"
done

# What was made holds regular files and directories only, and is inside the output.
[ -z "$(find "$out" ! -type f ! -type d -print -quit)" ] || { echo "something that is not a file or a directory was staged" >&2; exit 1; }
