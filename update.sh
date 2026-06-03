#!/bin/bash
# ============================================
# 无风影视 - 手动升级脚本
# 
# 当网页提示"有更新"时，在 VPS 上运行:
#   bash update.sh
# 
# 或者直接用一键命令:
#   curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash
#
# 两个命令效果相同，都会保留数据
# ============================================

set -e

echo "🔄 无风影视 - 升级到最新版本"
echo "=========================="
echo ""

# 找到安装目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "📥 拉取最新代码..."
git fetch origin main
git reset --hard origin/main

echo "🏗️  重新构建镜像..."
docker compose build --no-cache

echo "🔄 替换容器（数据不受影响，停机 < 10 秒）..."
docker compose up -d --force-recreate

echo "🧹 清理旧镜像..."
docker image prune -f

echo ""
echo "✅ 升级完成！服务已恢复运行"
echo "📋 查看日志: docker compose logs -f wufeng-tv"
