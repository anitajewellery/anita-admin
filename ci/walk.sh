#!/usr/bin/env bash
# Scripted walk of Anita Admin on the emulator (GitHub Actions).
# Every tap is located fresh from a uiautomator dump, so layout shifts
# (keyboard opening, dialogs) don't break the walk. Steps never abort the
# script: a missed tap shows up in the screenshots instead of failing the run.
set -u
PKG=com.anitajewellery.admin
SHOTS="$GITHUB_WORKSPACE/shots"
mkdir -p "$SHOTS"

shot() { adb exec-out screencap -p > "$SHOTS/$1.png"; echo "shot: $1"; }

dump_ui() {
  adb shell uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1
  adb pull /data/local/tmp/ui.xml /tmp/ui.xml >/dev/null 2>&1
}

# Print "x y" centre of the node whose text matches $1 (exact, or contains if $2=contains).
center_of() {
  python3 - "$1" "${2:-exact}" <<'PY'
import re, sys
want, mode = sys.argv[1], sys.argv[2]
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)
for m in re.finditer(r'text="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
    t = m.group(1)
    if (mode == 'exact' and t == want) or (mode == 'contains' and want in t):
        print((int(m.group(2)) + int(m.group(4))) // 2, (int(m.group(3)) + int(m.group(5))) // 2)
        break
PY
}

tap_text() {
  dump_ui
  C=$(center_of "$1" "${2:-exact}")
  if [ -n "$C" ]; then echo "tap text '$1' at $C"; adb shell input tap $C; else echo "NOT FOUND (text): $1"; fi
  sleep 2
}

# Tap the Nth (0-based) EditText on screen, located from a fresh dump.
tap_field() {
  dump_ui
  C=$(python3 - "$1" <<'PY'
import re, sys
n = int(sys.argv[1])
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    sys.exit(0)
fields = [m for m in re.finditer(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)]
if n < len(fields):
    m = fields[n]
    print((int(m.group(1)) + int(m.group(3))) // 2, (int(m.group(2)) + int(m.group(4))) // 2)
PY
)
  if [ -n "$C" ]; then echo "tap field $1 at $C"; adb shell input tap $C; else echo "NOT FOUND (field): $1"; fi
  sleep 2
}

type() { adb shell input text "$1"; sleep 1; }
hide_keyboard() { adb shell input keyevent 4; sleep 1; }

echo "== install =="
adb install -r "$GITHUB_WORKSPACE/app.apk"
adb shell am start -n $PKG/.MainActivity
sleep 8
tap_text "Later"            # update dialog, only if an older APK was picked
shot 01-pin

echo "== set PIN 1234 (emulator only) =="
tap_field 0; type 1234
tap_field 1; type 1234
shot 02-pin-filled
tap_text "Set PIN & Unlock"
sleep 4
shot 03-receipt-form

echo "== fill a bill =="
tap_field 0; type "Emulator%sTest"
tap_field 1; type 9876543210
tap_field 2; type "Imphal"
tap_field 3; type "Necklace%sSet"
tap_field 4; type 1499
hide_keyboard
shot 04-bill-filled
tap_text "Generate" contains
sleep 5
shot 05-bill

echo "== tabs =="
tap_text "History";  sleep 4; shot 06-history
tap_text "Products"; sleep 8; shot 07-products
tap_text "Upload";   sleep 3; shot 08-upload
tap_text "Receipt";  sleep 3

echo "== catalogue picker =="
tap_text "Catalogue" contains
sleep 4
shot 09-picker
tap_text "TEST" contains
sleep 3
hide_keyboard
shot 10-picker-added

echo "== walk done =="
ls -la "$SHOTS"
