#!/usr/bin/env bash
# Background-launch Diffary on a throwaway demo repo, capture its window by id
# (works while it's behind other windows, never takes focus), then quit it.
# Usage: scripts/screenshot.sh <out.png> [extra diffary args...]
set -euo pipefail
out=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
APP="${DIFFARY_APP:-$HOME/Applications/Diffary.app}"
here=$(cd "$(dirname "$0")" && pwd)

demo=$(mktemp -d)/demo
trap 'kill "${pid:-}" 2>/dev/null || true; rm -rf "$(dirname "$demo")"' EXIT
mkdir -p "$demo/src" && cd "$demo"
git init -q -b master && git config user.email d@example.com && git config user.name demo
printf 'import Foundation\n\nfunc greet(_ name: String) -> String {\n    return "Hello, " + name\n}\n' > src/greet.swift
printf '# demo\n' > README.md
printf 'old\n' > legacy.txt
git add -A && git commit -qm base && git checkout -qb feat
printf 'import Foundation\n\n/// Greets someone politely.\nfunc greet(_ name: String, excited: Bool = false) -> String {\n    let mark = excited ? "!" : "."\n    return "Hello, \\(name)\\(mark)"\n}\n' > src/greet.swift
git rm -q legacy.txt && git commit -qam "feat work"
printf 'func farewell() -> String { "Bye" }\n' > src/farewell.swift

# Neutral prompt: no hostname or temp path in screenshots. (zsh only.)
zdot=$(dirname "$demo")/zdot
mkdir -p "$zdot" && printf "PROMPT='%%F{blue}demo%%f %%F{yellow}feat%%f \$ '\n" > "$zdot/.zshrc"

before=$(pgrep -x Diffary | sort || true)
# Empty config: screenshots show defaults, not the local user's settings.
open -g -n -a "$APP" --env ZDOTDIR="$zdot" --args "$demo" --config "$zdot/none.toml" "$@"
sleep 3
# Only the Diffary we just launched: never touch one the user has open.
pid=""
for _ in 1 2 3 4 5; do
  pid=$(pgrep -x Diffary | sort | comm -13 <(echo "$before") - | head -1 || true)
  [[ -n $pid ]] && break
  sleep 1
done
[[ -n $pid ]] || { echo "Diffary didn't start" >&2; exit 1; }
id=$(swift "$here/window-id.swift" "$pid")
screencapture -o -x -l"$id" "$out"
echo "saved $out"
