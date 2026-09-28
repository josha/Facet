import CoreGraphics
import Foundation
let args = CommandLine.arguments
guard args.count == 4, let pid = Int32(args[1]), let code = UInt16(args[2]), let hold = Double(args[3]) else {
    FileHandle.standardError.write("usage: pad_key.swift <pid> <keycode> <seconds>\n".data(using: .utf8)!)
    exit(2)
}
let source = CGEventSource(stateID: .hidSystemState)
CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!.postToPid(pid)
usleep(useconds_t(hold * 1_000_000))
CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)!.postToPid(pid)
print("sent \(code)")
