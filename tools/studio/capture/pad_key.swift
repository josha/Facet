import CoreGraphics
import Foundation
let args = CommandLine.arguments
guard args.count == 4, let pid = Int32(args[1]), let code = UInt16(args[2]), let hold = Double(args[3]) else {
    FileHandle.standardError.write("usage: pad_key.swift <pid> <keycode> <seconds>\nController Emulator key codes: 18 D-pad up, 19 left, 20 down, 21 right; 13 stick up, 0 left, 1 down, 2 right\n".data(using: .utf8)!)
    exit(2)
}
let source = CGEventSource(stateID: .hidSystemState)
CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!.postToPid(pid)
usleep(useconds_t(hold * 1_000_000))
CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)!.postToPid(pid)
print("sent \(code)")
