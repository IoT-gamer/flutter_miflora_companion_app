# Flutter MiFlora Companion App

[![Work in Progress](https://img.shields.io/badge/status-work%20in%20progress-yellow)](https://example.com/your-project-status-page)

A companion mobile app for the [pico_miflora_datalogger](https://github.com/IoT-gamer/pico_miflora_datalogger).

This Flutter app scans for your "MiFlora Logger" Pico W device and provides two main functions: syncing the time and downloading historical data.

## Features

* **Scan & Connect:** Scans for the Pico W device advertising the "MiFlora Logger" service.
* **RTC Sync:** Allows you to sync the Pico's internal Real-Time Clock (RTC) with your phone's current time. This is mandatory for the logger to start its logging cycle.
* **Download Log History:** Connect to the device and download log files (e.g., `2025-10-31.txt`) directly from its SD card over BLE.
* **Plot Data:** Automatically parses the downloaded log data and plots Temperature and Light in a simple chart.
* **View Raw Data:** Displays the raw, line-by-line log data received from the device.