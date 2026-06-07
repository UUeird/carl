#!/usr/bin/env bash
# Run the coded test suite (GUT) headlessly. Use before opening a PR.
# Exit code is non-zero if any test fails, so it works as a gate.
set -euo pipefail

cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  # Fall back to the macOS app bundle.
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fi

# Run GUT; capture output so we can both show it and key the exit code off the
# real test result (engine teardown can emit unrelated noise).
out="$("$GODOT" --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://test -ginclude_subdirs -gexit -gprefix=test_ 2>&1)"

# Filter the engine/addon noise that isn't about our tests, then print.
echo "$out" | grep -vE \
  "Vulkan|OpenGL|gut_loader|gut_cmdln|Failed loading resource|DEPRECATED|Awaiting|Leaked|RID alloc|ObjectDB|PagedAllocator|instance_notify|in use at exit|fontdata|\.ttf|GutSceneTheme"

# Pass only if GUT reported all tests passed.
if echo "$out" | grep -q -- "---- All tests passed! ----"; then
  echo "✅ all tests passed"
  exit 0
else
  echo "❌ tests failed (or did not complete)"
  exit 1
fi
