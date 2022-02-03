import Foundation
import Arm64ToSimLib

guard CommandLine.arguments.count > 1 else {
    fatalError("Please add a path to command!")
}

let binaryPath = CommandLine.arguments[1]
let minos = (CommandLine.arguments.count > 2 ? UInt32(CommandLine.arguments[2]) : nil) ?? 12
let sdk = (CommandLine.arguments.count > 3 ? UInt32(CommandLine.arguments[3]) : nil) ?? 13
let isDynamic = (CommandLine.arguments.count > 4 ? Bool(CommandLine.arguments[4]) : nil) ?? false
if isDynamic {
    print("[arm64-to-sim] notice: running in dynamic framework mode")
}

Transmogrifier.processBinary(atPath: binaryPath, minos: minos, sdk: sdk, isDynamic: isDynamic)
