#!/bin/sh
# sing-box 日志裁剪 (copytruncate 模式):
# 超过 SIZE_KB 则把末尾 KEEP 行回写到同一 inode —— sing-box 的 FD 始终有效, 不会产生幽灵文件
LOG="/tmp/log/sing-box.log"  # GL固件 /var 是 /tmp 软链, 等价于 sing-box.json 里 log.output /var/log/sing-box.log; 其他固件请对齐你的 log.output
SIZE_KB=5120
KEEP=2000

[ -f "$LOG" ] || exit 0
size=$(du -k "$LOG" | cut -f1)
[ "$size" -le "$SIZE_KB" ] && exit 0

# 快照末尾 → 原地覆盖 (清空同一文件再写回); cat 打开的是既有 inode, 不换文件
tail -n "$KEEP" "$LOG" > "$LOG.keep" && cat "$LOG.keep" > "$LOG" && rm -f "$LOG.keep"
