import Foundation

/// A ZIP archive of files stored as they are, uncompressed: what an Office
/// Open XML file such as an .xlsx is, without a compression library. Every
/// ZIP reader takes stored files; a few small XML files lose little by it.
struct StoredZip {
    private var files: [(name: String, data: Data)] = []

    /// Adds a file; `name` is its path in the archive, ASCII, with "/".
    mutating func add(_ name: String, _ data: Data) {
        files.append((name, data))
    }

    /// The archive: each file after its local header, then the central
    /// directory and its end record. Dated 1 January 1980, the first date
    /// ZIP can hold, so the same files make the same bytes.
    var data: Data {
        var archive = Data()
        var directory = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = CRC32.checksum(file.data)
            let offset = UInt32(archive.count)
            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendHeaderFields(crc: crc, size: UInt32(file.data.count), nameLength: UInt16(name.count))
            archive.append(name)
            archive.append(file.data)

            directory.appendLittleEndian(UInt32(0x0201_4B50))
            directory.appendLittleEndian(UInt16(20))  // made by: ZIP 2.0
            directory.appendHeaderFields(crc: crc, size: UInt32(file.data.count), nameLength: UInt16(name.count))
            directory.appendLittleEndian(UInt16(0))  // comment length
            directory.appendLittleEndian(UInt16(0))  // disk
            directory.appendLittleEndian(UInt16(0))  // internal attributes
            directory.appendLittleEndian(UInt32(0))  // external attributes
            directory.appendLittleEndian(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))  // this disk
        archive.appendLittleEndian(UInt16(0))  // the directory's disk
        archive.appendLittleEndian(UInt16(files.count))
        archive.appendLittleEndian(UInt16(files.count))
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0))  // comment length
        return archive
    }
}

/// CRC-32 as ZIP (and Ethernet) computes it: polynomial 0xEDB88320,
/// reflected, starting from and finishing with all ones.
enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { byte in
        (0 ..< 8).reduce(UInt32(byte)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    /// From "version needed" to "extra field length", the fields a local
    /// header and a directory entry share for a stored file.
    mutating func appendHeaderFields(crc: UInt32, size: UInt32, nameLength: UInt16) {
        appendLittleEndian(UInt16(20))  // needed: ZIP 2.0
        appendLittleEndian(UInt16(0))  // flags
        appendLittleEndian(UInt16(0))  // method: stored
        appendLittleEndian(UInt16(0))  // time: 00:00
        appendLittleEndian(UInt16(0x21))  // date: 1 January 1980
        appendLittleEndian(crc)
        appendLittleEndian(size)  // compressed
        appendLittleEndian(size)  // uncompressed
        appendLittleEndian(nameLength)
        appendLittleEndian(UInt16(0))  // extra field length
    }
}
