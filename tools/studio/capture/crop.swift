// Crop a PNG to a rect given in LOGICAL points. The pixel scale is derived from
// the image width against the window's logical width, so this is correct on
// Retina and non-Retina alike. Operates purely on a file already on disk.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 8,
      let winW = Double(a[3]), let x = Double(a[4]),
      let y = Double(a[5]), let w = Double(a[6]), let h = Double(a[7]) else {
    FileHandle.standardError.write("usage: crop <in.png> <out.png> <winLogicalW> <x> <y> <w> <h>\n".data(using: .utf8)!)
    exit(2)
}
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("cannot read \(a[1])\n".data(using: .utf8)!); exit(3)
}
let scale = Double(img.width) / winW
guard let out = img.cropping(to: CGRect(x: x*scale, y: y*scale, width: w*scale, height: h*scale)) else {
    FileHandle.standardError.write("crop out of bounds for \(img.width)x\(img.height)\n".data(using: .utf8)!); exit(4)
}
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(5) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(6) }
print("\(out.width)x\(out.height)")
