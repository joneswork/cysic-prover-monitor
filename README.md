# Cysic Prover Monitor

![Feishu Notification Example](feishu-notification-example.png)

This project provides two shell scripts to **run and monitor a Cysic Prover process** inside a `tmux` session, with **automatic restart** and **Feishu (Lark) webhook notifications**.

---

## 📌 Features

### 1. `start2.sh` – Prover Runner Script
- **Purpose:** Starts the Cysic Prover with the necessary environment variables.
- **Logging:**
  - Outputs prover logs to `/var/log/prover.log`.
  - Automatically trims the log file to the last **100,000 lines** to prevent excessive disk usage.
- **Task Tracking:**
  - Detects when a prover task starts or finishes and sends notifications to Feishu.
- **Error Handling:**
  - Watches for fatal errors in prover output (e.g., TLS errors, execution failures).
  - Sends a Feishu alert and terminates itself when critical errors occur.
- **Feishu Notifications:**
  - Customizable `WEBHOOK_URL` for Feishu bot integration.
  - Optional `MACHINE_ID` for identifying the machine in notifications.

---

### 2. `cysic-prover-monitor.sh` – Prover Monitor Script
- **Purpose:** Monitors the prover log file and automatically restarts the prover if no new log entries are detected for a set time.
- **How it works:**
  1. Checks `/var/log/prover.log` every `CHECK_INTERVAL` seconds (default: 60).
  2. If there’s no log update for `TIMEOUT` seconds (default: 300), it:
     - Stops the current `tmux` session running the prover.
     - Waits 30 seconds.
     - Starts a new `tmux` session and runs `start2.sh`.
     - Waits an additional 2 minutes before resuming monitoring.
- **Session Management:**
  - Uses `tmux` to run prover in a background session (`SESSION_NAME`, default: `cysic`).
  - Kills old sessions before creating new ones.
- **Feishu Notifications:**
  - Alerts on script start, prover restarts, and errors.
  - Can use the same `MACHINE_ID` as `start2.sh`.

---

## 🛠 Requirements
- **tmux** (check with `which tmux`)
- **curl** (for Feishu webhook notifications)
- Cysic Prover binary and dependencies in `/root/cysic-prover`
- Linux environment with bash

---

## 🚀 Installation & Usage

### 1. Place Scripts
```bash
cd /root/cysic-prover
# Place start2.sh here
chmod +x start2.sh

# Place cysic-prover-monitor.sh anywhere (e.g., /root/)
chmod +x /root/cysic-prover-monitor.sh
/root/cysic-prover-monitor.sh

2. Edit Configurations
Open both scripts and set:

WEBHOOK_URL → Your Feishu bot webhook URL (required for notifications).

MACHINE_ID → A short identifier for this machine (optional but recommended).

In cysic-prover-monitor.sh you may also adjust:

LOG_FILE → Path to the prover log (default /var/log/prover.log).

SESSION_NAME → tmux session name (default cysic).

TIMEOUT → Seconds without new log lines before restart (default 300).

CHECK_INTERVAL → How often the monitor checks the log file (default 60).

TMUX_PATH → Absolute path to tmux (use which tmux to find it).

In start2.sh you may adjust:

PROVER_BASE_DIR → Directory where prover runs (default /root/cysic-prover).

LOG_DIR and LOG_FILE → Where logs are written and rotated.

MAX_LINES → How many lines to keep when trimming logs.

Tip: Keep WEBHOOK_URL private (don’t commit it to public repositories).

3. Start monitoring
Run the monitor script (it will manage the prover inside tmux):

bash
# Start monitor (runs in foreground by default)
/root/cysic-prover-monitor.sh

# (Optional) Run it under systemd or as a background job for persistence
🔄 How They Work Together
mermaid

flowchart TD
    A[Start cysic-prover-monitor.sh] --> B[Check /var/log/prover.log every CHECK_INTERVAL]
    B -->|No log update for TIMEOUT seconds| C[Kill old tmux session]
    C --> D[Wait 30 seconds]
    D --> E[Start new tmux session running start2.sh]
    E --> F[Prover logs written to /var/log/prover.log]
    F --> G[Monitor detects task start/finish]
    G --> H[Send Feishu notifications]
    B -->|Log updated| B
📷 Example Feishu Notification
Place an image file feishu-notification-example.png at the repository root (or change the image path above). Example notification texts:

csharp

[Monitor Script][machine-01] Monitor script started.
[Monitor Script][machine-01] No log updates for more than 5 minutes. Restarting Prover service.
[machine-01] Task Started: 123456
[machine-01] Task Finished: 123456
[Monitor Script][machine-01] New tmux session 'cysic' started successfully.
📝 Troubleshooting & Tips
No tmux found: set TMUX_PATH to the correct path (run which tmux).

Feishu messages not delivered: check WEBHOOK_URL and network connectivity from the host.

Persistent monitoring: consider creating a systemd service to run cysic-prover-monitor.sh at boot.

Log file permissions: ensure the scripts have permission to write to the configured LOG_FILE.
