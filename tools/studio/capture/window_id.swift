// Print the CGWindowID of the Roblox Studio window, plus its logical size.
// Used by capture_viewport.sh so the capture can target THAT WINDOW ONLY.
import CoreGraphics
import Foundation

// Optional argv[1]: a substring the window TITLE must contain. With two Studio
// windows open (measured 2026-07-26: a LuauUI place and a game place side by
// side) the first large window is a coin toss, and a capture of the WRONG place
// looks exactly like a capture of the right one — the failure mode this whole
// script exists to prevent. Pass the place name to be sure.
let match = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Roblox Studio" {
    guard let n = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let width = b["Width"] as? Double, let height = b["Height"] as? Double else { continue }
    // the document window is the large one; skip palettes and tooltips
    if width < 600 || height < 400 { continue }
    if !match.isEmpty {
        let name = w[kCGWindowName as String] as? String ?? ""
        if !name.contains(match) { continue }
    }
    print("\(n) \(Int(width)) \(Int(height))")
    exit(0)
}
FileHandle.standardError.write("Roblox Studio window not found\n".data(using: .utf8)!)
exit(3)
