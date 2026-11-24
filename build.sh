#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/TouchBarTicker.app"
INSTALL_PATH="/Applications/TouchBarTicker.app"
BUNDLE_ID="com.touchbarticker.app"

quit_running_app() {
    if pgrep -x "TouchBarTicker" >/dev/null 2>&1; then
        osascript -e 'tell application "TouchBarTicker" to quit' >/dev/null 2>&1 || true
        sleep 0.5
        pkill -x "TouchBarTicker" >/dev/null 2>&1 || true
    fi
}

case "${1:-}" in
    --uninstall)
        echo "Uninstalling TouchBarTicker..."
        quit_running_app

        if [[ -d "$INSTALL_PATH" ]]; then
            rm -rf "$INSTALL_PATH"
            echo "Removed $INSTALL_PATH"
        else
            echo "$INSTALL_PATH was not installed."
        fi

        defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        echo "Cleared saved preferences."
        echo "Uninstalled TouchBarTicker."
        exit 0
        ;;
    --update)
        echo "Updating TouchBarTicker..."
        quit_running_app

        if [[ -d "$INSTALL_PATH" ]]; then
            rm -rf "$INSTALL_PATH"
            echo "Removed current version at $INSTALL_PATH"
        fi

        echo "Pulling latest changes..."
        git -C "$ROOT_DIR" pull

        # Re-exec build.sh so any updates to build.sh itself are used for the reinstall
        exec "$ROOT_DIR/build.sh" --install
        ;;
    ""|--install)
        ;;
    -h|--help)
        echo "Usage: ./build.sh [--install | --update | --uninstall]"
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: ./build.sh [--install | --update | --uninstall]" >&2
        exit 1
        ;;
esac

CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building TouchBarTicker..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Compile Swift sources into native binary
export TMPDIR="/tmp"
export CLANG_MODULE_CACHE_PATH="/tmp/touchbarticker-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swiftc \
    -O \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    -Xcc "-fmodules-cache-path=$CLANG_MODULE_CACHE_PATH" \
    -F /System/Library/PrivateFrameworks \
    -framework AppKit \
    -framework QuartzCore \
    -framework DFRFoundation \
    -import-objc-header "$ROOT_DIR/Sources/BridgingHeader.h" \
    "$ROOT_DIR/Sources/Feeds.swift" \
    "$ROOT_DIR/Sources/QuoteService.swift" \
    "$ROOT_DIR/Sources/TickerTouchBarView.swift" \
    "$ROOT_DIR/Sources/SettingsTouchBarView.swift" \
    "$ROOT_DIR/Sources/AppDelegate.swift" \
    "$ROOT_DIR/Sources/main.swift" \
    -o "$MACOS_DIR/TouchBarTicker"

# Copy Info.plist
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Generate a clean native app icon (.icns) directly in Swift
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" -Xcc "-fmodules-cache-path=$CLANG_MODULE_CACHE_PATH" - "$RESOURCES_DIR/AppIcon.icns" <<'EOF'
import AppKit

let outPath = CommandLine.arguments[1]

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius = bgRect.width * 0.22
    let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0),
        ending: NSColor(srgbRed: 0.03, green: 0.04, blue: 0.05, alpha: 1.0)
    )
    gradient?.draw(in: path, angle: -90)

    NSColor(white: 1.0, alpha: 0.12).setStroke()
    path.lineWidth = max(1, size * 0.015)
    path.stroke()

    if let symbol = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [
                NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)
            ]))
        if let styled = symbol.withSymbolConfiguration(config) {
            let symSize = styled.size
            let drawRect = NSRect(
                x: (size - symSize.width) / 2,
                y: (size - symSize.height) / 2,
                width: symSize.width,
                height: symSize.height
            )
            styled.draw(in: drawRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// ICNS PNG chunk types: (fourCC, pixelSize)
let entries: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("ic11", 32),
    ("ic12", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic13", 256),
    ("ic09", 512),
    ("ic14", 512),
    ("ic10", 1024)
]

var body = Data()
for (fourCC, px) in entries {
    if let png = renderIcon(pixelSize: px) {
        body.append(contentsOf: fourCC.utf8)
        var chunkLen = UInt32(8 + png.count).bigEndian
        body.append(Data(bytes: &chunkLen, count: 4))
        body.append(png)
    }
}

var icns = Data("icns".utf8)
var totalLen = UInt32(8 + body.count).bigEndian
icns.append(Data(bytes: &totalLen, count: 4))
icns.append(body)
try icns.write(to: URL(fileURLWithPath: outPath))
EOF

# Ad-hoc sign so macOS launches cleanly
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Built: $APP_BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installing to $INSTALL_PATH..."

    # Cleanly quit any running instance before replacing the bundle
    quit_running_app

    rm -rf "$INSTALL_PATH"
    ditto "$APP_BUNDLE" "$INSTALL_PATH"
    xattr -dr com.apple.quarantine "$INSTALL_PATH" >/dev/null 2>&1 || true

    # Refresh LaunchServices so Finder and Spotlight pick up updates immediately
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -f "$INSTALL_PATH" >/dev/null 2>&1 || true
    fi

    echo "Installed! Open TouchBarTicker from Applications or Spotlight."
fi
