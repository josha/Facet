import CoreGraphics
import Foundation
let args = CommandLine.arguments
guard args.count == 4, let pid = Int32(args[1]), let x = Double(args[2]), let y = Double(args[3]) else {
    FileHandle.standardError.write("usage: pid_click.swift <pid> <x> <y>\n".data(using: .utf8)!)
    exit(2)
}
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.postToPid(pid)
    usleep(60_000)
}
