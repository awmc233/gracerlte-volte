//SPDX-License-Identifier: GPL-2.0
package me.phh.sip

import android.media.AudioManager
import android.telephony.Rlog

/**
 * Samsung's audio HAL forces AudioManager.MODE_IN_CALL whenever a telephony call
 * starts, which routes the microphone to the modem (CS path) instead of
 * AudioFlinger. AudioRecord then returns pure silence for the IMS uplink.
 *
 * Poll quickly and push the mode back to MODE_IN_COMMUNICATION for the whole
 * duration of the IMS call, then stop when the call is torn down.
 */
object SipAudioModeEnforcer {
    @Volatile
    private var running = false
    private var worker: Thread? = null

    @Synchronized
    fun start(logTag: String, audioManager: AudioManager) {
        if (running) return
        running = true
        worker = Thread {
            var fixes = 0
            while (running) {
                try {
                    if (audioManager.mode == AudioManager.MODE_IN_CALL) {
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        // Samsung routes the mic to the modem on the voice path; the
                        // speaker route keeps capture on the AudioFlinger side.
                        if (!audioManager.isSpeakerphoneOn) {
                            audioManager.isSpeakerphoneOn = true
                        }
                        fixes++
                        if (fixes <= 5) {
                            Rlog.d(logTag, "AudioModeEnforcer: MODE_IN_CALL -> MODE_IN_COMMUNICATION (#$fixes)")
                        }
                    }
                } catch (_: Throwable) {
                    // Keep trying; permission or transient binder failures must not kill the call.
                }
                try {
                    Thread.sleep(40)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }.apply {
            name = "PhhImsAudioModeEnforcer"
            isDaemon = true
            start()
        }
    }

    @Synchronized
    fun stop() {
        running = false
        worker?.interrupt()
        worker = null
    }
}
