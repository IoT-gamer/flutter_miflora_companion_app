import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'cubit/ble_scanner_cubit.dart';
import 'history_screen.dart';

void main() {
  // Wrap the app in a BlocProvider to make the Cubit available
  // to all widgets below it.
  runApp(
    BlocProvider(
      create: (context) => BleScannerCubit(),
      child: const PicoTimeSetterApp(),
    ),
  );
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

// BleScannerScreen is now a StatelessWidget!
class BleScannerScreen extends StatelessWidget {
  const BleScannerScreen({super.key});

  // --- UI Helper Methods to show SnackBars ---
  // These are called from the UI event handlers

  void _showSnackBar(BuildContext context, String message, bool isError) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    // Use context.watch to get the current state and rebuild
    // whenever the state changes.
    final state = context.watch<BleScannerCubit>().state;
    final cubit = context.read<BleScannerCubit>();

    final isScanning = state.status == BleScannerStatus.scanning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pico Time Setter'),
        actions: [
          IconButton(
            icon: Icon(isScanning ? Icons.stop_circle_outlined : Icons.search),
            // Use context.read to call methods on the Cubit
            onPressed: isScanning ? cubit.stopScan : cubit.startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusDisplay(context, state),
          if (state.connectedDevice != null)
            _buildConnectedDeviceCard(context, state)
          else
            _buildScanResultList(context, state),
        ],
      ),
    );
  }

  Widget _buildStatusDisplay(BuildContext context, BleScannerState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(
        state.statusMessage, // Read status from the state
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildConnectedDeviceCard(
    BuildContext context,
    BleScannerState state,
  ) {
    final device = state.connectedDevice!;
    final cubit = context.read<BleScannerCubit>();

    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              device.platformName.isNotEmpty
                  ? device.platformName
                  : "Unknown Device",
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              device.remoteId.toString(),
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
              onPressed: () async {
                // Call the cubit method and wait for the result
                final (success, message) = await cubit.syncTime();
                // Show snackbar from the UI layer
                _showSnackBar(context, message, !success);
              },
            ),
            const SizedBox(height: 12.0),

            ElevatedButton.icon(
              icon: const Icon(Icons.history_edu_outlined),
              label: const Text('View Log History'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    // We provide the *existing* cubit to the new screen
                    // so it doesn't create a new one.
                    builder: (_) => BlocProvider.value(
                      value: context.read<BleScannerCubit>(),
                      child: const HistoryScreen(),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12.0),

            ElevatedButton.icon(
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Run Pump (5 Sec)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                backgroundColor: Theme.of(context).colorScheme.tertiary,
                foregroundColor: Theme.of(context).colorScheme.onTertiary,
              ),
              onPressed: () async {
                // Call the cubit method and wait for the result
                final (success, message) = await cubit.runPump();
                // Show snackbar from the UI layer
                if (!context.mounted) return;
                _showSnackBar(context, message, !success);
              },
            ),
            const SizedBox(height: 12.0),

            OutlinedButton(
              onPressed: cubit.disconnect, // Call cubit method
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanResultList(BuildContext context, BleScannerState state) {
    final cubit = context.read<BleScannerCubit>();

    if (state.status == BleScannerStatus.connecting) {
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
        itemCount: state.scanResults.length,
        itemBuilder: (context, index) {
          final result = state.scanResults[index];
          final deviceName = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : "Unknown Device";
          return ListTile(
            leading: const Icon(Icons.memory), // Icon for Pico
            title: Text(deviceName),
            subtitle: Text(result.device.remoteId.toString()),
            trailing: Text("${result.rssi} dBm"),
            onTap: () => cubit.connectToDevice(result.device),
          );
        },
      ),
    );
  }
}
