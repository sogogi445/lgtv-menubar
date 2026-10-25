#!/bin/sh
# Tests the app against fake local servers. Nothing is sent to a real TV.
#   ./tools/run_tests.sh            (builds first, needs python3 with the `websockets` package)
set -e
cd "$(dirname "$0")/.."
PY="${PYTHON:-python3}"
ARCHS="$(uname -m)" ./build.sh >/dev/null
BIN="build/LG TV.app/Contents/MacOS/LGTVBar"
fail=0

echo "== protocol test (fake TV on 127.0.0.1)"
"$PY" tools/fake_tv.py 20 > build/fake_tv.log 2>&1 &
TVPID=$!
sleep 2
LGTV_IP=127.0.0.1 LGTV_REG="$PWD/res/registration.json" "$BIN" --selftest | tee build/selftest.out
kill $TVPID 2>/dev/null || true
for want in "REGISTER client-key-sent=False manifest=True" "ssap://audio/volumeUp" "ssap://tv/openChannel {'channelNumber': '5-1'}" \
            "ssap://tv/switchInput {'inputId': 'HDMI_1'}" "ssap://audio/setMute {'mute': True}" "POINTER <- 'type:button\\nname:HOME"; do
  if grep -qF "$want" build/fake_tv.log; then echo "  ok   $want"; else echo "  FAIL $want"; fail=1; fi
done
grep -q "connected: true" build/selftest.out || { echo "  FAIL connect"; fail=1; }

echo "== discovery test (fake SSDP responder on 127.0.0.1)"
"$PY" tools/fake_ssdp.py 10 > build/fake_ssdp.log 2>&1 &
SSPID=$!
sleep 1
out="$(LGTV_SSDP=127.0.0.1:1900 "$BIN" --discover-test)"
kill $SSPID 2>/dev/null || true
echo "  $out"
echo "$out" | grep -q '127.0.0.1' && echo "  ok   discovered" || { echo "  FAIL discovery"; fail=1; }

echo "== language test (English default, Korean selectable)"
en="$(LGTV_LANG=en "$BIN" --l10n-test)"; ko="$(LGTV_LANG=ko "$BIN" --l10n-test)"; xx="$("$BIN" --l10n-test)"
echo "  $en"; echo "  $ko"
echo "$en" | grep -qF "en | Power On | Quit | Connected, volume 12" && echo "  ok   English" || { echo "  FAIL English"; fail=1; }
echo "$ko" | grep -qF "ko | 전원 켜기 | 종료 | 연결됨, 볼륨 12" && echo "  ok   Korean" || { echo "  FAIL Korean"; fail=1; }
echo "$xx" | grep -q "^en |" && echo "  ok   default is English" || { echo "  FAIL default language"; fail=1; }
# every string used in the code must exist in both translation files
"$PY" - <<'PYEOF' || fail=1
import re, sys
src = open("src/main.swift", encoding="utf-8").read()
used = set(re.findall(r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"', src))
for lang in ("en", "ko"):
    have = set(k.replace('\\"', '"') for k in re.findall(r'^"((?:[^"\\]|\\.)*)" =', open(f"res/{lang}.lproj/Localizable.strings", encoding="utf-8").read(), re.M))
    miss = sorted(used - have)
    print(f"  {'ok  ' if not miss else 'FAIL'} {lang}.lproj has all {len(used)} keys" + (f" - missing: {miss}" if miss else ""))
    if miss: sys.exit(1)
PYEOF

[ "$fail" = 0 ] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
