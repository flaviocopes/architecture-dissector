#!/usr/bin/env swift
// Renders the Blueprint app icon into Blueprint/AppIcon.icon, an Icon Composer bundle.
// Three node cards joined by connections, on a blueprint grid, with an amber badge on the
// card that changed. Layers are flat 1024pt PNGs: macOS adds the Liquid Glass, and Xcode
// derives the icons for older macOS releases from the same bundle.
// Usage: swift scripts/render-icon.swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let cardSize = CGSize(width: 276, height: 156)
let cardRadius: CGFloat = 46
let cardOrigins = [CGPoint(x: 148, y: 228), CGPoint(x: 148, y: 640), CGPoint(x: 590, y: 434)]
let edgeWidth: CGFloat = 30
let edgeSpread: CGFloat = 34
let tileSize: CGFloat = 64
let tileRadius: CGFloat = 18
let tileInset: CGFloat = 30
let barSize = CGSize(width: 112, height: 26)
let badgeRadius: CGFloat = 50
let gridSpacing: CGFloat = 64
let gridWidth: CGFloat = 3

let backgroundTop: UInt32 = 0x2F63EC
let backgroundBottom: UInt32 = 0x0B2378
let darkBackgroundTop: UInt32 = 0x132A66
let darkBackgroundBottom: UInt32 = 0x050C2B
let cardColor: UInt32 = 0xFFFFFF
let detailColor: UInt32 = 0x3B6FF0
let badgeColor: UInt32 = 0xFFB020
let gridColor: UInt32 = 0xFFFFFF

func rgb(_ hex: UInt32) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
  (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}

func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  let color = rgb(hex)
  return CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha)
}

func iconColor(_ hex: UInt32) -> String {
  let color = rgb(hex)
  return "\"extended-srgb:" + [color.red, color.green, color.blue, 1].map { String(format: "%.5f", $0) }.joined(separator: ",") + "\""
}

func layer(_ draw: (CGContext) -> Void) -> CGImage {
  let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: 0, y: canvas)
  context.scaleBy(x: 1, y: -1)
  draw(context)
  return context.makeImage()!
}

func card(_ index: Int) -> CGRect { CGRect(origin: cardOrigins[index], size: cardSize) }

let grid = layer { context in
  context.setStrokeColor(cgColor(gridColor))
  context.setLineWidth(gridWidth)
  var position = gridSpacing / 2
  while position < canvas {
    context.move(to: CGPoint(x: position, y: 0))
    context.addLine(to: CGPoint(x: position, y: canvas))
    context.move(to: CGPoint(x: 0, y: position))
    context.addLine(to: CGPoint(x: canvas, y: position))
    position += gridSpacing
  }
  context.strokePath()
}

// Two curves from the left cards into the right one, arriving a little apart.
let edges = layer { context in
  context.setStrokeColor(cgColor(cardColor))
  context.setLineWidth(edgeWidth)
  context.setLineCap(.round)
  let target = card(2)
  for (index, offset) in [(0, -edgeSpread), (1, edgeSpread)] {
    let source = card(index)
    let start = CGPoint(x: source.maxX - 10, y: source.midY)
    let end = CGPoint(x: target.minX + 10, y: target.midY + offset)
    let bend = (end.x - start.x) * 0.55
    context.move(to: start)
    context.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y), control2: CGPoint(x: end.x - bend, y: end.y))
  }
  context.strokePath()
}

let cards = layer { context in
  context.setFillColor(cgColor(cardColor))
  for index in cardOrigins.indices {
    context.addPath(CGPath(roundedRect: card(index), cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil))
  }
  context.fillPath()
}

// An icon tile and a line of text on each card, like the cards in the app.
let details = layer { context in
  context.setFillColor(cgColor(detailColor))
  for index in cardOrigins.indices {
    let frame = card(index)
    let tile = CGRect(x: frame.minX + tileInset, y: frame.midY - tileSize / 2, width: tileSize, height: tileSize)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil))
    let bar = CGRect(x: tile.maxX + 24, y: frame.midY - barSize.height / 2, width: barSize.width, height: barSize.height)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: barSize.height / 2, cornerHeight: barSize.height / 2, transform: nil))
  }
  context.fillPath()
}

let badge = layer { context in
  let frame = card(2)
  let center = CGPoint(x: frame.maxX - 26, y: frame.minY + 8)
  context.setFillColor(cgColor(badgeColor))
  context.fillEllipse(in: CGRect(x: center.x - badgeRadius, y: center.y - badgeRadius, width: 2 * badgeRadius, height: 2 * badgeRadius))
}

let manifest = """
{
  "fill-specializations" : [
    { "value" : { "linear-gradient" : [\(iconColor(backgroundTop)), \(iconColor(backgroundBottom))] } },
    { "appearance" : "dark", "value" : { "linear-gradient" : [\(iconColor(darkBackgroundTop)), \(iconColor(darkBackgroundBottom))] } }
  ],
  "groups" : [
    {
      "name" : "Badge",
      "layers" : [
        { "name" : "Badge", "image-name" : "badge.png", "glass" : true }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.2 }
    },
    {
      "name" : "Graph",
      "layers" : [
        { "name" : "Details", "image-name" : "details.png", "glass" : true, "opacity" : 0.9 },
        { "name" : "Cards", "image-name" : "cards.png", "glass" : true },
        { "name" : "Edges", "image-name" : "edges.png", "glass" : true, "opacity" : 0.85 }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.3 }
    },
    {
      "name" : "Grid",
      "layers" : [
        { "name" : "Grid", "image-name" : "grid.png", "glass" : false, "opacity" : 0.1 }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false
    }
  ],
  "supported-platforms" : {
    "squares" : ["macOS"]
  }
}

"""

func write(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  CGImageDestinationFinalize(destination)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("Blueprint/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: bundle)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
write(grid, to: assets.appendingPathComponent("grid.png"))
write(edges, to: assets.appendingPathComponent("edges.png"))
write(cards, to: assets.appendingPathComponent("cards.png"))
write(details, to: assets.appendingPathComponent("details.png"))
write(badge, to: assets.appendingPathComponent("badge.png"))
try! manifest.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(bundle.path)")
