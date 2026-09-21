# Redacción Local

A native Mac app that redacts personal data from Mexican legal documents. Analysis stays on the device: RFC, CURP, CLABE, names, companies, addresses, and other identifiers. Nothing is uploaded.

**Requires macOS 14 or later.** Names and addresses are richer on macOS 26 with Apple Intelligence.

## Install

[**Download for Mac**](https://github.com/drax10/local-redaction/releases/latest/download/RedaccionLocal.zip)

1. Unzip the download.
2. Drag **LocalRedaction** (Finder may show **Redacción Local**) into `/Applications`.
3. Double-click the app. macOS 15 and later will block it with *Apple could not verify “LocalRedaction.app” is free of malware*. Click **Done**. Control-click → Open no longer bypasses this.
4. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to the message that the app was blocked.
5. Confirm **Open Anyway** again and authenticate. After that, double-click works normally.

If **Open Anyway** never appears, clear the download quarantine in Terminal, then open the app again:

```bash
xattr -dr com.apple.quarantine /Applications/LocalRedaction.app
open /Applications/LocalRedaction.app
```

Apple Silicon and Intel Macs are both supported. A one-click install without these steps needs an Apple Developer ID and notarization. If the latest release is missing, use [Releases](https://github.com/drax10/local-redaction/releases) or build from source below.

## Use

1. Drop in a PDF or `.txt` file (the PDF must contain real text, not only a scan).
2. Review the findings table. Click a row to jump to it in the document.
3. Change types or uncheck anything that should stay visible.
4. Copy the tagged text and paste it into another AI. The same person stays `[NOMBRE 1]` throughout, so you can still ask about that party without sending the real name.

## Build from source

You need [Xcode](https://developer.apple.com/xcode/) 16 or later.

```bash
git clone https://github.com/drax10/local-redaction.git
cd local-redaction
open LocalRedaction.xcodeproj
```

Select the **LocalRedaction** scheme, then Run. To regenerate the Xcode project after editing `project.yml`:

```bash
brew install xcodegen
xcodegen generate
```

## Privacy

- App Sandbox; the app only reads files you choose.
- Regex plus on-device Foundation Models (Apple Intelligence) when available, with NLTagger as fallback.
- No network calls for extraction.
