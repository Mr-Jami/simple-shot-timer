// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import Flutter
import UIKit
import UniformTypeIdentifiers

/// "Or choose from Files" for the video feature, the iOS side of
/// ClipFilesChannel.kt: the system document picker for one video, which
/// needs no permission. The picker copies the file into the app (and
/// downloads it from iCloud first, with its own progress), and this moves
/// that copy into the folder Dart names (the clip's work folder): a rename,
/// so there is no copy progress and `cancel` has nothing to stop. Backing
/// out of the picker replies null; a full storage fails with `no_space`.
final class ClipFilesChannel: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "cc.jami.simpleshottimer.clip_files")
  private var pending: (result: FlutterResult, dir: URL)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "cc.jami.simpleshottimer/clip_files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "cancel":
      result(nil)
    case "pickVideo":
      guard let dir = (call.arguments as? [String: Any])?["targetDir"] as? String else {
        return result(FlutterError(code: "copy_failed", message: "missing targetDir", details: nil))
      }
      if pending != nil { return result(FlutterError(code: "busy", message: nil, details: nil)) }
      guard let presenter = Self.topViewController() else {
        return result(FlutterError(code: "no_picker", message: "no window", details: nil))
      }
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
      picker.delegate = self
      picker.allowsMultipleSelection = false
      // Swiping the picker away is backing out too.
      picker.presentationController?.delegate = self
      pending = (result, URL(fileURLWithPath: dir, isDirectory: true))
      presenter.present(picker, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let pick = pending else { return }
    pending = nil
    guard let picked = urls.first else { return pick.result(nil) }
    worker.async {
      do {
        let path = try Self.move(picked, into: pick.dir)
        DispatchQueue.main.async { pick.result(path) }
      } catch {
        let code = isNoSpace(error) ? "no_space" : "copy_failed"
        DispatchQueue.main.async {
          pick.result(FlutterError(code: code, message: "\(error)", details: nil))
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    backedOut()
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    backedOut()
  }

  private func backedOut() {
    pending?.result(nil)
    pending = nil
  }

  /// Moves the picker's copy into [dir] under a plain file name; also when
  /// that fails, the picker's copy is gone afterwards. Runs on [worker].
  nonisolated private static func move(_ picked: URL, into dir: URL) throws -> String {
    let name = picked.lastPathComponent.replacingOccurrences(
      of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    let target = dir.appendingPathComponent(name.isEmpty ? "clip.mov" : name)
    let files = FileManager.default
    try? files.removeItem(at: target)
    do {
      try files.moveItem(at: picked, to: target)
    } catch {
      defer { try? files.removeItem(at: picked) }
      try files.copyItem(at: picked, to: target)
    }
    return target.path
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
