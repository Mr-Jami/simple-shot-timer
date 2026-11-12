// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import AVFoundation
import XCTest

@testable import Runner

/// Exports made by ClipExportChannel's own session and compositor, read back
/// frame by frame (.github/workflows/ios-tests.yml runs them in a simulator).
/// The clips are written here: a white picture with a green band along its
/// four edges, on black. An export that shows the picture and nothing else
/// is green along every edge.
final class ClipExportTests: XCTestCase {
  /// The green band's width in a clip, in pixels.
  private let band = 16

  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clip_export_tests_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: dir)
  }

  /// H.264 stores 1080 rows as 1088: the 8 spare ones must not show at the
  /// bottom.
  func testALandscapeExportShowsThePictureUpToItsEdges() throws {
    let stored = CGSize(width: 1920, height: 1080)
    let clip = try writeClip(
      "landscape", stored: stored, picture: CGRect(origin: .zero, size: stored))
    check(try export(clip), size: stored)
  }

  /// As above, where the spare rows would show along the right edge.
  func testAPortraitExportShowsThePictureUpToItsEdges() throws {
    let stored = CGSize(width: 1920, height: 1080)
    let clip = try writeClip(
      "portrait", stored: stored, picture: CGRect(origin: .zero, size: stored), turned: true)
    check(try export(clip), size: CGSize(width: 1080, height: 1920))
  }

  /// A clip that stores a margin around its picture, as iPhones do where
  /// they stabilise it: the margin stays out of the export (issue #66). The
  /// picture is off centre both ways, so a cut at the wrong place shows.
  func testAnExportLeavesOutTheMarginAroundTheCleanAperture() throws {
    let picture = CGRect(x: 20, y: 60, width: 560, height: 400)
    let clip = try writeClip(
      "margin", stored: CGSize(width: 640, height: 480), picture: picture, turned: true)
    // Else the clip has no clean aperture and this test checks nothing.
    let track = try XCTUnwrap(AVURLAsset(url: clip).tracks(withMediaType: .video).first)
    XCTAssertEqual(track.naturalSize, picture.size, "the clip's clean aperture")
    check(try export(clip), size: CGSize(width: 400, height: 560))
  }

  /// As above, scaled to 360 on the short side: the band is 14 pixels then.
  func testAScaledExportLeavesOutTheMarginToo() throws {
    let picture = CGRect(x: 60, y: 20, width: 560, height: 400)
    let clip = try writeClip(
      "scaled", stored: CGSize(width: 640, height: 480), picture: picture)
    check(try export(clip, shortSide: 360), size: CGSize(width: 504, height: 360), band: 14)
  }

  /// A third of a second of video: every frame is black with [picture] (y
  /// from the top) in it, which is also the clip's clean aperture when it is
  /// smaller than [stored]. [turned] marks it as filmed upright (shown
  /// turned by 90 degrees).
  private func writeClip(
    _ name: String, stored: CGSize, picture: CGRect, turned: Bool = false
  ) throws -> URL {
    let url = dir.appendingPathComponent("\(name).mov")
    let width = Int(stored.width)
    let height = Int(stored.height)
    var settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ]
    if picture.size != stored {
      // The offsets are the picture's centre from the frame's, y down.
      settings[AVVideoCleanApertureKey] = [
        AVVideoCleanApertureWidthKey: Int(picture.width),
        AVVideoCleanApertureHeightKey: Int(picture.height),
        AVVideoCleanApertureHorizontalOffsetKey: Int(picture.midX) - width / 2,
        AVVideoCleanApertureVerticalOffsetKey: Int(picture.midY) - height / 2,
      ]
    }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    if turned { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    writer.add(input)
    guard writer.startWriting() else { throw try XCTUnwrap(writer.error) }
    writer.startSession(atSourceTime: .zero)
    for i in 0..<10 {
      while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
      let frame = try drawn(stored, picture)
      guard adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
      else { throw try XCTUnwrap(writer.error) }
    }
    input.markAsFinished()
    let written = expectation(description: "\(name) written")
    writer.finishWriting { written.fulfill() }
    wait(for: [written], timeout: 60)
    XCTAssertEqual(writer.status, .completed, "\(name): \(String(describing: writer.error))")
    return url
  }

  /// A black [stored] frame with [picture] (y from the top) in it: white,
  /// green along its edges.
  private func drawn(_ stored: CGSize, _ picture: CGRect) throws -> CVPixelBuffer {
    var made: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault, Int(stored.width), Int(stored.height), kCVPixelFormatType_32BGRA,
      nil, &made)
    let buffer = try XCTUnwrap(made)
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    // BGRA in memory.
    let context = try XCTUnwrap(
      CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: Int(stored.width), height: Int(stored.height), bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue))
    // Core Graphics counts y from the bottom.
    context.translateBy(x: 0, y: stored.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(origin: .zero, size: stored))
    context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
    context.fill(picture)
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(picture.insetBy(dx: CGFloat(band), dy: CGFloat(band)))
    return buffer
  }

  /// The frames of [clip] exported whole, as ClipExportChannel's `export`
  /// makes them.
  private func export(_ clip: URL, shortSide: Int? = nil) throws -> [CVPixelBuffer] {
    let name = clip.deletingPathExtension().lastPathComponent
    let output = dir.appendingPathComponent("\(name)_export.mp4")
    var args: [String: Any] = [
      "input": clip.path,
      "startMs": NSNumber(value: 0),
      "endMs": NSNumber(value: 60_000),
    ]
    if let shortSide { args["shortSide"] = NSNumber(value: shortSide) }
    let session = try ClipExportChannel.makeSession(args, output: output)
    let exported = expectation(description: "\(name) exported")
    session.exportAsynchronously { exported.fulfill() }
    wait(for: [exported], timeout: 120)
    XCTAssertEqual(session.status, .completed, "\(name): \(String(describing: session.error))")

    let asset = AVURLAsset(url: output)
    let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let frames = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(frames)
    guard reader.startReading() else { throw try XCTUnwrap(reader.error) }
    var read: [CVPixelBuffer] = []
    while let sample = frames.copyNextSampleBuffer() {
      if let frame = CMSampleBufferGetImageBuffer(sample) { read.append(frame) }
    }
    XCTAssertEqual(reader.status, .completed, "\(name): \(String(describing: reader.error))")
    return read
  }

  /// Every one of [frames] is [size] and shows the whole picture and nothing
  /// else: green near each edge and at the inner side of the [band] pixels
  /// wide band, white right behind it. The 5 pixels of slack are for the
  /// encoder's blur.
  private func check(
    _ frames: [CVPixelBuffer], size: CGSize, band: Int = 16,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertFalse(frames.isEmpty, "no frames", file: file, line: line)
    for (i, frame) in frames.enumerated() {
      let width = CVPixelBufferGetWidth(frame)
      let height = CVPixelBufferGetHeight(frame)
      XCTAssertEqual(
        CGSize(width: width, height: height), size, "frame \(i)'s size", file: file, line: line)
      let probes: [(depth: Int, green: Bool)] = [(3, true), (band - 5, true), (band + 5, false)]
      CVPixelBufferLockBaseAddress(frame, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
      for (depth, green) in probes {
        let spots = [
          ("left", depth, height / 2),
          ("right", width - 1 - depth, height / 2),
          ("top", width / 2, depth),
          ("bottom", width / 2, height - 1 - depth),
        ]
        for (edge, x, y) in spots {
          let found = pixel(frame, x, y)
          XCTAssertTrue(
            green ? found.isGreen : found.isWhite,
            "frame \(i), \(depth) px in from the \(edge) edge: \(found) is not "
              + (green ? "green" : "white"),
            file: file, line: line)
        }
      }
    }
  }

  private func pixel(_ frame: CVPixelBuffer, _ x: Int, _ y: Int) -> Pixel {
    guard let base = CVPixelBufferGetBaseAddress(frame) else { return Pixel(r: -1, g: -1, b: -1) }
    let at = base.advanced(by: y * CVPixelBufferGetBytesPerRow(frame) + x * 4)
      .assumingMemoryBound(to: UInt8.self)
    return Pixel(r: Int(at[2]), g: Int(at[1]), b: Int(at[0]))
  }
}

private struct Pixel: CustomStringConvertible {
  let r: Int
  let g: Int
  let b: Int

  var isGreen: Bool { g > 150 && r < 110 && b < 110 }
  var isWhite: Bool { r > 180 && g > 180 && b > 180 }
  var description: String { "(r \(r), g \(g), b \(b))" }
}
