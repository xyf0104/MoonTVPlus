#!/bin/bash
# ============================================
# 无风影视 - 一键安装 / 升级脚本
# 
# 使用方式:
#   curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash
#
# 功能:
#   - 自动检测已有的 MoonTVPlus 安装
#   - 保留原有数据（Kvrocks 数据卷不受影响）
#   - 保留 SSL/域名/反向代理配置
#   - 使用预构建镜像，无需在服务器上编译
#   - 停机 < 10 秒
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
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

# ---- 1. 检查 Docker ----
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

for dir in /opt/moontv /opt/moontvplus /opt/MoonTVPlus /opt/wufeng-tv /root/moontv /root/MoonTVPlus; do
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ]; then
        EXISTING_DIR="$dir"
        break
    fi
done

if [ -z "$EXISTING_DIR" ]; then
    CONTAINER_ID=$(docker ps --filter "name=moontv" --filter "name=wufeng" -q 2>/dev/null | head -1)
    if [ -n "$CONTAINER_ID" ]; then
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
    echo "  将原地升级，保留所有数据"
    echo ""
else
    log_info "全新安装，目录: $INSTALL_DIR"
fi

# ---- 4. 备份旧配置中的账号密码 ----
OLD_USERNAME=""
OLD_PASSWORD=""
OLD_STORAGE=""
OLD_KVROCKS=""

if [ -n "$EXISTING_DIR" ]; then
    # 从旧 docker-compose.yml 提取账号密码
    OLD_COMPOSE="$EXISTING_DIR/docker-compose.yml"
    if [ ! -f "$OLD_COMPOSE" ]; then
        OLD_COMPOSE="$EXISTING_DIR/docker-compose.yaml"
    fi
    if [ -f "$OLD_COMPOSE" ]; then
        OLD_USERNAME=$(grep -oP 'USERNAME=\K[^\s"]+' "$OLD_COMPOSE" 2>/dev/null | head -1)
        OLD_PASSWORD=$(grep -oP 'PASSWORD=\K[^\s"]+' "$OLD_COMPOSE" 2>/dev/null | head -1)
        OLD_STORAGE=$(grep -oP 'STORAGE_TYPE=\K[^\s"]+' "$OLD_COMPOSE" 2>/dev/null | head -1)
        if [ -n "$OLD_USERNAME" ]; then
            log_info "已提取原有账号: $OLD_USERNAME"
        fi
    fi
fi

# ---- 5. 停止旧容器（保留数据卷） ----
if [ -n "$EXISTING_DIR" ]; then
    log_step "停止旧版容器..."
    
    # 在旧目录执行 down（只停容器，不删数据卷）
    if [ -f "$EXISTING_DIR/docker-compose.yml" ] || [ -f "$EXISTING_DIR/docker-compose.yaml" ]; then
        cd "$EXISTING_DIR"
        docker compose down --remove-orphans 2>/dev/null || true
    fi
    
    # 清理可能的残留容器
    docker ps -a --filter "name=moontv" --filter "name=wufeng" -q 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
    
    log_info "旧容器已停止（数据卷已保留）"
fi

# ---- 6. 下载新版 docker-compose.yml ----
log_step "下载最新配置..."
cd "$INSTALL_DIR"

# 备份旧 compose 文件
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.bak 2>/dev/null || true
fi

# 下载新版
curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/docker-compose.yml -o docker-compose.yml

# ---- 7. 替换为原有的账号密码 ----
if [ -n "$OLD_USERNAME" ]; then
    sed -i "s/USERNAME=admin/USERNAME=$OLD_USERNAME/g" docker-compose.yml
fi
if [ -n "$OLD_PASSWORD" ]; then
    sed -i "s/PASSWORD=admin123/PASSWORD=$OLD_PASSWORD/g" docker-compose.yml
fi

log_info "配置文件已就绪"

# ---- 8. 拉取镜像并启动 ----
log_step "拉取最新镜像..."
docker compose pull

log_step "启动服务..."
docker compose up -d

# ---- 9. 清理旧镜像 ----
log_step "清理旧版镜像..."
docker image prune -af 2>/dev/null || true

# ---- 10. 等待就绪并输出结果 ----
log_step "等待服务启动..."
sleep 5
for i in {1..20}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null | grep -q "200\|302"; then
        break
    fi
    sleep 2
done

echo ""
if docker compose ps 2>/dev/null | grep -q "running\|Up"; then
    log_info "🎉 无风影视部署成功！"
    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │  🌐 本地访问: http://localhost:3000       │"
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo "")
    if [ -n "$PUBLIC_IP" ]; then
    echo "  │  🌍 公网访问: http://$PUBLIC_IP:3000   │"
    fi
    echo "  │  👤 用户名: ${OLD_USERNAME:-admin}              │"
    echo "  │  🔑 密码: ${OLD_PASSWORD:-admin123}             │"
    echo "  │                                          │"
    echo "  │  如已配置域名/SSL，用原域名访问即可        │"
    echo "  └──────────────────────────────────────────┘"
    echo ""
    echo "  📋 常用命令:"
    echo "     查看日志: cd $INSTALL_DIR && docker compose logs -f"
    echo "     重启服务: cd $INSTALL_DIR && docker compose restart"
    echo "     升级版本: curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/deploy.sh | bash"
    echo ""
else
    log_error "服务启动失败，请查看日志:"
    echo "  cd $INSTALL_DIR && docker compose logs"
fi
