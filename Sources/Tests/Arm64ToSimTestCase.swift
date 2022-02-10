import Foundation
import XCTest
import Arm64ToSimLib

class Arm64ToSimTestCase: XCTestCase {


  var tempDir: URL!
  override func setUp() {
    self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID.init().uuidString)
    try! FileManager.default.createDirectory(at: self.tempDir, withIntermediateDirectories: false, attributes: nil)
    copyFixtures()
  }

  override func tearDown() {
    try! FileManager.default.removeItem(at: self.tempDir)
  }

  private func copyFixtures() {
    let testResourcesPath = Bundle.module.resourcePath!.appending("/TestResources")
    if let files = try? FileManager.default.contentsOfDirectory(atPath: testResourcesPath){
      for file in files {
        var isDir : ObjCBool = false
        let fileURL = URL(fileURLWithPath: testResourcesPath).appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
          if !isDir.boolValue {
            try! FileManager.default.copyItem(at: fileURL, to: tempDir.appendingPathComponent(fileURL.lastPathComponent.replacingOccurrences(of: ".fixture", with: "")))
          }
        }
      }
    }
  }

  @discardableResult func runCommand(args: [String]) -> (String, Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: args[0])
    task.arguments = Array(args.dropFirst())
    task.currentDirectoryURL = tempDir
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.launch()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (output!, task.terminationStatus)
  }

  private func testConvert(deviceTarget: String, simulatorTarget:String, file: StaticString = #file, line: UInt = #line) {
    let (sysroot, _) = runCommand(args: ["/usr/bin/xcrun", "--show-sdk-path", "--sdk", "iphonesimulator"])
    runCommand(args: ["/usr/bin/clang", "-isysroot", sysroot, "-target", simulatorTarget, "-c", "main.c", "-o", "main.arm64.ios.simulator.o"])
    runCommand(args: ["/usr/bin/clang", "-isysroot", sysroot, "-target", deviceTarget, "-c", "return2.c", "-o", "return2.ios.device.o"])
    let (loadCommandsOutput, _) = runCommand(args: ["/usr/bin/otool", "-l", "return2.ios.device.o" ])
    print("LOAD_COMMANDS:")
    for lc in loadCommandsOutput.split(separator: "\n").filter({$0.contains("cmd")}) {
      print(lc)
    }
    let (_, link_status_failing) = runCommand(args: ["/usr/bin/clang", "-isysroot", sysroot, "-target", deviceTarget, "main.arm64.ios.simulator.o", "return2.ios.device.o"])
    XCTAssert(link_status_failing != 0)
    Transmogrifier.processBinary(atPath: tempDir.appendingPathComponent("return2.ios.device.o").path, minos: 13, sdk: 13, isDynamic: false)
    let (_, link_status_success) = runCommand(args: ["/usr/bin/clang", "-isysroot", sysroot, "-target", "arm64-apple-ios-simulator", "main.arm64.ios.simulator.o", "return2.ios.device.o"])
    XCTAssert(link_status_success == 0)
  }

  func testConvertPreiOS12FileFormatToSim() {
    testConvert(deviceTarget: "arm64-apple-ios11", simulatorTarget: "arm64-apple-ios12-simulator")
  }

  func testConvertNewObjectFileFormatToSim() {
    testConvert(deviceTarget: "arm64-apple-ios12", simulatorTarget: "arm64-apple-ios12-simulator")
  }

}
