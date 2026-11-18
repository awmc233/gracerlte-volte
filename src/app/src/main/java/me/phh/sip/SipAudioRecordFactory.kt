// SPDX-License-Identifier: GPL-2.0
package me.phh.sip

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.telephony.Rlog

object SipAudioRecordFactory {
    private const val TAG = "PHH SipAudioRecordFactory"

    private fun tryCreate(source: Int, bufferSize: Int, audioCodec: NegotiatedAudioCodec): AudioRecord? {
        return try {
            val record = AudioRecord(
                source,
                audioCodec.sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
            if (record.state == AudioRecord.STATE_INITIALIZED) {
                record
            } else {
                Rlog.w(TAG, "AudioRecord source=$source uninitialized on Exynos HAL")
                record.release()
                null
            }
        } catch (t: Throwable) {
            Rlog.w(TAG, "AudioRecord creation failed for source=$source", t)
            null
        }
    }

    fun createVoiceCommunicationRecord(
        bufferSize: Int,
        audioCodec: NegotiatedAudioCodec = SipAudioCodecs.AMR_NB,
    ): AudioRecord {
        // On Samsung Exynos the VOICE_COMMUNICATION input is tied to the modem voice
        // path while a call is active and reads pure silence for app capture. Prefer
        // the plain MIC source (AudioFlinger path) and only fall back if unavailable.
        tryCreate(MediaRecorder.AudioSource.MIC, bufferSize, audioCodec)?.let { return it }
        tryCreate(MediaRecorder.AudioSource.VOICE_COMMUNICATION, bufferSize, audioCodec)?.let { return it }
        return AudioRecord(
            MediaRecorder.AudioSource.DEFAULT,
            audioCodec.sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )
    }

    fun minBufferSize(
        audioCodec: NegotiatedAudioCodec = SipAudioCodecs.AMR_NB,
    ): Int =
        AudioRecord.getMinBufferSize(
            audioCodec.sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
}
