import CoreGraphics
import FantasyMapCore
import Foundation
import SwiftUI
import Testing
@testable import FantasyMapKit

/// A measurement, not a test of behaviour (docs/plans/drawing-zoom.md): how long the zoomable view takes to draw a **prepared** `MapDrawing` at several zooms, and how
/// long the viewport arithmetic a gesture runs takes. Kept apart: drawing construction (not measured here, see `ViewSpeedMeasurement`), a redraw of the view at a
/// viewport, and the gesture's own arithmetic. It asserts nothing about speed. Run it on request, in release mode:
///
///     FMK_MEASURE=1 swift test -c release --filter ZoomSpeedMeasurement
///
/// The view is rendered **offscreen through `ImageRenderer`** (the CPU path of this process): it measures the cost of the drawing commands, **not the on-screen
/// display with a window server and a GPU, and not a frame rate**; a live redraw while zooming on screen was not measured. Nothing is profiled here: which of
/// geometry traversal, clipping and transparency layers dominates is not known from these numbers.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FMK_MEASURE"] != nil))
struct ZoomSpeedMeasurement {
	func ms(_ body: () throws -> Void) rethrows -> Double {
		let start = DispatchTime.now().uptimeNanoseconds
		try body()
		return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
	}

	func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

	@MainActor
	@Test func measure() throws {
		for cells in [10_000, 100_000] {
			let map = try LandMap.generate(seed: "kaz-1", cellsDesired: cells, template: try #require(HeightmapTemplate.named("continents")))
			let water = try WaterMap.generate(land: map)
			let drawing = MapDrawing(water: water)
			let g = MapViewportGeometry(mapWidth: map.width, mapHeight: map.height, viewWidth: 1280, viewHeight: 800, cellSpacing: drawing.cellSpacing)
			let maximum = g.maximumZoom
			print("ZOOM \(cells) cells: maximum zoom \(String(format: "%.1f", maximum)) (spacing \(String(format: "%.2f", drawing.cellSpacing)) map units)")
			for zoom in [1.0, 2, maximum / 2, maximum] {
				let viewport = MapViewport(zoom: zoom, center: Point(x: map.width * 0.45, y: map.height * 0.5))
				var times: [Double] = []
				for _ in 0..<7 {
					let renderer = ImageRenderer(content: FantasyMapView(drawing: drawing, viewport: .constant(viewport)).frame(width: 1280, height: 800))
					renderer.scale = 1
					times.append(ms { _ = renderer.cgImage })
				}
				print("ZOOM \(cells) cells, zoom \(String(format: "%.1f", zoom)): redraw median \(String(format: "%.1f", median(Array(times.dropFirst(2))))) ms (renders 3 to 7 of a fresh view each; first two \(String(format: "%.0f", times[0])) and \(String(format: "%.0f", times[1])) ms)")
			}
			// the gesture's own arithmetic: a zoom and a pan step, many times
			var v = MapViewport.fit
			let n = 100_000
			let t = ms { for i in 0..<n { v = g.zoomed(v, by: i % 2 == 0 ? 1.01 : 0.99, around: Point(x: 600, y: 300)); v = g.panned(v, byViewPoints: 1, -1) } }
			print("ZOOM \(cells) cells: a zoom step and a pan step take about \(String(format: "%.2f", t / Double(n) * 1000)) microseconds together")
		}
	}
}
