import Foundation

enum ICNSError: LocalizedError {
    case invalidArguments
    case invalidChunkType(String)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: create-icns.swift INPUT.iconset OUTPUT.icns"
        case .invalidChunkType(let type):
            return "Invalid ICNS chunk type: \(type)"
        case .fileTooLarge:
            return "The generated ICNS file is too large."
        }
    }
}

private struct Chunk {
    let type: String
    let fileName: String
}

private let chunks = [
    Chunk(type: "icp4", fileName: "icon_16x16.png"),
    Chunk(type: "ic11", fileName: "icon_16x16@2x.png"),
    Chunk(type: "icp5", fileName: "icon_32x32.png"),
    Chunk(type: "ic12", fileName: "icon_32x32@2x.png"),
    Chunk(type: "ic07", fileName: "icon_128x128.png"),
    Chunk(type: "ic13", fileName: "icon_128x128@2x.png"),
    Chunk(type: "ic08", fileName: "icon_256x256.png"),
    Chunk(type: "ic14", fileName: "icon_256x256@2x.png"),
    Chunk(type: "ic09", fileName: "icon_512x512.png"),
    Chunk(type: "ic10", fileName: "icon_512x512@2x.png")
]

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }
}

func createICNS(arguments: [String]) throws {
    guard arguments.count == 3 else { throw ICNSError.invalidArguments }
    let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
    let outputURL = URL(fileURLWithPath: arguments[2])

    var body = Data()
    for chunk in chunks {
        guard let typeData = chunk.type.data(using: .ascii), typeData.count == 4 else {
            throw ICNSError.invalidChunkType(chunk.type)
        }
        let imageData = try Data(contentsOf: iconsetURL.appendingPathComponent(chunk.fileName))
        let (chunkSize, overflow) = UInt32(imageData.count).addingReportingOverflow(8)
        guard !overflow else { throw ICNSError.fileTooLarge }
        body.append(typeData)
        body.appendBigEndian(chunkSize)
        body.append(imageData)
    }

    let (totalSize, overflow) = UInt32(body.count).addingReportingOverflow(8)
    guard !overflow else { throw ICNSError.fileTooLarge }
    var output = Data("icns".utf8)
    output.appendBigEndian(totalSize)
    output.append(body)
    try output.write(to: outputURL, options: .atomic)
}

do {
    try createICNS(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
