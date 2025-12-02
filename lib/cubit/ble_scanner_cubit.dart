import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

part 'ble_scanner_state.dart';

// --- Pico Datalogger BLE Definitions ---
final Guid picoServiceUuid = Guid("0000aaa0-0000-1000-8000-00805f9b34fb");
final Guid picoTimeCharUuid = Guid("0000aaa1-0000-1000-8000-00805f9b34fb");
final Guid picoCommandCharUuid = Guid("0000aaa2-0000-1000-8000-00805f9b34fb");
final Guid picoDataCharUuid = Guid("0000aaa3-0000-1000-8000-00805f9b34fb");
// -----------------------------------------

class BleScannerCubit extends Cubit<BleScannerState> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _internalDeviceRef; // For calling disconnect

  // --- CHARACTERISTIC REFS ---
  BluetoothCharacteristic? _timeCharacteristic;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;

  // --- DATA STREAMING ---
  StreamSubscription<List<int>>? _dataSubscription; // For data notifications
  final List<int> _dataBuffer = []; // Buffer for partial lines
  final List<String> _tempLogBuffer = [];

  BleScannerCubit() : super(const BleScannerState()) {
    requestPermissions();
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    _dataSubscription?.cancel();
    _internalDeviceRef?.disconnect();
    return super.close();
  }

  Future<void> requestPermissions() async {
    emit(
      state.copyWith(
        status: BleScannerStatus.initial,
        statusMessage: "Requesting permissions...",
      ),
    );

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        (statuses[Permission.location]!.isGranted ||
            statuses[Permission.location]!.isLimited)) {
      emit(
        state.copyWith(
          status: BleScannerStatus.permissionsGranted,
          statusMessage: "Ready to scan. Press the scan icon.",
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: BleScannerStatus.permissionsDenied,
          statusMessage:
              "Permissions not granted. Please enable them in settings.",
        ),
      );
    }
  }

  void startScan() {
    emit(
      state.copyWith(
        status: BleScannerStatus.scanning,
        scanResults: [], // Clear old results
        statusMessage: "Scanning for 'MiFlora Logger'...",
      ),
    );

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) {
        emit(
          state.copyWith(
            status: BleScannerStatus.error,
            statusMessage: "Scan Error: ${e.toString()}",
          ),
        );
      },
    );

    FlutterBluePlus.startScan(
      withServices: [picoServiceUuid],
      timeout: const Duration(seconds: 15),
    ).whenComplete(() {
      if (state.status == BleScannerStatus.scanning) {
        final msg = state.scanResults.isEmpty
            ? "Scan finished. No loggers found. Try again."
            : "Scan finished. Found ${state.scanResults.length} logger(s).";
        emit(
          state.copyWith(
            status: BleScannerStatus.scanFinished,
            statusMessage: msg,
          ),
        );
      }
    });
  }

  void _onScanResults(List<ScanResult> results) {
    final filteredResults = results
        .where(
          (r) => r.advertisementData.serviceUuids.contains(picoServiceUuid),
        )
        .toList();

    String msg = state.statusMessage;
    if (state.status == BleScannerStatus.scanning) {
      msg = filteredResults.isEmpty
          ? "Scanning... No loggers found yet."
          : "Found logger! Tap to connect.";
    }

    emit(state.copyWith(scanResults: filteredResults, statusMessage: msg));
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    if (state.status == BleScannerStatus.scanning) {
      emit(
        state.copyWith(
          status: BleScannerStatus.scanFinished,
          statusMessage: "Scan stopped.",
        ),
      );
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (state.status == BleScannerStatus.connecting) return;
    emit(
      state.copyWith(
        status: BleScannerStatus.connecting,
        statusMessage: "Connecting to ${device.platformName}...",
      ),
    );
    try {
      stopScan(); // Stop scanning when we initiate a connection
      await device.connect(timeout: const Duration(seconds: 10));
      emit(state.copyWith(statusMessage: "Discovering services..."));
      List<BluetoothService> services = await device.discoverServices();

      BluetoothCharacteristic? foundTimeChar;
      BluetoothCharacteristic? foundCmdChar;
      BluetoothCharacteristic? foundDataChar;

      for (var service in services) {
        if (service.uuid == picoServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == picoTimeCharUuid) {
              foundTimeChar = char;
            } else if (char.uuid == picoCommandCharUuid) {
              foundCmdChar = char;
            } else if (char.uuid == picoDataCharUuid) {
              foundDataChar = char;
            }
          }
        }
      }

      // Check for all required characteristics
      if (foundTimeChar != null &&
          foundCmdChar != null &&
          foundDataChar != null) {
        _internalDeviceRef = device;
        _timeCharacteristic = foundTimeChar;
        _commandCharacteristic = foundCmdChar;
        _dataCharacteristic = foundDataChar;

        emit(
          state.copyWith(
            status: BleScannerStatus.connected,
            connectedDevice: () => device,
            statusMessage: "Connected to ${device.platformName}!",
            scanResults: [], // Clear scan results
          ),
        );
      } else {
        await device.disconnect();
        emit(
          state.copyWith(
            status: BleScannerStatus.error,
            statusMessage:
                "Connection failed: Could not find all required characteristics.",
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: BleScannerStatus.error,
          statusMessage: "Connection Error: ${e.toString()}",
        ),
      );
    }
  }

  /// Returns a tuple of (bool success, String message)
  Future<(bool, String)> syncTime() async {
    if (_timeCharacteristic == null ||
        state.status != BleScannerStatus.connected) {
      const msg = "Sync Error: Not connected or characteristic not found.";
      emit(state.copyWith(status: BleScannerStatus.error, statusMessage: msg));
      return (false, msg);
    }

    try {
      DateTime now = DateTime.now();
      Uint8List data = Uint8List(7);
      ByteData.view(data.buffer).setUint16(0, now.year, Endian.little);
      data[2] = now.month;
      data[3] = now.day;
      data[4] = now.hour;
      data[5] = now.minute;
      data[6] = now.second;

      await _timeCharacteristic!.write(data, withoutResponse: true);

      final successMsg = "Time Synced! Set to: ${now.toIso8601String()}";
      // We don't emit a new state, just return success
      // The UI will show a temporary snackbar
      return (true, successMsg);
    } catch (e) {
      final errorMsg = "Sync Error: ${e.toString()}";
      emit(
        state.copyWith(status: BleScannerStatus.error, statusMessage: errorMsg),
      );
      return (false, errorMsg);
    }
  }

  /// Returns a tuple of (bool success, String message)
  Future<(bool, String)> runPump() async {
    if (_commandCharacteristic == null ||
        state.status != BleScannerStatus.connected) {
      const msg = "Pump Error: Not connected or characteristic not found.";
      emit(state.copyWith(status: BleScannerStatus.error, statusMessage: msg));
      return (false, msg);
    }

    try {
      final command = "PUMP";
      await _commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: true,
      );

      const successMsg = "Pump command sent!";
      // We don't emit a new state, just return success
      // The UI will show a temporary snackbar
      return (true, successMsg);
    } catch (e) {
      final errorMsg = "Pump Error: ${e.toString()}";
      emit(
        state.copyWith(status: BleScannerStatus.error, statusMessage: errorMsg),
      );
      return (false, errorMsg);
    }
  }

  // --- DATA HANDLING METHODS ---

  /// Internal helper to process buffer and emit new lines
  void _processBufferLines(String data, {bool isEot = false}) {
    if (data.isEmpty && !isEot) return;

    final lines = data.split('\n').where((l) => l.isNotEmpty).toList();

    // Add to invisible buffer
    _tempLogBuffer.addAll(lines);

    // Only update the UI when finished
    if (isEot) {
      emit(
        state.copyWith(
          logLines: List.from(_tempLogBuffer), // Move buffer to state
          isLoading: false,
          statusMessage: "Data received!",
        ),
      );
      _tempLogBuffer.clear(); // Cleanup
    }
  }

  /// Callback for when a data chunk is received from the Pico
  void _handleDataChunk(List<int> chunk) {
    _dataBuffer.addAll(chunk);

    // We use fromCharCodes as the log is plain ASCII
    String data = String.fromCharCodes(_dataBuffer);

    // Check for End-of-Transmission
    if (data.contains(r'$$EOT$$')) {
      String finalData = data.replaceAll(r'$$EOT$$', '');
      _processBufferLines(finalData, isEot: true);

      // Clean up
      _dataBuffer.clear();
      _dataSubscription?.cancel();
      _dataSubscription = null;
      _dataCharacteristic?.setNotifyValue(false);
      return;
    }

    // Check for complete lines (terminated by newline)
    int lastNewline = data.lastIndexOf('\n');
    if (lastNewline != -1) {
      String completeLines = data.substring(0, lastNewline);
      String partialLine = data.substring(lastNewline + 1);

      // Process the complete lines
      _processBufferLines(completeLines, isEot: false);

      // Reset buffer with the remaining partial line
      _dataBuffer.clear();
      _dataBuffer.addAll(partialLine.codeUnits);
    }
    // If no newline, just keep buffering...
  }

  /// Public method to be called from the UI
  Future<void> requestLogFile(String filename) async {
    if (_commandCharacteristic == null || _dataCharacteristic == null) {
      emit(
        state.copyWith(
          status: BleScannerStatus.error,
          statusMessage: "Characteristics not found.",
        ),
      );
      return;
    }

    // 1. Clear old state and set loading
    _dataBuffer.clear();
    _tempLogBuffer.clear();
    emit(
      state.copyWith(
        isLoading: true,
        logLines: [], // Clear old lines
        statusMessage: "Requesting file $filename...",
      ),
    );

    try {
      // 2. Subscribe to data characteristic
      await _dataSubscription?.cancel(); // Cancel any old subscription
      await _dataCharacteristic!.setNotifyValue(true);
      _dataSubscription = _dataCharacteristic!.onValueReceived.listen(
        _handleDataChunk,
        onError: (e) {
          emit(
            state.copyWith(
              isLoading: false,
              status: BleScannerStatus.error,
              statusMessage: "Data stream error: $e",
            ),
          );
        },
      );

      // 3. Send command to Pico
      final command = "GET:$filename";
      await _commandCharacteristic!.write(
        command.codeUnits,
        withoutResponse: true,
      );

      emit(state.copyWith(statusMessage: "Waiting for data..."));
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          status: BleScannerStatus.error,
          statusMessage: "Failed to request file: $e",
        ),
      );
    }
  }

  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    if (_dataCharacteristic != null) {
      try {
        await _dataCharacteristic!.setNotifyValue(false);
      } catch (e) {
        // Ignore errors on disconnect
      }
    }
    _dataBuffer.clear();

    await _internalDeviceRef?.disconnect();
    _internalDeviceRef = null;
    _timeCharacteristic = null;
    _commandCharacteristic = null;
    _dataCharacteristic = null;
    emit(
      state.copyWith(
        status: BleScannerStatus.permissionsGranted, // Back to a neutral state
        connectedDevice: () => null, // Explicitly set device to null
        statusMessage: "Disconnected. Ready to scan again.",
        isLoading: false, // NEW
        logLines: [], // NEW
      ),
    );
  }
}
