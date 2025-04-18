#!/data/data/com.termux/files/usr/bin/bash

# Ops Node Integration
termux-toast "Device connected as Ops Node."

# Always update system first
pkg update -y && pkg upgrade -y

# Install helpful Termux tools
pkg install openssh python git wget termux-api -y

# Notify device is ready
termux-toast "Ops Node setup complete."

# Infinite loop: Device stays connected, ready for commands
while true; do
    sleep 3600
done
