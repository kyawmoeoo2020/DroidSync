# KMO DroidSync

**KMO DroidSync** is a high-performance, native macOS application designed to connect and manage Android devices with zero friction. Built with **SwiftUI** for macOS 14+, it replaces outdated and bloated tools like Android File Transfer, OpenMTP, and MacDroid with a lightweight, native, and responsive experience.

---

## ✨ Features

- **⚡️ 100% Native macOS (SwiftUI)**: Featherweight (~1.7 MB binary, <20 MB RAM), instant startup, dark mode & macOS Sonoma/Sequoia design language.
- **📱 Real-time Dashboard**:
  - Live battery health gauge, temperature, and charging status.
  - Storage breakdown meter (used vs. free space).
  - Hardware specs and OS version detection.
- **📁 High-Speed File Explorer**:
  - Breadcrumb navigation (`Internal Storage > DCIM > Camera`).
  - Search filter.
  - Two-way drag-and-drop directly with macOS Finder.
  - Multi-file download and upload.
  - Folder creation and file deletion.
- **👁 Quick Look (Spacebar Preview)**:
  - Preview images, text, and documents directly on the phone without copying them to your Mac first.
- **📦 App Manager & Installer**:
  - View installed third-party apps and packages.
  - Drag and drop `.apk` files directly into the window to install them.
  - 1-click uninstaller.
- **📊 Storage Lens**:
  - Instant directory size analyzer (`du -k`) to find space-hogging folders.
- **📶 Wireless ADB Pairing**:
  - Complete wire-free management over local Wi-Fi.
  - Built-in pairing wizard for Android 11+ Wireless Debugging.
- **🚀 Background Transfer Queue**:
  - Real-time transfer speed (MB/s), progress bar, and queue history.

---

## 🛠 Tech Stack

- **Language**: Swift 6
- **UI Framework**: SwiftUI + AppKit (macOS 14+)
- **Build System**: Swift Package Manager (SPM)
- **Protocol**: Android Debug Bridge (ADB) via USB and Wi-Fi

---

## 🚀 Getting Started

### 1. Launch the Built App
The release bundle is ready inside `build/`:
```bash
open "/Users/kmo/.gemini/antigravity/scratch/kmo-droidsync/build/KMO DroidSync.app"
```

### 2. Run Directly via Terminal
```bash
cd /Users/kmo/.gemini/antigravity/scratch/kmo-droidsync
swift run KMODroidSync
```

### 3. Open in Xcode
To edit, preview SwiftUI components, or build with Xcode:
```bash
open /Users/kmo/.gemini/antigravity/scratch/kmo-droidsync/Package.swift
```

---

## 📱 Connecting Your Phone

1. On your Android phone, enable **Developer Options** (tap `Build number` 7 times in Settings > About phone).
2. Turn on **USB Debugging** (or **Wireless debugging**).
3. Connect your phone to your Mac via USB cable or use the **Wireless Pairing** tab.
4. When prompted on your phone, tap **"Always allow from this computer"**.
