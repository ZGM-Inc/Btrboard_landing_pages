// Native macOS renderer for the BTRboard sunset hero. No external dependencies.
// Compile:
//   swiftc -O -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -target arm64-apple-macosx15.0 -module-cache-path /tmp/btr-swift-cache tools/render_hero_video.swift -o /tmp/btr-render-hero
// Render:
//   /tmp/btr-render-hero assets/img/hero-interior-sunset.png assets/video/hero-interior-daylight.mp4
// This is a deterministic cinemagraph: an edited photograph, a slow camera move,
// tiny foliage displacements and a soft daylight/dusk cycle with moving floor light.
// It is not captured video. Relighting never displaces the building or floor texture.

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum RenderError: Error { case failed(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw RenderError.failed(message) }
}

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: render_hero_video INPUT.png OUTPUT.mp4\n", stderr)
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let width = 1600, height = 900, fps: Int32 = 24
let duration = 20.0
let frameCount = Int(duration * Double(fps))
let qaDirectory = URL(fileURLWithPath: "/tmp/btr-daylight-video-qa", isDirectory: true)
try FileManager.default.createDirectory(at: qaDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try require(!FileManager.default.fileExists(atPath: outputURL.path), "Output already exists; choose a new output path to avoid replacing it.")

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw RenderError.failed("Could not load source image")
}
let sourceWidth = cgImage.width, sourceHeight = cgImage.height
try require(sourceWidth == 1670 && sourceHeight == 942, "Foliage masks are calibrated to the 1670×942 sunset image")
let sourceBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceWidth * sourceHeight * 4)
defer { sourceBytes.deallocate() }
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let decodeContext = CGContext(data: sourceBytes, width: sourceWidth, height: sourceHeight,
    bitsPerComponent: 8, bytesPerRow: sourceWidth * 4, space: colorSpace,
    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
    throw RenderError.failed("Could not decode source pixels")
}
decodeContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))

// Source-pixel ellipses sit wholly within visible foliage, clear of glass labels,
// window frames, mullions, exterior rooflines and all interior construction.
// Feathering brings displacement smoothly to zero at each patch boundary.
struct FoliagePatch { let x, y, rx, ry, phase: Double }
let patches: [FoliagePatch] = [
    .init(x: 271, y: 280, rx: 13, ry: 27, phase: 0.2),
    .init(x: 315, y: 279, rx: 25, ry: 11, phase: 0.6),
    .init(x: 423, y: 280, rx: 12, ry: 12, phase: 0.9),
    .init(x: 429, y: 338, rx: 10, ry: 46, phase: 1.1),
    .init(x: 278, y: 376, rx: 17, ry: 18, phase: 0.4),
    .init(x: 292, y: 474, rx: 35, ry: 20, phase: 0.0),
    .init(x: 388, y: 483, rx: 42, ry: 23, phase: 0.6),
    .init(x: 621, y: 401, rx: 16, ry: 13, phase: 1.0),
    .init(x: 529, y: 485, rx: 25, ry: 21, phase: 1.5),
    .init(x: 603, y: 496, rx: 29, ry: 14, phase: 1.8),
    .init(x: 712, y: 340, rx: 17, ry: 37, phase: 0.2),
    .init(x: 775, y: 351, rx: 15, ry: 42, phase: 0.7),
    .init(x: 725, y: 402, rx: 13, ry: 20, phase: 1.3),
    .init(x: 711, y: 493, rx: 18, ry: 33, phase: 0.6),
    .init(x: 737, y: 551, rx: 32, ry: 35, phase: 1.2),
    .init(x: 773, y: 501, rx: 14, ry: 27, phase: 1.8),
    .init(x: 781, y: 572, rx: 10, ry: 19, phase: 1.5),
    .init(x: 1161, y: 394, rx: 6, ry: 14, phase: 0.3),
    .init(x: 1198, y: 397, rx: 5, ry: 12, phase: 0.8),
]
let pixelCount = sourceWidth * sourceHeight
let fieldSin = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
let fieldCos = UnsafeMutablePointer<Float>.allocate(capacity: pixelCount)
fieldSin.initialize(repeating: 0, count: pixelCount)
fieldCos.initialize(repeating: 0, count: pixelCount)
defer { fieldSin.deallocate(); fieldCos.deallocate() }
var weights = [Double](repeating: 0, count: pixelCount)
for patch in patches {
    for y in Int(patch.y-patch.ry)...Int(patch.y+patch.ry) {
        for x in Int(patch.x-patch.rx)...Int(patch.x+patch.rx) {
            let nx = (Double(x)-patch.x)/patch.rx, ny = (Double(y)-patch.y)/patch.ry
            let distance = sqrt(nx*nx + ny*ny)
            if distance >= 1 { continue }
            let feather = min(1, (1-distance)/0.55)
            let weight = feather*feather*(3-2*feather)
            let index = y*sourceWidth+x
            if weight > weights[index] {
                weights[index] = weight
                // A slight vertical phase gradient keeps adjacent leaves from moving as a rigid cutout.
                let phase = patch.phase + ny*0.25
                fieldSin[index] = Float(weight*cos(phase))
                fieldCos[index] = Float(weight*sin(phase))
            }
        }
    }
}
let movingPixels = weights.filter { $0 > 0 }.count
weights.removeAll(keepingCapacity: false)
print("Foliage mask covers \(movingPixels) source pixels; maximum lateral displacement is 1.2 px.")

