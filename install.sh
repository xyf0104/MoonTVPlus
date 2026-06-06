#!/bin/bash
# ============================================================
#  无风影视 MoonTVPlus 一键安装/更新脚本
#  用法: curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/install.sh | bash
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/moontv"
COMPOSE_URL="https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/docker-compose.yml"

# 打印 Logo
print_logo() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║                                      ║"
    echo "  ║        🌙 无风影视 MoonTVPlus        ║"
    echo "  ║                                      ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检测并安装 Docker
check_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}✓${NC} Docker 已安装: $(docker --version | awk '{print $3}' | tr -d ',')"
    else
        echo -e "${YELLOW}⏳ 正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker && systemctl start docker
        echo -e "${GREEN}✓${NC} Docker 安装完成"
    fi

    if docker compose version &>/dev/null; then
        echo -e "${GREEN}✓${NC} Docker Compose 已就绪"
    else
        echo -e "${RED}✗ Docker Compose 不可用，请升级 Docker${NC}"
        exit 1
    fi
}

# 交互式配置
interactive_setup() {
    echo ""
    echo -e "${BOLD}========== 基础配置 ==========${NC}"
    echo ""

    # 用户名
    local default_user="admin"
    read -p "$(echo -e "${CYAN}请输入用户名${NC} [${default_user}]: ")" TV_USERNAME </dev/tty
    TV_USERNAME=${TV_USERNAME:-$default_user}

    # 密码
    while true; do
        read -s -p "$(echo -e "${CYAN}请输入密码${NC}: ")" TV_PASSWORD </dev/tty
        echo ""
        if [ -z "$TV_PASSWORD" ]; then
            echo -e "${RED}密码不能为空${NC}"
            continue
        fi
        read -s -p "$(echo -e "${CYAN}确认密码${NC}: ")" TV_PASSWORD_CONFIRM </dev/tty
        echo ""
        if [ "$TV_PASSWORD" != "$TV_PASSWORD_CONFIRM" ]; then
            echo -e "${RED}两次密码不一致，请重新输入${NC}"
            continue
        fi
        break
    done

    # 端口
    local default_port="3000"
    read -p "$(echo -e "${CYAN}请输入访问端口${NC} [${default_port}]: ")" TV_PORT </dev/tty
    TV_PORT=${TV_PORT:-$default_port}

    # 确认
    echo ""
    echo -e "${BOLD}========== 配置确认 ==========${NC}"
    echo -e "  用户名: ${GREEN}${TV_USERNAME}${NC}"
    echo -e "  密  码: ${GREEN}******${NC}"
    echo -e "  端  口: ${GREEN}${TV_PORT}${NC}"
    echo -e "  目  录: ${GREEN}${INSTALL_DIR}${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}确认安装? (Y/n)${NC}: ")" CONFIRM </dev/tty
    CONFIRM=${CONFIRM:-Y}
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${RED}已取消安装${NC}"
        exit 0
    fi
}

# 生成配置文件
generate_config() {
    mkdir -p "$INSTALL_DIR"

    # 生成 .env
    cat > "${INSTALL_DIR}/.env" << EOF
TV_USERNAME=${TV_USERNAME}
TV_PASSWORD=${TV_PASSWORD}
TV_PORT=${TV_PORT}
EOF
    chmod 600 "${INSTALL_DIR}/.env"

    # 下载 docker-compose.yml
    curl -sSL "$COMPOSE_URL" -o "${INSTALL_DIR}/docker-compose.yml"
}

# 启动服务
start_services() {
    echo ""
    echo -e "${YELLOW}⏳ 正在拉取镜像并启动服务...${NC}"
    cd "$INSTALL_DIR"
    docker compose pull
    docker compose up -d
    echo ""

    # 获取公网 IP
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || curl -s --connect-timeout 3 ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")

    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       ✅ 安装完成！                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  访问地址: ${BOLD}http://${PUBLIC_IP}:${TV_PORT}${NC}"
    echo -e "${GREEN}║${NC}  用户名:   ${BOLD}${TV_USERNAME}${NC}"
    echo -e "${GREEN}║${NC}  安装目录: ${BOLD}${INSTALL_DIR}${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  更新: ${CYAN}cd ${INSTALL_DIR} && docker compose pull && docker compose up -d${NC}"
    echo -e "${GREEN}║${NC}  卸载: ${CYAN}cd ${INSTALL_DIR} && docker compose down -v${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
}

# 更新模式
update_services() {
    echo -e "${YELLOW}⏳ 正在更新...${NC}"
    cd "$INSTALL_DIR"
    docker compose pull
    docker compose up -d
    docker image prune -af &>/dev/null || true
    echo -e "${GREEN}✅ 更新完成！${NC}"
}

# 主流程
main() {
    print_logo

    # 检测是否已安装
    if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
        echo -e "${YELLOW}检测到已有安装 (${INSTALL_DIR})${NC}"
        echo ""
        echo -e "  ${BOLD}1)${NC} 更新到最新版本"
        echo -e "  ${BOLD}2)${NC} 重新配置并安装"
        echo -e "  ${BOLD}3)${NC} 卸载"
        echo -e "  ${BOLD}0)${NC} 退出"
        echo ""
        read -p "$(echo -e "${CYAN}请选择操作${NC} [1]: ")" CHOICE </dev/tty
        CHOICE=${CHOICE:-1}

        case "$CHOICE" in
            1)
                check_docker
                update_services
                ;;
            2)
                check_docker
                cd "$INSTALL_DIR" && docker compose down 2>/dev/null || true
                interactive_setup
                generate_config
                start_services
                ;;
            3)
                read -p "$(echo -e "${RED}确认卸载？数据将被清除 (y/N)${NC}: ")" DEL_CONFIRM </dev/tty
                if [[ "$DEL_CONFIRM" =~ ^[Yy]$ ]]; then
                    cd "$INSTALL_DIR" && docker compose down -v 2>/dev/null || true
                    rm -rf "$INSTALL_DIR"
                    echo -e "${GREEN}✅ 已卸载${NC}"
                else
                    echo "已取消"
                fi
                ;;
            0)
                echo "退出"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                exit 1
                ;;
        esac
    else
        # 全新安装
        check_docker
        interactive_setup
        generate_config
        start_services
    fi
}

main
