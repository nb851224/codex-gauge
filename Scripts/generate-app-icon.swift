import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func iconImage(size: Int) throws -> CGImage {
    let dimension = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    let tileInset = dimension * 0.055
    let tileRect = CGRect(
        x: tileInset,
        y: tileInset,
        width: dimension - 2 * tileInset,
        height: dimension - 2 * tileInset
    )
    let tile = CGPath(
        roundedRect: tileRect,
        cornerWidth: dimension * 0.215,
        cornerHeight: dimension * 0.215,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -dimension * 0.025),
        blur: dimension * 0.045,
        color: color(3, 9, 20, alpha: 0.42)
    )
    context.addPath(tile)
    context.setFillColor(color(20, 34, 58))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(51, 132, 255), color(72, 72, 214)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
        options: []
    )
    context.restoreGState()

    let center = CGPoint(x: dimension / 2, y: dimension / 2)
    let sectorRadius = dimension * 0.205
    context.beginPath()
    context.move(to: center)
    context.addArc(
        center: center,
        radius: sectorRadius,
        startAngle: .pi / 2,
        endAngle: -.pi * 0.51,
        clockwise: true
    )
    context.closePath()
    context.setFillColor(color(255, 255, 255, alpha: 0.24))
    context.fillPath()

    let radius = dimension * 0.292
    let lineWidth = max(1.5, dimension * 0.054)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(color(255, 255, 255, alpha: 0.20))
    context.strokeEllipse(in: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))

    context.beginPath()
    context.addArc(
        center: center,
        radius: radius,
        startAngle: .pi / 2,
        endAngle: -.pi * 1.07,
        clockwise: true
    )
    context.setLineCap(.round)
    context.setStrokeColor(color(255, 255, 255))
    context.strokePath()

    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return image
}

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.icns.identifier as CFString,
    sizes.count,
    nil
) else { throw CocoaError(.fileWriteUnknown) }
for size in sizes {
    CGImageDestinationAddImage(destination, try iconImage(size: size), nil)
}
guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