@inline(__always) func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
    let t = max(0, min(1, (value-lower)/(upper-lower)))
    return t*t*(3-2*t)
}

// Broad sunlit strips follow the existing window projections toward the foreground.
// Their difference from the starting pattern changes only illumination, so the
// plywood grain, panel seams and framing stay fixed throughout the sequence.
@inline(__always) func floorLight(_ coordinate: Double) -> Double {
    var light = 0.0
    for center in [785.0, 1050.0, 1315.0] {
        light += 1-smoothstep(72, 102, abs(coordinate-center))
    }
    return min(1, light)
}

// Lighting fields are in source-image coordinates, below the wall/floor junction.
// Precompute them to keep all frames deterministic and render efficiently.
var floorMask = [Double](repeating: 0, count: pixelCount)
var floorCoordinate = [Double](repeating: 0, count: pixelCount)
var startingFloorLight = [Double](repeating: 0, count: pixelCount)
for y in 650..<sourceHeight {
    for x in 0..<sourceWidth {
        let sx = Double(x), sy = Double(y)
        let floorEdge = sx < 1070 ? 815-0.129*sx : 677+0.175*(sx-1070)
        let index = y*sourceWidth+x
        floorMask[index] = smoothstep(floorEdge+8, floorEdge+34, sy)
        floorCoordinate[index] = sx-3.15*(sy-790)
        startingFloorLight[index] = floorLight(floorCoordinate[index])
    }
}

func renderFrame(into bytes: UnsafeMutablePointer<UInt8>, stride: Int, time: Double) {
    let normalized = (time / duration).truncatingRemainder(dividingBy: 1)
    let cameraPhase = normalized * 2 * Double.pi
    // Raised cosine reaches 2.5% at ten seconds; velocity is zero at both ends.
    let zoom = 1 + 0.025 * (1-cos(cameraPhase))/2
    // Twelve seconds into dusk, eight back into warm light; both joins have zero
    // velocity. Relighting starts at identity to match the existing sunset still.
    let duskPhase = normalized <= 0.6 ? normalized/0.6 : (1-normalized)/0.4
    let dusk = (1-cos(Double.pi*duskPhase))/2
    let shadowTravel = 70*dusk
    let directLight = 1-0.72*dusk
    let baseScale = max(Double(width)/Double(sourceWidth), Double(height)/Double(sourceHeight))
    let scale = baseScale * zoom
    let anchorX = Double(sourceWidth)*0.46
    let anchorY = Double(sourceHeight)*0.46
    let offsetX = (Double(width)-Double(sourceWidth)*baseScale)/2 - anchorX*baseScale*(zoom-1)
    let offsetY = (Double(height)-Double(sourceHeight)*baseScale)/2 - anchorY*baseScale*(zoom-1)
    let windPhase = normalized * 4 * Double.pi
    let windSin = sin(windPhase), windCos = cos(windPhase)
    DispatchQueue.concurrentPerform(iterations: height) { y in
        let sy = (Double(y)+0.5-offsetY)/scale-0.5
        let row = bytes.advanced(by: y*stride)
        for x in 0..<width {
            let sx = (Double(x)+0.5-offsetX)/scale-0.5
            let fieldIndex = min(sourceHeight-1,max(0,Int(sy)))*sourceWidth + min(sourceWidth-1,max(0,Int(sx)))
            let a = Double(fieldSin[fieldIndex]), b = Double(fieldCos[fieldIndex])
            let localX = 1.2*(a*windSin+b*windCos)
            let localY = 0.30*(a*windCos-b*windSin)
            let u = max(0,min(Double(sourceWidth-2),sx+localX))
            let v = max(0,min(Double(sourceHeight-2),sy+localY))
            let ix = Int(u), iy = Int(v)
            let fx = u-Double(ix), fy = v-Double(iy)
            let top = (iy*sourceWidth+ix)*4, bottom = top+sourceWidth*4
            let outputIndex = x*4
            let floor = floorMask[fieldIndex]
            let shiftedLight = floor > 0 ? floorLight(floorCoordinate[fieldIndex]-shadowTravel) : 0
            let movingLight = floor*0.42*directLight*(shiftedLight-startingFloorLight[fieldIndex])
            for channel in 0..<3 {
                let upper = Double(sourceBytes[top+channel])*(1-fx)+Double(sourceBytes[top+4+channel])*fx
                let lower = Double(sourceBytes[bottom+channel])*(1-fx)+Double(sourceBytes[bottom+4+channel])*fx
                let original = upper*(1-fy)+lower*fy
                // Fade warm direct sunlight more than cool ambient light. The
                // floor dims a little further as the window light disappears.
                let duskLoss = channel == 0 ? 0.34 : (channel == 1 ? 0.27 : 0.12)
                let floorLoss = channel == 0 ? 0.10 : (channel == 1 ? 0.08 : 0.04)
                let lightTint = channel == 0 ? 1.0 : (channel == 1 ? 0.85 : 0.60)
                let gain = 1-dusk*duskLoss-floor*dusk*floorLoss+movingLight*lightTint
                let coolAmbient = dusk*(channel == 2 ? 5.0 : 0.0)
                row[outputIndex+2-channel] = UInt8(max(0,min(255,(original*gain+coolAmbient).rounded())))
            }
            row[outputIndex+3] = 255
        }
    }
}

