package com.airbridge.service

import kotlin.math.ceil

/**
 * Remaining-time estimate for a transfer.
 *
 * Rounds UP: a transfer with a fraction of a second left has "1 s" left, not
 * "0". Zero is reserved for "nothing left" and "no estimate" — the UI blanks
 * the countdown on 0 — so the previous integer division blanked it just as a
 * transfer was finishing.
 */
object TransferEta {
    fun seconds(remainingBytes: Long, speedBps: Long): Int {
        if (speedBps <= 0L || remainingBytes <= 0L) return 0
        return ceil(remainingBytes.toDouble() / speedBps.toDouble()).toInt()
    }
}
