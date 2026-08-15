#!/bin/sh
# 奥维企业服务器容器入口：单容器拉起 MariaDB + omservice
set -e

DATADIR=/var/lib/mysql
SOCK=$DATADIR/mysql.sock

# 1. 数据卷首次为空时，初始化 MariaDB 系统库
if [ ! -d "$DATADIR/mysql" ]; then
    echo "[entrypoint] 初始化 MariaDB 数据目录 ..."
    mysql_install_db --user=mysql --datadir="$DATADIR" >/dev/null
fi

# 2. 启动 MariaDB（容器内无 systemd，直接 mysqld_safe）
echo "[entrypoint] 启动 MariaDB ..."
mysqld_safe --user=mysql --datadir="$DATADIR" &

# 3. 等待 MySQL 就绪（最多 60 秒）。
#    初始化后 root 密码会被改为 ovital，所以两种凭据都试，保证容器重启后也能正确等待。
echo "[entrypoint] 等待 MariaDB 就绪 ..."
for i in $(seq 1 60); do
    if [ -S "$SOCK" ] && \
       { mysql -uroot -e 'select 1' >/dev/null 2>&1 || \
         mysql -uroot -povital -e 'select 1' >/dev/null 2>&1; }; then
        break
    fi
    if [ "$i" = 60 ]; then
        echo "[entrypoint] MariaDB 启动超时" >&2
        exit 1
    fi
    sleep 1
done

# 4. 首次运行初始化奥维数据库（创建 ovsrv 库，并把 root 密码设为 ovital，与 omservice.conf 默认一致）
if [ ! -d "$DATADIR/ovsrv" ]; then
    echo "[entrypoint] 初始化奥维数据库 ovsrv ..."
    echo | /usr/local/bin/initomservice.sh
fi

# 5. 启动 omservice（二进制自身 fork 到后台，参数为配置文件路径）
#    omservice 不认 HTTP_PROXY 环境变量，用 proxychains(LD_PRELOAD) 强制其走宿主机代理。
#    PROXY_PORT 默认 7890（宿主机 Clash 端口）；设 PROXY_PORT=0 可停用（如改用透明代理/TUN）。
PROXY_PORT=${PROXY_PORT:-7890}
if [ "$PROXY_PORT" != "0" ]; then
    # 宿主机地址：优先 host.docker.internal（compose 已注入 host-gateway），兜底取默认网关 IP。
    # 注意 proxychains 的 ProxyList 只接受数字 IP，所以先 getent 解析。
    PROXY_IP=$(getent hosts host.docker.internal | awk '{print $1}' | head -1)
    if [ -z "$PROXY_IP" ]; then
        GWHEX=$(awk '$2=="00000000"{print $3}' /proc/net/route | head -1)
        PROXY_IP=$(printf "%d.%d.%d.%d" 0x${GWHEX:6:2} 0x${GWHEX:4:2} 0x${GWHEX:2:2} 0x${GWHEX:0:2})
    fi
    # localnet 必须排除内网/本机，否则 omservice 连本地 MySQL(127.0.0.1:3306) 也会被塞进代理
    cat > /etc/proxychains.conf <<EOF
strict_chain
proxy_dns
quiet_mode
localnet 127.0.0.0/255.0.0.0
localnet 10.0.0.0/255.0.0.0
localnet 172.16.0.0/255.240.0.0
localnet 192.168.0.0/255.255.0.0
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
http $PROXY_IP $PROXY_PORT
EOF
    echo "[entrypoint] 启动 omservice（经 proxychains -> http://$PROXY_IP:$PROXY_PORT）..."
    proxychains4 /usr/local/bin/omservice /etc/omservice.conf
else
    echo "[entrypoint] 启动 omservice（直连，不使用代理）..."
    /usr/local/bin/omservice /etc/omservice.conf
fi

# 6. 等服务日志文件出现后再前台跟随（保持容器存活；
#    直接 tail -F 不存在的文件，GNU tail 可能报 "giving up on this name" 并退出，导致容器重启循环）
echo "[entrypoint] omservice 已启动，等待服务日志 ..."
while [ ! -f /var/log/OMapService.log ]; do
    sleep 2
done
exec tail -F /var/log/OMapService.log
