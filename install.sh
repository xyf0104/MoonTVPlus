#!/bin/bash
# 无风影视 一键安装
set -e
mkdir -p /opt/moontv && cd /opt/moontv
curl -sSL https://raw.githubusercontent.com/xyf0104/MoonTVPlus/main/docker-compose.yml -o docker-compose.yml
docker compose pull && docker compose up -d
echo "✅ 安装完成！访问 http://$(curl -s ifconfig.me):3000"
