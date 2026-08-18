#!/bin/zsh
set -euo pipefail

root=${0:A:h}
output="$root/firmware/sihp1020.dl"

if [[ -f "$output" ]]; then
    print "$output already exists"
    exit 0
fi

print "Downloading HP LaserJet 1020 firmware (Copyright Hewlett-Packard 2005)."
print "Run this only if you accept HP's applicable firmware terms."

work=$(mktemp -d -t hp1020-firmware)
trap 'rm -rf -- "$work"' EXIT

curl -fL \
    https://www.quirinux.org/printers/sihp1020.tar.gz \
    -o "$work/sihp1020.tar.gz"

expected=ec4665c6704c2db3cfaeb71bb06f1bbc9449c030504b04f533a84bdfae89f966
actual=$(shasum -a 256 "$work/sihp1020.tar.gz" | cut -d ' ' -f 1)
[[ "$actual" == "$expected" ]] || {
    print -u2 "Firmware archive checksum mismatch"
    exit 1
}

tar -xzf "$work/sihp1020.tar.gz" -C "$work"

make -C "$root/upstream" arm2hpdl
mkdir -p "$root/firmware"
"$root/upstream/arm2hpdl" "$work/sihp1020.img" > "$output"
print "$output"
