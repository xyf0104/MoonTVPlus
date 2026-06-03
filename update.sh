#!/bin/bash
# ============================================
# 无风影视 - 无感升级脚本
# 使用方式: bash update.sh
# 
# 原理：
# 1. 拉取最新代码并构建新镜像
# 2. 用新镜像替换旧容器
# 3. 数据存在 Docker 卷中，不受容器更换影响
# 4. 整个过程停机时间 < 5 秒
# ============================================

set -e

PROJECT_DIR="/opt/wufeng-tv"
cd "$PROJECT_DIR"

echo "🔄 无风影视 - 无感升级"
echo "=========================="

# 1. 拉取最新代码
echo "📥 拉取最新代码..."
if [ -d "MoonTVPlus" ]; then
    cd MoonTVPlus
    git pull origin main
    cd ..
else
    git clone https://github.com/xyf0104/MoonTVPlus.git
fi

# 2. 构建新镜像（不影响正在运行的旧容器）
echo "🏗️  构建新镜像..."
docker compose build --no-cache wufeng-tv

# 3. 用新镜像无缝替换旧容器（停机 < 5 秒）
echo "🔄 替换容器（数据不受影响）..."
docker compose up -d --force-recreate --no-deps wufeng-tv

# 4. 清理旧镜像
echo "🧹 清理旧镜像..."
docker image prune -f

echo ""
echo "✅ 升级完成！"
echo "🌐 服务已恢复运行: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):3000"
echo ""
echo "📋 查看日志: docker compose logs -f wufeng-tv"
