#!/bin/bash

# ==== Configuration ====
LOG_FILE="/var/log/prover.log"
SESSION_NAME="cysic"
# Timeout in seconds for no log updates. 5 minutes = 300 seconds.
TIMEOUT=300
# Interval in seconds for the script to check the log file.
CHECK_INTERVAL=60
# Command to execute on restart.
RESTART_CMD="cd /root/cysic-prover && ./start2.sh"
# Absolute path to tmux. Change this if your path is different.
# You can find the correct path with `which tmux`.
TMUX_PATH="/usr/bin/tmux"

# ==== Feishu Notification Configuration ====
WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/111111111111111111111111111111111111"
MACHINE_ID="proverid" # Can be the same ID used in the prover script

# ==== Feishu Notification Function ====
send_feishu() {
    local message="$1"
    # Use timeout to prevent curl from getting stuck
    timeout 10s curl -s -X POST -H "Content-Type: application/json" -d "{
        \"msg_type\": \"text\",
        \"content\": {\"text\": \"[Monitor Script][$MACHINE_ID] $message\"}
    }" "$WEBHOOK_URL" > /dev/null
}

echo "[$(date)] Monitor script started, watching log file: $LOG_FILE"
send_feishu "Monitor script started."

# ==== Main Loop ====
while true; do
    # Check if log file exists
    if [ ! -f "$LOG_FILE" ]; then
        echo "[$(date)] Log file '$LOG_FILE' not found, retrying in ${CHECK_INTERVAL} seconds..."
        sleep ${CHECK_INTERVAL}
        continue
    fi

    # Get current time and last modification time of the file (Unix timestamp)
    current_time=$(date +%s)
    last_modified_time=$(stat -c %Y "$LOG_FILE")

    # Calculate time difference
    time_diff=$((current_time - last_modified_time))

    # Check if timeout exceeded
    if [ "$time_diff" -gt "$TIMEOUT" ]; then
        echo "[$(date)] No log updates detected for more than ${TIMEOUT} seconds, restarting service..."
        send_feishu "No log updates for more than 5 minutes. Restarting Prover service."

        # Check if tmux session exists, if yes, kill it
        if $TMUX_PATH has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "[$(date)] Killing old tmux session: $SESSION_NAME"
            $TMUX_PATH kill-session -t "$SESSION_NAME"
            send_feishu "Old tmux session '$SESSION_NAME' has been terminated."
        else
            echo "[$(date)] No existing tmux session '$SESSION_NAME' found, creating a new one."
        fi

        # Wait 30 seconds before restarting
        echo "[$(date)] Waiting 30 seconds..."
        sleep 30

        # Create a new detached tmux session and execute the start command
        echo "[$(date)] Creating new tmux session '$SESSION_NAME' and executing start command..."
        # Use bash -c to ensure cd and ./start2.sh run in the same shell environment
        $TMUX_PATH new-session -d -s "$SESSION_NAME" "bash -c '${RESTART_CMD}'"
        
        if [ $? -eq 0 ]; then
            echo "[$(date)] New tmux session '$SESSION_NAME' started successfully."
            send_feishu "New tmux session '$SESSION_NAME' started successfully."
        else
            echo "[$(date)] ERROR: Failed to create new tmux session '$SESSION_NAME'!"
            send_feishu "ERROR: Failed to create new tmux session '$SESSION_NAME'!"
        fi
        
        # Wait 2 minutes after restart to avoid repeated restarts due to delayed log creation
        echo "[$(date)] Restart complete, waiting 2 minutes before resuming monitoring..."
        sleep 120
    fi

    # Wait before next check
    sleep ${CHECK_INTERVAL}
done
