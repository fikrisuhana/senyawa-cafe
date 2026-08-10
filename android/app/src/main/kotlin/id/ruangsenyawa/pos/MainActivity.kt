package id.ruangsenyawa.pos

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "id.ruangsenyawa.pos/printer"
    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12+ (API 31): BLUETOOTH_CONNECT/SCAN adalah izin runtime → minta saat buka.
        requestBtPermissionsIfNeeded()
    }

    /** True kalau izin konek BT sudah ada (atau perangkat < Android 12 yang tak butuh runtime). */
    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBtPermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 1001)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Dipanggil dari Flutter buat memicu dialog izin BT sebelum cetak.
                "requestBtPermission" -> {
                    requestBtPermissionsIfNeeded()
                    result.success(hasConnectPermission())
                }
                "getPairedDevices" -> {
                    try {
                        if (!hasConnectPermission()) {
                            requestBtPermissionsIfNeeded()
                            result.error("NO_PERMISSION", "Izin Bluetooth ('Perangkat di sekitar') belum diizinkan. Izinkan lalu coba lagi.", null)
                            return@setMethodCallHandler
                        }
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        if (adapter == null || !adapter.isEnabled) {
                            result.error("BT_DISABLED", "Bluetooth HP belum diaktifkan", null)
                            return@setMethodCallHandler
                        }
                        val pairedDevices: Set<BluetoothDevice>? = adapter.bondedDevices
                        val list = mutableListOf<Map<String, String>>()
                        pairedDevices?.forEach { device ->
                            list.add(mapOf(
                                "name" to (device.name ?: "Unknown Device"),
                                "address" to device.address
                            ))
                        }
                        result.success(list)
                    } catch (e: SecurityException) {
                        requestBtPermissionsIfNeeded()
                        result.error("NO_PERMISSION", "Izin Bluetooth belum diberi: ${e.message}", null)
                    } catch (e: Exception) {
                        result.error("BT_ERROR", e.message, null)
                    }
                }
                "printBytes" -> {
                    val printerName = call.argument<String>("printerName") ?: ""
                    val bytes = call.argument<ByteArray>("bytes")

                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGS", "Data cetak kosong", null)
                        return@setMethodCallHandler
                    }
                    if (!hasConnectPermission()) {
                        requestBtPermissionsIfNeeded()
                        result.error("NO_PERMISSION", "Izin Bluetooth ('Perangkat di sekitar') belum diizinkan. Izinkan di Setelan → Izin, lalu coba cetak lagi.", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        var socket: BluetoothSocket? = null
                        var outputStream: OutputStream? = null
                        var targetDevice: BluetoothDevice? = null

                        try {
                            val adapter = BluetoothAdapter.getDefaultAdapter()
                            if (adapter == null || !adapter.isEnabled) {
                                runOnUiThread { result.error("BT_DISABLED", "Bluetooth HP belum dinyalakan", null) }
                                return@Thread
                            }

                            val pairedDevices: Set<BluetoothDevice>? = adapter.bondedDevices

                            if (printerName.isNotEmpty()) {
                                targetDevice = pairedDevices?.firstOrNull {
                                    (it.name ?: "").equals(printerName, ignoreCase = true) || it.address.equals(printerName, ignoreCase = true)
                                }
                            }

                            if (targetDevice == null) {
                                targetDevice = pairedDevices?.firstOrNull {
                                    val n = it.name?.uppercase() ?: ""
                                    n.contains("POS") || n.contains("PRINTER") || n.contains("BT") || n.contains("RPP") || n.contains("PT") || n.contains("MTP")
                                }
                            }

                            if (targetDevice == null && !pairedDevices.isNullOrEmpty()) {
                                targetDevice = pairedDevices.first()
                            }

                            if (targetDevice == null) {
                                runOnUiThread { result.error("NO_DEVICE", "Belum ada printer Bluetooth tersanding (paired) di Pengaturan HP bro", null) }
                                return@Thread
                            }

                            adapter.cancelDiscovery()

                            try {
                                socket = targetDevice.createRfcommSocketToServiceRecord(SPP_UUID)
                                socket.connect()
                            } catch (e1: Exception) {
                                try {
                                    val m = targetDevice.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                                    socket = m.invoke(targetDevice, 1) as BluetoothSocket
                                    socket.connect()
                                } catch (e2: Exception) {
                                    throw Exception("Socket gagal (SPP: ${e1.message} | Reflection: ${e2.message})")
                                }
                            }

                            outputStream = socket.outputStream
                            outputStream.write(bytes)
                            outputStream.flush()

                            Thread.sleep(400)
                            socket.close()

                            runOnUiThread { result.success("SUCCESS_PRINT") }
                        } catch (e: SecurityException) {
                            try { socket?.close() } catch (_: Exception) {}
                            runOnUiThread { result.error("NO_PERMISSION", "Izin Bluetooth belum diberi: ${e.message}", null) }
                        } catch (e: Exception) {
                            try { socket?.close() } catch (_: Exception) {}
                            val name = targetDevice?.name ?: printerName
                            runOnUiThread { result.error("PRINT_FAILED", "Gagal konek ke printer Bluetooth ($name): ${e.message}", null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
