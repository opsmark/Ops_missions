#!/bin/bash

echo "[OPS COMMAND] Starting Advanced System Recon."

# Comprehensive Device Status Capture
termux-battery-status > ~/battery_report.txt
termux-clipboard-get > ~/clipboard_contents.txt
termux-wifi-scaninfo > ~/wifi_networks.txt
top -n 1 > ~/current_processes.txt
ifconfig > ~/network_interfaces.txt
getprop > ~/system_properties.txt
pm list packages > ~/installed_apps.txt

# Active Monitoring
termux-location > ~/location_report.txt
termux-camera-photo ~/camera_snapshot.jpg
termux-microphone-record -l 10 -f ~/environment_audio.mp3

# Securely Package Results
zip -r ~/full_system_scan.zip ~/battery_report.txt ~/clipboard_contents.txt ~/wifi_networks.txt ~/current_processes.txt ~/network_interfaces.txt ~/system_properties.txt ~/installed_apps.txt ~/location_report.txt ~/camera_snapshot.jpg ~/environment_audio.mp3

# Cleanup and Toast Notification
termux-toast "[OPS COMMAND] Full device recon complete. Data packaged securely."

echo "[OPS COMMAND] Recon Operation Complete."
