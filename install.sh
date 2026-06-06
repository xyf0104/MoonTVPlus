#!/bin/bash
# 无风影视 一键安装
set -e
mkdir -p /opt/moontv && cd /opt/moontv
# 下载 docker-compose.yml
curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/docker-compose.yml -o docker-compose.yml
echo "========== 无风影视 配置 =========="
read -p "请输入用户名: " TV_USERNAME < /dev/tty
while [ -z "$TV_USERNAME" ]; do
    read -p "用户名不能为空，请重新输入: " TV_USERNAME < /dev/tty
done
read -s -p "请输入密码: " TV_PASSWORD < /dev/tty
echo
while [ -z "$TV_PASSWORD" ]; do
    read -s -p "密码不能为空，请重新输入: " TV_PASSWORD < /dev/tty
    echo
done
# 写入 .env 文件
cat > .env << EOF
TV_USERNAME=${TV_USERNAME}
TV_PASSWORD=${TV_PASSWORD}
EOF
chmod 600 .env

docker compose pull && docker compose up -d
echo "✅ 安装完成！访问 http://$(curl -s ifconfig.me):3000"
