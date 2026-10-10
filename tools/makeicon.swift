// makeicon —— 把一张方形 PNG 做成 macOS 的 .icns
//
//   swiftc -O -o /tmp/makeicon tools/makeicon.swift
//   /tmp/makeicon app/AppIcon-source.png /tmp/AppIcon.iconset
//   iconutil -c icns /tmp/AppIcon.iconset -o app/AppIcon.icns
//
// 为什么要这一步：源图是「圆形贴满画布」的，直接当图标用会显得比旁边的
// App 大一圈（macOS 的图标网格是圆角方形，内容只占约 80–86%）。
// 这里把源图等比缩到 SCALE 比例、居中放到透明画布上，再导出各尺寸。

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: makeicon <源图.png> <输出.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let srcPath = args[1]
let outDir  = args[2]

/// 内容在图标画布里占的比例。0.86 ≈ 视觉上和系统图标一样大。
let SCALE: CGFloat = 0.86
let CANVAS: CGFloat = 1024

guard let src = NSImage(contentsOfFile: srcPath),
      let tiff = src.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else {
    FileHandle.standardError.write("读不到源图: \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}
print("源图 \(cg.width)x\(cg.height)")

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    let side = CGFloat(px) * SCALE
    let inset = (CGFloat(px) - side) / 2
    ctx.draw(cg, in: CGRect(x: inset, y: inset, width: side, height: side))
    return ctx.makeImage()
}

func write(_ px: Int, _ name: String) -> Bool {
    guard let img = render(px) else { return false }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, img, nil)
    return CGImageDestinationFinalize(dest)
}

// .iconset 要求的 10 个文件
let jobs: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

var ok = 0
for (px, name) in jobs {
    if write(px, name) { ok += 1 }
    else { FileHandle.standardError.write("写失败: \(name)\n".data(using: .utf8)!) }
}
print("写出 \(ok)/\(jobs.count) 个尺寸 → \(outDir)")
exit(ok == jobs.count ? 0 : 1)
