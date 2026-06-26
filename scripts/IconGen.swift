import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let margin = size * 0.085
let rect = CGRect(x: margin, y: margin, width: size - margin*2, height: size - margin*2)
let corner = (size - margin*2) * 0.225
let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

ctx.saveGState()
bgPath.addClip()
let colors = [NSColor(srgbRed: 0.36, green: 0.42, blue: 1.0, alpha: 1).cgColor,
              NSColor(srgbRed: 0.54, green: 0.36, blue: 1.0, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

func rounded(_ r: CGRect, _ rad: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad).fill()
}

let boardW = size * 0.46
let boardH = size * 0.54
let boardX = (size - boardW) / 2
let boardY = (size - boardH) / 2 - size * 0.01
let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size*0.012), blur: size*0.03,
              color: NSColor.black.withAlphaComponent(0.22).cgColor)
rounded(boardRect, size*0.045, NSColor.white)
ctx.restoreGState()

let clipW = boardW * 0.42
let clipH = size * 0.085
let clipRect = CGRect(x: (size - clipW)/2, y: boardY + boardH - clipH*0.55,
                      width: clipW, height: clipH)
rounded(clipRect, clipH*0.34, NSColor(srgbRed: 0.82, green: 0.85, blue: 0.92, alpha: 1))
let clipInner = clipRect.insetBy(dx: clipW*0.16, dy: clipH*0.26)
rounded(clipInner, clipInner.height*0.4, NSColor(srgbRed: 0.36, green: 0.42, blue: 1.0, alpha: 1))

let barColors = [NSColor(srgbRed: 0.39, green: 0.55, blue: 0.98, alpha: 1),
                 NSColor(srgbRed: 0.20, green: 0.74, blue: 0.62, alpha: 1),
                 NSColor(srgbRed: 0.96, green: 0.62, blue: 0.26, alpha: 1)]
let barH = size * 0.052
let barGap = size * 0.045
let barX = boardX + boardW*0.16
let barFull = boardW * 0.68
let widths = [barFull, barFull*0.78, barFull*0.55]
var by = boardY + boardH*0.62
for (i, c) in barColors.enumerated() {
    rounded(CGRect(x: barX, y: by, width: widths[i], height: barH), barH*0.5, c)
    by -= (barH + barGap)
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "packaging/icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
