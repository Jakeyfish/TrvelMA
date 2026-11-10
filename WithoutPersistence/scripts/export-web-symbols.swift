import AppKit
import Foundation

// Export the same system-symbol shapes used by the App as alpha masks. The
// browser supplies currentColor, so selection/tint does not require extra PNGs.
let names = [
    "house.fill", "books.vertical", "person.text.rectangle.fill", "wallet.bifold.fill",
    "person.crop.rectangle.badge.plus.fill", "building.2.fill", "gearshape.fill",
    "airplane", "airplane.arrival", "airplane.departure", "car.fill", "clock.fill",
    "figure.wave", "ellipsis.circle.fill", "checkmark.circle.fill", "checkmark",
    "book.closed", "location.north.fill", "arrow.triangle.turn.up.right.diamond.fill",
    "arrow.up.arrow.down", "mappin.and.ellipse", "mappin", "flag.checkered",
    "person.fill", "suitcase.fill", "calendar", "magnifyingglass", "plus", "plus.circle",
    "minus.circle.fill", "xmark", "chevron.right", "chevron.down", "chevron.up", "chevron.left",
    "arrow.clockwise", "chart.pie.fill", "list.bullet.rectangle", "qrcode", "qrcode.viewfinder",
    "trash", "arrow.down.left", "arrow.up.right", "person.2", "tray.full", "t.square",
    "dollarsign.circle", "checkmark.circle", "bell.badge", "questionmark.circle", "eye", "eye.slash", "phone.fill", "message.fill"
]
guard CommandLine.arguments.count == 2 else { fatalError("Usage: export-web-symbols.swift OUTPUT_DIRECTORY") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for name in names {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(.init(pointSize: 24, weight: .regular)),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Missing symbol: \(name)") }
    bitmap.size = NSSize(width: 32, height: 32)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: 3, y: 3)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 32, height: 32).fill(using: .copy)
    let size = symbol.size
    symbol.draw(in: NSRect(x: (32 - size.width) / 2, y: (32 - size.height) / 2,
                          width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode \(name)") }
    try data.write(to: output.appendingPathComponent(name.replacingOccurrences(of: ".", with: "-") + ".png"))
}
let manifest = ["symbols": names, "canvas_points": [32, 32], "pixels": [96, 96]] as [String : Any]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("manifest.json"))
print("Exported \(names.count) App symbol masks")
