import CryptoKit
import Testing
import Foundation

/// Loads the fixtures captured from the original (see Fixtures/original/README.md).
enum Fixtures {
	static func data(_ name: String) throws -> Data {
		let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/original"))
		return try Data(contentsOf: url)
	}
}

extension Fixtures {
	/// sha256 of Int32 values written explicitly little-endian, as the capture scripts write them.
	static func hashInt32s(_ values: [Int]) -> String {
		var data = Data()
		for v in values { withUnsafeBytes(of: Int32(v).littleEndian) { data.append(contentsOf: $0) } }
		return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}

extension Fixtures {
	/// sha256 of UInt16 values written explicitly little-endian.
	static func hashUInt16s(_ values: [UInt16]) -> String {
		var data = Data()
		for v in values { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
		return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}

extension Fixtures {
	/// sha256 of Float64 values written explicitly little-endian, as the capture scripts write them.
	static func hashDoubles(_ values: [Double]) -> String {
		var data = Data()
		for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
		return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
	}
}

extension Fixtures {
	/// sha256 of raw bytes, as the capture scripts hash them.
	static func hashBytes(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
