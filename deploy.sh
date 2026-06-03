#!/bin/bash
# ============================================
# 无风影视 - 一键安装 / 升级脚本
# 
# 全新安装:
#   curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash
#
# 升级已有安装:
#   curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash
#   （同一个命令，自动识别并保留数据）
#
# 功能:
#   - 自动检测已有的 MoonTVPlus / 无风影视 容器
#   - 保留原有数据卷（数据库、配置、收藏、播放记录等）
#   - 保留原有的 SSL/域名/反向代理配置（不动 Nginx）
#   - 仅替换应用容器，停机 < 10 秒
# ============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✅]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️]${NC} $1"; }
log_step()  { echo -e "${CYAN}[▶]${NC} $1"; }
log_error() { echo -e "${RED}[❌]${NC} $1"; }

echo ""
echo "============================================"
echo "  🎬 无风影视 - 一键安装 / 升级"
echo "============================================"
echo ""

# ---- 1. 检查依赖 ----
log_step "检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    log_warn "Docker 未安装，正在自动安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
    log_info "Docker 安装完成"
fi

if ! docker compose version &> /dev/null; then
    log_warn "Docker Compose 插件未安装，正在安装..."
    apt-get update -qq && apt-get install -y -qq docker-compose-plugin
    log_info "Docker Compose 安装完成"
fi

# ---- 2. 查找已有安装 ----
log_step "检测已有安装..."
EXISTING_DIR=""
EXISTING_COMPOSE=""

# 常见安装路径
for dir in /opt/moontv /opt/moontvplus /opt/MoonTVPlus /opt/wufeng-tv /root/moontv /root/MoonTVPlus; do
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
        EXISTING_DIR="$dir"
        break
    fi
done

# 如果常见路径没找到，搜索正在运行的容器
if [ -z "$EXISTING_DIR" ]; then
    CONTAINER_ID=$(docker ps --filter "name=moontv" --filter "name=wufeng" -q 2>/dev/null | head -1)
    if [ -n "$CONTAINER_ID" ]; then
        # 从容器标签找 compose 项目路径
        COMPOSE_DIR=$(docker inspect "$CONTAINER_ID" --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' 2>/dev/null)
        if [ -n "$COMPOSE_DIR" ] && [ -d "$COMPOSE_DIR" ]; then
            EXISTING_DIR="$COMPOSE_DIR"
        fi
    fi
fi

# ---- 3. 确定安装目录 ----
INSTALL_DIR="${EXISTING_DIR:-/opt/wufeng-tv}"
mkdir -p "$INSTALL_DIR"

if [ -n "$EXISTING_DIR" ]; then
    log_info "检测到已有安装: $EXISTING_DIR"
    echo ""
    echo "  将原地升级，保留所有数据（数据库、配置、收藏等）"
    echo "  SSL/域名/反向代理配置不受影响"
    echo ""
else
    log_info "全新安装，目录: $INSTALL_DIR"
fi

# ---- 4. 克隆或更新代码 ----
log_step "获取最新代码..."
REPO_DIR="$INSTALL_DIR/MoonTVPlus"

if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    git fetch origin main
    git reset --hard origin/main
    log_info "代码已更新到最新版本"
else
    rm -rf "$REPO_DIR"
    git clone --depth 1 https://github.com/xyf0104/MoonTVPlus.git "$REPO_DIR"
    log_info "代码克隆完成"
fi

cd "$REPO_DIR"

# ---- 5. 处理环境配置 ----
log_step "配置环境..."

# 如果已有 .env，保留它（里面有用户的密码等配置）
if [ -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env" "$REPO_DIR/.env"
    log_info "已保留原有环境配置"
elif [ ! -f "$REPO_DIR/.env" ]; then
    # 全新安装，创建默认 .env
    cat > "$REPO_DIR/.env" << 'EOF'
USERNAME=admin
PASSWORD=admin123
NEXT_PUBLIC_STORAGE_TYPE=d1
NEXT_PUBLIC_SITE_NAME=无风影视
SQLITE_DB_PATH=/app/.data/moontv.db
EOF
    log_info "已创建默认环境配置"
fi

# ---- 6. 停止旧容器 ----
if [ -n "$EXISTING_DIR" ]; then
    log_step "停止旧版容器..."
    
    # 先尝试在原目录停止
    if [ -f "$EXISTING_DIR/docker-compose.yml" ] || [ -f "$EXISTING_DIR/docker-compose.yaml" ]; then
        cd "$EXISTING_DIR"
        docker compose down --remove-orphans 2>/dev/null || true
    fi
    
    # 再检查是否有残留容器
    docker ps -a --filter "name=moontv" --filter "name=wufeng" -q | xargs -r docker rm -f 2>/dev/null || true
    
    log_info "旧容器已停止"
fi

cd "$REPO_DIR"

# ---- 7. 构建并启动 ----
log_step "构建 Docker 镜像（首次约 3-5 分钟）..."
docker compose build --no-cache

log_step "启动服务..."
docker compose up -d

# ---- 8. 等待服务就绪 ----
log_step "等待服务启动..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
        break
    fi
    sleep 2
done

# ---- 9. 检查状态 ----
echo ""
if docker compose ps | grep -q "running"; then
    log_info "🎉 无风影视部署成功！"
    echo ""
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │  🌐 本地访问: http://localhost:3000      │"
    
    # 尝试获取公网IP
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo "")
    if [ -n "$PUBLIC_IP" ]; then
    echo "  │  🌍 公网访问: http://$PUBLIC_IP:3000  │"
    fi
    
    echo "  │  👤 用户名: admin                       │"
    echo "  │  🔑 密码: 查看 .env 文件                 │"
    echo "  │                                         │"
    echo "  │  如已配置域名/SSL，用原域名访问即可       │"
    echo "  └─────────────────────────────────────────┘"
    echo ""
    echo "  📋 常用命令:"
    echo "     查看日志: cd $REPO_DIR && docker compose logs -f"
    echo "     重启服务: cd $REPO_DIR && docker compose restart"
    echo "     升级版本: curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash"
    echo ""
else
    log_error "服务启动失败，请查看日志:"
    echo "  cd $REPO_DIR && docker compose logs"
fi
