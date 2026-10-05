# HP LaserJet 1020 macOS Application

A fully **self-contained macOS Electron application** providing a seamless **one-click installation and printing experience** for the HP LaserJet 1020 connected over USB (`USB VID 03f0`, `PID 2b17`).

---

## 🚀 One-App Installation Experience

The application requires **NO manual Terminal commands**, **NO Homebrew**, **NO wget/curl**, **NO manual archive extraction**, and **NO manual CUPS configuration**.

```text
Download HP LaserJet 1020 DMG
         ↓
Install / Open App
         ↓
Click "Set Up Printer"
         ↓
Connect HP LaserJet 1020
         ↓
Select PDF & Print!
```

---

## 📦 Dependency Inventory & Strategy

All technical components, binaries, firmware files, and conversion tools are bundled directly inside the application resources (`Contents/Resources/bundled_resources/`):

| Component | Packaging Strategy | Description / Technical Rationale |
|---|---|---|
| **HP 1020 USB Utility (`hp1020_usb`)** | Bundled Binary | Compiled native C executable statically linked against `libusb`. Talks directly to USB bulk OUT endpoint `03f0:2b17`. |
| **Firmware (`sihp1020.dl`)** | Bundled File | Pre-converted ARM firmware from `upstream/sihp1020.img` using `arm2hpdl`. Stored in app bundle; uploaded to printer RAM on demand. |
| **foo2zjs Converter Suite** | Bundled Binaries | `foo2zjs`, `foo2zjs-pstops`, `arm2hpdl`, and `foo2zjs-wrapper` compiled from source and bundled into app resources. |
| **Ghostscript Engine (`gs`)** | Bundled Executable + Dylibs | Fully self-contained Ghostscript binary bundled along with its required open-source dynamic libraries (`.dylib`) and resource files. No Homebrew or internet required. |
| **Print Pipeline (`print-pipeline.sh`)** | Bundled Script | Orchestrates document transformation: PDF → Ghostscript → ZjStream → `hp1020_usb --send`. |
| **Electron Manager Suite** | App Core | `InstallationManager` state machine and `PrintManager` running safely in Electron main process with real-time progress callbacks. |

---

## 🛠 Features & Capabilities

- **Zero External Dependencies**: Works out-of-the-box on fresh macOS installations without Homebrew, Terminal, or internet connectivity.
- **Automated USB Detection**: Auto-detects device status (`03f0:2b17`) and checks for loaded firmware (`FWVER`).
- **Resumable State Machine**: Manages state transitions (`NOT_STARTED` → `CHECKING` → `INSTALLING` → `CONFIGURING` → `READY` / `FAILED`) with idempotent retry capabilities.
- **Actionable Error Handling**: Human-readable error descriptions and step-by-step guidance for USB unplugged, power-off, and security permissions.
- **Modern UI**: Dark-mode glassmorphism interface, progress indicators, drag-and-drop PDF dropzone, copy counter (1-99), and live technical logs.

---

## 🏗 Building & Packaging

### Prerequisites for Developer Build

- macOS (Apple Silicon or Intel)
- Node.js (v18+) & npm
- Xcode Command Line Tools (`clang`, `make`)
- Homebrew packages for the native build and the print pipeline: Ghostscript, libusb, and GNU sed (`gsed`)

```sh
brew install ghostscript libusb gnu-sed
```

Without `gsed`, rasterizing fails. The app reports that error and does not send the document to the printer.

### Build Steps

1. **Clone repository with submodules**:
   ```sh
   git clone --recurse-submodules <repo_url>
   cd revive_1020
   ```

2. **Install Node dependencies**:
   ```sh
   npm install
   ```

3. **Build Native Resources & Binaries**:
   ```sh
   npm run build:resources
   ```
   This compiles native C binaries (`hp1020_usb`, `foo2zjs`, `arm2hpdl`), generates the printer firmware (`sihp1020.dl`), and bundles Ghostscript + dynamic libraries into `bundled_resources/`.

4. **Run in Development**:
   ```sh
   npm run dev
   ```

5. **Package macOS App Bundle**:
   ```sh
   npm run pack
   ```
   Outputs packaged `.app` to `dist/mac-arm64/HP LaserJet 1020.app`.

6. **Build Standalone DMG Installer**:
   ```sh
   npm run dist
   ```
   Outputs standalone installer DMG to `dist/HP LaserJet 1020-1.0.0-arm64.dmg`.

---

## 📄 License & Attribution

- **foo2zjs**: GPLv2 License (Rick Richardson)
- **Ghostscript**: AGPL / GPL License
- **libusb**: LGPL 2.1 License
