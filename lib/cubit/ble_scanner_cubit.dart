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
// -----------------------------------------

class BleScannerCubit extends Cubit<BleScannerState> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothCharacteristic? _timeCharacteristic;
  BluetoothDevice? _internalDeviceRef; // For calling disconnect

  BleScannerCubit() : super(const BleScannerState()) {
    requestPermissions();
  }

  @override
  Future<void> close() {
    _scanSubscription?.cancel();
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

      BluetoothCharacteristic? foundChar;
      for (var service in services) {
        if (service.uuid == picoServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid == picoTimeCharUuid) {
              foundChar = char;
              break;
            }
          }
        }
      }

      if (foundChar != null) {
        _internalDeviceRef = device;
        _timeCharacteristic = foundChar;
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
                "Connection failed: Could not find time characteristic.",
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

  Future<void> disconnect() async {
    await _internalDeviceRef?.disconnect();
    _internalDeviceRef = null;
    _timeCharacteristic = null;
    emit(
      state.copyWith(
        status: BleScannerStatus.permissionsGranted, // Back to a neutral state
        connectedDevice: () => null, // Explicitly set device to null
        statusMessage: "Disconnected. Ready to scan again.",
      ),
    );
  }
}
