#!/bin/bash

# ==== 代理设置 (Proxy Settings) ====
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7891"

# ==== 参数配置 (Configuration) ====
WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/11111111111111111111"
MACHINE_ID="ID"
CHAIN_ID="534352"
ENV_VARS="SP1_PROVER=cuda LD_LIBRARY_PATH=. CHAIN_ID=$CHAIN_ID"
prover_cmd="./prover"

# 日志和脚本路径配置
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/prover.log"
MAX_LINES=100000

PROVER_BASE_DIR="/root/cysic-prover"

# 确保日志目录和文件存在
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log_task_hash=""

# ==== 飞书通知 (Feishu Notification Function) ====
send_feishu() {
    local message="$1"
    # 使用 timeout 防止 curl 卡死
    timeout 10s curl -s -X POST -H "Content-Type: application/json" -d "{
        \"msg_type\": \"text\",
        \"content\": {\"text\": \"[$MACHINE_ID] $message\"}
    }" "$WEBHOOK_URL" > /dev/null
}

# ==== 日志裁剪函数 (Log Trimming Function) ====
trim_log_file() {
    local line_count
    line_count=$(wc -l < "$LOG_FILE")
    if [ "$line_count" -gt "$MAX_LINES" ]; then
        tail -n "$MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        echo "[$(date)] Log file exceeds max lines, truncated to the last $MAX_LINES lines." >> "$LOG_FILE"
    fi
}

# ==== 主逻辑 (Main Logic) ====

# 切换到 Prover 的工作目录
cd "$PROVER_BASE_DIR" || {
    echo "[$(date)] CRITICAL: Failed to cd to $PROVER_BASE_DIR. Exiting." | tee -a "$LOG_FILE"
    send_feishu "CRITICAL: 无法进入目录 $PROVER_BASE_DIR，脚本退出。"
    exit 1
}

# 启动前裁剪一次日志
trim_log_file
echo "[$(date)] Starting prover..." | tee -a "$LOG_FILE"
send_feishu "Prover 脚本启动。"

# 确保当管道中任何一个命令失败时，整个管道的返回码都是失败的
set -o pipefail

# 执行 prover 并监控输出
eval $ENV_VARS $prover_cmd 2>&1 | while IFS= read -r line; do
    timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $line" | tee -a "$LOG_FILE"

    # 任务开始和结束的通知逻辑
    if [[ "$line" =~ create\ task\ success,\ task\ hash:\ ([0-9]+) ]]; then
        log_task_hash="${BASH_REMATCH[1]}"
        send_feishu "任务开始 (Task Started): $log_task_hash"
    elif [[ "$line" =~ task:\ ([0-9]+)\ process\ submitProofData\ finish ]]; then
        finished_task="${BASH_REMATCH[1]}"
        if [[ "$finished_task" == "$log_task_hash" ]]; then
            send_feishu "任务完成 (Task Finished): $finished_task"
            log_task_hash=""
        fi
    # --- 错误检测与退出 ---
    # 当检测到任何一个严重错误时，发送通知并终止整个脚本
    elif [[ "$line" =~ "rsp_main: error: Local Execution Failed" ]] || \
         [[ "$line" == *"error when read message from ws, msgType: -1 err: local error: tls: bad record MAC"* ]] || \
         [[ "$line" == *"/home/cysic/rsp/crates/executor/host/src/full_executor.rs"* ]] || \
         [[ "$line" =~ "rsp_main: error: error sending request for url" ]] || \
         [[ "$line" =~ "goroutine 1 [running]" ]]; then

        echo "[$(date)] Fatal error detected. Script will now exit." | tee -a "$LOG_FILE"
        send_feishu "检测到严重错误，脚本已退出: $line"

        # 使用 kill $$ 向当前脚本的主进程发送 SIGTERM 信号，从而终止整个脚本
        # 这是从管道子 shell 中退出整个脚本的可靠方法
        kill $$
    fi
done

# 检查 prover 进程的退出状态
# 只有当 prover 正常退出 (没有被 while 循环中的错误检测杀死) 时，才会执行到这里
prover_exit_code=${PIPESTATUS[0]}
if [[ $prover_exit_code -ne 0 ]]; then
    echo "[$(date)] Prover process exited with non-zero status: $prover_exit_code. Script is terminating." | tee -a "$LOG_FILE"
    send_feishu "Prover 进程异常退出 (代码: $prover_exit_code)，脚本终止。"
    exit $prover_exit_code
fi

echo "[$(date)] Prover exited normally. Script finished." | tee -a "$LOG_FILE"
send_feishu "Prover 正常退出，脚本执行完毕。"
exit 0
