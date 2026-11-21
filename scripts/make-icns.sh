#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_PNG="${1:-$REPO_DIR/assets/logo.png}"
OUT_ICNS="${2:-$REPO_DIR/build/AppIcon.icns}"

if [[ ! -f "$SRC_PNG" ]]; then
    echo "Error: Source icon PNG not found at $SRC_PNG" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/padwake-icns.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$(dirname "$OUT_ICNS")"

cat > "$TMP_DIR/gen_icns.swift" <<'SWIFT'
import Cocoa
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: gen_icns <src.png> <out.icns>\n", stderr)
    exit(1)
}

guard let srcImg = NSImage(contentsOfFile: args[1]),
      let cgSrc = srcImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Failed to load source image\n", stderr)
    exit(1)
}

let w = cgSrc.width
let h = cgSrc.height
let insetX = Int(Double(w) * 0.178)
let insetY = Int(Double(h) * 0.178)
let cropRect = CGRect(x: insetX, y: insetY, width: w - 2 * insetX, height: h - 2 * insetY)
guard let cropped = cgSrc.cropping(to: cropRect) else {
    fputs("Failed to crop source image\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func renderPNG(px: Int, dpi: Double) -> Data {
    let size = CGFloat(px)
    let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let iconSize = size * (824.0 / 1024.0)
    let origin = (size - iconSize) / 2.0
    let iconRect = CGRect(x: origin, y: origin, width: iconSize, height: iconSize)
    let radius = iconSize * 0.2237
    let path = CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Subtle Apple HIG drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * (16.0 / 1024.0)),
        blur: size * (30.0 / 1024.0),
        color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.28])
    )
    ctx.addPath(path)
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.12, 0.14, 0.22, 1.0])!)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip cleanly to squircle and draw cropped logo
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: iconRect)
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi
    ]
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        fputs("Failed to encode PNG \(px)px\n", stderr)
        exit(1)
    }
    return data as Data
}

func appendUInt32BE(_ data: inout Data, _ val: UInt32) {
    var be = val.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

// Standard Apple .icns PNG OSType entries (16x16 through 512x512@2x)
let specs: [(String, Int, Double)] = [
    ("icp4",   16,  72),
    ("ic11",   32, 144),
    ("icp5",   32,  72),
    ("ic12",   64, 144),
    ("ic07",  128,  72),
    ("ic13",  256, 144),
    ("ic08",  256,  72),
    ("ic14",  512, 144),
    ("ic09",  512,  72),
    ("ic10", 1024, 144)
]

var body = Data()
for (ostype, px, dpi) in specs {
    let png = renderPNG(px: px, dpi: dpi)
    body.append(contentsOf: ostype.utf8)
    appendUInt32BE(&body, UInt32(8 + png.count))
    body.append(png)
}

var icns = Data()
icns.append(contentsOf: "icns".utf8)
appendUInt32BE(&icns, UInt32(8 + body.count))
icns.append(body)

try icns.write(to: URL(fileURLWithPath: args[2]))
SWIFT

mkdir -p "$TMP_DIR/module-cache"
swiftc -module-cache-path "$TMP_DIR/module-cache" -framework Cocoa -framework ImageIO "$TMP_DIR/gen_icns.swift" -o "$TMP_DIR/gen_icns"
"$TMP_DIR/gen_icns" "$SRC_PNG" "$OUT_ICNS"
echo "[icon] Built $OUT_ICNS"
