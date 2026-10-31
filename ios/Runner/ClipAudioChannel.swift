// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import AVFoundation
import Flutter
import UIKit

/// Reads a video clip's sound for the offline clip analyzer
/// (lib/services/video/clip_audio_source.dart), the iOS side of
/// ClipAudioChannel.kt: `probe` describes the clip, `decode` writes its
/// audio (or a window of it) as raw little-endian 16-bit mono PCM (the first
/// channel) to a file the Dart side owns and deletes, and for clips too long
/// to analyse whole, `loudness` and `thumbnails` feed the Choose-the-part
/// screen.
///
/// Decode and loudness share one background queue, and probe and thumbnails
/// run on a second one so they never wait behind them; the replies and the
/// messages a job sends back go out on the main queue, in order. A job stops
/// when cancel names it. Failures carry the codes the Dart side maps:
/// no_audio_track, unsupported_codec, unreadable_file, unsupported_file,
/// no_space, decode_failed, cancelled.
final class ClipAudioChannel: NSObject, @unchecked Sendable {
  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "cc.jami.simpleshottimer.clip_audio")

  /// Probes and thumbnails: quick work that must not wait behind a decode.
  private let light = DispatchQueue(label: "cc.jami.simpleshottimer.clip_audio.light")
  private let lock = NSLock()
  private var cancelled = Set<Int>()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "cc.jami.simpleshottimer/clip_audio", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let path = args["path"] as? String
    let jobId = (args["jobId"] as? NSNumber)?.intValue
    switch call.method {
    case "probe":
      reply(result, on: light) { try self.probe(argument(path, "path")) }
    case "decode":
      let startMs = (args["startMs"] as? NSNumber)?.int64Value ?? 0
      let endMs = (args["endMs"] as? NSNumber)?.int64Value
      reply(result, on: worker) {
        try self.decode(
          path: argument(path, "path"),
          outputPath: argument(args["outputPath"] as? String, "outputPath"),
          jobId: jobId,
          startUs: startMs * 1000,
          endUs: endMs.map { $0 * 1000 })
      }
    case "loudness":
      let bucketMs = (args["bucketMs"] as? NSNumber)?.intValue ?? 250
      reply(result, on: worker) {
        try self.loudness(path: argument(path, "path"), jobId: jobId ?? 0, bucketMs: bucketMs)
      }
    case "thumbnails":
      let timesMs = (args["timesMs"] as? [NSNumber])?.map { $0.int64Value } ?? []
      let width = (args["width"] as? NSNumber)?.intValue ?? 160
      reply(result, on: light) {
        try self.thumbnails(
          path: argument(path, "path"), jobId: jobId ?? 0, timesMs: timesMs, width: width)
      }
    case "cancel":
      // Answered here, not on the worker: it must not wait behind the decode
      // it stops. A job cancelled before it starts never runs.
      if let jobId {
        lock.lock()
        cancelled.insert(jobId)
        lock.unlock()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Whether [jobId] was cancelled; each cancel is taken once.
  private func takeCancel(_ jobId: Int?) -> Bool {
    guard let jobId else { return false }
    lock.lock()
    defer { lock.unlock() }
    return cancelled.remove(jobId) != nil
  }

  private func reply(
    _ result: @escaping FlutterResult, on queue: DispatchQueue,
    _ work: @escaping () throws -> Any?
  ) {
    queue.async {
      let value: Any?
      do {
        value = try work()
      } catch let failure as ClipFailure {
        DispatchQueue.main.async {
          result(FlutterError(code: failure.code, message: failure.message, details: nil))
        }
        return
      } catch {
        let code = isNoSpace(error) ? "no_space" : "decode_failed"
        DispatchQueue.main.async {
          result(FlutterError(code: code, message: "\(error)", details: nil))
        }
        return
      }
      DispatchQueue.main.async { result(value) }
    }
  }

  private func send(_ method: String, _ arguments: [String: Any]) {
    DispatchQueue.main.async { self.channel.invokeMethod(method, arguments: arguments) }
  }

  private func probe(_ path: String) throws -> [String: Any] {
    let asset = try open(path)
    let audio = Self.audioTrack(of: asset)
    let video = asset.tracks(withMediaType: .video).first
    var info: [String: Any] = [
      "hasAudio": audio != nil,
      "durationMs": Int(max(0, microseconds(asset.duration)) / 1000),
      "rotation": 0,
    ]
    if let audio, let format = firstFormat(of: audio) {
      info["audioMime"] = Self.mime(audio: CMFormatDescriptionGetMediaSubType(format))
    }
    if let video, let format = firstFormat(of: video) {
      // A video this iPhone can't play (no decoder) counts as none.
      if video.isPlayable {
        info["videoMime"] = Self.mime(video: CMFormatDescriptionGetMediaSubType(format))
      }
      let transform = video.preferredTransform
      info["rotation"] = rotationDegrees(transform)
      let size = video.naturalSize.applying(transform)
      info["width"] = Int(abs(size.width).rounded())
      info["height"] = Int(abs(size.height).rounded())
      if let transfer = Self.transfer(format) { info["colorTransfer"] = transfer }
      if video.nominalFrameRate > 0 {
        info["frameRate"] = Double(video.nominalFrameRate)
      }
    }
    // Android writes the rate a slow-motion or time-lapse clip was recorded
    // at. iPhone slow motion is a normal high-frame-rate file with real-time
    // sound, so it needs no such tag.
    let capture = asset.metadata(forFormat: .quickTimeMetadata).first {
      ($0.key as? String) == "com.android.capture.fps"
    }
    if let rate = capture?.numberValue?.doubleValue, rate > 0 {
      info["captureFrameRate"] = rate
    }
    // Files without a date carry 1904-01-01 (the MP4 epoch).
    if let date = asset.creationDate?.dateValue, date.timeIntervalSince1970 > 0 {
      info["creationTimeMs"] = Int(date.timeIntervalSince1970 * 1000)
    }
    return info
  }

  /// Writes [path]'s sound from [startUs] to [endUs] (nil: to the end) as
  /// 16-bit little-endian mono PCM. firstSampleTimeUs is the media time of
  /// the first sample written, so the window stays in step with the video.
  private func decode(
    path: String, outputPath: String, jobId: Int?, startUs: Int64, endUs: Int64?
  ) throws -> [String: Any] {
    let url = URL(fileURLWithPath: outputPath)
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: url) } }
    guard FileManager.default.createFile(atPath: outputPath, contents: nil) else {
      throw ClipFailure("decode_failed", "cannot create \(outputPath)")
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    var firstTimeUs: Int64?
    var written = 0
    var pending = [Int16]()
    pending.reserveCapacity(1 << 15)
    func flush() throws {
      if pending.isEmpty { return }
      try pending.withUnsafeBufferPointer { try handle.write(contentsOf: Data(buffer: $0)) }
      pending.removeAll(keepingCapacity: true)
    }
    let loop = try decodeLoop(
      path: path, jobId: jobId, startUs: startUs, endUs: endUs, reportProgress: true
    ) { samples, timeUs, _ in
      if firstTimeUs == nil { firstTimeUs = timeUs }
      pending.append(contentsOf: samples)
      written += samples.count
      if pending.count >= 1 << 15 { try flush() }
    }
    try flush()
    if written == 0 { throw ClipFailure("no_audio_track", "the audio track is empty") }
    finished = true
    return [
      "sampleRate": loop.sampleRate,
      "channelCount": loop.channels,
      "sampleCount": written,
      "firstSampleTimeUs": Int(firstTimeUs ?? 0),
    ]
  }

  /// The whole track's loudness for Choose the part: the RMS of the first
  /// channel over every [bucketMs], sent as `loudness` batches
  /// ({jobId, from, values}) about every 200 ms while it runs. Returns the
  /// bucket count.
  private func loudness(path: String, jobId: Int, bucketMs: Int) throws -> [String: Any] {
    var pending = [Double]()
    var sent = 0
    var sum = 0.0
    var inBucket = 0
    var lastSend = clockSeconds()
    func flush(force: Bool) {
      let now = clockSeconds()
      if pending.isEmpty || (!force && now - lastSend < 0.2) { return }
      lastSend = now
      send("loudness", ["jobId": jobId, "from": sent, "values": pending])
      sent += pending.count
      pending.removeAll()
    }
    let loop = try decodeLoop(
      path: path, jobId: jobId, startUs: 0, endUs: nil, reportProgress: false
    ) { samples, _, rate in
      let bucketSamples = max(1, rate * bucketMs / 1000)
      for sample in samples {
        let v = Double(sample) / 32768
        sum += v * v
        inBucket += 1
        if inBucket >= bucketSamples {
          pending.append((sum / Double(inBucket)).squareRoot())
          sum = 0
          inBucket = 0
        }
      }
      flush(force: false)
    }
    if inBucket > 0 { pending.append((sum / Double(inBucket)).squareRoot()) }
    flush(force: true)
    return ["buckets": sent, "sampleRate": loop.sampleRate]
  }

  /// Decodes the audio track and hands [sink] the first channel as 16-bit
  /// samples with the media time of the first one, cut to [startUs]..[endUs]
  /// sample-accurately. Stops when [jobId] is cancelled.
  private func decodeLoop(
    path: String, jobId: Int?, startUs: Int64, endUs: Int64?, reportProgress: Bool,
    sink: (_ samples: ArraySlice<Int16>, _ timeUs: Int64, _ sampleRate: Int) throws -> Void
  ) throws -> (sampleRate: Int, channels: Int) {
    if takeCancel(jobId) { throw ClipFailure.cancelled }
    let asset = try open(path)
    guard let track = Self.audioTrack(of: asset) else {
      throw ClipFailure("no_audio_track", nil)
    }
    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw ClipFailure("unsupported_file", "\(error)")
    }
    // Interleaved 16-bit at the track's own rate and channel count.
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw ClipFailure("unsupported_codec", nil) }
    reader.add(output)
    if startUs > 0 || endUs != nil {
      reader.timeRange = CMTimeRange(
        start: CMTime(value: startUs, timescale: 1_000_000),
        duration: endUs.map { CMTime(value: $0 - startUs, timescale: 1_000_000) }
          ?? .positiveInfinity)
    }
    guard reader.startReading() else {
      throw ClipFailure("unsupported_codec", reader.error.map { "\($0)" })
    }
    defer { if reader.status == .reading { reader.cancelReading() } }

    let spanUs = (endUs ?? microseconds(asset.duration)) - startUs
    var lastProgressAt = 0.0
    var sampleRate = 0
    var channels = 0
    var interleaved = [Int16]()
    var mono = [Int16]()

    // One decoded buffer per pass; false at the end of the track.
    while try autoreleasepool(invoking: { () throws -> Bool in
      if takeCancel(jobId) { throw ClipFailure.cancelled }
      guard let buffer = output.copyNextSampleBuffer() else { return false }
      let frames = CMSampleBufferGetNumSamples(buffer)
      guard frames > 0, let block = CMSampleBufferGetDataBuffer(buffer),
        let format = CMSampleBufferGetFormatDescription(buffer),
        let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
        stream.mChannelsPerFrame > 0, stream.mSampleRate > 0
      else { return true }
      sampleRate = Int(stream.mSampleRate)
      channels = Int(stream.mChannelsPerFrame)
      let count = min(CMBlockBufferGetDataLength(block) / 2, frames * channels)
      if count < channels { return true }
      if interleaved.count < count { interleaved = [Int16](repeating: 0, count: count) }
      let status = interleaved.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(
          block, atOffset: 0, dataLength: count * 2, destination: $0.baseAddress!)
      }
      guard status == kCMBlockBufferNoErr else {
        throw ClipFailure("decode_failed", "block copy \(status)")
      }
      let n = count / channels
      if mono.count < n { mono = [Int16](repeating: 0, count: n) }
      for i in 0..<n { mono[i] = interleaved[i * channels] }

      // Cut to the window, sample-accurately.
      let t0 = microseconds(CMSampleBufferGetPresentationTimeStamp(buffer))
      let rate = Int64(sampleRate)
      let skip = t0 < startUs ? Int(min(Int64(n), (startUs - t0) * rate / 1_000_000)) : 0
      var end = n
      if let endUs { end = Int(max(0, min(Int64(n), (endUs - t0) * rate / 1_000_000))) }
      if end > skip {
        try sink(mono[skip..<end], t0 + Int64(skip) * 1_000_000 / rate, sampleRate)
      }

      let now = clockSeconds()
      if reportProgress, let jobId, spanUs > 0, now - lastProgressAt >= 0.1 {
        lastProgressAt = now
        let fraction = min(1, max(0, Double(t0 - startUs) / Double(spanUs)))
        self.send("progress", ["jobId": jobId, "fraction": fraction])
      }
      return true
    }) {}
    if reader.status == .failed {
      throw ClipFailure("decode_failed", reader.error.map { "\($0)" })
    }
    return (sampleRate, channels)
  }

  /// Preview frames for the Choose-the-part filmstrip, nearest keyframe to
  /// each time, sent one by one as `thumbnail` ({jobId, index, bytes}: a
  /// JPEG [width] wide) so the strip fills from the left. Frames the phone
  /// can't read are skipped.
  private func thumbnails(
    path: String, jobId: Int, timesMs: [Int64], width: Int
  ) throws -> [String: Any] {
    let generator = AVAssetImageGenerator(asset: try open(path))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: width, height: width * 2)
    generator.requestedTimeToleranceBefore = .positiveInfinity
    generator.requestedTimeToleranceAfter = .positiveInfinity
    for (index, ms) in timesMs.enumerated() {
      if takeCancel(jobId) { throw ClipFailure.cancelled }
      autoreleasepool {
        guard
          let image = try? generator.copyCGImage(
            at: CMTime(value: ms, timescale: 1000), actualTime: nil),
          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.75)
        else { return }
        send(
          "thumbnail",
          ["jobId": jobId, "index": index, "bytes": FlutterStandardTypedData(bytes: jpeg)])
      }
    }
    return ["count": timesMs.count]
  }

  private func open(_ path: String) throws -> AVURLAsset {
    guard FileManager.default.isReadableFile(atPath: path) else {
      throw ClipFailure("unreadable_file", path)
    }
    let asset = AVURLAsset(
      url: URL(fileURLWithPath: path),
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    // The file is there but holds nothing AVFoundation reads: cut short (no
    // index) or a container iOS can't open.
    if asset.tracks.isEmpty { throw ClipFailure("unsupported_file", "no tracks") }
    return asset
  }

  /// The audio track to analyse: stereo or mono AAC when there is one
  /// (iPhone spatial-audio clips add a 4-channel APAC track next to it), else
  /// the first audio track. The export keeps the same one.
  static func audioTrack(of asset: AVAsset) -> AVAssetTrack? {
    let tracks = asset.tracks(withMediaType: .audio)
    let aac = tracks.first { track in
      guard let format = firstFormat(of: track),
        CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC,
        let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)
      else { return false }
      return stream.pointee.mChannelsPerFrame <= 2
    }
    return aac ?? tracks.first
  }

  /// Android's names for the codecs, so the diagnostics read the same.
  private static func mime(audio code: FourCharCode) -> String {
    let name = fourCC(code)
    return name == "aac" ? "audio/mp4a-latm" : "audio/\(name)"
  }

  private static func mime(video code: FourCharCode) -> String {
    switch fourCC(code) {
    case "avc1", "avc3": return "video/avc"
    case "hvc1", "hev1": return "video/hevc"
    case "dvh1", "dvhe": return "video/dolby-vision"
    case let name: return "video/\(name)"
    }
  }

  /// 'sdr', 'pq' (HDR10, Dolby Vision) or 'hlg'; nil when the file doesn't
  /// say.
  private static func transfer(_ format: CMFormatDescription) -> String? {
    guard
      let value = CMFormatDescriptionGetExtension(
        format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
    else { return nil }
    if value == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String { return "pq" }
    if value == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { return "hlg" }
    return "sdr"
  }

  private static func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return (String(bytes: bytes, encoding: .ascii) ?? "\(code)")
      .trimmingCharacters(in: .whitespaces)
  }
}

