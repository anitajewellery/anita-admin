#!/usr/bin/env bash
# Scripted walk of Anita Admin on the emulator (GitHub Actions), v2.
# Every tap is located fresh from a uiautomator dump. Critical steps verify
# their result and retry. Everything is logged to shots/walk.log and the
# relevant hierarchy dumps are saved next to the screenshots, so a failed
# step can be diagnosed from the published branch alone.
set -u
PKG=com.anitajewellery.admin
SHOTS="$GITHUB_WORKSPACE/shots"
mkdir -p "$SHOTS"
exec > >(tee -a "$SHOTS/walk.log") 2>&1

shot() { adb exec-out screencap -p > "$SHOTS/$1.png"; echo "shot: $1"; }
save_dump() { dump_ui; cp /tmp/ui.xml "$SHOTS/dump-$1.xml" 2>/dev/null; }

dump_ui() {
  adb shell uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1
  adb pull /data/local/tmp/ui.xml /tmp/ui.xml >/dev/null 2>&1
}

has_text() { dump_ui; grep -q "text=\"$1\"" /tmp/ui.xml; }

visible_texts() {
  python3 - <<'PY'
import re
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
except OSError:
    print("(no dump)")
    raise SystemExit
ts = [m.group(1) for m in re.finditer(r'text="([^"]+)"', xml)]
print("visible texts:", " | ".join(ts[:40]))
PY
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
  if [ -n "$C" ]; then echo "tap text '$1' at $C"; adb shell input tap $C; else echo "NOT FOUND (text): $1"; visible_texts; fi
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
  if [ -n "$C" ]; then echo "tap field $1 at $C"; adb shell input tap $C; else echo "NOT FOUND (field): $1"; visible_texts; fi
  sleep 2
}

type() { adb shell input text "$1"; sleep 1; }
hide_keyboard() { adb shell input keyevent 111; sleep 1; }  # ESC: dismiss keyboard, never exits the app

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

echo "== unlock (verified, retries) =="
UNLOCKED=0
for i in 1 2 3; do
  hide_keyboard
  tap_text "Set PIN & Unlock"
  sleep 3
  if has_text "New Receipt"; then echo "unlocked on attempt $i"; UNLOCKED=1; break; fi
  echo "still locked after attempt $i"
  visible_texts
done
save_dump after-unlock
shot 03-receipt-form
if [ "$UNLOCKED" != "1" ]; then echo "WALK ABORTED: could not unlock"; exit 0; fi

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
save_dump bill
shot 05-bill

echo "== tabs =="
tap_text "History";  sleep 4; shot 06-history
tap_text "Products"; sleep 8; shot 07-products
tap_text "Upload";   sleep 3; shot 08-upload
tap_text "Receipt";  sleep 3

echo "== catalogue picker =="
tap_text "Catalogue" contains
sleep 4
save_dump picker
shot 09-picker
tap_text "TEST" contains
sleep 3
shot 10-picker-added

echo "== walk done =="
ls -la "$SHOTS"
