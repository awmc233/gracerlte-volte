// SPDX-License-Identifier: GPL-2.0
package me.phh.sip

import android.os.Handler
import android.telephony.Rlog

internal class SipCallSetupTimers(
    private val tag: String,
    private val handler: Handler,
    private val policy: () -> SipCallSetupTimerPolicy,
    private val onOutgoingTimeout: (String, String) -> Unit,
    private val onIncomingTimeout: (String) -> Unit,
) {
    companion object {
        /** Timeout reason used when the INVITE got no SIP response at all. */
        const val REASON_NO_RESPONSE = "INVITE no response"
    }

    private var outgoingCallId: String? = null
    private var outgoingGeneration = 0
    private var incomingCallId: String? = null
    private var incomingGeneration = 0

    /**
     * Arms the short "no response at all" timer right after the initial INVITE
     * has been written. A 100 Trying replaces it with the normal invite timer.
     *
     * If a response managed to arrive before the writer called us, a timer for
     * this call-id is already armed; keep that one instead of downgrading it to
     * the short no-response timeout.
     */
    fun onOutgoingInviteSent(callId: String) {
        if (outgoingCallId == callId) {
            Rlog.d(tag, "Outgoing INVITE already got a response; keeping existing setup timer: callId=$callId")
            return
        }
        startOutgoing(callId, policy().noResponseTimeoutMs, REASON_NO_RESPONSE)
    }

    fun onOutgoingInviteResponse(callId: String, statusCode: Int) {
        when {
            statusCode == 100 -> startOutgoing(
                callId,
                policy().inviteTimeoutMs,
                "INVITE response timeout",
            )
            statusCode == 180 -> {
                cancelOutgoing("180 Ringing")
                startOutgoing(
                    callId,
                    policy().ringbackTimeoutMs,
                    "ringback timeout",
                )
            }
            statusCode > 100 -> cancelOutgoing("INVITE response $statusCode")
        }
    }

    fun startIncoming(callId: String) {
        cancelIncoming("new incoming INVITE")
        val generation = ++incomingGeneration
        incomingCallId = callId
        val delayMs = policy().ringingTimeoutMs.coerceAtLeast(1L)
        Rlog.d(tag, "Starting incoming ringing timer: callId=$callId delayMs=$delayMs")
        handler.postDelayed({
            if (incomingGeneration == generation && incomingCallId == callId) {
                incomingCallId = null
                onIncomingTimeout(callId)
            }
        }, delayMs)
    }

    fun cancelAll(reason: String) {
        cancelOutgoing(reason)
        cancelIncoming(reason)
    }

    private fun startOutgoing(callId: String, delayMs: Long, reason: String) {
        val generation = ++outgoingGeneration
        outgoingCallId = callId
        val boundedDelayMs = delayMs.coerceAtLeast(1L)
        Rlog.d(
            tag,
            "Starting outgoing call setup timer: callId=$callId " +
                "delayMs=$boundedDelayMs reason=$reason",
        )
        handler.postDelayed({
            if (outgoingGeneration == generation && outgoingCallId == callId) {
                outgoingCallId = null
                onOutgoingTimeout(callId, reason)
            }
        }, boundedDelayMs)
    }

    private fun cancelOutgoing(reason: String) {
        if (outgoingCallId != null) {
            Rlog.d(tag, "Cancelling outgoing call setup timer: $reason")
        }
        outgoingCallId = null
        outgoingGeneration++
    }

    private fun cancelIncoming(reason: String) {
        if (incomingCallId != null) {
            Rlog.d(tag, "Cancelling incoming ringing timer: $reason")
        }
        incomingCallId = null
        incomingGeneration++
    }
}
