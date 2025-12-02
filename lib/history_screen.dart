import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'cubit/ble_scanner_cubit.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Controller for the date text field
  late final TextEditingController _dateController;

  @override
  void initState() {
    super.initState();
    // Pre-fill the text field with today's date in the correct format
    final now = DateTime.now();
    final formattedDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    _dateController = TextEditingController(text: formattedDate);
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  /// Called when the download button is pressed
  void _requestData() {
    final cubit = context.read<BleScannerCubit>();
    final date = _dateController.text;
    if (date.isNotEmpty) {
      // Add the .txt suffix and request the file
      cubit.requestLogFile("$date.txt");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log History')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- 1. Date Request UI ---
            _buildDateRequester(),
            const SizedBox(height: 16),
            const Divider(),
            // --- 2. Data Display Area ---
            Expanded(
              child: BlocBuilder<BleScannerCubit, BleScannerState>(
                builder: (context, state) {
                  // --- Loading State ---
                  if (state.isLoading) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text("Receiving data..."),
                        ],
                      ),
                    );
                  }

                  // --- Empty State ---
                  if (state.logLines.isEmpty) {
                    return const Center(
                      child: Text(
                        'Please request a log file to see data.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  // --- Data Loaded State ---
                  return _buildDataDisplay(state.logLines);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the TextField and Button to request a file
  Widget _buildDateRequester() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _dateController,
            decoration: const InputDecoration(
              labelText: 'Log Date (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: _requestData,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }

  /// Builds the Chart and List view once data is loaded
  Widget _buildDataDisplay(List<String> lines) {
    // Parse the data
    final (
      tempSpots,
      lightSpots,
      moistureSpots,
      conductivitySpots,
      batterySpots,
    ) = _parseLogData(
      lines,
    );

    // Helper to keep code clean
    Widget buildChartSection(String title, List<FlSpot> spots, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (spots.isEmpty)
            Text('No $title data found.')
          else
            SizedBox(
              height: 200,
              child: LineChart(_buildChartData(spots, color)),
            ),
          const SizedBox(height: 24),
        ],
      );
    }

    return ListView(
      children: [
        buildChartSection('Temperature (°C)', tempSpots, Colors.redAccent),
        buildChartSection('Light (lux)', lightSpots, Colors.orangeAccent),
        buildChartSection('Moisture (%)', moistureSpots, Colors.blueAccent),
        buildChartSection(
          'Conductivity (µS/cm)',
          conductivitySpots,
          Colors.brown,
        ),
        buildChartSection('Battery (%)', batterySpots, Colors.green),

        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Raw Data (${lines.length} lines)',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),

        // Raw Data List
        Container(
          height: 300,
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest, // updated for Material 3
          child: ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Text(
                  lines[index],
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Helper function to parse log lines into chartable data
  /// Returns a Record of (Temp, Light, Moisture, Conductivity, Battery)
  (List<FlSpot>, List<FlSpot>, List<FlSpot>, List<FlSpot>, List<FlSpot>)
  _parseLogData(List<String> lines) {
    final List<FlSpot> tempSpots = [];
    final List<FlSpot> lightSpots = [];
    final List<FlSpot> moistureSpots = [];
    final List<FlSpot> conductivitySpots = [];
    final List<FlSpot> batterySpots = [];

    for (final line in lines) {
      try {
        // Line format:
        // 2025-10-30T08:30:05,Temp:28.5,Light:150,Moisture:45,Conductivity:350,Battery:88
        final parts = line.split(',');
        if (parts.length < 6) continue; // Ensure we have all parts

        final timestampStr = parts[0];
        final tempStr = parts[1].split(':')[1];
        final lightStr = parts[2].split(':')[1];
        final moistureStr = parts[3].split(':')[1];
        final conductivityStr = parts[4].split(':')[1];
        final batteryStr = parts[5].split(':')[1];

        final dateTime = DateTime.parse(timestampStr);
        final double x = dateTime.millisecondsSinceEpoch.toDouble();

        // Parse values
        tempSpots.add(FlSpot(x, double.parse(tempStr)));
        lightSpots.add(FlSpot(x, double.parse(lightStr)));
        moistureSpots.add(FlSpot(x, double.parse(moistureStr)));
        conductivitySpots.add(FlSpot(x, double.parse(conductivityStr)));
        batterySpots.add(FlSpot(x, double.parse(batteryStr)));
      } catch (e) {
        print("Error parsing log line: $e");
      }
    }
    return (
      tempSpots,
      lightSpots,
      moistureSpots,
      conductivitySpots,
      batterySpots,
    );
  }

  /// Helper to create the chart data for fl_chart
  LineChartData _buildChartData(List<FlSpot> spots, Color color) {
    return LineChartData(
      gridData: FlGridData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 40),
        ),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ), // Hide time labels for simplicity
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade700),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withOpacity(0.3)),
        ),
      ],
    );
  }
}
