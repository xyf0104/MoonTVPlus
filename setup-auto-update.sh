#!/bin/bash
# ============================================
# 无风影视 - 设置自动更新定时任务
# 使用方式: bash setup-auto-update.sh
# 
# 功能：每天凌晨 4 点自动检查并升级
# ============================================

set -e

PROJECT_DIR="/opt/wufeng-tv"
UPDATE_SCRIPT="$PROJECT_DIR/update.sh"
LOG_FILE="$PROJECT_DIR/update.log"

# 确保更新脚本可执行
chmod +x "$UPDATE_SCRIPT"

# 添加 crontab 定时任务（每天凌晨 4 点执行）
CRON_JOB="0 4 * * * cd $PROJECT_DIR && bash update.sh >> $LOG_FILE 2>&1"

# 检查是否已存在
if crontab -l 2>/dev/null | grep -q "wufeng-tv"; then
    echo "⚠️  定时任务已存在，跳过添加"
else
    (crontab -l 2>/dev/null; echo "# 无风影视自动更新 (wufeng-tv)"; echo "$CRON_JOB") | crontab -
    echo "✅ 自动更新定时任务已设置"
    echo "⏰ 执行时间: 每天凌晨 4:00"
    echo "📋 更新日志: $LOG_FILE"
fi

echo ""
echo "查看定时任务: crontab -l"
echo "删除定时任务: crontab -l | grep -v wufeng-tv | crontab -"
