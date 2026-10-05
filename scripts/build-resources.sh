#!/bin/zsh
set -euo pipefail

echo "==> Building bundled resources for HP LaserJet 1020 app..."

root=${0:A:h:h}
target="$root/bundled_resources"

mkdir -p "$target/bin" "$target/lib" "$target/share" "$target/firmware" "$target/scripts"

# 1. Build upstream foo2zjs executables
echo "--> Compiling foo2zjs components..."
make -C "$root/upstream" arm2hpdl foo2zjs foo2zjs-wrapper foo2zjs-pstops

# 2. Build HP 1020 USB executable
echo "--> Compiling hp1020_usb C binary..."
clang -Wall -Wextra -O2 \
    -I/opt/homebrew/include/libusb-1.0 \
    /opt/homebrew/lib/libusb-1.0.a \
    -framework CoreFoundation -framework IOKit -framework Security \
    "$root/hp1020_usb.c" -o "$target/bin/hp1020_usb"

# 3. Generate firmware
echo "--> Generating firmware..."
"$root/upstream/arm2hpdl" "$root/upstream/sihp1020.img" > "$target/firmware/sihp1020.dl"

# 4. Copy foo2zjs binaries and scripts
echo "--> Copying foo2zjs binaries and scripts..."
rm -f "$target/scripts/foo2zjs-wrapper"
cp -f "$root/upstream/foo2zjs" "$target/bin/foo2zjs"
cp -f "$root/upstream/foo2zjs-pstops" "$target/bin/foo2zjs-pstops"
# macOS sed implements the commands this script uses.
sed -i '' 's#Darwin)[[:space:]]*sed=gsed#Darwin)		sed=/usr/bin/sed#' \
    "$target/bin/foo2zjs-pstops"
cp -f "$root/upstream/arm2hpdl" "$target/bin/arm2hpdl"
cp -f "$root/upstream/foo2zjs-wrapper" "$target/scripts/foo2zjs-wrapper"

# 5. Bundle Ghostscript & dynamic libraries
echo "--> Bundling Ghostscript binary and libraries..."
gs_cmd=""
if command -v gs >/dev/null 2>&1; then
    gs_cmd=$(command -v gs)
elif [[ -x /opt/homebrew/bin/gs ]]; then
    gs_cmd=/opt/homebrew/bin/gs
fi
gs_real=""
if [[ -n "$gs_cmd" ]]; then
    gs_real=$(realpath "$gs_cmd")
fi
if [[ -f "$gs_real" ]]; then
    cp "$gs_real" "$target/bin/gs"
    chmod 755 "$target/bin/gs"

    # Find ghostscript share dir
    gs_ver=$("$gs_real" --version)
    gs_share_dir="/opt/homebrew/Cellar/ghostscript/$gs_ver/share/ghostscript"
    if [[ -d "$gs_share_dir" ]]; then
        mkdir -p "$target/share/ghostscript/$gs_ver"
        cp -R "$gs_share_dir/"* "$target/share/ghostscript/$gs_ver/"
    elif [[ -d "/opt/homebrew/share/ghostscript" ]]; then
        mkdir -p "$target/share/ghostscript/$gs_ver"
        cp -R /opt/homebrew/share/ghostscript/* "$target/share/ghostscript/$gs_ver/"
    fi

    # Copy every Homebrew dylib under the filename dyld looks up,
    # then point the bundle at those copies so printing does not
    # need Ghostscript installed afterwards.
    rm -rf "$target/lib"
    mkdir -p "$target/lib"
    typeset -a macho_files
    macho_files=()

    resolve_dep() {
        local dep="$1"
        local fname candidate
        if [[ "$dep" == /opt/homebrew/* && -e "$dep" ]]; then
            realpath "$dep"
            return 0
        fi
        fname=${dep:t}
        candidate="/opt/homebrew/lib/$fname"
        if [[ -e "$candidate" ]]; then
            realpath "$candidate"
            return 0
        fi
        for candidate in /opt/homebrew/opt/*/lib/$fname(N); do
            realpath "$candidate"
            return 0
        done
        return 1
    }

    collect_libs() {
        local file="$1"
        local lib real_lib fname
        for lib in $(otool -L "$file" 2>/dev/null | awk '/^\t(\/opt\/homebrew\/|@rpath\/)/{print $1}'); do
            real_lib=$(resolve_dep "$lib") || continue
            fname=$(basename "$lib")
            if [[ -f "$real_lib" && ! -f "$target/lib/$fname" ]]; then
                cp -L "$real_lib" "$target/lib/$fname"
                chmod 755 "$target/lib/$fname"
                macho_files+=("$target/lib/$fname")
                collect_libs "$target/lib/$fname"
            fi
        done
    }
    collect_libs "$target/bin/gs"
    macho_files+=("$target/bin/gs")

    relink_macho() {
        local file="$1"
        local dep fname new_id new_dep
        if [[ "$file" == "$target/lib/"* ]]; then
            new_id="@loader_path/$(basename "$file")"
            install_name_tool -id "$new_id" "$file"
        fi
        for dep in $(otool -L "$file" 2>/dev/null | awk '/^\t(\/opt\/homebrew\/|@rpath\/)/{print $1}'); do
            fname=$(basename "$dep")
            if [[ "$file" == "$target/lib/"* ]]; then
                new_dep="@loader_path/$fname"
            else
                new_dep="@executable_path/../lib/$fname"
            fi
            install_name_tool -change "$dep" "$new_dep" "$file"
        done
        codesign --force --sign - "$file"
    }
    for file in "${macho_files[@]}"; do
        relink_macho "$file"
    done
