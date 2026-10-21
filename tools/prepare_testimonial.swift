// Prepare the supplied interview for the web using native macOS media tools.
// Run: swift tools/prepare_testimonial.swift INPUT.mp4 OUTPUT_ASSETS_DIRECTORY [--poster-only]
// The source is never changed. Choose an empty output directory when rerunning.
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum PreparationError: Error { case failed(String) }
let arguments = CommandLine.arguments
guard arguments.count == 3 || (arguments.count == 4 && arguments[3] == "--poster-only") else {
    fputs("Usage: prepare_testimonial.swift INPUT.mp4 OUTPUT_ASSETS_DIRECTORY [--poster-only]\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let videoDirectory = root.appendingPathComponent("video", isDirectory: true)
let imageDirectory = root.appendingPathComponent("img/opt", isDirectory: true)
let videoURL = videoDirectory.appendingPathComponent("jay-westman-interview-v4-1080p.mp4")
let posterOnly = arguments.last == "--poster-only"
guard posterOnly || !FileManager.default.fileExists(atPath: videoURL.path) else {
    throw PreparationError.failed("Output exists; use another output directory.")
}
try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
if !posterOnly {
let duration = try await asset.load(.duration)
guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
    throw PreparationError.failed("Could not create a 1080p export.")
}
export.shouldOptimizeForNetworkUse = true
export.fileLengthLimit = 80_000_000
export.metadata = []
print("Exporting full \(CMTimeGetSeconds(duration))-second interview at 1080p...")
fflush(stdout)
try await export.export(to: videoURL, as: .mp4)
let bytes = try videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
guard bytes > 0 && bytes < 100_000_000 else {
    throw PreparationError.failed("Unexpected output size: \(bytes) bytes; inspect before publishing.")
}
print("Video: \(videoURL.path) (\(bytes) bytes)")
}

// Opening title shot matching the user's selected still, with Jay's name and role.
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
for width in [700, 1280, 1920] {
    generator.maximumSize = CGSize(width: Double(width), height: Double(width) * 9 / 16)
    let (image, _) = try await generator.image(at: CMTime(seconds: 8, preferredTimescale: 600))
    let poster = imageDirectory.appendingPathComponent("jay-westman-interview-v4-title-\(width).jpg")
    guard let destination = CGImageDestinationCreateWithURL(poster as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw PreparationError.failed("Could not create poster.")
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw PreparationError.failed("Could not save poster.")
    }
    print("Poster: \(poster.path)")
}
