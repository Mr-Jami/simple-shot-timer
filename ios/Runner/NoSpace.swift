// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import AVFoundation
import Foundation

/// Whether [error] or one it wraps is the storage running full, so the video
/// channels can reply `no_space` instead of a generic failure.
func isNoSpace(_ error: Error) -> Bool {
  var next: NSError? = error as NSError
  while let e = next {
    switch e.domain {
    case NSCocoaErrorDomain where e.code == NSFileWriteOutOfSpaceError,
      NSPOSIXErrorDomain where e.code == Int(ENOSPC),
      AVFoundationErrorDomain where e.code == AVError.Code.diskFull.rawValue:
      return true
    default:
      next = e.userInfo[NSUnderlyingErrorKey] as? NSError
    }
  }
  return false
}
