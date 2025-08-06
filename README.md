Tool: tmux
start2.sh
This is a sub-script that should be placed in the /root/cysic-prover directory.

Optional Variables:

WEBHOOK_URL: Feishu (Lark) Webhook API URL.

MACHINE_ID: Prover ID.
These variables are optional; the script will still run without them.

cysic-prover-monitor.sh
This is the main script. After setting up the above configuration, run cysic-prover-monitor.sh to continuously monitor the process in a loop.

Cysic ReferralCode: bc29a
