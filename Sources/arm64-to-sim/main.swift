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

extension Array where Element == Data {
    func merge() -> Data {
        return reduce(into: Data()) { $0.append($1) }
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
    
    private static func updateSegment64(_ data: Data, _ offset: UInt32) -> Data {
        // decode both the segment_command_64 and the subsequent section_64s
        var segment: segment_command_64 = data.asStruct()
        
        let sections: [section_64] = (0..<Int(segment.nsects)).map { index in
            let offset = MemoryLayout<segment_command_64>.stride + index * MemoryLayout<section_64>.stride
            return data.asStruct(fromByteOffset: offset)
        }
        
        // shift segment information by the offset
        segment.fileoff += UInt64(offset)
        segment.filesize += UInt64(offset)
        segment.vmsize += UInt64(offset)
        
        let offsetSections = sections.map { section -> section_64 in
            var section = section
            section.offset += UInt32(offset)
            section.reloff += section.reloff > 0 ? UInt32(offset) : 0
            return section
        }
        
        var datas = [Data]()
        datas.append(Data(bytes: &segment, count: MemoryLayout<segment_command_64>.stride))
        datas.append(contentsOf: offsetSections.map { section in
            var section = section
            return Data(bytes: &section, count: MemoryLayout<section_64>.stride)
        })
        
        return datas.merge()
    }
    
    private static func updateVersionMin(_ data: Data, _ offset: UInt32) -> Data {
        var command = build_version_command(cmd: UInt32(LC_BUILD_VERSION),
                                            cmdsize: UInt32(MemoryLayout<build_version_command>.stride),
                                            platform: UInt32(PLATFORM_IOSSIMULATOR),
                                            minos: 13 << 16 | 0 << 8 | 0,
                                            sdk: 13 << 16 | 0 << 8 | 0,
                                            ntools: 0)
        
        return Data(bytes: &command, count: MemoryLayout<build_version_command>.stride)
    }
    
    private static func updateDataInCode(_ data: Data, _ offset: UInt32) -> Data {
        var command: linkedit_data_command = data.asStruct()
        command.dataoff += offset
        return Data(bytes: &command, count: data.commandSize)
    }
    
    private static func updateSymTab(_ data: Data, _ offset: UInt32) -> Data {
        var command: symtab_command = data.asStruct()
        command.stroff += offset
        command.symoff += offset
        return Data(bytes: &command, count: data.commandSize)
    }
    
    private static func updateDySymTab(_ data: Data, _ offset: UInt32) -> Data {
        var command: dysymtab_command = data.asStruct()
        command.modtaboff += offset
        command.tocoff += offset
        command.extreloff += offset
        command.locreloff += offset
        command.extrefsymoff += offset
        command.indirectsymoff += offset
        return Data(bytes: &command, count: data.commandSize)
    }

    private static func updateDyLdInfoOnly(_ data: Data, _ offset: UInt32) -> Data {
        var command: dyld_info_command = data.asStruct()
        command.bind_off += offset
        command.rebase_off += offset
        command.export_off += offset
        command.weak_bind_off += offset
        command.lazy_bind_off += offset
        return Data(bytes: &command, count: data.commandSize)
    }
    private static func updateDylib(_ data: Data, _ offset: UInt32) -> Data {
        var command: dylib_command = data.asStruct()
        return Data(bytes: &command, count: data.commandSize)
    }

    static func processBinary(atPath path: String) {
        let (headerData, loadCommandsData, programData) = readBinary(atPath: path)
        
        // `offset` is kind of a magic number here, since we know that's the only meaningful change to binary size
        // having a dynamic `offset` requires two passes over the load commands and is left as an exercise to the reader
        let offset = UInt32(abs(MemoryLayout<build_version_command>.stride - MemoryLayout<version_min_command>.stride))
        
        let editedCommandsData = loadCommandsData
            .map { (lc) -> Data in
                print("lc: (command:\(lc.loadCommand), size:\(lc.commandSize)")
                switch lc.loadCommand {
                case UInt32(LC_SEGMENT_64):
                    print("LC_SEGMENT_64")
                    return updateSegment64(lc, offset)
                case UInt32(LC_VERSION_MIN_IPHONEOS):
                    print("LC_VERSION_MIN_IPHONEOS")
                    return updateVersionMin(lc, offset)
                case UInt32(LC_DATA_IN_CODE), UInt32(LC_LINKER_OPTIMIZATION_HINT):
                    print("LC_DATA_IN_CODE|LC_LINKER_OPTIMIZATION_HINT")
                    return updateDataInCode(lc, offset)
                case UInt32(LC_SYMTAB):
                    print("LC_SYMTAB")
                    return updateSymTab(lc, offset)
                case UInt32(LC_BUILD_VERSION):
                    print("LC_BUILD_VERSION")
                    fatalError("This arm64 binary already contains an LC_BUILD_VERSION load command!")
                case UInt32(LC_ID_DYLIB), UInt32(LC_LOAD_DYLIB):
                    print("LC_ID_DYLIB|LC_LOAD_DYLIB")
//                    return updateDylib(lc, offset)
                    return lc
                case UInt32(LC_DYLD_INFO_ONLY):
                    print("LC_DYLD_INFO_ONLY")
                    return updateDyLdInfoOnly(lc, offset)
                case UInt32(LC_DYSYMTAB):
                    print("LC_DYSYMTAB")
                    return updateDySymTab(lc, offset)
                case UInt32(LC_SOURCE_VERSION):
                    print("LC_SOURCE_VERSION")
                    return lc
                case UInt32(LC_UUID):
                    print("LC_UUID")
                    return lc
                case UInt32(LC_VERSION_MIN_IPHONEOS):
                    print("LC_VERSION_MIN_IPHONEOS")
                    return lc
                case UInt32(LC_FUNCTION_STARTS):
                    print("LC_FUNCTION_STARTS")
                    return lc
                default:
                    return lc
                }
            }
            .merge()
        var header: mach_header_64 = headerData.asStruct()
        header.sizeofcmds = UInt32(editedCommandsData.count)
        
        // reassemble the binary
        let reworkedData = [
            Data(bytes: &header, count: MemoryLayout<mach_header_64>.stride),
            editedCommandsData,
            programData
        ].merge()
        
        // save back to disk
        try! reworkedData.write(to: URL(fileURLWithPath: path))
    }
}

let binaryPath = CommandLine.arguments[1]
Transmogrifier.processBinary(atPath: binaryPath)
