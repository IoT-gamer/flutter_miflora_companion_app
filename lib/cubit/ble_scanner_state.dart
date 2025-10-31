part of 'ble_scanner_cubit.dart';

// An enum to represent the distinct states of our scanner
enum BleScannerStatus {
  initial,
  permissionsGranted,
  permissionsDenied,
  scanning,
  scanFinished,
  connecting,
  connected,
  error,
}

class BleScannerState extends Equatable {
  final BleScannerStatus status;
  final List<ScanResult> scanResults;
  final BluetoothDevice? connectedDevice;
  final String statusMessage;
  final bool isLoading;
  final List<String> logLines;

  const BleScannerState({
    this.status = BleScannerStatus.initial,
    this.scanResults = const [],
    this.connectedDevice,
    this.statusMessage = "Requesting permissions...",
    this.isLoading = false,
    this.logLines = const [],
  });

  BleScannerState copyWith({
    BleScannerStatus? status,
    List<ScanResult>? scanResults,
    // Use a nullable function to allow explicitly setting device to null
    BluetoothDevice? Function()? connectedDevice,
    String? statusMessage,
    bool? isLoading,
    List<String>? logLines,
  }) {
    return BleScannerState(
      status: status ?? this.status,
      scanResults: scanResults ?? this.scanResults,
      connectedDevice: connectedDevice != null
          ? connectedDevice()
          : this.connectedDevice,
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      logLines: logLines ?? this.logLines,
    );
  }

  @override
  List<Object?> get props => [
    status,
    scanResults,
    connectedDevice,
    statusMessage,
    isLoading,
    logLines,
  ];
}
