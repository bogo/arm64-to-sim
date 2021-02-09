import Foundation
import MachO

// support checking for Mach-O `cmd` and `cmdsize` properties
extension Data {
    var loadCommand: UInt32 {
        let lc: load_command = withUnsafeBytes { $0.load(as: load_command.self) }
        return lc.cmd
    }
    
    var commandSize: Int {
        let lc: load_command = withUnsafeBytes { $0.load(as: load_command.self) }
        return Int(lc.cmdsize)
    }
    
    func asStruct<T>(fromByteOffset offset: Int = 0) -> T {
        return withUnsafeBytes { $0.load(fromByteOffset: offset, as: T.self) }
    }
}

// support peeking at Data contents
extension FileHandle {
    func peek(upToCount count: Int) throws -> Data? {
        // persist the current offset, since `upToCount` doesn't guarantee all bytes will be read
        let originalOffset = offsetInFile
        let data = try read(upToCount: count)
        try seek(toOffset: originalOffset)
        return data
    }
}

// a pair of Data and data offset that can be used to represent ongoing changes to the binary
class DataOffsetPair {
    private(set) var data: Data
    private(set) var offset: UInt32
    
    init(_ data: Data = Data(), _ offset: UInt32 = 0) {
        self.data = data
        self.offset = offset
    }
    
    func merge(_ dop: DataOffsetPair) {
        self.data.append(dop.data)
        self.offset += dop.offset
    }
}

enum Transmogrifier {
    private static func readBinary(atPath path: String) -> (Data, [Data], Data) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            fatalError("Cannot open a handle for the file at \(path). Aborting.")
        }
        
        // chop up the file into a relevant number of segments
        let headerData = try! handle.read(upToCount: MemoryLayout<mach_header_64>.stride)!
        
        let header: mach_header_64 = headerData.asStruct()
        if header.magic != MH_MAGIC_64 || header.cputype != CPU_TYPE_ARM64 {
            fatalError("The file is not a correct arm64 binary. Try thinning (via lipo) or unarchiving (via ar) first.")
        }
        
        let loadCommandsData: [Data] = (0..<header.ncmds).map { _ in
            let loadCommandPeekData = try! handle.peek(upToCount: MemoryLayout<load_command>.stride)
            return try! handle.read(upToCount: Int(loadCommandPeekData!.commandSize))!
        }
        
        let programData = try! handle.readToEnd()!
        
        try! handle.close()
        
        return (headerData, loadCommandsData, programData)
    }
    
    private static func updateSegment64(_ dop: DataOffsetPair) -> DataOffsetPair {
        // decode both the segment_command_64 and the subsequent section_64s
        var segment: segment_command_64 = dop.data.asStruct()
        
        let sections: [section_64] = (0..<Int(segment.nsects)).map { index in
            let offset = MemoryLayout<segment_command_64>.stride + index * MemoryLayout<section_64>.stride
            return dop.data.asStruct(fromByteOffset: offset)
        }
        
        // shift segment information by 8 bytes
        segment.fileoff += UInt64(dop.offset)
        segment.filesize += UInt64(dop.offset)
        segment.vmsize += UInt64(dop.offset)
        
        let offsetSections = sections.map { section -> section_64 in
            var section = section
            section.offset += 8
            section.reloff += section.reloff > 0 ? 8 : 0
            return section
        }
        
        var datas = [Data]()
        datas.append(Data(bytes: &segment, count: MemoryLayout<segment_command_64>.stride))
        datas.append(contentsOf: offsetSections.map { section in
            var section = section
            return Data(bytes: &section, count: MemoryLayout<section_64>.stride)
        })
        
        return DataOffsetPair(datas.reduce(into: Data()) { $0.append($1) })
    }
    
    private static func updateVersionMin(_ dop: DataOffsetPair) -> DataOffsetPair {
        var command = build_version_command(cmd: UInt32(LC_BUILD_VERSION),
                                            cmdsize: UInt32(MemoryLayout<build_version_command>.stride),
                                            platform: UInt32(PLATFORM_IOSSIMULATOR),
                                            minos: 13 << 16 | 0 << 8 | 0,
                                            sdk: 13 << 16 | 0 << 8 | 0,
                                            ntools: 0)
        
        return DataOffsetPair(Data(bytes: &command, count: MemoryLayout<build_version_command>.stride), 8)
    }
    
    private static func updateDataInCode(_ dop: DataOffsetPair) -> DataOffsetPair {
        var command: linkedit_data_command = dop.data.asStruct()
        command.dataoff += dop.offset
        return DataOffsetPair(Data(bytes: &command, count: dop.data.commandSize))
    }
    
    private static func updateSymTab(_ dop: DataOffsetPair) -> DataOffsetPair {
        var command: symtab_command = dop.data.asStruct()
        command.stroff += dop.offset
        command.symoff += dop.offset
        return DataOffsetPair(Data(bytes: &command, count: dop.data.commandSize))
    }
    
    static func processBinary(atPath path: String) {
        let (headerData, loadCommandsData, programData) = readBinary(atPath: path)
        
        let editedCommandsData = loadCommandsData
            .reduce(into: DataOffsetPair()) { (dop, lc) -> () in
                let lco = DataOffsetPair(lc, dop.offset)
                switch Int32(lc.loadCommand) {
                case LC_SEGMENT_64:
                    dop.merge(updateSegment64(lco))
                case LC_VERSION_MIN_IPHONEOS:
                    dop.merge(updateVersionMin(lco))
                case LC_DATA_IN_CODE, LC_LINKER_OPTIMIZATION_HINT:
                    dop.merge(updateDataInCode(lco))
                case LC_SYMTAB:
                    dop.merge(updateSymTab(lco))
                case LC_BUILD_VERSION:
                    fatalError("This arm64 binary already contains an LC_BUILD_VERSION load command!")
                default:
                    dop.merge(lco)
                }
            }
            .data
        
        var header: mach_header_64 = headerData.asStruct()
        header.sizeofcmds = UInt32(editedCommandsData.count)
        
        // reassemble the binary
        let reworkedData = [
            Data(bytes: &header, count: MemoryLayout<mach_header_64>.stride),
            editedCommandsData,
            programData
        ].reduce(into: Data()) { $0.append($1) }
        
        // save back to disk
        try! reworkedData.write(to: URL(fileURLWithPath: path))
    }
}

let binaryPath = CommandLine.arguments[1]
Transmogrifier.processBinary(atPath: binaryPath)
