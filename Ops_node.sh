#!/data/data/com.termux/files/usr/bin/bash

termux-toast "[OPS NODE] Initiating Full Autonomous Setup."

# System Upgrade
pkg update -y && pkg upgrade -y

# Comprehensive toolkit installation
pkg install openssh python git wget termux-api nmap metasploit-framework proot proot-distro nodejs-lts termux-services termux-exec tsu -y

# Full Ops Framework Clone
rm -rf ~/Ops_Framework
git clone https://github.com/opsmark/Ops_Framework.git ~/Ops_Framework

# Initiate Complete Node Integration
bash ~/Ops_Framework/initialize_ops_node.sh

termux-toast "[OPS NODE] Autonomous Node Fully Online."

# Infinite Autonomous Maintenance Loop
while true; do
    bash ~/Ops_Framework/maintain_and_upgrade.sh
    sleep 900 # 15 min intervals
done
