#!/usr/bin/env bash
# Release strip check (spec 21). Exports the "Linux" preset in release mode and checks that the debug
# console is absent from the export: the strings "debug_console" and "F9" and the debug file names
# must not appear in any exported file (the binary or the .pck). Nothing is written into the project.
#
# Usage: GODOT=/path/to/godot tests/acceptance/release_strip_check.sh [project_dir] [work_dir]
#   project_dir defaults to the repository root. work_dir defaults to a new temporary directory.
# Exit codes: 0 PASS, 1 FAIL (a string was found, or the export ran but produced no binary),
#             3 NOT RUN (no Godot binary, or no release template at ~/.local/share/godot/export_templates).
# The export templates are required. Without them this script reports NOT RUN and does not fake a result.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:-$(cd "$HERE/../.." && pwd)}"
WORK="${2:-$(mktemp -d)}"
GODOT_BIN="${GODOT:-godot}"
TEMPLATE="${HOME}/.local/share/godot/export_templates/4.3.stable/linux_release.x86_64"
NEEDLES=("debug_console" "F9" "debug_guard" "debug_commands" "debug_day_defaults" "debug_console.gd" "scripts/debug")

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
	echo "STRIP   NOT RUN: Godot binary not found (set GODOT=/path/to/godot)"
	exit 3
fi
if [ ! -f "$TEMPLATE" ]; then
	echo "STRIP   NOT RUN: release template not found at $TEMPLATE"
	exit 3
fi

mkdir -p "$WORK/out"
"$GODOT_BIN" --headless --path "$PROJECT" --export-release "Linux" "$WORK/out/CARBON.x86_64" > "$WORK/export.log" 2>&1
rc=$?
if [ $rc -ne 0 ] || [ ! -f "$WORK/out/CARBON.x86_64" ]; then
	echo "STRIP   NOT RUN: the release export failed (exit $rc). Log: $WORK/export.log"
	exit 3
fi

fail=0
binary="$WORK/out/CARBON.x86_64"
pck="$WORK/out/CARBON.pck"
if [ ! -f "$pck" ]; then
	echo "STRIP   NOT RUN: the export produced no .pck in $WORK/out"
	exit 3
fi

# The binary: an export without embedded data is the stock template byte for byte, so the game
# adds nothing to it. The engine itself contains "F9" (its key-name table), so the binary is only
# compared with the template: any extra occurrence of a needle would be a game string.
if cmp -s "$TEMPLATE" "$binary"; then
	echo "BINARY  identical to the stock release template, so the game adds no strings to it"
else
	for n in "${NEEDLES[@]}"; do
		t=$(grep -a -o -F -- "$n" "$TEMPLATE" | wc -l)
		e=$(grep -a -o -F -- "$n" "$binary" | wc -l)
		if [ "$e" -gt "$t" ]; then
			echo "FOUND   '$n' in the binary: $e occurrence(s), the stock template has $t"
			fail=1
		fi
	done
fi

# The .pck: every file name, and every text-coded entry (pck_strings.py, spec 21).
python3 "$HERE/pck_strings.py" "$pck" "${NEEDLES[@]}"
rc=$?
if [ $rc -eq 2 ] || [ $rc -eq 3 ]; then
	echo "STRIP   NOT RUN: the .pck could not be checked (see above)"
	exit 3
fi
if [ $rc -ne 0 ]; then
	fail=1
fi

if [ $fail -eq 0 ]; then
	echo "STRIP   PASS: no debug string in the release export (needles: ${NEEDLES[*]})"
	exit 0
fi
echo "STRIP   FAIL: debug strings are present in the release export (see FOUND lines)"
exit 1
