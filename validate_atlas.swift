import AppKit
import CoreGraphics

let defaultPath = FileManager.default.currentDirectoryPath
    + "/build/阿念.app/Contents/Resources/sprite_sheet.png"
let path = CommandLine.arguments.dropFirst().first ?? defaultPath
guard let image = NSImage(contentsOfFile: path),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("cannot load atlas") }

precondition(source.width == 512 && source.height == 1408, "unexpected atlas size")

func containsVisiblePixel(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: bitmap) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
}

var nonempty: [Int] = []
for row in 0..<11 {
    for column in 0..<4 {
        let rect = CGRect(x: column * 128,
                          y: row * 128,
                          width: 128, height: 128)
        if let frame = source.cropping(to: rect), containsVisiblePixel(frame) {
            nonempty.append(row * 4 + column)
        }
    }
}

let expected = [0, 1, 2, 3, 4, 5,
                8, 9, 10, 11, 12, 13, 14,
                16, 17, 18, 19, 20, 21,
                24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
                36, 37, 38, 39, 40, 41, 42, 43]

print("size=\(source.width)x\(source.height) alpha=yes")
print("nonempty=\(nonempty)")
print("empty=\((0..<44).filter { !nonempty.contains($0) })")
precondition(nonempty == expected, "atlas frame occupancy mismatch")
print("atlas_check=pass")
