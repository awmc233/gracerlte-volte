#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""
Patch a MindTheGapps zip so it installs on gracerlte under TWRP.

The stock installer fails with "could not mount /mnt/system" on this device because:
  1. its fstab lookup requires a leading blank before the mount point, but TWRP's
     /etc/recovery.fstab starts the line with "/system";
  2. its fallback path /dev/block/bootdevice/by-name/system does not exist on Exynos
     (the device uses /dev/block/platform/155a0000.ufs/by-name/SYSTEM);
  3. TWRP does not define ro.bionic.arch, so the arch check aborts.

This script only rewrites META-INF/com/google/android/update-binary inside a copy of
the zip you provide. It does not add, remove, or redistribute any Google application.

Usage:
    python patch-mindthegapps.py MindTheGapps-13.0.0-arm64-*.zip MindTheGapps-fixed.zip
"""

import argparse
import os
import sys
import zipfile

UPDATE_BINARY = "META-INF/com/google/android/update-binary"

OLD_FN = '''get_block_for_mount_point() {
  grep -v "^#" /etc/recovery.fstab | grep "[[:blank:]]$1[[:blank:]]" | tail -n1 | tr -s [:blank:] ' ' | cut -d' ' -f1
}'''

NEW_FN = '''get_block_for_mount_point() {
  line=$(grep -v "^#" /etc/recovery.fstab | grep -E "(^|[[:blank:]])$1([[:blank:]]|$)" | tail -n1)
  [ -z "$line" ] && return
  for f in $line; do
    case "$f" in
      /dev/*) echo "$f"; return;;
    esac
  done
}'''

OLD_ARCH = "CPU_ARCH=$(getprop ro.bionic.arch)"
NEW_ARCH = 'CPU_ARCH=$(getprop ro.bionic.arch)\n[ -z "$CPU_ARCH" ] && CPU_ARCH="$GAPPS_ARCH"'


def patch_script(text: str) -> str:
    if 'CPU_ARCH="$GAPPS_ARCH"' in text and '"$1([[:blank:]]|$)"' in text:
        return text  # already patched
    if OLD_FN not in text:
        raise SystemExit("error: unrecognised update-binary (fstab helper not found)")
    if OLD_ARCH not in text:
        raise SystemExit("error: unrecognised update-binary (arch check not found)")
    text = text.replace(OLD_FN, NEW_FN, 1)
    text = text.replace(OLD_ARCH, NEW_ARCH, 1)
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="original MindTheGapps zip")
    ap.add_argument("output", help="patched zip to write")
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        raise SystemExit("error: input not found: " + args.input)
    if os.path.abspath(args.input) == os.path.abspath(args.output):
        raise SystemExit("error: output must differ from input")

    with zipfile.ZipFile(args.input) as zin:
        try:
            script = zin.read(UPDATE_BINARY).decode("utf-8")
        except KeyError:
            raise SystemExit("error: %s not found in %s" % (UPDATE_BINARY, args.input))
        patched = patch_script(script)

        with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
            for item in zin.infolist():
                data = patched.encode("utf-8") if item.filename == UPDATE_BINARY else zin.read(item.filename)
                zout.writestr(item, data)

    print("patched:", args.output)
    print("size   :", os.path.getsize(args.output), "bytes")
    print("note   : zip signature is now invalid; TWRP does not verify it by default.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
