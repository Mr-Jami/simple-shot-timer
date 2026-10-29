// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import AVFoundation
import CoreImage
import Flutter
import UIKit

/// Exports a range video with the shot timer overlay
/// (lib/services/video/clip_exporter.dart), the iOS side of
/// ClipExportChannel.kt:
///
/// - `export` trims the clip to [startMs, endMs) (output time = clip time -
///   startMs), turns it upright, scales it to at most `shortSide` and
///   `maxFps`, converts HDR to SDR (BT.709) and writes H.264 with the sound
///   kept. Each overlay is a folder of images (`i.z`: premultiplied RGBA,
///   zlib) that Dart drew, image `i` showing from `timesUs[i]` (output time)
///   on, its top left at (`x`, `y`) in fractions of the frame. Progress
///   (0..1) comes back as `progress` messages; `cancel` names the job to
///   stop. Fails with `cancelled`, `no_space` or `export_failed`, leaving no
///   file, or with `busy` while another export runs. AVAssetExportSession
///   chooses the bitrate (`bitrate` is Android's), and the export stops if
///   the app goes to the background.
/// - `checkEncoderColors`: Apple's encoder converts with the matrix it tags,
///   so it never needs Android's `colorFix`.
final class ClipExportChannel: NSObject, @unchecked Sendable {
  private let channel: FlutterMethodChannel

  /// Builds the export off the main queue: it reads the clip's tracks.
  private let setup = DispatchQueue(label: "cc.jami.simpleshottimer.clip_export")

  /// The running export. Only touched on the main queue.
  private var job: Job?
  private var progressTimer: Timer?

  private final class Job {
    let id: Int
    let result: FlutterResult
    let output: URL

    /// Nil while the export is being set up.
    var session: AVAssetExportSession?

