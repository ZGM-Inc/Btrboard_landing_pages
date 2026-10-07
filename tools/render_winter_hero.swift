// Native, deterministic animated-photo renderer for the version B winter hero.
// The camera and house are fixed. Snow is composited in depth layers, and a tiny
// photographic resident crosses the bedroom behind its real frame and furniture.
// Compile:
// swiftc -O -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -target arm64-apple-macosx15.0 -module-cache-path /tmp/btr-swift-cache tools/render_winter_hero.swift -o /tmp/btr-render-winter
// Render (refuses to overwrite an existing output):
// /tmp/btr-render-winter assets/img/gen-home-dusk.png assets/img/hero-winter-resident-sprites.png assets/video/hero-home-winter-life.mp4

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum RenderError: Error { case failed(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw RenderError.failed(message) }
}
@inline(__always) func smoothstep(_ a: Double, _ b: Double, _ value: Double) -> Double {
    let t = max(0, min(1, (value-a)/(b-a)))
    return t*t*(3-2*t)
}
@inline(__always) func clampByte(_ value: Double) -> UInt8 {
    UInt8(max(0, min(255, value.rounded())))
}
let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("Usage: render_winter_hero HOUSE.png RESIDENT_SPRITES.png OUTPUT.mp4\n", stderr)
    exit(1)
}
let outputURL = URL(fileURLWithPath: args[3])
let width = 1376, height = 768, fps: Int32 = 24
let duration = 20.0, frameCount = 480
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let qaDirectory = URL(fileURLWithPath: "/tmp/btr-winter-video-qa", isDirectory: true)
try FileManager.default.createDirectory(at: qaDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try require(!FileManager.default.fileExists(atPath: outputURL.path), "Output already exists; choose a new output path.")

func decode(_ path: String, expectedWidth: Int, expectedHeight: Int) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw RenderError.failed("Could not decode \(path)")
    }
    try require(image.width == expectedWidth && image.height == expectedHeight,
                "Unexpected image dimensions; masks and sprite layout use native pixel coordinates.")
    var bytes = [UInt8](repeating: 0, count: expectedWidth*expectedHeight*4)
    try bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: expectedWidth, height: expectedHeight,
            bitsPerComponent: 8, bytesPerRow: expectedWidth*4, space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.failed("Could not allocate image context")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight))
    }
    return bytes
}
let house = try decode(args[1], expectedWidth: width, expectedHeight: height)
let spriteWidth = 1536, spriteHeight = 1024
let spriteBytes = try decode(args[2], expectedWidth: spriteWidth, expectedHeight: spriteHeight)
var baseBGRA = [UInt8](repeating: 255, count: width*height*4)
for p in 0..<(width*height) {
    baseBGRA[p*4] = house[p*4+2]
    baseBGRA[p*4+1] = house[p*4+1]
    baseBGRA[p*4+2] = house[p*4]
}

// Masks use top-left photo coordinates. A one-pixel edge preserves the original
// window frame. The vertical mullion always remains in front of the resident.
@inline(__always) func glassMask(_ x: Double, _ y: Double) -> Double {
    let top = 264-(x-1080)*16/133
    let bottom = 348-(x-1080)*14/133
    let edge = min(x-1080, 1213-x, y-top, bottom-y)
    let outer = smoothstep(0, 1.1, edge)
    let mullion = 1-smoothstep(1168.4, 1169.5, x)*(1-smoothstep(1177.8, 1179, x))
    return outer*mullion
}
@inline(__always) func residentMask(_ x: Double, _ y: Double) -> Double {
    let glass = glassMask(x, y)
    // Foreground bed rises toward the right-hand side of the bedroom.
    let bedEdge = x < 1113 ? 345-(x-1102)*1.02 : 333.8-(x-1113)*0.11
    let bed = smoothstep(1102, 1106, x)*smoothstep(bedEdge-0.8, bedEdge+0.8, y)
    // The raised pillow in the right pane is also in front of the resident.
    let pillowEdge: Double
    if x < 1195 { pillowEdge = 328-(x-1189)*11/6 }
    else if x < 1207 { pillowEdge = 317-(x-1195)*9/12 }
    else { pillowEdge = 308+(x-1207)*12/4 }
    let pillow = smoothstep(1188.5, 1190, x)*(1-smoothstep(1211, 1213, x))
        * smoothstep(pillowEdge-0.7, pillowEdge+0.7, y)
    return glass*(1-max(bed, pillow))
}
struct WindowPixel { let x, y: Int; let glass, resident: Double }
var windowPixels: [WindowPixel] = []
for y in 246...350 {
    for x in 1078...1215 {
        let glass = glassMask(Double(x)+0.5, Double(y)+0.5)
        if glass > 0 {
            windowPixels.append(.init(x: x, y: y, glass: glass,
                resident: residentMask(Double(x)+0.5, Double(y)+0.5)))
        }
    }
}

