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
gs=${commands[gs]:-/opt/homebrew/bin/gs}
[[ -x "$gs" ]] || gs=/usr/local/bin/gs
[[ -x "$gs" ]] || { print -u2 "Ghostscript not found"; exit 1; }

work=$(mktemp -d -t hp1020)
trap 'rm -rf -- "$work"' EXIT

"$root/hp1020_usb" "$root/sihp1020.dl"
"$gs" -q -dNOPAUSE -dBATCH -sDEVICE=ps2write \
    -sOutputFile="$work/input.ps" -- "$1"

(
    cd "$root"
    PATH="$root:$PATH" GSBIN="$gs" ./foo2zjs-wrapper \
        -r600x600 -P -z1 -L0 -p9 -n "$copies" \
        "$work/input.ps" > "$work/job.zm"
)

"$root/hp1020_usb" --send "$work/job.zm"