    init(id: Int, result: @escaping FlutterResult, output: URL) {
      self.id = id
      self.result = result
      self.output = output
    }
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "cc.jami.simpleshottimer/clip_export", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "export":
      if job != nil { return result(FlutterError(code: "busy", message: nil, details: nil)) }
      guard let id = (args["jobId"] as? NSNumber)?.intValue,
        let output = args["output"] as? String
      else {
        return result(FlutterError(code: "export_failed", message: "missing arguments", details: nil))
      }
      start(Job(id: id, result: result, output: URL(fileURLWithPath: output)), args)
    case "cancel":
      if let running = job, running.id == (args["jobId"] as? NSNumber)?.intValue {
        running.session?.cancelExport()
        finish(running) { $0(FlutterError(code: "cancelled", message: nil, details: nil)) }
      }
      result(nil)
    case "checkEncoderColors":
      result(["needsFix": false])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ running: Job, _ args: [String: Any]) {
    job = running
    setup.async {
      let session: AVAssetExportSession
      do {
        session = try Self.makeSession(args, output: running.output)
      } catch {
        let code = isNoSpace(error) ? "no_space" : "export_failed"
        let message = (error as? ClipFailure)?.message ?? "\(error)"
        DispatchQueue.main.async {
          self.finish(running) { $0(FlutterError(code: code, message: message, details: nil)) }
        }
        return
      }
      DispatchQueue.main.async {
        // Cancelled while it was set up: the cancel already replied.
        guard self.job === running else { return }
        running.session = session
        session.exportAsynchronously {
          DispatchQueue.main.async { self.completed(running) }
        }
        self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
          [weak self] _ in
          guard let self, let running = self.job, let session = running.session else { return }
          self.channel.invokeMethod(
            "progress", arguments: ["jobId": running.id, "fraction": Double(session.progress)])
        }
      }
    }
  }

  private func completed(_ running: Job) {
    guard let session = running.session else { return }
    switch session.status {
    case .completed:
      finish(running, made: true) { $0(nil) }
    case .cancelled:
      finish(running) { $0(FlutterError(code: "cancelled", message: nil, details: nil)) }
    default:
      let error = session.error
      let code = error.map(isNoSpace) == true ? "no_space" : "export_failed"
      finish(running) {
        $0(FlutterError(code: code, message: error.map { "\($0)" } ?? "\(session.status)", details: nil))
      }
    }
  }

  /// Ends [running] once: replies through [reply]; unless [made], deletes
  /// what was written.
  private func finish(_ running: Job, made: Bool = false, _ reply: (FlutterResult) -> Void) {
    guard job === running else { return }
    job = nil
    progressTimer?.invalidate()
    progressTimer = nil
    reply(running.result)
    if !made { try? FileManager.default.removeItem(at: running.output) }
  }

  /// The export session for [args]: the range of the clip as its own
  /// composition starting at 0, drawn by [OverlayCompositor].
  private static func makeSession(_ args: [String: Any], output: URL) throws -> AVAssetExportSession {
    func number(_ key: String) -> NSNumber? { args[key] as? NSNumber }
    guard let input = args["input"] as? String,
      let startMs = number("startMs")?.int64Value,
      let endMs = number("endMs")?.int64Value
    else { throw ClipFailure("export_failed", "missing arguments") }
    let asset = AVURLAsset(
      url: URL(fileURLWithPath: input),
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let source = asset.tracks(withMediaType: .video).first else {
      throw ClipFailure("export_failed", "no video track")
    }
    let requested = CMTimeRangeFromTimeToTime(
      start: CMTime(value: startMs, timescale: 1000),
      end: CMTime(value: endMs, timescale: 1000))
    let range = CMTimeRangeGetIntersection(requested, otherRange: source.timeRange)
    guard range.duration.seconds > 0 else { throw ClipFailure("export_failed", "empty range") }
    // Output time = clip time - startMs, also when the picture starts a little
    // after startMs (a track that begins after 0): that gap stays black.
    func insert(_ range: CMTimeRange, of track: AVAssetTrack, into target: AVMutableCompositionTrack)
      throws
    {
      let at = CMTimeSubtract(range.start, requested.start)
      if at.seconds > 0 { target.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: at)) }
      try target.insertTimeRange(range, of: track, at: at)
    }

    let composition = AVMutableComposition()
    guard
      let video = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw ClipFailure("export_failed", "no composition track") }
    try insert(range, of: source, into: video)
    // Sound within the picture's range only.
    if let sound = ClipAudioChannel.audioTrack(of: asset) {
      let soundRange = CMTimeRangeGetIntersection(range, otherRange: sound.timeRange)
      if soundRange.duration.seconds > 0,
        let track = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      {
        try insert(soundRange, of: sound, into: track)
      }
    }

    let overlays = try ((args["overlays"] as? [[String: Any]]) ?? []).map(OverlayFrames.init)
    let videoComposition = AVMutableVideoComposition()
    videoComposition.customVideoCompositorClass = OverlayCompositor.self
    videoComposition.renderSize = renderSize(
      upright(source), shortSide: number("shortSide")?.intValue)
    videoComposition.frameDuration = frameDuration(source, maxFps: number("maxFps")?.doubleValue)
    // SDR out; HDR sources are tone-mapped into this before the compositor
    // sees them, since it doesn't declare HDR support.
    videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    videoComposition.instructions = [
      OverlayInstruction(
        timeRange: CMTimeRange(start: .zero, duration: composition.duration),
        trackID: video.trackID,
        orientation: orientation(source.preferredTransform),
        overlays: overlays)
    ]

    try? FileManager.default.removeItem(at: output)
    guard
      let session = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { throw ClipFailure("export_failed", "no export session") }
    session.outputURL = output
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    session.videoComposition = videoComposition
    return session
  }

  /// The picture's size as displayed (rotation applied).
  private static func upright(_ track: AVAssetTrack) -> CGSize {
    let size = track.naturalSize.applying(track.preferredTransform)
    return CGSize(width: abs(size.width), height: abs(size.height))
  }

  /// [upright] scaled to at most [shortSide] on its short side, with even
  /// sides: the frame ExportPlan (export_plan.dart) drew the overlay for.
  private static func renderSize(_ upright: CGSize, shortSide: Int?) -> CGSize {
    let short = min(upright.width, upright.height)
    var scale: CGFloat = 1
    if let shortSide, short > CGFloat(shortSide) { scale = CGFloat(shortSide) / short }
    func even(_ v: CGFloat) -> CGFloat { (v / 2).rounded() * 2 }
    return CGSize(width: even(upright.width * scale), height: even(upright.height * scale))
  }

  /// One frame at the clip's own rate, capped at [maxFps]: the rate
  /// ExportPlan drew one overlay image per frame for.
  private static func frameDuration(_ track: AVAssetTrack, maxFps: Double?) -> CMTime {
    var fps = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30
    if let maxFps, maxFps > 0 { fps = min(fps, maxFps) }
    return CMTime(seconds: 1 / fps, preferredTimescale: 60_000)
  }

  private static func orientation(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
    switch rotationDegrees(transform) {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }
}

/// The one instruction of an export: the source track to draw upright, and
/// the overlays on top.
private final class OverlayInstruction: NSObject, AVVideoCompositionInstructionProtocol,
  @unchecked Sendable
{
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = true
  let requiredSourceTrackIDs: [NSValue]?
  let passthroughTrackID = kCMPersistentTrackID_Invalid

  let trackID: CMPersistentTrackID
  let orientation: CGImagePropertyOrientation
  let overlays: [OverlayFrames]

  init(
    timeRange: CMTimeRange, trackID: CMPersistentTrackID,
    orientation: CGImagePropertyOrientation, overlays: [OverlayFrames]
  ) {
    self.timeRange = timeRange
    self.trackID = trackID
    self.orientation = orientation
    self.overlays = overlays
    requiredSourceTrackIDs = [NSNumber(value: trackID)]
  }
}

