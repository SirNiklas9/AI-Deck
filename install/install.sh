#!/usr/bin/env sh
set -eu

bundle=""
bundle_url=""
sha256=""
cards="lexicon"
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/ai-deck"
add_to_path=0
verify=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle) bundle="$2"; shift 2 ;;
    --bundle-url) bundle_url="$2"; shift 2 ;;
    --sha256) sha256="$2"; shift 2 ;;
    --cards) cards="$2"; shift 2 ;;
    --install-root) install_root="$2"; shift 2 ;;
    --add-to-path) add_to_path=1; shift ;;
    --verify) verify=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if { [ -n "$bundle" ] && [ -n "$bundle_url" ]; } || { [ -z "$bundle" ] && [ -z "$bundle_url" ]; }; then
  echo 'specify exactly one of --bundle or --bundle-url' >&2; exit 2
fi
if [ -n "$bundle_url" ] && [ -z "$sha256" ]; then
  echo '--bundle-url requires --sha256' >&2; exit 2
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
if [ -n "$bundle_url" ]; then
  case "$bundle_url" in https://*) ;; *) echo '--bundle-url must use HTTPS' >&2; exit 2;; esac
  archive="$stage/bundle.tar.gz"
  curl --fail --location --silent --show-error "$bundle_url" -o "$archive"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [ "$actual" = "$sha256" ] || { echo 'SHA-256 mismatch' >&2; exit 1; }
  tar -xzf "$archive" -C "$stage"
elif [ -d "$bundle" ]; then
  # Keep the release directory name so direct local installs retain their
  # versioned path instead of being recorded as the generic staging name.
  cp -R "$bundle" "$stage/$(basename "$bundle")"
else
  tar -xzf "$bundle" -C "$stage"
fi

set -- "$stage"/*
[ "$#" -eq 1 ] && [ -d "$1/bin" ] || { echo 'bundle must contain a single root with bin/' >&2; exit 1; }
root="$1"
if [ -f "$root/checksums.sha256" ]; then
  # A local directory is just as much a release artifact as a downloaded
  # archive. Verify every declared payload before it becomes the current deck.
  while IFS=' ' read -r expected relative; do
    [ -n "$expected" ] || continue
    relative="${relative# }"
    relative="${relative#\*}"
    relative="$(printf '%s' "$relative" | tr -d '\r')"
    file="$root/$relative"
    [ -f "$file" ] || { echo "bundle checksum entry is missing: $relative" >&2; exit 1; }
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || { echo "bundle checksum mismatch: $relative" >&2; exit 1; }
  done < "$root/checksums.sha256"
fi
version="$(basename "$root")"
target="$install_root/versions/$version"
[ ! -e "$target" ] || { echo "already installed: $target" >&2; exit 1; }
mkdir -p "$(dirname "$target")"
mv "$root" "$target"
# Archives assembled on a Windows filesystem can lose POSIX executable mode
# bits. Launchers are release payloads, not user scripts, so restore the
# required mode deterministically after extraction and before the first run.
chmod 755 "$target/bin"/*
printf '{"version":"%s","root":"%s","cards":"%s"}\n' "$version" "$target" "$cards" > "$install_root/current.json"
"$target/bin/aideck" deck --cards "$cards"
state="$install_root/state"
mkdir -p "$state"
if [ ! -f "$state/canonical-registry.json" ]; then "$target/bin/aideck" init --state-root "$state"; fi
if [ "$verify" -eq 1 ]; then "$target/bin/aideck" doctor --bundle-root "$target" --state-root "$state" --cards "$cards"; fi
if [ "$add_to_path" -eq 1 ]; then
  echo "Add $target/bin to PATH in your shell profile; this installer does not edit shell startup files."
fi
echo "AI Deck installed: $target"
echo 'Codex lifecycle hooks must be reviewed once with /hooks; the installer never forges host trust.'
