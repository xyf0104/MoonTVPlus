#!/bin/bash
# ============================================
# 无风影视 - VPS 一键部署脚本
# 使用方式: curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash
# 或者: bash deploy.sh
# ============================================

set -e

echo "🎬 无风影视 - VPS 一键部署"
echo "=========================="

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "📦 Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker 安装完成"
fi

# 检查 Docker Compose 是否安装
if ! docker compose version &> /dev/null; then
    echo "📦 Docker Compose 未安装，正在安装..."
    apt-get update && apt-get install -y docker-compose-plugin
    echo "✅ Docker Compose 安装完成"
fi

# 创建项目目录
PROJECT_DIR="/opt/wufeng-tv"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 下载 docker-compose.yml
echo "📥 下载配置文件..."
curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/docker-compose.yml -o docker-compose.yml

# 提示用户设置密码
echo ""
echo "⚙️  请设置管理员密码（直接回车使用默认 admin123）："
read -r -p "密码: " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin123}

# 修改 docker-compose.yml 中的密码
sed -i "s/PASSWORD=admin123/PASSWORD=$ADMIN_PASSWORD/g" docker-compose.yml

# 拉取镜像并启动
echo ""
echo "🚀 正在构建并启动服务..."
docker compose up -d --build

echo ""
echo "============================================"
echo "✅ 无风影视部署完成！"
echo ""
echo "🌐 访问地址: http://$(curl -s ifconfig.me):3000"
echo "👤 用户名: admin"
echo "🔑 密码: $ADMIN_PASSWORD"
echo ""
echo "📁 数据目录: $PROJECT_DIR"
echo "🔄 更新命令: cd $PROJECT_DIR && docker compose pull && docker compose up -d"
echo "📋 查看日志: cd $PROJECT_DIR && docker compose logs -f"
echo "============================================"