/// Draws each output frame: the source turned upright and scaled to the
/// render size, then the overlay images for its time. Requests are drawn
/// one at a time on [queue].
private final class OverlayCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
  private let queue = DispatchQueue(label: "cc.jami.simpleshottimer.clip_export.render")

  /// Pixel values pass through unchanged, as on Android: the overlay's
  /// colours land in the video as Dart drew them.
  private let context = CIContext(options: [
    .workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false,
  ])
  private let lock = NSLock()
  private var cancelling = false

  let sourcePixelBufferAttributes: [String: any Sendable]? = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
  ]
  let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
  ]

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    queue.async {
      if self.isCancelling {
        request.finishCancelledRequest()
        return
      }
      do {
        let frame = try self.render(request)
        request.finish(withComposedVideoFrame: frame)
      } catch {
        request.finish(with: error)
      }
    }
  }

  func cancelAllPendingVideoCompositionRequests() {
    // Queued requests finish as cancelled; new ones are drawn again.
    isCancelling = true
    queue.async { self.isCancelling = false }
  }

  private var isCancelling: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return cancelling
    }
    set {
      lock.lock()
      cancelling = newValue
      lock.unlock()
    }
  }

  private func render(_ request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
    guard let instruction = request.videoCompositionInstruction as? OverlayInstruction,
      let out = request.renderContext.newPixelBuffer()
    else { throw ClipFailure("export_failed", "no frame to draw into") }
    let size = request.renderContext.size
    let bounds = CGRect(origin: .zero, size: size)

    var frame: CIImage
    if let source = request.sourceFrame(byTrackID: instruction.trackID) {
      frame = CIImage(cvPixelBuffer: source, options: [.colorSpace: NSNull()])
        .oriented(instruction.orientation)
      frame = frame.transformed(
        by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
      let sx = size.width / frame.extent.width
      let sy = size.height / frame.extent.height
      if sx != 1 || sy != 1 { frame = frame.transformed(by: CGAffineTransform(scaleX: sx, y: sy)) }
    } else {
      frame = CIImage(color: .black).cropped(to: bounds)
    }

    // Core Image counts y from the bottom; the overlay's y from the top.
    let timeUs = microseconds(request.compositionTime)
    for overlay in instruction.overlays {
      let image = try overlay.image(at: timeUs)
      let x = (overlay.x * size.width).rounded()
      let y = (size.height - overlay.y * size.height - CGFloat(overlay.height)).rounded()
      frame = image.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: frame)
    }

    context.render(frame.cropped(to: bounds), to: out, bounds: bounds, colorSpace: nil)
    CVBufferSetAttachment(
      out, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2,
      .shouldPropagate)
    CVBufferSetAttachment(
      out, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2,
      .shouldPropagate)
    CVBufferSetAttachment(
      out, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    return out
  }
}

/// Image `i` of [dir] (`i.z`, [width] x [height] premultiplied RGBA, zlib)
/// from [timesUs]`[i]` on. Keeps the image last shown; used by one
/// compositor's queue only.
private final class OverlayFrames: @unchecked Sendable {
  let dir: URL
  let timesUs: [Int64]
  let width: Int
  let height: Int
  let x: CGFloat
  let y: CGFloat

  private var current = -1
  private var shown: CIImage?

  init(_ map: [String: Any]) throws {
    guard let dir = map["dir"] as? String,
      let times = map["timesUs"] as? [NSNumber], !times.isEmpty,
      let width = (map["width"] as? NSNumber)?.intValue,
      let height = (map["height"] as? NSNumber)?.intValue,
      let x = (map["x"] as? NSNumber)?.doubleValue,
      let y = (map["y"] as? NSNumber)?.doubleValue
    else { throw ClipFailure("export_failed", "bad overlay") }
    self.dir = URL(fileURLWithPath: dir, isDirectory: true)
    timesUs = times.map { $0.int64Value }
    self.width = width
    self.height = height
    self.x = CGFloat(x)
    self.y = CGFloat(y)
  }

  /// The image showing at [timeUs] (output time).
  func image(at timeUs: Int64) throws -> CIImage {
    // The last image that starts at or before timeUs.
    var low = 0
    var high = timesUs.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if timesUs[mid] <= timeUs { low = mid } else { high = mid - 1 }
    }
    if low == current, let shown { return shown }
    let image = CIImage(
      bitmapData: try pixels(low), bytesPerRow: width * 4,
      size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
    current = low
    shown = image
    return image
  }

  /// Image [i]'s pixels. Dart writes zlib (RFC 1950); Apple's decoder takes
  /// the raw deflate stream between its 2-byte header and 4-byte checksum.
  private func pixels(_ i: Int) throws -> Data {
    let file = try Data(contentsOf: dir.appendingPathComponent("\(i).z"))
    guard file.count > 6 else { throw ClipFailure("export_failed", "overlay \(i) is empty") }
    let deflated = file.subdata(in: 2..<(file.count - 4)) as NSData
    let pixels = try deflated.decompressed(using: .zlib) as Data
    guard pixels.count == width * height * 4 else {
      throw ClipFailure("export_failed", "overlay \(i) has \(pixels.count) bytes")
    }
    return pixels
  }
}