// Lighting includes the illuminated reveals, sill and mullion edges. The
// resident's smaller glass mask is only an occlusion mask; using it for light
// left bright strips around each pane when the room went dark.
@inline(__always) func roomLightMask(_ x: Double, _ y: Double) -> Double {
    let top = 259-(x-1075)*16.5/142
    let bottom = 353-(x-1075)*14.5/142
    let edge = min(x-1075, 1217-x, y-top, bottom-y)
    // Feather outside the lit reveal, where the original frame is already dark.
    return smoothstep(-3, 0, edge)
}
struct RoomLightPixel { let x, y: Int; let weight: Double; let offBGR: [Double] }
var roomLightPixels: [RoomLightPixel] = []
for y in 238...357 {
    for x in 1071...1221 {
        let weight = roomLightMask(Double(x)+0.5, Double(y)+0.5)
        if weight <= 0 { continue }
        let index = (y*width+x)*4
        let blue = Double(baseBGRA[index]), green = Double(baseBGRA[index+1])
        let red = Double(baseBGRA[index+2])
        let luminance = red*0.2126+green*0.7152+blue*0.0722
        // A cool, dim ambient room retains detail without the old green cast.
        // Already-dark structural frames respond less than the glowing room.
        let materialResponse = 0.35+0.65*smoothstep(20, 75, luminance)
        roomLightPixels.append(.init(x: x, y: y, weight: weight*materialResponse,
            offBGR: [luminance*0.28, luminance*0.21, luminance*0.17]))
    }
}

