//SPDX-License-Identifier: GPL-2.0
package me.phh.sip

import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaCodec
import android.telephony.Rlog

object SipAudioRecordStarter {
    fun startForImsUplink(
        logTag: String,
        audioManager: AudioManager,
        audioRecord: AudioRecord,
        encoder: MediaCodec,
    ): Int? {
        val previousAudioMode = audioManager.mode
        // Keep forcing MODE_IN_COMMUNICATION before the capture stream is opened:
        // Samsung configures the mic route when AudioRecord starts, so starting the
        // enforcer afterwards is too late.
        SipAudioModeEnforcer.start(logTag, audioManager)
        try {
            Thread.sleep(150)
        } catch (_: InterruptedException) {
        }
        val modeBeforeSet = audioManager.mode
        val setErr = try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            null
        } catch (t: Throwable) {
            t
        }
        Rlog.d(
            logTag,
            "setMode(IN_COMMUNICATION): before=$modeBeforeSet after=${audioManager.mode} " +
                "err=${setErr?.javaClass?.simpleName ?: "none"}",
        )
        try {
            audioRecord.startRecording()
        } catch (t: Throwable) {
            Rlog.e(logTag, "AudioRecord.startRecording failed", t)
            try {
                audioRecord.release()
            } catch (_: Throwable) {
            }
            try {
                encoder.stop()
            } catch (_: Throwable) {
            }
            try {
                encoder.release()
            } catch (_: Throwable) {
            }
            return null
        }
        Rlog.d(
            logTag,
            "AudioRecord started, state=${audioRecord.recordingState} " +
                "audioMode=${audioManager.mode} (was $previousAudioMode) " +
                "preferredDevice=${audioRecord.preferredDevice?.type}"
        )
        // Samsung keeps forcing MODE_IN_CALL; the enforcer is already running.
        return previousAudioMode
    }
}