else
    echo "WARNING: Ghostscript binary not found on build system!"
fi

# 6. Create print-pipeline.sh script
echo "--> Creating print-pipeline.sh script..."
cat << 'EOF' > "$target/scripts/print-pipeline.sh"
#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
res_root=${script_dir:h}

bin_dir="$res_root/bin"
lib_dir="$res_root/lib"
share_dir="$res_root/share"
firmware_dir="$res_root/firmware"
scripts_dir="$res_root/scripts"

copies=1
if [[ ${1:-} == --copies ]]; then
    copies=${2:-1}
    shift 2
fi

input_file=${1:-}
if [[ -z "$input_file" || ! -f "$input_file" ]]; then
    echo "ERROR: Input file missing or not found" >&2
    exit 2
fi

export PATH="$bin_dir:$scripts_dir:$PATH"
export DYLD_LIBRARY_PATH="$lib_dir:${DYLD_LIBRARY_PATH:-}"

# Find Ghostscript version share path dynamically
gs_ver_dir=$(ls -d "$share_dir/ghostscript/"* 2>/dev/null | head -n 1 || echo "$share_dir/ghostscript")
export GS_LIB="$gs_ver_dir/Resource/Init:$gs_ver_dir/Resource:$share_dir/ghostscript"

gs_bin="$bin_dir/gs"
hp_usb="$bin_dir/hp1020_usb"
fw_file="$firmware_dir/sihp1020.dl"
wrapper="$scripts_dir/foo2zjs-wrapper"

echo "[STEP 1/4] Checking printer connection and firmware..."
"$hp_usb" "$fw_file"

echo "[STEP 2/4] Processing document..."
work=$(mktemp -d -t hp1020-job)
trap 'rm -rf -- "$work"' EXIT

"$gs_bin" -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=ps2write \
    -sGenericResourceDir="$gs_ver_dir/Resource/" \
    -sOutputFile="$work/input.ps" -- "$input_file"

echo "[STEP 3/4] Rasterizing for HP LaserJet 1020..."
raster_err="$work/raster.err"
raster_failed=0
# foo2zjs-wrapper expands $GSBIN without quotes. An absolute path fails
# when the .app name contains spaces ("HP LaserJet 1020.app"): the shell
# splits it and tries to execute the first word. The bare name is resolved
# through PATH, which already lists this bundle's bin directory.
if ! (
    cd "$bin_dir"
    PATH="$bin_dir:$scripts_dir:$PATH" GSBIN=gs "$wrapper" \
        -r600x600 -P -z1 -L0 -p9 -n "$copies" \
        "$work/input.ps" > "$work/job.zm"
) 2>"$raster_err"; then
    raster_failed=1
fi
if [[ -s "$raster_err" ]]; then
    cat "$raster_err" >&2
fi

# foo2zjs-wrapper always exits 0, even when the raster data is not a
# PBM. Do not send that output to the printer.
if [[ "$raster_failed" -ne 0 ]] || [[ ! -s "$work/job.zm" ]] || \
    grep -E -q 'command not found|Not a pbm|Not a pbmraw|Not a pksmraw' "$raster_err"; then
    echo "ERROR: Rasterizing failed, so the document was not sent to the printer." >&2
    exit 1
fi

echo "[STEP 4/4] Sending data to printer..."
"$hp_usb" --send "$work/job.zm"

echo "SUCCESS: Print job completed successfully."
EOF

# Ensure all scripts & binaries are executable
chmod +x "$target/bin/"*
chmod +x "$target/scripts/"*

echo "==> Bundled resources build complete!"
ls -la "$target/bin"
ls -la "$target/firmware"
