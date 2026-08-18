# HP LaserJet 1020 USB printing for modern macOS

A small, driver-independent macOS app that prints PDF and PostScript files on
an HP LaserJet 1020 connected directly over USB.

Tested on Apple Silicon with macOS 27. It does not use a legacy HP package,
Gutenprint, a CUPS printer queue, or Rosetta.

> [!IMPORTANT]
> This project supports **HP LaserJet 1020** (`USB VID 03f0`, `PID 2b17`).
> Despite similar names and partially compatible drivers, the 1020 and 1022
> are different devices.

## Why this exists

The LaserJet 1020 is a host-based printer with very little onboard storage.
After every power cycle, the host must upload firmware before the printer can
accept a print job. A printer without firmware still appears in the USB device
list, which makes the failure look like an ordinary driver problem.

The old HP, Apple, and Gutenprint packages depend on printing components that
are no longer reliable on current macOS releases. This project replaces that
path with a small userspace pipeline:

```text
PDF or PostScript
        |
        v
Ghostscript / ps2write
        |
        v
foo2zjs (-P -z1 -L0, A4, 600 dpi)
        |
        v
ZjStream + JBIG raster data
        |
        v
libusb bulk OUT
        |
        v
HP LaserJet 1020
```

## Features

- Direct USB printing without a CUPS queue.
- Automatic firmware detection and upload after power-on.
- PDF and PostScript input.
- Configurable copy count from 1 to 99.
- Finder drag-and-drop application.
- Native Apple Silicon executables.
- Partial USB write handling: already-transferred bytes are not resent after
  a timeout.
- Statically linked `libusb` in the built application.

## Current limitations

- Apple Silicon/macOS only. The USB code is portable, but Windows and Linux
  packaging has not been added.
- A4, monochrome, 600 dpi.
- No system printer queue or normal `Cmd+P` destination yet.
- One print job at a time.
- Ghostscript is a runtime dependency.
- Only the LaserJet 1020 USB ID has been tested.

## Quick start

### Requirements

- Apple Silicon Mac.
- HP LaserJet 1020 connected over USB and powered on.
- Xcode Command Line Tools.
- [Homebrew](https://brew.sh/).
- Ghostscript and libusb:

```sh
brew install ghostscript libusb
```

`libusb` is needed when building the app and is then linked statically.
Ghostscript remains a runtime dependency.

### Build from source

Clone this repository together with its `foo2zjs` submodule:

```sh
git clone --recurse-submodules YOUR_REPOSITORY_URL
cd hp_printer
```

Prepare the HP firmware locally:

```sh
./prepare-firmware.sh
```

The script verifies the downloaded archive against a pinned SHA-256 checksum
before extracting or converting it.

Build and ad-hoc sign the application:

```sh
./build-app.sh
```

Output:

```text
HP 1020 Print.app
```

The build script compiles the required ARM64 binaries, copies the printing
pipeline into the application bundle, validates `Info.plist`, and applies a
local ad-hoc signature.

## Usage

Drag a PDF or PostScript file onto `HP 1020 Print.app`, choose the number of
copies, and click **Print**.

Alternatively, double-click the app and choose a file. A notification appears
after the job has been sent to the printer. Errors are shown in a dialog.

Command-line printing is also available:

```sh
./print.sh document.pdf
./print.sh --copies 3 document.pdf
```

The app looks for Ghostscript in:

1. the process `PATH`;
2. `/opt/homebrew/bin/gs`;
3. `/usr/local/bin/gs`.

## What happens during a print

1. `hp1020_usb` opens USB device `03f0:2b17`.
2. It requests the IEEE 1284 Device ID from the printer.
3. If the ID lacks `FWVER`, it uploads `sihp1020.dl` and waits eight seconds
   for the printer to initialize.
4. Ghostscript normalizes the input into PostScript using `ps2write`.
5. `foo2zjs-wrapper` rasterizes it at 600 dpi and runs `foo2zjs` with the
   LaserJet 1020-specific flags `-P -z1 -L0` and the selected copy count.
6. `hp1020_usb --send` writes the resulting ZjStream data to the bulk OUT USB
   endpoint.

A successfully initialized printer reports a Device ID containing:

```text
FWVER:20050309
```

Firmware is stored in printer RAM. Turning the printer off removes it; this is
normal, and the next print uploads it again automatically.

## Repository layout

```text
app/HP1020Print       Finder launcher, file picker, notifications
app/Info.plist        macOS application metadata and supported document types
hp1020_usb.c          firmware detection and direct USB transfer
print.sh              PDF/PS -> PostScript -> ZjStream -> USB pipeline
prepare-firmware.sh   local firmware download and conversion
build-app.sh          ARM64 build and .app assembly
upstream/             foo2zjs Git submodule (GPLv2)
```

Generated files are intentionally ignored by Git:

```text
firmware/
HP 1020 Print.app/
hp1020_usb
```

## Troubleshooting

### Printer is not found

Confirm the USB identity:

```sh
ioreg -p IOUSB -l -w 0 | grep -A 25 "HP LaserJet 1020"
```

Expected values:

```text
idVendor  = 1008   # 0x03f0
idProduct = 11031  # 0x2b17
```

Try a direct cable or a different powered USB adapter if the device is absent.

### `Ghostscript not found`

Install it:

```sh
brew install ghostscript
```

Then verify:

```sh
/opt/homebrew/bin/gs --version
```

### Firmware uploads, but nothing prints

Run the command-line path to see the complete log:

```sh
./print.sh document.pdf
```

The log should show `FWVER:20050309` before `Print data sent.`

### `LIBUSB_ERROR_TIMEOUT`

If a malformed or interrupted job leaves the printer endpoint stalled:

1. Turn the printer off.
2. Wait ten seconds.
3. Turn it on and wait for the green light.
4. Retry once.

The app handles partial writes, but it cannot recover printer firmware that has
stopped parsing an already-corrupted job.

### macOS blocks the app

Release builds are only ad-hoc signed unless the maintainer signs and notarizes
them with an Apple Developer ID. Building from source is the safest option.
For a downloaded build, use Finder's **Open** context-menu action only after
verifying that it came from the expected repository/release.

## Firmware and licensing

`foo2zjs` is GPLv2 software. Its source and license are provided through the
`upstream` submodule; see `upstream/COPYING`.

The LaserJet firmware is Copyright Hewlett-Packard 2005. It is deliberately
excluded from Git. `prepare-firmware.sh` downloads and converts it on the
printer owner's machine. Run that script only if you accept the firmware terms
applicable to you.

Do **not** publish `firmware/sihp1020.dl` or a prebuilt `.app` containing it
until you have verified that redistribution is permitted. Source-only GitHub
releases avoid bundling the firmware.

`hp1020_usb.c`, the launcher, and build scripts currently have no explicit
project license. Add one before accepting external contributions or publishing
the project as reusable open-source software.

## Acknowledgments

Developed with assistance from [OpenAI Codex](https://developers.openai.com/codex/).

## Publishing checklist

- Keep `upstream/` as the declared Git submodule.
- Do not commit `firmware/` or the built `.app` without reviewing HP terms.
- Choose and add a license for this project's original source.
- Replace `YOUR_REPOSITORY_URL` above with the final GitHub clone URL.
- Build from a clean clone using `--recurse-submodules`.
- Test one PDF after a printer power cycle.
- For public binary releases, use Developer ID signing and notarization.