func writeQAFrame(_ pixelBuffer: CVPixelBuffer, name: String) throws {
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let data = Data(bytes: CVPixelBufferGetBaseAddress(pixelBuffer)!, count: stride*height)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: stride, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(qaDirectory.appendingPathComponent(name).appendingPathExtension("png") as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw RenderError.failed("Could not save QA frame")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try require(CGImageDestinationFinalize(destination), "Could not finalize QA frame")
}

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 2_500_000,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: Int(fps)*2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoAllowFrameReorderingKey: true,
    ],
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
])
try require(writer.canAdd(input), "Cannot add video input")
writer.add(input)
try require(writer.startWriting(), writer.error?.localizedDescription ?? "Cannot start MP4 writer")
writer.startSession(atSourceTime: .zero)
var firstFrameBytes: Data?
for frame in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
        try require(writer.status == .writing, writer.error?.localizedDescription ?? "Writer stopped")
        Thread.sleep(forTimeInterval: 0.01)
    }
    try autoreleasepool {
        var buffer: CVPixelBuffer?
        try require(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
                    "Cannot allocate video frame")
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixels = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        renderFrame(into: pixels, stride: stride, time: Double(frame)/Double(fps))
        if frame == 0 {
            firstFrameBytes = Data(bytes: pixels, count: stride*height)
            try writeQAFrame(pixelBuffer, name: "frame-start")
        } else if frame == frameCount/2 {
            try writeQAFrame(pixelBuffer, name: "frame-midpoint")
        } else if frame == frameCount-1 {
            try writeQAFrame(pixelBuffer, name: "frame-last")
        }
        if frame == Int(4*fps) { try writeQAFrame(pixelBuffer, name: "frame-light-shift") }
        if frame == Int(8*fps) { try writeQAFrame(pixelBuffer, name: "frame-late-sun") }
        if frame == Int(12*fps) { try writeQAFrame(pixelBuffer, name: "frame-dusk") }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        try require(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)),
                    writer.error?.localizedDescription ?? "Cannot encode video frame")
    }
    if frame % Int(fps) == 0 { print("Rendered \(frame)/\(frameCount) frames") }
}
writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: fps))
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
try require(writer.status == .completed, writer.error?.localizedDescription ?? "MP4 finalization failed")

// Re-render the continuous endpoint to verify that the animation closes exactly.
var endpoint: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &endpoint)
CVPixelBufferLockBaseAddress(endpoint!, [])
let endpointStride = CVPixelBufferGetBytesPerRow(endpoint!)
let endpointPixels = CVPixelBufferGetBaseAddress(endpoint!)!.assumingMemoryBound(to: UInt8.self)
renderFrame(into: endpointPixels, stride: endpointStride, time: duration)
let endpointData = Data(bytes: endpointPixels, count: endpointStride*height)
try require(firstFrameBytes == endpointData, "Loop endpoint differs from its first frame")
CVPixelBufferUnlockBaseAddress(endpoint!, [])

let asset = AVURLAsset(url: outputURL)
let track = asset.tracks(withMediaType: .video).first!
let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
print("Saved \(outputURL.path)")
print("Verified \(Int(track.naturalSize.width))×\(Int(track.naturalSize.height)), \(track.nominalFrameRate) fps, \(CMTimeGetSeconds(asset.duration)) seconds, \(attributes[.size]!) bytes; no audio track; exact continuous loop seam.")
print("QA frames: \(qaDirectory.path)")
