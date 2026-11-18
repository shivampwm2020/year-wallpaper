import AppKit
import CoreText

// A year in pixels: 365 cells on black, one per day, filled white as the year
// passes. Rows are months (January at the top), columns are days, and short
// months leave their row ragged rather than padding with fake days.
//
//   YearWallpaper                     set the desktop picture on every display
//   YearWallpaper --preview OUT.png   render 3840x2160 to OUT.png and exit
//   YearWallpaper --preview OUT.png --size 1920x1080

private let targetWidthFraction: CGFloat = 0.9
private let gapFraction: CGFloat = 0.22

/// Draws a quiet label in the top margin. y is the text baseline, in the
/// same y-up space as the grid.
private func drawLabel(_ text: String, baselineY: CGFloat, x: CGFloat, rightEdge: CGFloat?,
                       fontSize: CGFloat, context: CGContext) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 0.55)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    context.textPosition = CGPoint(x: rightEdge.map { $0 - width } ?? x, y: baselineY)
    CTLineDraw(line, context)
}

private func renderWallpaper(size: CGSize, date: Date) -> Data? {
    let width = Int(size.width.rounded()), height = Int(size.height.rounded())
    guard width > 0, height > 0,
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        FileHandle.standardError.write(Data("could not create context\n".utf8))
        return nil
    }

    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    let calendar = Calendar.current
    let year = calendar.component(.year, from: date)
    let today = calendar.startOfDay(for: date)

    let monthLengths: [Int] = (1...12).map { month in
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 30 }
        return range.count
    }

    let maxColumns = monthLengths.max() ?? 31
    let gridWidth = size.width * targetWidthFraction
    let cell = gridWidth / (CGFloat(maxColumns) + CGFloat(maxColumns - 1) * gapFraction)
    let gap = cell * gapFraction
    let totalWidth = CGFloat(maxColumns) * cell + CGFloat(maxColumns - 1) * gap
    let totalHeight = 12 * cell + 11 * gap
    let left = (size.width - totalWidth) / 2
    let top = (size.height + totalHeight) / 2

    for (index, count) in monthLengths.enumerated() {
        for day in 1...count {
            guard let dayDate = calendar.date(from: DateComponents(year: year, month: index + 1, day: day)) else { continue }
            let rect = CGRect(x: left + CGFloat(day - 1) * (cell + gap),
                              y: top - CGFloat(index) * (cell + gap) - cell,
                              width: cell, height: cell)
            let path = CGPath(roundedRect: rect,
                              cornerWidth: cell * 0.06, cornerHeight: cell * 0.06, transform: nil)
            if dayDate < today {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
            } else if dayDate == today {
                context.setFillColor(CGColor(gray: 1, alpha: 0.45))
            } else {
                context.setFillColor(CGColor(gray: 0.086, alpha: 1))
            }
            context.addPath(path)
            context.fillPath()
        }
    }

    let daysInYear = monthLengths.reduce(0, +)
    let dayOfYear = calendar.ordinality(of: .day, in: .year, for: today) ?? 1
    let daysLeft = max(0, daysInYear - dayOfYear)
    let labelSize = cell * 0.62
    let baseline = top + cell * 0.85
    drawLabel(String(year), baselineY: baseline, x: left, rightEdge: nil,
              fontSize: labelSize, context: context)
    drawLabel(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left",
              baselineY: baseline, x: left, rightEdge: left + totalWidth,
              fontSize: labelSize, context: context)

    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode png\n".utf8))
        return nil
    }
    return data
}

private func outputDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("YearWallpaper", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func applyWallpaper() {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let stamp = formatter.string(from: Date())
    let directory = outputDirectory()

    for (index, screen) in NSScreen.screens.enumerated() {
        let scale = screen.backingScaleFactor
        let pixels = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        guard let data = renderWallpaper(size: pixels, date: Date()) else { continue }
        let url = directory.appendingPathComponent("wallpaper-\(stamp)-\(index).png")
        try? data.write(to: url)
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue
        ])
    }

    // Keep the last few days so the current file is never deleted out from
    // under a display that is mid-refresh.
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]))?
        .filter { $0.lastPathComponent.hasPrefix("wallpaper-") }
        .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    for old in files.dropFirst(6) {
        try? FileManager.default.removeItem(at: old)
    }
}

private func preview(to path: String, size: CGSize) {
    guard let data = renderWallpaper(size: size, date: Date()) else {
        FileHandle.standardError.write(Data("could not render\n".utf8))
        exit(1)
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let arguments = CommandLine.arguments
if let previewIndex = arguments.firstIndex(of: "--preview"), previewIndex + 1 < arguments.count {
    var size = CGSize(width: 3840, height: 2160)
    if let sizeIndex = arguments.firstIndex(of: "--size"), sizeIndex + 1 < arguments.count {
        let parts = arguments[sizeIndex + 1].lowercased().split(separator: "x")
        if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
            size = CGSize(width: w, height: h)
        }
    }
    preview(to: arguments[previewIndex + 1], size: size)
} else {
    applyWallpaper()
    print("wallpaper updated")
}