/// A failure with the code the Dart side maps.
struct ClipFailure: Error {
  let code: String
  let message: String?

  init(_ code: String, _ message: String?) {
    self.code = code
    self.message = message
  }

  static let cancelled = ClipFailure("cancelled", nil)
}

private func argument(_ value: String?, _ name: String) throws -> String {
  guard let value else { throw ClipFailure("decode_failed", "missing \(name)") }
  return value
}

func firstFormat(of track: AVAssetTrack) -> CMFormatDescription? {
  (track.formatDescriptions as! [CMFormatDescription]).first
}

/// [time] in microseconds; 0 when it isn't a number.
func microseconds(_ time: CMTime) -> Int64 {
  guard time.isNumeric else { return 0 }
  return CMTimeConvertScale(time, timescale: 1_000_000, method: .roundHalfAwayFromZero).value
}

/// How far [transform] turns the picture, in degrees clockwise: 0, 90, 180
/// or 270, as Android reports it.
func rotationDegrees(_ transform: CGAffineTransform) -> Int {
  let degrees = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
  return ((degrees % 360) + 360) % 360
}

/// Seconds, to space out progress messages. Wall time on purpose: Apple
/// counts systemUptime (and mach_absolute_time) as required-reason APIs that
/// need a privacy manifest, and a throttle doesn't need a monotonic clock.
private func clockSeconds() -> TimeInterval {
  Date().timeIntervalSinceReferenceDate
}
