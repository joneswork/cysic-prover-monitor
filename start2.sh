#!/bin/bash
# ==== Configuration ====
WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/11111111111111111111"
MACHINE_ID="ID"
CHAIN_ID="534352"
ENV_VARS="SP1_PROVER=cuda LD_LIBRARY_PATH=. CHAIN_ID=$CHAIN_ID"
prover_cmd="./prover"

# Log and script path configuration
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/prover.log"
MAX_LINES=100000

PROVER_BASE_DIR="/root/cysic-prover"

# Ensure log directory and file exist
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log_task_hash=""

# ==== Feishu Notification Function ====
send_feishu() {
    local message="$1"
    # Use timeout to prevent curl from hanging
    timeout 10s curl -s -X POST -H "Content-Type: application/json" -d "{
        \"msg_type\": \"text\",
        \"content\": {\"text\": \"[$MACHINE_ID] $message\"}
    }" "$WEBHOOK_URL" > /dev/null
}

# ==== Log Trimming Function ====
trim_log_file() {
    local line_count
    line_count=$(wc -l < "$LOG_FILE")
    if [ "$line_count" -gt "$MAX_LINES" ]; then
        tail -n "$MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        echo "[$(date)] Log file exceeds max lines, truncated to the last $MAX_LINES lines." >> "$LOG_FILE"
    fi
}

# ==== Main Logic ====

# Switch to Prover working directory
cd "$PROVER_BASE_DIR" || {
    echo "[$(date)] CRITICAL: Failed to cd to $PROVER_BASE_DIR. Exiting." | tee -a "$LOG_FILE"
    send_feishu "CRITICAL: Failed to enter directory $PROVER_BASE_DIR, script exiting."
    exit 1
}

# Trim log before starting
trim_log_file
echo "[$(date)] Starting prover..." | tee -a "$LOG_FILE"
send_feishu "Prover script started."

# Ensure that if any command in a pipeline fails, the pipeline’s return code is failure
set -o pipefail

# Run prover and monitor output
eval $ENV_VARS $prover_cmd 2>&1 | while IFS= read -r line; do
    timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $line" | tee -a "$LOG_FILE"

    # Task start and end notification logic
    if [[ "$line" =~ create\ task\ success,\ task\ hash:\ ([0-9]+) ]]; then
        log_task_hash="${BASH_REMATCH[1]}"
        send_feishu "Task Started: $log_task_hash"
    elif [[ "$line" =~ task:\ ([0-9]+)\ process\ submitProofData\ finish ]]; then
        finished_task="${BASH_REMATCH[1]}"
        if [[ "$finished_task" == "$log_task_hash" ]]; then
            send_feishu "Task Finished: $finished_task"
            log_task_hash=""
        fi
    # --- Error detection and exit ---
    # When any critical error is detected, send notification and terminate the script
    elif [[ "$line" =~ "rsp_main: error: Local Execution Failed" ]] || \
         [[ "$line" == *"error when read message from ws, msgType: -1 err: local error: tls: bad record MAC"* ]] || \
         [[ "$line" == *"/home/cysic/rsp/crates/executor/host/src/full_executor.rs"* ]] || \
         [[ "$line" =~ "rsp_main: error: error sending request for url" ]] || \
         [[ "$line" =~ "goroutine 1 [running]" ]]; then

        echo "[$(date)] Fatal error detected. Script will now exit." | tee -a "$LOG_FILE"
        send_feishu "Critical error detected, script exited: $line"

        # Use kill $$ to send SIGTERM to the main process of the current script,
        # thus terminating the entire script
        kill $$
    fi
done

# Check prover process exit status
# This will only be reached if prover exited normally (not killed by error detection above)
prover_exit_code=${PIPESTATUS[0]}
if [[ $prover_exit_code -ne 0 ]]; then
    echo "[$(date)] Prover process exited with non-zero status: $prover_exit_code. Script is terminating." | tee -a "$LOG_FILE"
    send_feishu "Prover process exited abnormally (code: $prover_exit_code), script terminating."
    exit $prover_exit_code
fi

echo "[$(date)] Prover exited normally. Script finished." | tee -a "$LOG_FILE"
send_feishu "Prover exited normally, script finished."
exit 0
