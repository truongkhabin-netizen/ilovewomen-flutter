package com.example.cham_cong_nhan_vien

import android.nfc.NfcAdapter
import android.nfc.NdefRecord
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.location.Geocoder
import android.util.Base64
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity(), NfcAdapter.ReaderCallback {
    companion object {
        private const val NFC_CHANNEL = "chamcong/nfc"
        private const val BIOMETRIC_CHANNEL = "chamcong/biometrics"
    }

    private var nfcAdapter: NfcAdapter? = null
    private var pendingScan: MethodChannel.Result? = null
    private var pendingAvatar: MethodChannel.Result? = null
    private val avatarPicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val result = pendingAvatar
        pendingAvatar = null
        if (result == null) return@registerForActivityResult
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            val sample = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 512)
            val bitmap = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply {
                    inSampleSize = sample
                })
            }
                ?: throw IllegalArgumentException("Không đọc được ảnh đã chọn.")
            val scale = minOf(1.0, 512.0 / maxOf(bitmap.width, bitmap.height))
            val resized = if (scale < 1.0) Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt().coerceAtLeast(1),
                (bitmap.height * scale).toInt().coerceAtLeast(1),
                true
            ) else bitmap
            val output = java.io.ByteArrayOutputStream()
            resized.compress(Bitmap.CompressFormat.JPEG, 78, output)
            if (resized !== bitmap) resized.recycle()
            bitmap.recycle()
            result.success(Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP))
        } catch (error: Exception) {
            result.error("AVATAR_READ_FAILED", error.message ?: "Không đọc được ảnh.", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(nfcAdapter?.isEnabled == true)
                    "scan" -> startNfcScan(result)
                    "cancel" -> {
                        stopNfcScan(null)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "hardwareCapabilities") {
                    result.success(
                        mapOf(
                            "fingerprint" to packageManager.hasSystemFeature("android.hardware.fingerprint"),
                            "face" to packageManager.hasSystemFeature("android.hardware.biometrics.face")
                        )
                    )
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chamcong/location")
            .setMethodCallHandler { call, result ->
                if (call.method != "reverseGeocode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val latitude = call.argument<Double>("latitude")
                val longitude = call.argument<Double>("longitude")
                if (latitude == null || longitude == null) {
                    result.error("INVALID_COORDINATES", "Tọa độ không hợp lệ.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        if (!Geocoder.isPresent()) {
                            runOnUiThread { result.success(null) }
                            return@Thread
                        }
                        @Suppress("DEPRECATION")
                        val matches = Geocoder(this, Locale("vi", "VN"))
                            .getFromLocation(latitude, longitude, 1)
                        val address = matches?.firstOrNull()
                        val street = listOfNotNull(
                            address?.subThoroughfare?.takeIf { it.isNotBlank() },
                            address?.thoroughfare?.takeIf { it.isNotBlank() }
                        ).joinToString(" ")
                        val district = address?.subLocality?.takeIf { it.isNotBlank() }
                            ?: address?.subAdminArea?.takeIf { it.isNotBlank() }
                        val city = address?.locality?.takeIf { it.isNotBlank() }
                            ?: address?.adminArea?.takeIf { it.isNotBlank() }
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "street" to street,
                                    "district" to district,
                                    "city" to city,
                                    "address" to address?.getAddressLine(0)
                                )
                            )
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("GEOCODING_FAILED", error.message, null)
                        }
                    }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chamcong/avatar")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") {
                    result.notImplemented()
                } else if (pendingAvatar != null) {
                    result.error("AVATAR_BUSY", "Đang mở thư viện ảnh.", null)
                } else {
                    pendingAvatar = result
                    avatarPicker.launch("image/*")
                }
            }
    }

    private fun startNfcScan(result: MethodChannel.Result) {
        val adapter = nfcAdapter
        if (adapter == null) {
            result.error("NFC_UNSUPPORTED", "Thiết bị không hỗ trợ NFC.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("NFC_DISABLED", "Hãy bật NFC trong cài đặt điện thoại.", null)
            return
        }
        if (pendingScan != null) {
            result.error("NFC_BUSY", "Đang chờ quét thẻ NFC.", null)
            return
        }
        pendingScan = result
        adapter.enableReaderMode(
            this,
            this,
            NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_NFC_F or
                NfcAdapter.FLAG_READER_NFC_V or
                NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS,
            null
        )
    }

    override fun onTagDiscovered(tag: Tag) {
        val value = readNdefText(tag)
        runOnUiThread {
            stopNfcScan(value)
        }
    }

    private fun readNdefText(tag: Tag): String? {
        val ndef = Ndef.get(tag) ?: return null
        return try {
            ndef.connect()
            val records = ndef.ndefMessage?.records ?: return null
            records.firstNotNullOfOrNull { record ->
                val payload = record.payload ?: return@firstNotNullOfOrNull null
                if (record.tnf == NdefRecord.TNF_WELL_KNOWN &&
                    record.type.contentEquals(NdefRecord.RTD_TEXT) && payload.isNotEmpty()
                ) {
                    val status = payload[0].toInt() and 0xFF
                    val languageLength = status and 0x3F
                    if (payload.size <= languageLength + 1) return@firstNotNullOfOrNull null
                    val charset = if ((status and 0x80) == 0) Charsets.UTF_8 else Charsets.UTF_16
                    String(payload, languageLength + 1, payload.size - languageLength - 1, charset).trim()
                } else {
                    String(payload, Charsets.UTF_8).trim().takeIf { it.isNotEmpty() }
                }
            }
        } catch (_: Exception) {
            null
        } finally {
            try {
                ndef.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun stopNfcScan(value: String?) {
        nfcAdapter?.disableReaderMode(this)
        val result = pendingScan
        pendingScan = null
        result?.success(value)
    }

    override fun onPause() {
        nfcAdapter?.disableReaderMode(this)
        pendingScan?.error("NFC_INTERRUPTED", "Quét NFC đã tạm dừng.", null)
        pendingScan = null
        super.onPause()
    }

    override fun onDestroy() {
        stopNfcScan(null)
        super.onDestroy()
    }
}
