#!/bin/zsh
set -euo pipefail

root=${0:A:h}
bundle="$root/HP 1020 Print.app"
macos="$bundle/Contents/MacOS"
resources="$bundle/Contents/Resources"
firmware="$root/firmware/sihp1020.dl"

[[ -f "$firmware" ]] || {
    print -u2 "Firmware missing. Run ./prepare-firmware.sh first."
    exit 1
}

make -C "$root/upstream" foo2zjs foo2zjs-wrapper foo2zjs-pstops

mkdir -p "$macos" "$resources"
clang -Wall -Wextra -O2 \
    -I/opt/homebrew/include/libusb-1.0 \
    /opt/homebrew/lib/libusb-1.0.a \
    -framework CoreFoundation -framework IOKit -framework Security \
    "$root/hp1020_usb.c" -o "$resources/hp1020_usb"

install -m 755 "$root/app/HP1020Print" "$macos/HP1020Print"
install -m 755 "$root/print.sh" "$resources/print.sh"
install -m 755 "$root/upstream/foo2zjs" "$resources/foo2zjs"
install -m 755 "$root/upstream/foo2zjs-wrapper" "$resources/foo2zjs-wrapper"
install -m 755 "$root/upstream/foo2zjs-pstops" "$resources/foo2zjs-pstops"
install -m 644 "$firmware" "$resources/sihp1020.dl"
install -m 644 "$root/app/Info.plist" "$bundle/Contents/Info.plist"

plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
print "$bundle"
