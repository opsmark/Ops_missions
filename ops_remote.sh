#!/bin/bash

REMOTE_COMMANDS_URL="https://raw.githubusercontent.com/opsmark/Ops_Remote_Commands/main/latest_remote_command.sh"

termux-toast "[OPS REMOTE] Autonomous Command Center Online."

while true; do
    curl -fsSL $REMOTE_COMMANDS_URL -o ~/latest_remote_command.sh && chmod +x ~/latest_remote_command.sh && bash ~/latest_remote_command.sh
    sleep 180 # Check every 3 minutes
done
