# Redacción Local

A native Mac app that redacts personal data from Mexican legal documents. Analysis stays on the device: RFC, CURP, CLABE, names, companies, addresses, and other identifiers. Nothing is uploaded.

**Requires macOS 14 or later.** Names and addresses are richer on macOS 26 with Apple Intelligence.

## Install

Apple will not let a downloaded `.app` open with a double-click unless it is signed and notarized with a paid Developer ID. There is no free way around that Finder warning.

The free option is to install from Terminal. That removes the quarantine flag macOS attaches to GitHub downloads, which is what triggers the malware dialog:

```bash
curl -fsSL https://raw.githubusercontent.com/drax10/local-redaction/main/install.sh | sh
```

That puts **LocalRedaction** in `/Applications` and opens it. Run it once; afterward, double-click works.

If you already downloaded the zip and dragged the app to Applications, only the quarantine step is needed:

```bash
xattr -dr com.apple.quarantine /Applications/LocalRedaction.app
open /Applications/LocalRedaction.app
```

Building from source on the same Mac (below) also avoids the warning, because Gatekeeper only treats internet downloads this way.

[Zip download](https://github.com/drax10/local-redaction/releases/latest/download/RedaccionLocal.zip) if you prefer to install by hand: unzip, drag to Applications, then run the `xattr` command above. **System Settings → Privacy & Security → Open Anyway** is Apple’s GUI equivalent; Control-click → Open no longer works on macOS 15+.

## Use

1. Drop in a PDF, Word (`.doc` / `.docx`), or `.txt` file. Scanned PDFs are read with on-device OCR; nothing is uploaded.
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
- Scanned PDFs use Apple Vision OCR on the device.
- No network calls for extraction.
