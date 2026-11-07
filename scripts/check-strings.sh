#!/bin/zsh
# Syncs Localizable.xcstrings with the strings extracted by the last Debug build
# and lists keys still missing an Italian translation. Run after `xcodebuild build`.
set -euo pipefail
cd "$(dirname "$0")/.."
CATALOG=Lampo/Resources/Localizable.xcstrings
DATA=(${(f)"$(find build/DerivedData/Build/Intermediates.noindex/Lampo.build -name '*.stringsdata')"})
xcrun xcstringstool sync "$CATALOG" --stringsdata "${DATA[@]}"
python3 - "$CATALOG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
missing = [k for k, v in d["strings"].items()
           if v.get("extractionState") != "stale" and v.get("shouldTranslate", True)
           and "it" not in v.get("localizations", {})]
for k in missing: print("missing it:", repr(k))
sys.exit(1 if missing else 0)
PY
