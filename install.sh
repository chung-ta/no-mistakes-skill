#!/usr/bin/env bash
#
# Install this repo's skills into Claude Code.
#
#   ./install.sh                 symlink each skill into ~/.claude/skills (default)
#   ./install.sh --copy          copy instead of symlink
#   ./install.sh --force         replace anything already installed under the same name
#   ./install.sh --uninstall     remove the skills this repo provides
#   ./install.sh --dir <path>    install somewhere other than ~/.claude/skills
#
# Symlinking is the default so `git pull` updates the installed skills with no
# reinstall. Use --copy on a machine where you want the skills to survive this
# checkout being moved or deleted.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/skills"
DEST_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
MODE=symlink
FORCE=0
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --copy)      MODE=copy ;;
    --force)     FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --dir)       shift; DEST_DIR="${1:?--dir needs a path}" ;;
    -h|--help)   awk 'NR>=3 && /^#/ { sub(/^# ?/, ""); print; next } NR>=3 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)           echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$SRC_DIR" ] || { echo "no skills/ directory in $REPO_DIR" >&2; exit 1; }

skills=()
for d in "$SRC_DIR"/*/; do
  [ -f "$d/SKILL.md" ] && skills+=("$(basename "$d")")
done
[ ${#skills[@]} -gt 0 ] || { echo "no skills found in $SRC_DIR" >&2; exit 1; }

if [ "$UNINSTALL" = 1 ]; then
  for s in "${skills[@]}"; do
    target="$DEST_DIR/$s"
    if [ -L "$target" ] || [ -d "$target" ]; then
      rm -rf "$target"
      echo "  removed  $s"
    else
      echo "  absent   $s"
    fi
  done
  echo
  echo "Uninstalled from $DEST_DIR"
  exit 0
fi

mkdir -p "$DEST_DIR"
echo "Installing into $DEST_DIR ($MODE)"
echo

installed=0
for s in "${skills[@]}"; do
  src="$SRC_DIR/$s"
  target="$DEST_DIR/$s"

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" = 1 ]; then
      rm -rf "$target"
    else
      # A symlink already pointing at this checkout is already correct.
      if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
        echo "  current  $s"
        continue
      fi
      echo "  SKIP     $s — already exists at $target (use --force to replace)" >&2
      continue
    fi
  fi

  if [ "$MODE" = symlink ]; then
    ln -s "$src" "$target"
  else
    cp -R "$src" "$target"
  fi
  echo "  ok       $s"
  installed=$((installed + 1))
done

# Scripts lose their executable bit through some copy and clone paths.
find "$SRC_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

echo
if [ "$installed" -gt 0 ]; then
  echo "Installed $installed skill(s). Start a new Claude Code session to pick them up."
else
  echo "Nothing changed."
fi
