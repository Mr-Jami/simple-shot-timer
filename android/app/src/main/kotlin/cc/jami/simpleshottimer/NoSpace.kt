// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

package cc.jami.simpleshottimer

import android.system.ErrnoException
import android.system.OsConstants

/**
 * Whether this or one of its causes is the storage running full (ENOSPC),
 * so the video channels can reply `no_space` instead of a generic failure.
 */
internal fun Throwable.isNoSpace(): Boolean =
    generateSequence(this) { it.cause }.any {
        (it is ErrnoException && it.errno == OsConstants.ENOSPC) ||
            it.message?.contains("ENOSPC") == true
    }
