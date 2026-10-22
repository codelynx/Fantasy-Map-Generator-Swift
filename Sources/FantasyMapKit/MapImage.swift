import CoreGraphics
import FantasyMapCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders a `MapDrawing` to a bitmap, needing no visible view.
///
/// - **Pixel dimensions:** the caller's width and height in pixels.
/// - **Aspect fit:** the map is scaled to fit inside the bitmap, keeping its proportions, and centred.
/// - **Background:** the style's paper colour fills the whole bitmap, margins included.
/// - **Stroke widths** (from stage 2) are in map units and scale with the map, so a bitmap at twice the size has strokes twice as
///   wide in pixels. The thin same-colour outline stage 1 puts on each filled cell to hide seams between neighbours is the one
///   exception: it is a fixed fraction of a pixel.
public enum MapImage {
	/// Why an image could not be made.
	public enum Failure: Error, Equatable, Sendable {
		case invalidSize
		case couldNotCreateBitmap
		case couldNotEncode
	}

	/// The largest side of an image this renderer will make, in pixels.
	public static let maximumPixels = 16_384
	/// The most pixels in total (width times height) this renderer will make: 32 million, which is 128 MB of bitmap at four bytes
	/// a pixel, before any encoding. A resource policy, not a promise that a device has the memory; a caller may impose less.
	public static let maximumTotalPixels = 32_000_000

	/// Where the map sits in a bitmap of the given size: the scale and the offset of the map's top-left corner, in pixels.
	public static func fit(width: Double, height: Double, pixelWidth: Int, pixelHeight: Int) -> (scale: Double, originX: Double, originY: Double) {
		let scale = min(Double(pixelWidth) / width, Double(pixelHeight) / height)
		return (scale, (Double(pixelWidth) - width * scale) / 2, (Double(pixelHeight) - height * scale) / 2)
	}

	/// The bitmap, in sRGB with premultiplied alpha, 8 bits a channel. The thin same-colour outline that hides seams between
	/// neighbouring cells is drawn only for opaque cells (filling and then stroking a translucent cell would composite its edge
	/// twice), and it is half an **output pixel** wide.
	public static func render(_ drawing: MapDrawing, pixelWidth: Int, pixelHeight: Int) throws -> CGImage {
		guard pixelWidth > 0, pixelHeight > 0, pixelWidth <= maximumPixels, pixelHeight <= maximumPixels,
			pixelWidth * pixelHeight <= maximumTotalPixels,
			drawing.width.isFinite, drawing.height.isFinite, drawing.width > 0, drawing.height > 0 else { throw Failure.invalidSize }
		// the fit scale must be finite and positive before it is used to transform or to size the seam outline
		let fitScale = fit(width: drawing.width, height: drawing.height, pixelWidth: pixelWidth, pixelHeight: pixelHeight).scale
		guard fitScale.isFinite, fitScale > 0 else { throw Failure.invalidSize }
		guard let space = CGColorSpace(name: CGColorSpace.sRGB),
			let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.couldNotCreateBitmap }

		// paper over the whole bitmap, margins included
		context.setFillColor(cgColor(drawing.paper, space))
		context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

		// the map's own coordinates have y going down; the bitmap's go up, so flip while fitting the map in
		let f = fit(width: drawing.width, height: drawing.height, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
		context.translateBy(x: f.originX, y: Double(pixelHeight) - f.originY)
		context.scaleBy(x: f.scale, y: -f.scale)
		context.clip(to: CGRect(x: 0, y: 0, width: drawing.width, height: drawing.height))

		let hairline = 0.5 / f.scale // half a pixel, in map units: hides seams between neighbouring cells
		context.setLineWidth(hairline)
		context.setLineJoin(.round)
		func paint(_ fills: [FillCommand]) {
			for fill in fills {
				guard let first = fill.points.first else { continue }
				let color = cgColor(fill.color, space)
				context.setFillColor(color)
				context.setStrokeColor(color)
				context.beginPath()
				context.move(to: CGPoint(x: first.x, y: first.y))
				for p in fill.points.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
				context.closePath()
				context.drawPath(using: fill.color.alpha >= 1 ? .fillStroke : .fill)
			}
		}
		func paintRivers() {
			for river in drawing.rivers {
				guard let first = river.points.first else { continue }
				context.setFillColor(cgColor(river.color, space))
				context.beginPath()
				context.move(to: CGPoint(x: first.x, y: first.y))
				for p in river.points.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
				context.closePath()
				context.fillPath()
			}
		}
		if let rings = drawing.landClip {
			// water as it is, then the land clipped to the same outline the ink follows
			paint(drawing.receded)
			paint(drawing.fills.filter { !$0.isLand })
			context.saveGState()
			context.beginPath()
			for ring in rings {
				guard let first = ring.first else { continue }
				context.move(to: CGPoint(x: first.x, y: first.y))
				for p in ring.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
				context.closePath()
			}
			context.clip(using: .evenOdd)
			paint(drawing.exposed)
			paint(drawing.fills.filter(\.isLand))
			// the realms' wash: opaque polygons drawn together at the wash opacity (so overlaps do not darken), under the rivers
			if drawing.realmWashOpacity > 0, !drawing.realmWash.isEmpty {
				context.setAlpha(drawing.realmWashOpacity)
				context.beginTransparencyLayer(auxiliaryInfo: nil)
				paint(drawing.realmWash)
				context.endTransparencyLayer()
				context.setAlpha(1)
			}
			// the rivers, over the land and clipped to the same outline, so a widened river never paints on the water
			paintRivers()
			// the realms' borders, dashed, over the rivers, clipped to the land
			context.setLineCap(.butt)
			for line in drawing.realmBorders {
				guard let first = line.points.first, line.width > 0 else { continue }
				context.setStrokeColor(cgColor(line.color, space))
				context.setLineWidth(line.width)
				context.setLineDash(phase: 0, lengths: line.dash.map { CGFloat($0) })
				context.beginPath()
				context.move(to: CGPoint(x: first.x, y: first.y))
				for p in line.points.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
				if line.isClosed { context.closePath() }
				context.strokePath()
			}
			context.setLineDash(phase: 0, lengths: [])
			context.restoreGState()
		} else {
			paint(drawing.fills)
			paintRivers() // the coast is not trusted: the rivers are drawn as generated
		}
		// the coastline ink, over the fills; widths are in map units, and the clip keeps it off the paper margin
		context.setLineCap(.round)
		for line in drawing.ink {
			guard let first = line.points.first, line.width > 0 else { continue }
			context.setStrokeColor(cgColor(line.color, space))
			context.setLineWidth(line.width)
			context.beginPath()
			context.move(to: CGPoint(x: first.x, y: first.y))
			for p in line.points.dropFirst() { context.addLine(to: CGPoint(x: p.x, y: p.y)) }
			if line.isClosed { context.closePath() }
			context.strokePath()
		}
		guard let image = context.makeImage() else { throw Failure.couldNotCreateBitmap }
		return image
	}

	/// The bitmap as PNG data.
	public static func pngData(_ drawing: MapDrawing, pixelWidth: Int, pixelHeight: Int) throws -> Data {
		let image = try render(drawing, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw Failure.couldNotEncode }
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else { throw Failure.couldNotEncode }
		return data as Data
	}

	static func cgColor(_ c: MapColor, _ space: CGColorSpace) -> CGColor {
		CGColor(colorSpace: space, components: [CGFloat(c.red), CGFloat(c.green), CGFloat(c.blue), CGFloat(c.alpha)]) ?? CGColor(gray: 0, alpha: 1)
	}
}
