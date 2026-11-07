#!/usr/bin/env bash
# Prints the release description: a table that links every build artifact
# with its checksum, followed by GitHub's generated notes.
#
# Usage: release-notes.sh <tag> <owner/repo> <dist dir> [generated notes file]
#
# Without the notes file only the download table is printed.
set -euo pipefail

tag=$1
repo=$2
dist=$3
notes=${4:-}

base="https://github.com/$repo/releases/download/$tag"

# Percent-encodes a file name for use in a download URL.
urlencode() { jq -rn --arg s "$1" '$s | @uri'; }

# Display order of the platforms; each entry is "label|install hint", where
# FILE stands for the file name.
categories=(
  'Fedora / RHEL|`sudo dnf install ./FILE`'
  'Debian / Ubuntu|`sudo apt install ./FILE`'
  'Arch Linux|`sudo pacman -U FILE`'
  'Linux (portable)|Extract, run `wow-butler/wow_butler`'
  'Windows (installer)|Run it; per user or for all users'
  'Windows (MSI)|Double-click or `msiexec /i FILE`'
  'Windows (portable)|Extract, run `wow-butler\wow_butler.exe`'
  'macOS (DMG)|Open, drag the app to Applications'
  'macOS (ZIP)|Extract, move the app to Applications'
  'Other|'
)

# Prints the index into `categories` for a file name.
category_of() {
  case "$1" in
    *.rpm) echo 0 ;;
    *.deb) echo 1 ;;
    *.pkg.tar.zst) echo 2 ;;
    *-linux-*.tar.gz) echo 3 ;;
    *-setup.exe) echo 4 ;;
    *.msi) echo 5 ;;
    *-windows-*.zip) echo 6 ;;
    *.dmg) echo 7 ;;
    *-macos-*.zip) echo 8 ;;
    *) echo 9 ;;
  esac
}

declare -A rows=()
found=0
while IFS= read -r file; do
  name=$(basename "$file")
  index=$(category_of "$name")
  IFS='|' read -r label hint <<<"${categories[$index]}"
  url="$base/$(urlencode "$name")"
  checksum="—"
  if [[ -f "$file.sha256" ]]; then
    checksum="[SHA-256]($url.sha256)"
  fi
  install=${hint//FILE/$name}
  rows[$index]+="| $label | [$name]($url) | $checksum | $install |"$'\n'
  found=1
done < <(find "$dist" -maxdepth 1 -type f ! -name '*.sha256' | sort)

if [[ $found -eq 0 ]]; then
  echo "No build artifacts in $dist" >&2
  exit 1
fi

echo "## Downloads"
echo
echo "| Platform | File | Checksum | Install |"
echo "| --- | --- | --- | --- |"
for index in "${!categories[@]}"; do
  printf '%s' "${rows[$index]:-}"
done
echo
echo "The builds are not signed or notarized. Verify a download with"
echo "\`sha256sum -c <file>.sha256\`."

if [[ -n "$notes" && -s "$notes" ]]; then
  echo
  cat "$notes"
fi
