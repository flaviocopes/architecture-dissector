#!/usr/bin/env swift
// Renders the README banner, docs/banner.png, at 2x: the icon, the name, a tagline and
// feature chips on the left, the real window on the right.
// The background is the icon's blue under a blueprint grid.
// An .icon is rendered through Icon Composer's ictool, so it has the real Liquid Glass.
// The window is docs/screenshot-dark.png, made by scripts/screenshot.sh.
// Usage: swift scripts/render-banner.swift

import AppKit
import SwiftUI

let name = "Blueprint"
let tagline = "See how your apps are built,\nand how they change."
let chips = ["Architecture", "Every workflow", "Data and explainers"]
let size = CGSize(width: 1280, height: 560)
// Where the window's top-left corner sits, and how much it's scaled down.
let windowOrigin = CGPoint(x: 600, y: 92)
let windowScale: CGFloat = 0.62

// Take these from the app icon's background, a bit deeper.
let backgroundTop = Color(hex: 0x2152D6)
let backgroundBottom = Color(hex: 0x081A5C)
let glow = Color(hex: 0x5B8CFF)
let muted = Color.white.opacity(0.72)

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSource = root.appending(path: "\(name)/AppIcon.icon")
let screenshot = root.appending(path: "docs/screenshot-dark.png")
let output = root.appending(path: "docs/banner.png")
// scripts/screenshot.sh leaves a 48pt margin around the window for its shadow.
let shadowMargin: CGFloat = 48

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

func run(_ tool: String, _ arguments: [String]) -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(filePath: tool)
  process.arguments = arguments
  process.standardOutput = pipe
  try! process.run()
  process.waitUntilExit()
  return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

// A PNG icon is used as is. It should already have the squircle and its padding.
func renderIcon() -> NSImage {
  guard iconSource.pathExtension == "icon" else { return NSImage(contentsOf: iconSource)! }
  let developer = run("/usr/bin/xcode-select", ["-p"])
  let ictool = URL(filePath: developer).deletingLastPathComponent()
    .appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool").path
  let file = FileManager.default.temporaryDirectory.appending(path: "\(name)-banner-icon.png")
  _ = run(ictool, [
    iconSource.path, "--export-image", "--output-file", file.path, "--platform", "macOS",
    "--rendition", "Default", "--width", "512", "--height", "512", "--scale", "2",
  ])
  return NSImage(contentsOf: file)!
}

/// The blueprint grid: fine lines every 24pt and stronger ones every 120pt, like the app's canvas.
struct Grid: View {
  var body: some View {
    Canvas { context, canvasSize in
      for (step, alpha) in [(CGFloat(24), 0.06), (120, 0.11)] {
        var path = Path()
        for x in stride(from: CGFloat(0), through: canvasSize.width, by: step) {
          path.move(to: CGPoint(x: x, y: 0))
          path.addLine(to: CGPoint(x: x, y: canvasSize.height))
        }
        for y in stride(from: CGFloat(0), through: canvasSize.height, by: step) {
          path.move(to: CGPoint(x: 0, y: y))
          path.addLine(to: CGPoint(x: canvasSize.width, y: y))
        }
        context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1)
      }
    }
  }
}

struct Banner: View {
  let icon: NSImage
  let window: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [glow.opacity(0.45), glow.opacity(0)], center: UnitPoint(x: 0.16, y: 0.36), startRadius: 0, endRadius: 420)
      Grid()

      // The screenshot is 2x, so its size in points is half its pixels.
      Image(nsImage: window)
        .resizable()
        .interpolation(.high)
        .frame(width: CGFloat(window.representations[0].pixelsWide) / 2 * windowScale, height: CGFloat(window.representations[0].pixelsHigh) / 2 * windowScale)
        .offset(x: windowOrigin.x - shadowMargin * windowScale, y: windowOrigin.y - shadowMargin * windowScale)

      VStack(alignment: .leading, spacing: 0) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 132, height: 132)
          .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        Text(name)
          .font(.system(size: 76, weight: .bold))
          .tracking(-1.8)
          .foregroundStyle(.white)
          .padding(.top, 26)
        Text(tagline)
          .font(.system(size: 27, weight: .regular))
          .lineSpacing(4)
          .foregroundStyle(muted)
          .padding(.top, 8)
        HStack(spacing: 10) {
          ForEach(chips, id: \.self) { chip in
            Text(chip)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white.opacity(0.9))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(.white.opacity(0.1), in: .capsule)
              .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
          }
        }
        .padding(.top, 26)
      }
      .offset(x: 84, y: 78)
    }
    // The window runs past the right and bottom edges, so pin the layout to the top left.
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .clipShape(.rect(cornerRadius: 28))
  }
}

MainActor.assumeIsolated {
  let renderer = ImageRenderer(content: Banner(icon: renderIcon(), window: NSImage(contentsOf: screenshot)!))
  renderer.scale = 2
  // ImageRenderer produces 16 bits per channel. Redraw at 8 bits for a small PNG.
  let image = renderer.cgImage!
  let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: output)
  print("Wrote \(output.path)")
}