// Threshold only the near-transparent haze in the generated cutout, then keep
// soft anti-aliased edges. Store premultiplied, warm interior-colour RGB samples.
struct SpritePixel { let r, g, b, a: Double }
var sprites = [SpritePixel](repeating: .init(r: 0, g: 0, b: 0, a: 0), count: spriteWidth*spriteHeight)
for i in 0..<(spriteWidth*spriteHeight) {
    let sourceAlpha = Double(spriteBytes[i*4+3])/255
    let alpha = sourceAlpha*smoothstep(0.035, 0.18, sourceAlpha)
    if alpha > 0 {
        let unpremultiply = 1/max(sourceAlpha, 0.001)
        let red = Double(spriteBytes[i*4])*unpremultiply*0.91+9
        let green = Double(spriteBytes[i*4+1])*unpremultiply*0.85+7
        let blue = Double(spriteBytes[i*4+2])*unpremultiply*0.77+5
        sprites[i] = .init(r: red*alpha, g: green*alpha, b: blue*alpha, a: alpha)
    }
}
// Prefilter the one selected cutout before reducing it to a 58-pixel resident.
// Sampling the original 445-pixel person directly at this size made hair/clothes
// shimmer as the sampling grid moved, even with an otherwise stable pose.
let residentTextureWidth = 384, residentTextureHeight = 512
let blurRadius = 5, blurSigma = 2.2
let blurWeights = (-blurRadius...blurRadius).map { exp(-Double($0*$0)/(2*blurSigma*blurSigma)) }
let blurWeightSum = blurWeights.reduce(0,+)
var residentHorizontal = [SpritePixel](repeating: .init(r: 0, g: 0, b: 0, a: 0), count: residentTextureWidth*residentTextureHeight)
var residentTexture = residentHorizontal
for y in 0..<residentTextureHeight {
    for x in 0..<residentTextureWidth {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for offset in -blurRadius...blurRadius {
            let xx = min(residentTextureWidth-1, max(0, x+offset))
            let sample = sprites[y*spriteWidth+2*384+xx]
            let weight = blurWeights[offset+blurRadius]/blurWeightSum
            r += sample.r*weight; g += sample.g*weight; b += sample.b*weight; a += sample.a*weight
        }
        residentHorizontal[y*residentTextureWidth+x] = .init(r: r, g: g, b: b, a: a)
    }
}
for y in 0..<residentTextureHeight {
    for x in 0..<residentTextureWidth {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for offset in -blurRadius...blurRadius {
            let yy = min(residentTextureHeight-1, max(0, y+offset))
            let sample = residentHorizontal[yy*residentTextureWidth+x]
            let weight = blurWeights[offset+blurRadius]/blurWeightSum
            r += sample.r*weight; g += sample.g*weight; b += sample.b*weight; a += sample.a*weight
        }
        residentTexture[y*residentTextureWidth+x] = .init(r: r, g: g, b: b, a: a)
    }
}
residentHorizontal.removeAll(keepingCapacity: false)
// One photographic pose is used for the entire crossing. Blending separate
// generated gait cells changed the person's outline and produced ghost limbs.
// A continuous, low-amplitude deformation gives this fixed cutout an arm swing
// and subtle leg movement without ever replacing its head, clothing or texture.
struct ResidentRig {
    let nearArmSin, nearArmCos, farArmSin, farArmCos, legSin, legCos: Double
    init(phase: Double) {
        let armAngle = 0.125*sin(phase)
        let farAngle = -0.11*sin(phase)
        let legAngle = 0.070*sin(phase)
        nearArmSin = sin(armAngle); nearArmCos = cos(armAngle)
        farArmSin = sin(farAngle); farArmCos = cos(farAngle)
        legSin = sin(legAngle); legCos = cos(legAngle)
    }
}
@inline(__always) func residentDisplacement(_ x: Double, _ y: Double, rig: ResidentRig) -> (Double, Double) {
    let nearWeight = smoothstep(110, 148, y)*(1-smoothstep(285, 307, y))
        * (1-smoothstep(169, 216, x))
    let farWeight = smoothstep(157, 197, y)*(1-smoothstep(280, 301, y))
        * smoothstep(200, 243, x)
    let nearX = x-164, nearY = y-117
    let farX = x-215, farY = y-160
    var dx = nearWeight*(nearX*(rig.nearArmCos-1)-nearY*rig.nearArmSin)
        + farWeight*(farX*(rig.farArmCos-1)-farY*rig.farArmSin)
    var dy = nearWeight*(nearX*rig.nearArmSin+nearY*(rig.nearArmCos-1))
        + farWeight*(farX*rig.farArmSin+farY*(rig.farArmCos-1))
    let legWeight = smoothstep(269, 301, y)
    let nearLeg = smoothstep(151, 219, x)
    let legX = x-193, legY = y-268
    let signedSin = rig.legSin*(2*nearLeg-1)
    dx += legWeight*(legX*(rig.legCos-1)-legY*signedSin)
    dy += legWeight*(legX*signedSin+legY*(rig.legCos-1))
    return (dx, dy)
}
@inline(__always) func spriteSample(localX: Double, localY: Double, rig: ResidentRig) -> SpritePixel {
    let targetX = localX+211, targetY = localY+22
    var sx = targetX, sy = targetY
    // Invert a smooth source-space deformation, preserving a single solid
    // silhouette rather than cross-fading two independently placed silhouettes.
    for _ in 0..<5 {
        let displacement = residentDisplacement(sx, sy, rig: rig)
        sx = targetX-displacement.0
        sy = targetY-displacement.1
    }
    if sx < 0 || sx >= 383 || sy < 0 || sy >= 511 { return .init(r: 0, g: 0, b: 0, a: 0) }
    let left = Int(sx), top = Int(sy), fx = sx-Double(left), fy = sy-Double(top)
    let index = top*residentTextureWidth+left
    let a = residentTexture[index], b = residentTexture[index+1]
    let c = residentTexture[index+residentTextureWidth], d = residentTexture[index+residentTextureWidth+1]
    let aa = (1-fx)*(1-fy), bb = fx*(1-fy), cc = (1-fx)*fy, dd = fx*fy
    return .init(r: a.r*aa+b.r*bb+c.r*cc+d.r*dd,
                 g: a.g*aa+b.g*bb+c.g*cc+d.g*dd,
                 b: a.b*aa+b.b*bb+c.b*cc+d.b*dd,
                 a: a.a*aa+b.a*bb+c.a*cc+d.a*dd)
}

