import CoreGraphics
import FantasyMapCore
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKit

/// A measurement, not a test of behaviour: it prints how long drawing construction and display take for a large map, and
/// asserts nothing about speed. Run it only on request, in release mode, because debug timings mean nothing:
///
///     FMK_MEASURE=1 swift test -c release --filter ViewSpeedMeasurement
///
/// What it measures, kept apart: building the map; building the `MapDrawing` (and, inside it, the coast outlines); the first
/// render of the SwiftUI view through `ImageRenderer` ("initial display") and the renders after it ("redraw", the same view
/// value); and `MapImage.render` for comparison. `ImageRenderer` renders offscreen on the CPU path of this process: it is not
/// the on-screen display with a window server and a GPU, and so it is **evidence about the cost of the drawing commands, not a
/// frame rate**.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FMK_MEASURE"] != nil))
struct ViewSpeedMeasurement {
	func ms(_ body: () throws -> Void) rethrows -> Double {
		let start = DispatchTime.now().uptimeNanoseconds
		try body()
		return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
	}

	func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

	func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Double, Double, Double) {
		var data = [UInt8](repeating: 0, count: 4)
		let space = CGColorSpace(name: CGColorSpace.sRGB)!
		let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
		return (Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255)
	}

	func machine() -> String {
		func sysctl(_ name: String) -> String {
			var size = 0
			sysctlbyname(name, nil, &size, nil, 0)
			var buffer = [CChar](repeating: 0, count: size)
			sysctlbyname(name, &buffer, &size, nil, 0)
			return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
		}
		return "\(sysctl("machdep.cpu.brand_string")), \(ProcessInfo.processInfo.activeProcessorCount) cores, \(ProcessInfo.processInfo.operatingSystemVersionString)"
	}

	@MainActor
	@Test func measure() throws {
		print("MEASURE machine: \(machine())")
		var optimized = true
		assert({ optimized = false; return true }())
		print("MEASURE build: \(optimized ? "release (optimised)" : "DEBUG: the numbers mean nothing")")
		for (key, cells) in [("continents", 10_000), ("continents", 100_000), ("shattered", 100_000)] {
			var map: LandMap!
			let mapTime = try ms { map = try LandMap.generate(seed: "kaz-1", width: 1280, height: 800, cellsDesired: cells, template: try #require(HeightmapTemplate.named(key))) }
			print("MEASURE --- \(key), \(cells) cells, 1280x800 map units; generating the map took \(Int(mapTime)) ms")
			var rough = RoughnessSettings()
			rough.smoothThreshold = 0.05
			let variants: [(String, MapStyle)] = [
				("standard (smoothing 2, no roughness)", .standard),
				("smoothing 0", { var s = MapStyle.standard; s.smoothing = 0; return s }()),
				("smoothing 2 + roughness (amplitude 0.75, threshold 0.05)", { var s = MapStyle.standard; s.roughness = rough; return s }())
			]
			for (name, style) in variants {
				var drawing: MapDrawing!
				let builds = (0..<3).map { _ in ms { drawing = MapDrawing(map: map, style: style) } }
				let coastOnly = (0..<3).map { _ in ms { _ = CoastOutlines(map: map, smoothing: style.smoothing, roughness: style.roughness) } }
				print("MEASURE [\(name)] roughness outcome: \(drawing.coast.roughness); fills \(drawing.fills.count), exposed \(drawing.exposed.count), receded \(drawing.receded.count), ink lines \(drawing.ink.count), ring points \(drawing.coast.landRings.map(\.count).reduce(0, +))")
				print("MEASURE [\(name)] build MapDrawing: median \(Int(median(builds))) ms of \(builds.map { Int($0) }); of which CoastOutlines alone: median \(Int(median(coastOnly))) ms")
				for scale in [1.0, 2.0] {
					// ImageRenderer keeps its image after the first call, so a repeat needs a fresh renderer: "repeat" below is a new
					// renderer and a new view value over the SAME prepared drawing (no rebuild of the drawing). An on-screen redraw
					// of a live Canvas cannot be measured this way.
					func render() -> CGImage? {
						let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing).frame(width: 1280, height: 800))
						renderer.scale = scale
						return renderer.cgImage
					}
					var first: CGImage?
					let initial = ms { first = render() }
					let repeats = (0..<3).map { _ in ms { _ = render() } }
					// the image must be the picture and not a blank: compare with the image renderer on a grid of pixels
					let reference = try MapImage.render(drawing, pixelWidth: first?.width ?? 1, pixelHeight: first?.height ?? 1)
					var agree = 0, checked = 0
					if let first {
						for y in stride(from: 8, to: first.height, by: 97) { for x in stride(from: 8, to: first.width, by: 89) {
							let a = pixel(first, x, y), b = pixel(reference, x, y)
							checked += 1
							if abs(a.0 - b.0) < 0.1 && abs(a.1 - b.1) < 0.1 && abs(a.2 - b.2) < 0.1 { agree += 1 }
						} }
					}
					print("MEASURE [\(name)] SwiftUI view at display scale \(Int(scale)) (\(first?.width ?? 0) x \(first?.height ?? 0) px): first render \(Int(initial)) ms, repeats \(repeats.map { Int($0) }) ms; \(agree) of \(checked) sampled pixels agree with MapImage.render")
				}
				for (w, h) in [(1280, 800), (2560, 1600)] {
					let times = try (0..<3).map { _ in try ms { _ = try MapImage.render(drawing, pixelWidth: w, pixelHeight: h) } }
					print("MEASURE [\(name)] MapImage.render \(w)x\(h): median \(Int(median(times))) ms of \(times.map { Int($0) })")
				}
			}
		}
	}
}
