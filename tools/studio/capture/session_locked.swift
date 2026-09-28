import CoreGraphics
import Foundation
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
print("locked:", session?["CGSSessionScreenIsLocked"] ?? "no-key")