// Periodic falling paths wrap entirely outside the picture. Each layer traverses
// an integer number of complete paths in twenty seconds, giving an exact seam.
struct Snowflake { let x, phase, radius, alpha, wind, sway: Double; let turns: Int }
var seed: UInt64 = 0x42545257494E5445
func random() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11)/9007199254740992
}
var snowflakes: [Snowflake] = []
for layer in 0..<3 {
    // Readable snowfall across the full hero, with most flakes small/far away
    // and a restrained number of softer foreground flakes for depth.
    let count = [400, 250, 65][layer]
    for _ in 0..<count {
        let radius = [0.60, 1.25, 2.15][layer]*(0.70+0.65*random())
        snowflakes.append(.init(x: random()*(Double(width)+160)-80, phase: random(), radius: radius,
            alpha: [0.50, 0.68, 0.50][layer]*(0.65+0.35*random()),
            wind: 26+random()*30, sway: 3+random()*7, turns: layer+1))
    }
}

func renderFrame(into bytes: UnsafeMutablePointer<UInt8>, stride: Int, time: Double) {
    let t = time.truncatingRemainder(dividingBy: duration)
    baseBGRA.withUnsafeBytes { base in
        for y in 0..<height {
            memcpy(bytes.advanced(by: y*stride), base.baseAddress!.advanced(by: y*width*4), width*4)
            if stride > width*4 { memset(bytes.advanced(by: y*stride+width*4), 0, stride-width*4) }
        }
    }
    // The resident leaves the visible room, then its warm lamp fades down.
    // Returning light is gradual; source illumination is restored well before
    // the loop ends and remains unchanged at both sides of the seam.
    let dim = smoothstep(10.1, 11.1, t)*(1-smoothstep(16, 17.3, t))
    let residentActive = t >= 3 && t <= 10
    let walkProgress = (t-3)/7
    let walkPhase = (t-3)*2*Double.pi*0.90
    let residentX = 1054+walkProgress*187+0.12*sin(2*walkPhase)
    // A lower, slightly smaller figure sits behind the foreground bed: only the
    // upper body and occasional upper leg are visible, never feet on the duvet.
    let residentTop = 292.0+0.24*cos(2*walkPhase)
    let residentScale = 58.0/445.0
    let residentRig = ResidentRig(phase: walkPhase)
    if dim > 0 {
        for pixel in roomLightPixels {
            let index = pixel.y*stride+pixel.x*4
            for c in 0..<3 {
                let original = Double(bytes[index+c])
                bytes[index+c] = clampByte(original+(pixel.offBGR[c]-original)*dim*pixel.weight)
            }
        }
    }
    for pixel in windowPixels {
        let index = pixel.y*stride+pixel.x*4
        if residentActive && pixel.resident > 0 {
            let localX = (Double(pixel.x)+0.5-residentX)/residentScale
            let localY = (Double(pixel.y)+0.5-residentTop)/residentScale
            let sample = spriteSample(localX: localX, localY: localY, rig: residentRig)
            let opacity = pixel.resident*0.94
            let alpha = sample.a*opacity
            if alpha > 0 {
                let foreground = [sample.b, sample.g, sample.r]
                for c in 0..<3 {
                    bytes[index+c] = clampByte(Double(bytes[index+c])*(1-alpha)+foreground[c]*opacity)
                }
            }
        }
    }
    for flake in snowflakes {
        let phase = (flake.phase+t/duration*Double(flake.turns)).truncatingRemainder(dividingBy: 1)
        let y = phase*(Double(height)+24)-12
        let x = flake.x+flake.wind*phase+flake.sway*sin(phase*2*Double.pi)
        let rx = max(0.55, flake.radius), ry = rx*(flake.turns == 3 ? 1.65 : 1.25)
        let left = max(0, Int(floor(x-rx*2.3))), right = min(width-1, Int(ceil(x+rx*2.3)))
        let top = max(0, Int(floor(y-ry*2.3))), bottom = min(height-1, Int(ceil(y+ry*2.3)))
        if left > right || top > bottom { continue }
        for yy in top...bottom {
            for xx in left...right {
                let dx = (Double(xx)+0.5-x)/rx, dy = (Double(yy)+0.5-y)/ry
                let distance = dx*dx+dy*dy
                if distance > 5.3 { continue }
                let alpha = flake.alpha*exp(-1.4*distance)
                let index = yy*stride+xx*4
                for c in 0..<3 {
                    let snowColor = [255.0, 246.0, 234.0][c]
                    bytes[index+c] = clampByte(Double(bytes[index+c])*(1-alpha)+snowColor*alpha)
                }
            }
        }
    }
}

