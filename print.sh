#!/bin/zsh
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    print "usage: $0 [--copies 1-99] FILE.pdf"
    exit 0
fi

copies=1
if [[ ${1:-} == --copies ]]; then
    (( $# >= 2 )) || { print -u2 "--copies requires a value"; exit 2; }
    copies=${2:-}
    shift 2
fi

if [[ "$copies" != <-> ]] || (( copies < 1 || copies > 99 )); then
    print -u2 "copies must be a whole number from 1 to 99"
    exit 2
fi

if (( $# != 1 )) || [[ ! -f "$1" ]]; then
    print -u2 "usage: $0 [--copies 1-99] FILE.pdf"
    exit 2
fi

root=${0:A:h}
[[ -d "$root/HP 1020 Print.app/Contents/Resources" ]] && root="$root/HP 1020 Print.app/Contents/Resources"
[[ -x "$root/hp1020_usb" && -f "$root/sihp1020.dl" && -x "$root/foo2zjs-wrapper" && -x "$root/foo2zjs" && -x "$root/foo2zjs-pstops" ]] || {
    print -u2 "Print pipeline missing. Run ./prepare-firmware.sh and ./build-app.sh first."
    exit 1
}
gs=${commands[gs]:-/opt/homebrew/bin/gs}
[[ -x "$gs" ]] || gs=/usr/local/bin/gs
[[ -x "$gs" ]] || { print -u2 "Ghostscript not found"; exit 1; }

work=$(mktemp -d -t hp1020)
trap 'rm -rf -- "$work"' EXIT

"$root/hp1020_usb" "$root/sihp1020.dl"
"$gs" -q -dNOPAUSE -dBATCH -sDEVICE=ps2write \
    -sOutputFile="$work/input.ps" -- "$1"

raster_err="$work/raster.err"
raster_failed=0
if ! (
    cd "$root"
    PATH="$root:$PATH" GSBIN="$gs" ./foo2zjs-wrapper \
        -r600x600 -P -z1 -L0 -p9 -n "$copies" \
        "$work/input.ps" > "$work/job.zm"
) 2>"$raster_err"; then
    raster_failed=1
fi
if [[ -s "$raster_err" ]]; then
    cat "$raster_err" >&2
fi

# foo2zjs-wrapper always exits 0, even when rasterizing fails.
if [[ "$raster_failed" -ne 0 ]] || [[ ! -s "$work/job.zm" ]] || \
    grep -E -q 'command not found|Not a pbm|Not a pbmraw|Not a pksmraw' "$raster_err"; then
    print -u2 "ERROR: Rasterizing failed. The document was not sent to the printer."
    exit 1
fi

"$root/hp1020_usb" --send "$work/job.zm"
