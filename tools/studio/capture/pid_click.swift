// Click at screen point (x, y) for Studio: posted as a real click, and only while Studio (pid) is frontmost.
// Studio ignores clicks posted to its process, so this is the one way to reach its own UI or give the game view keyboard focus.
import CoreGraphics
import AppKit
let a = CommandLine.arguments
guard a.count == 4, let pid = Int32(a[1]), let x = Double(a[2]), let y = Double(a[3]) else {
    FileHandle.standardError.write("usage: pid_click.swift <pid> <x> <y>\n".data(using: .utf8)!)
    exit(2)
}
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { print("refused: Studio not frontmost"); exit(3) }
let p = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(80_000)
for t in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(60_000) }
print("clicked", x, y)
