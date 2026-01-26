#!/usr/bin/env swift
// Renders the Chiptune Maker app icon at 1024×1024.
// Usage: xcrun swift Scripts/make-icon.swift <output.png>

import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("Could not create a drawing context.\n".utf8))
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let iconRect = CGRect(x: 40, y: 40, width: size - 80, height: size - 80)
let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 210, cornerHeight: 210, transform: nil)

context.saveGState()
context.addPath(iconPath)
context.clip()

// Deep navy-to-violet background.
let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [
                                NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.13, alpha: 1).cgColor,
                                NSColor(calibratedRed: 0.12, green: 0.04, blue: 0.25, alpha: 1).cgColor
                            ] as CFArray,
                            locations: [0.0, 1.0])!
context.drawLinearGradient(background,
                           start: CGPoint(x: size / 2, y: size),
                           end: CGPoint(x: size / 2, y: 0),
                           options: [])

// Sequencer grid.
context.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.0, alpha: 0.10).cgColor)
context.setLineWidth(3)
let gridInset: CGFloat = 120
let gridStep: CGFloat = 98
for i in 0...8 {
    let offset = gridInset + CGFloat(i) * gridStep
    context.move(to: CGPoint(x: offset, y: iconRect.minY + 40))
    context.addLine(to: CGPoint(x: offset, y: iconRect.maxY - 40))
    context.move(to: CGPoint(x: iconRect.minX + 40, y: offset))
    context.addLine(to: CGPoint(x: iconRect.maxX - 40, y: offset))
}
context.strokePath()

// Step-sequencer cells along the bottom.
let cellCount = 8
let cellSize: CGFloat = 66
let cellGap: CGFloat = 22
let totalWidth = CGFloat(cellCount) * cellSize + CGFloat(cellCount - 1) * cellGap
let cellStartX = (size - totalWidth) / 2
let cellY: CGFloat = 176
let lit: [Bool] = [true, false, true, true, false, true, false, true]
for index in 0..<cellCount {
    let rect = CGRect(x: cellStartX + CGFloat(index) * (cellSize + cellGap),
                      y: cellY,
                      width: cellSize,
                      height: cellSize)
    let path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    context.addPath(path)
    if lit[index] {
        let color = index % 2 == 0
            ? NSColor(calibratedRed: 0.15, green: 0.85, blue: 1.0, alpha: 1.0)
            : NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.70, alpha: 1.0)
        context.setFillColor(color.cgColor)
    } else {
        context.setFillColor(NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.45, alpha: 0.55).cgColor)
    }
    context.fillPath()
}

// Cyan pulse wave.
let wavePoints: [CGPoint] = [
    CGPoint(x: 150, y: 440), CGPoint(x: 270, y: 440),
    CGPoint(x: 270, y: 640), CGPoint(x: 410, y: 640),
    CGPoint(x: 410, y: 440), CGPoint(x: 550, y: 440),
    CGPoint(x: 550, y: 640), CGPoint(x: 690, y: 640),
    CGPoint(x: 690, y: 440), CGPoint(x: 874, y: 440)
]
let wave = CGMutablePath()
wave.addLines(between: wavePoints)

context.saveGState()
context.setShadow(offset: .zero,
                  blur: 42,
                  color: NSColor(calibratedRed: 0.10, green: 0.80, blue: 1.0, alpha: 0.85).cgColor)
context.addPath(wave)
context.setStrokeColor(NSColor(calibratedRed: 0.25, green: 0.90, blue: 1.0, alpha: 1.0).cgColor)
context.setLineWidth(46)
context.setLineJoin(.miter)
context.setLineCap(.square)
context.strokePath()
context.restoreGState()

// Magenta echo wave.
context.saveGState()
context.setShadow(offset: .zero,
                  blur: 24,
                  color: NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.65, alpha: 0.65).cgColor)
let echoPoints: [CGPoint] = [
    CGPoint(x: 150, y: 340), CGPoint(x: 310, y: 340),
    CGPoint(x: 310, y: 520), CGPoint(x: 470, y: 520),
    CGPoint(x: 470, y: 340), CGPoint(x: 630, y: 340),
    CGPoint(x: 630, y: 520), CGPoint(x: 790, y: 520),
    CGPoint(x: 790, y: 340), CGPoint(x: 874, y: 340)
]
let echo = CGMutablePath()
echo.addLines(between: echoPoints)
context.addPath(echo)
context.setStrokeColor(NSColor(calibratedRed: 1.0, green: 0.30, blue: 0.72, alpha: 0.9).cgColor)
context.setLineWidth(18)
context.setLineJoin(.miter)
context.setLineCap(.square)
context.strokePath()
context.restoreGState()

// A few floating pixels.
let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
    (184, 780, 20), (840, 760, 14), (820, 600, 10), (196, 590, 10)
]
for (x, y, side) in sparkles {
    context.setFillColor(NSColor(calibratedRed: 0.85, green: 0.95, blue: 1.0, alpha: 0.85).cgColor)
    context.fill(CGRect(x: x, y: y, width: side, height: side))
}

context.restoreGState()

// Subtle inner border.
context.addPath(iconPath)
context.setStrokeColor(NSColor(calibratedRed: 0.45, green: 0.65, blue: 1.0, alpha: 0.35).cgColor)
context.setLineWidth(5)
context.strokePath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode the icon.\n".utf8))
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath) (\(png.count) bytes)")
} catch {
    FileHandle.standardError.write(Data("Could not write \(outputPath): \(error)\n".utf8))
    exit(1)
}
