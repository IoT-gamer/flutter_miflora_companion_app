import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// --- Pico Datalogger BLE Definitions ---
// These GUIDs are derived from the pico's datalogger.gatt file
final Guid picoServiceUuid = Guid("0000aaa0-0000-1000-8000-00805f9b34fb");
final Guid picoTimeCharUuid = Guid("0000aaa1-0000-1000-8000-00805f9b34fb");
// -----------------------------------------

void main() {
  runApp(const PicoTimeSetterApp());
}

class PicoTimeSetterApp extends StatelessWidget {
  const PicoTimeSetterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pico Time Setter',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: const BleScannerScreen(),
    );
  }
}

class BleScannerScreen extends StatefulWidget {
  const BleScannerScreen({super.key});

  @override
  State<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends State<BleScannerScreen> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _timeCharacteristic;
  bool _isConnecting = false;
  String _status = "Request permissions, then scan.";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // Request Bluetooth and Location permissions
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
      setState(() {
        _status = "Ready to scan. Press the scan icon.";
      });
    } else {
      setState(() {
        _status = "Permissions not granted. Please enable them in settings.";
      });
    }
  }

  void _startScan() {
    setState(() {
      _scanResults = [];
      _status = "Scanning for 'MiFlora Logger'...";
    });

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        // Filter results to only show devices with the Pico service
        final filteredResults = results
            .where(
              (r) => r.advertisementData.serviceUuids.contains(picoServiceUuid),
            )
            .toList();

        // Update the UI
        setState(() {
          _scanResults = filteredResults;
          if (_scanResults.isEmpty && FlutterBluePlus.isScanningNow) {
            _status = "Scanning... No loggers found yet.";
          } else if (_scanResults.isNotEmpty) {
            _status = "Found logger! Tap to connect.";
          }
        });
      },
      onError: (e) {
        _showError("Scan Error", e.toString());
      },
    );

    // Start scanning specifically for our service
    FlutterBluePlus.startScan(
      withServices: [picoServiceUuid],
      timeout: const Duration(seconds: 15),
    ).whenComplete(() {
      // Update status when scan finishes
      setState(() {
        if (_scanResults.isEmpty) {
          _status = "Scan finished. No loggers found. Try again.";
        }
      });
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _status = "Connecting to ${device.platformName}...";
    });

    try {
      // 1. Connect
      await device.connect(timeout: const Duration(seconds: 10));

      // 2. Discover Services
      setState(() {
        _status = "Discovering services...";
      });
      List<BluetoothService> services = await device.discoverServices();

      // 3. Find the correct service and characteristic
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
        // Success!
        setState(() {
          _connectedDevice = device;
          _timeCharacteristic = foundChar;
          _status = "Connected to ${device.platformName}!";
        });
        // Stop scanning
        FlutterBluePlus.stopScan();
        _scanSubscription?.cancel();
      } else {
        // Characteristic not found
        _showError(
          "Connection Failed",
          "Could not find the time characteristic.",
        );
        await device.disconnect();
      }
    } catch (e) {
      _showError("Connection Error", e.toString());
    } finally {
      setState(() {
        _isConnecting = false;
        if (_connectedDevice == null) {
          _status = "Connection failed. Please try again.";
        }
      });
    }
  }

  Future<void> _syncTime() async {
    if (_timeCharacteristic == null) {
      _showError(
        "Sync Error",
        "Not connected or time characteristic not found.",
      );
      return;
    }

    try {
      // Get current time
      DateTime now = DateTime.now();

      // Format data as 7-byte array
      // [Year_L, Year_H, Month, Day, Hour, Min, Sec]
      // t.year = little_endian_read_16(buffer, 0);
      Uint8List data = Uint8List(7);
      ByteData.view(data.buffer).setUint16(0, now.year, Endian.little);
      data[2] = now.month;
      data[3] = now.day;
      data[4] = now.hour;
      data[5] = now.minute;
      data[6] = now.second;

      // Write data to characteristic
      // The pico's .gatt file specifies `WRITE | WRITE_WITHOUT_RESPONSE`
      await _timeCharacteristic!.write(data, withoutResponse: true);

      // 4. Show success
      _showSuccess(
        "Time Synced!",
        "Set Pico time to: ${now.toIso8601String()}",
      );
    } catch (e) {
      _showError("Sync Error", e.toString());
    }
  }

  void _disconnect() {
    _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
      _timeCharacteristic = null;
      _status = "Disconnected. Ready to scan again.";
    });
  }

  // --- UI Helper Methods ---

  void _showError(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
    setState(() {
      _status = message;
    });
  }

  void _showSuccess(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pico Time Setter'),
        actions: [
          IconButton(
            icon: Icon(
              FlutterBluePlus.isScanningNow
                  ? Icons.stop_circle_outlined
                  : Icons.search,
            ),
            onPressed: FlutterBluePlus.isScanningNow
                ? FlutterBluePlus.stopScan
                : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusDisplay(),
          if (_connectedDevice != null)
            _buildConnectedDeviceCard()
          else
            _buildScanResultList(),
        ],
      ),
    );
  }

  Widget _buildStatusDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        _status,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildConnectedDeviceCard() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _connectedDevice!.platformName.isNotEmpty
                  ? _connectedDevice!.platformName
                  : "Unknown Device",
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              _connectedDevice!.remoteId.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            ElevatedButton.icon(
              icon: const Icon(Icons.access_time_filled),
              label: const Text('Sync Current Time'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: _syncTime,
            ),
            const SizedBox(height: 12.0),
            OutlinedButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanResultList() {
    if (_isConnecting) {
      return const Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Connecting..."),
            ],
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          final deviceName = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : "Unknown Device";
          return ListTile(
            leading: const Icon(Icons.memory), // Icon for Pico
            title: Text(deviceName),
            subtitle: Text(result.device.remoteId.toString()),
            trailing: Text("${result.rssi} dBm"),
            onTap: () => _connectToDevice(result.device),
          );
        },
      ),
    );
  }
}
