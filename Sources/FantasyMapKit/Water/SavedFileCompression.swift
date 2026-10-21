import Foundation
#if canImport(Compression)
import Compression
#endif

/// Optional LZFSE compression of a saved file (Apple platforms). The file is the same JSON, compressed as a whole; loading tells the two apart
/// by the first bytes (an LZFSE stream starts with `bvx`, JSON never does). **The size a stream may expand to is bounded**, since a few
/// bytes can describe gigabytes.
enum SavedFileCompression {
	/// Provisional development limit on the decompressed size (the 100,000-cell water map is about 6 MB).
	static let maximumDecompressedBytes = 268_435_456

	static func isCompressed(_ data: Data) -> Bool { data.starts(with: [0x62, 0x76, 0x78]) }

	static func compress(_ data: Data) throws -> Data {
		#if canImport(Compression)
		do { return try (data as NSData).compressed(using: .lzfse) as Data } catch { throw SavedWaterMapError.invalidCompression }
		#else
		throw SavedWaterMapError.compressionUnavailable
		#endif
	}

	static func decompress(_ data: Data, limit: Int = maximumDecompressedBytes) throws -> Data {
		#if canImport(Compression)
		guard !data.isEmpty else { throw SavedWaterMapError.invalidCompression }
		let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
		defer { scratch.deallocate() }
		var stream = compression_stream(dst_ptr: scratch, dst_size: 0, src_ptr: UnsafePointer(scratch), src_size: 0, state: nil)
		guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else { throw SavedWaterMapError.invalidCompression }
		defer { compression_stream_destroy(&stream) }
		let chunk = 1 << 16
		var buffer = [UInt8](repeating: 0, count: chunk)
		var output = Data()
		try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
			stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress!
			stream.src_size = raw.count
			while true {
				var status = COMPRESSION_STATUS_ERROR
				buffer.withUnsafeMutableBufferPointer { b in
					stream.dst_ptr = b.baseAddress!
					stream.dst_size = chunk
					status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
				}
				let produced = chunk - stream.dst_size
				output.append(contentsOf: buffer[0..<produced])
				guard output.count <= limit else { throw SavedWaterMapError.decompressedTooLarge }
				if status == COMPRESSION_STATUS_END { break }
				// an error, or a stream that ended without finishing (truncated input makes no progress)
				guard status == COMPRESSION_STATUS_OK, produced > 0 || stream.src_size > 0 else { throw SavedWaterMapError.invalidCompression }
			}
		}
		return output
		#else
		throw SavedWaterMapError.compressionUnavailable
		#endif
	}
}
