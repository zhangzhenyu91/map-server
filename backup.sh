#!/bin/bash
# 奥维企业服务器数据备份：MySQL 全库 + 自定义地图目录
# 用法：./backup.sh [备份输出目录前缀]   默认 ./backup
set -e

PREFIX=${1:-./backup}
BACKUP_DIR="$PREFIX/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "==> 导出 MySQL 数据库 ..."
docker exec omservice mysqldump -uroot --all-databases --single-transaction \
    > "$BACKUP_DIR/mysql-all.sql"

echo "==> 打包自定义地图目录 ./data/map ..."
tar czf "$BACKUP_DIR/map.tar.gz" -C ./data map 2>/dev/null || echo "    (map 目录为空，跳过)"

echo "==> 备份服务器配置 ..."
docker exec omservice cat /etc/omservice.conf > "$BACKUP_DIR/omservice.conf" 2>/dev/null || true

echo "备份完成: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
