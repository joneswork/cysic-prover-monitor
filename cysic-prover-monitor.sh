#!/bin/bash

# ==== 参数配置 (Configuration) ====
LOG_FILE="/var/log/prover.log"
SESSION_NAME="cysic"
# 日志无更新的超时时间（秒），5分钟 = 300秒
# Timeout in seconds for no log updates. 5 minutes = 300 seconds.
TIMEOUT=300
# 脚本循环检测的间隔时间（秒）
# Interval in seconds for the script to check the log file.
CHECK_INTERVAL=60
# 重启后执行的命令
# Command to execute on restart.
RESTART_CMD="cd /root/cysic-prover && ./start2.sh"
# tmux 的绝对路径。如果你的路径不同，请修改这里。可以通过 `which tmux` 命令查找。
# Absolute path to tmux. Change this if your path is different. You can find it with `which tmux`.
TMUX_PATH="/usr/bin/tmux"


# ==== 飞书通知配置 (Feishu Notification Configuration) ====
WEBHOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/111111111111111111111111111111111111"
MACHINE_ID="proverid" # 可以和 prover 脚本使用同一个 ID

# ==== 飞书通知函数 (Feishu Notification Function) ====
send_feishu() {
    local message="$1"
    # 使用 timeout 防止 curl 卡死
    # Use timeout to prevent curl from getting stuck
    timeout 10s curl -s -X POST -H "Content-Type: application/json" -d "{
        \"msg_type\": \"text\",
        \"content\": {\"text\": \"[监控脚本][$MACHINE_ID] $message\"}
    }" "$WEBHOOK_URL" > /dev/null
}

echo "[$(date)] 监控脚本启动，开始监视日志文件: $LOG_FILE"
send_feishu "监控脚本已启动。"

# ==== 主循环 (Main Loop) ====
while true; do
    # 检查日志文件是否存在
    if [ ! -f "$LOG_FILE" ]; then
        echo "[$(date)] 日志文件 '$LOG_FILE' 未找到，等待 ${CHECK_INTERVAL} 秒后重试..."
        sleep ${CHECK_INTERVAL}
        continue
    fi

    # 获取当前时间和文件的最后修改时间（Unix 时间戳）
    current_time=$(date +%s)
    last_modified_time=$(stat -c %Y "$LOG_FILE")

    # 计算时间差
    time_diff=$((current_time - last_modified_time))

    # 判断是否超时
    if [ "$time_diff" -gt "$TIMEOUT" ]; then
        echo "[$(date)] 检测到日志文件无更新超过 ${TIMEOUT} 秒，准备重启服务..."
        send_feishu "检测到日志无更新超过5分钟，将重启 Prover 服务。"

        # 检查 tmux 会话是否存在，如果存在则终结它
        if $TMUX_PATH has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "[$(date)] 正在终结旧的 tmux 会话: $SESSION_NAME"
            $TMUX_PATH kill-session -t "$SESSION_NAME"
            send_feishu "旧的 tmux 会话 '$SESSION_NAME' 已终结。"
        else
            echo "[$(date)] 未找到旧的 tmux 会话 '$SESSION_NAME'，直接创建新会话。"
        fi

        # 等待30秒
        echo "[$(date)] 等待 30 秒..."
        sleep 30

        # 创建新的 detached tmux 会话并执行启动命令
        echo "[$(date)] 正在创建新的 tmux 会话 '$SESSION_NAME' 并执行启动命令..."
        # 使用 bash -c 来确保 cd 和 ./start2.sh 在同一个 shell 环境中顺序执行
        $TMUX_PATH new-session -d -s "$SESSION_NAME" "bash -c '${RESTART_CMD}'"
        
        if [ $? -eq 0 ]; then
            echo "[$(date)] 新的 tmux 会话 '$SESSION_NAME' 已成功启动。"
            send_feishu "新的 tmux 会话 '$SESSION_NAME' 已成功启动。"
        else
            echo "[$(date)] 错误：创建新的 tmux 会话 '$SESSION_NAME' 失败！"
            send_feishu "错误：创建新的 tmux 会话 '$SESSION_NAME' 失败！"
        fi
        
        # 重启后额外等待一段时间，避免因日志文件未立即生成而导致连续重启
        echo "[$(date)] 重启操作完成，等待 2 分钟后继续监控..."
        sleep 120
    fi

    # 等待指定间隔后进行下一次检测
    sleep ${CHECK_INTERVAL}
done
