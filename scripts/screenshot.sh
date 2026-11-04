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

open -g -n -a "$APP" --env ZDOTDIR="$zdot" --args "$demo" "$@"
sleep 3
pid=$(pgrep -n -x Diffary)
id=$(swift "$here/window-id.swift" "$pid")
screencapture -o -x -l"$id" "$out"
echo "saved $out"