func writeQAFrame(_ buffer: CVPixelBuffer, name: String) throws {
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let data = Data(bytes: CVPixelBufferGetBaseAddress(buffer)!, count: stride*height)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: stride, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(qaDirectory.appendingPathComponent(name).appendingPathExtension("png") as CFURL,
            UTType.png.identifier as CFString, 1, nil) else { throw RenderError.failed("Could not save QA image") }
    CGImageDestinationAddImage(destination, image, nil)
    try require(CGImageDestinationFinalize(destination), "Could not finalize QA image")
}

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000,
        AVVideoExpectedSourceFrameRateKey: fps, AVVideoMaxKeyFrameIntervalKey: Int(fps)*2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoAllowFrameReorderingKey: true],
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
try require(writer.canAdd(input), "Cannot add video input")
writer.add(input)
try require(writer.startWriting(), writer.error?.localizedDescription ?? "Cannot start writer")
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
                    "Cannot allocate frame")
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixels = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        renderFrame(into: pixels, stride: stride, time: Double(frame)/Double(fps))
        if frame == 0 { firstFrameBytes = Data(bytes: pixels, count: stride*height) }
        if [0, 4, 6, 8, 12, 18].contains(frame/Int(fps)) && frame%Int(fps) == 0 {
            try writeQAFrame(pixelBuffer, name: "frame-\(frame/Int(fps))s")
        }
        if frame >= 108 && frame <= 144 && frame%2 == 0 {
            try writeQAFrame(pixelBuffer, name: String(format: "walk-%03d", frame))
        }
        if frame == frameCount-1 { try writeQAFrame(pixelBuffer, name: "frame-last") }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        try require(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)),
                    writer.error?.localizedDescription ?? "Cannot append frame")
    }
    if frame%Int(fps*2) == 0 { print("Rendered \(frame)/\(frameCount) frames") }
}
writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: fps))
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
try require(writer.status == .completed, writer.error?.localizedDescription ?? "MP4 finalization failed")

var endpoint: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &endpoint)
CVPixelBufferLockBaseAddress(endpoint!, [])
let endpointStride = CVPixelBufferGetBytesPerRow(endpoint!)
let endpointPixels = CVPixelBufferGetBaseAddress(endpoint!)!.assumingMemoryBound(to: UInt8.self)
renderFrame(into: endpointPixels, stride: endpointStride, time: duration)
let endpointData = Data(bytes: endpointPixels, count: endpointStride*height)
try require(firstFrameBytes == endpointData, "Continuous loop endpoint differs from the first frame")
try writeQAFrame(endpoint!, name: "frame-endpoint")
CVPixelBufferUnlockBaseAddress(endpoint!, [])
let asset = AVURLAsset(url: outputURL)
let track = asset.tracks(withMediaType: .video).first!
try require(asset.tracks(withMediaType: .audio).isEmpty, "Unexpected audio track")
let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
print("Saved \(outputURL.path)")
print("Verified \(Int(track.naturalSize.width))×\(Int(track.naturalSize.height)), \(track.nominalFrameRate) fps, \(CMTimeGetSeconds(asset.duration)) seconds, \(attributes[.size]!) bytes; silent; exact continuous loop endpoint.")
print("QA frames: \(qaDirectory.path)")
