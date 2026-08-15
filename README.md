# 奥维互动地图企业服务器 Docker 部署 + 谷歌卫星图服务

通过 Docker 在云服务器上部署奥维企业服务器（omservice + MySQL 单容器），并利用企业服务器的**「本地代理」地图服务**，让客户端经服务器（走服务器上的代理）在线加载谷歌卫星图——客户端自身无需翻墙。

## 架构

```
奥维客户端(手机/PC) ──1616──> 云服务器 Docker 容器(omservice + MySQL)
                                     │
管理控制台(Windows)  ──1616──>       │ 本地代理：服务器代客户端请求瓦片
                                     ▼
                              宿主机代理(可访问谷歌) ──> mt*.google.com 瓦片
```

## 前置条件

- 云服务器：建议 ≥ 2 核 4G 内存、50G 硬盘、固定公网 IP（官方推荐 8 核 32G / 10M 带宽）
- 服务器已装 Docker 与 docker compose（未装：参考 https://docs.docker.com/engine/install/ ）
- 服务器上已部署可访问谷歌的 HTTP 端口代理（Clash 类，端口 7890，配置见「四、代理打通」）
- 一台 Windows 电脑：管理控制台（OMapSConsole）只有 Windows 版，[下载地址](https://www.ovital.com/enterprise/)
- **公网部署需在奥维官方审核**：注册企业账户 → 单位审核 → 公网 IP/域名审核（仅内网使用不需要）。审核入口见奥维官网企业服务页面

## 一、部署（方案 A：社区现成镜像，推荐）

```bash
# 1. 把本目录上传到云服务器，进入目录
cd omservice-deploy   # 即本目录

# 2. 启动（首次启动会自动初始化 MySQL 和奥维数据库，约 1~2 分钟）
docker compose up -d

# 3. 查看状态与日志
docker compose ps
docker logs -f omservice

# 4. 获取管理控制台登录密码（默认为 123456，登录后请立即修改）
docker exec omservice cat /etc/omservice.conf | grep -E "LoginPwd|ListenPort"
```

防火墙 / 安全组：在云服务商**安全组**放行 TCP **1616**；若系统开了 firewalld/iptables 同样放行。

> 需要长期固定配置文件时：先 `mkdir -p conf && docker cp omservice:/etc/omservice.conf conf/omservice.conf`，
> 再取消 `docker-compose.yml` 中 `omservice.conf` 挂载行的注释，`docker compose up -d` 重建容器。

## 二、管理控制台连接

1. Windows 电脑安装管理控制台（OMapSConsole V3.0.0+）
2. 打开控制台 →【系统】→【连接企业服务器】，输入 `服务器公网IP : 1616` 和上面的密码
3. 登录后即可添加 VIP 用户、设置组织架构等（详见[官方帮助手册](https://www.gpsov.com/appdoc/index.php?id=47)）

## 三、配置谷歌卫星图（核心：本地代理）

版本要求：企业服务器 ≥ V3.1.0（本镜像 3.3.3 满足）、控制台 ≥ V3.0.0、客户端 ≥ V9.0.0。
官方流程文档：[如何在企业服务器配置自定义地图服务](https://www.ovital.com/137249-2/)。

### 1. 在奥维电脑端添加谷歌卫星图自定义地图

奥维电脑端【自定义地图】→【自定义地图管理】→【添加】（[官方添加方法](https://www.ovital.com/131425-2/)），常用参数：

| 参数 | 值 |
|---|---|
| 地图ID | 200~999 之间任意不冲突的值（系统分配即可） |
| 地图名称 | 谷歌卫星图 |
| 协议 | https |
| 最大级别 | 20 |
| 投影类型 | 墨卡托全球（谷歌影像为球面墨卡托；不要选"墨卡托中国"，否则会偏移） |
| 图片类型 | 影像地图 |
| 图片格式 | JPG |
| 图片大小 | 256 像素 |
| 主机名 | `mt{$serverpart}.google.com`（主机编号填 0 至 3），或固定 `mt0.google.com` |
| 端口号 | 默认（443） |
| URL | `/vt/lyrs=s&hl=zh-CN&gl=CN&x={$x}&y={$y}&z={$z}` |

- 卫星 + 路网混合图：把 URL 中 `lyrs=s` 改为 `lyrs=y`
- 添加后先在电脑端切到该图层，确认能显示（电脑端需能访问谷歌，或先跳过直接到服务器上验证）
- 谷歌可能调整瓦片接口，参数以实测为准：把拼好的完整 URL 贴到浏览器能返回图片即有效

### 2. 把自定义地图文件夹拷到服务器

添加后奥维根目录 `map/` 下会生成以**地图ID**命名的文件夹。上传到宿主机的 `./data/map/`（即容器内 `/root/map`）：

```bash
# 在本地（奥维电脑端所在机器）执行，把 <地图ID> 文件夹传上去
scp -r "map/<地图ID>" user@服务器IP:/路径/到/本目录/data/map/
```

### 3. 控制台启用地图服务并设为「本地代理」

管理控制台登录企业服务器 →【系统】→【设置地图服务】：

1. 勾选【启用地图服务】，地图数据路径填 `/root/map`，确定
2. 重新进入【设置地图服务】→【选择地图】，批量选中图层，右键 →【设置为本地代理】
   - **本地代理** = 服务器在线请求互联网地图瓦片再分发给客户端（谷歌流量走服务器，正是我们要的）
   - 本地库 = 服务器读取本地离线瓦片库（不适合本场景）
3. 保存

### 4. 客户端加载

- 电脑端：【企业】→【登录企业服务器】→ 勾选该地图 → 在【自定义地图】菜单切换浏览
- 手机端：登录企业服务器 →【自定义地图】勾选即可

## 四、代理打通（HTTP 端口代理 7890）

omservice 做「本地代理」时，由**服务器侧进程**请求谷歌瓦片，必须让它走上宿主机的 7890 代理。按顺序来：

### 1. 放开 Clash 的局域网访问

容器是通过宿主机内网 IP 访问 7890 的，Clash 必须监听 `0.0.0.0`：

```yaml
# Clash 配置
mixed-port: 7890
allow-lan: true
```

改完重启 Clash。宿主机上验证：`curl -x http://127.0.0.1:7890 -I https://mt0.google.com/vt/lyrs=s\&x=1\&y=1\&z=1` 能通。

### 2. 先试 HTTP_PROXY 环境变量（最简单）

取消 `docker-compose.yml` 中 `HTTP_PROXY/HTTPS_PROXY` 两行的注释（已用 `host.docker.internal:7890` 预置好），然后：

```bash
docker compose up -d   # 重建容器使环境变量生效
```

### 3. 验证（分两层，第二层才是关键）

```bash
# 第一层：容器出网 OK（curl 自己会读环境变量，通过不代表 omservice 走代理）
docker exec omservice curl -I "https://mt0.google.com/vt/lyrs=s&x=1&y=1&z=1"
```

- **第二层（决定性）**：客户端登录企业服务器、切到谷歌卫星图层加载时，**看 Clash 的日志/连接面板**：
  - 出现 `mt*.google.com` 连接记录 → omservice 走了代理，完成 ✅
  - 没有任何记录（且客户端瓦片加载失败）→ omservice 不读环境变量（C++ 服务常见），走第 4 条 ❌

### 4. 环境变量不生效：用 proxychains 强制代理

proxychains 通过 LD_PRELOAD 劫持网络连接，不依赖程序自身是否支持代理：

```bash
docker exec -it omservice bash

# 安装（CentOS6 EPEL；若 yum 找不到该包，需放入静态编译的 proxychains4 二进制）
yum install -y epel-release && yum install -y proxychains-ng

# 配置：指向宿主机 7890（自动取容器网关 IP，即宿主机）
GW=$(ip route | awk '/default/ {print $3}') && printf '[ProxyList]\nhttp %s 7890\n' "$GW" > /etc/proxychains.conf

# 用 proxychains 重启 omservice
service omservice stop
proxychains4 service omservice start
exit
```

再次执行第 3 步第二层的验证。注意：**容器重建后需重做**，要固化可基于方案 B 的 Dockerfile 把 proxychains 装进去、并改启动脚本为 `proxychains4 service omservice start`。

### 5. 一劳永逸：Clash 开 TUN 模式

如果 Clash 支持 TUN/增强模式，直接接管宿主机全局网络，所有容器流量自动走代理，以上 1~4 全部不用配。

### 自定义地图参数不受影响

无论走哪条路，第三节的自定义地图参数都不变（主机名仍是 `mt{$serverpart}.google.com`）——代理发生在网络层，不改动地图配置。

## 五、方案 B：自建最新版镜像（当前 compose 默认）

```bash
docker compose build
docker compose up -d
```

> 若在 Apple Silicon Mac 上本地构建（服务器是 x86_64），需指定平台：`docker build --platform linux/amd64 -t omservice .`；
> 直接在 x86_64 云服务器上 `docker compose build` 则不需要。

要点说明：

- **必须用 CentOS 7**：当前官方 RPM（`omservice-latest` ≈ 3.3.3-3）需要 glibc 2.17 / GLIBCXX_3.4.14，CentOS 6.10（glibc 2.12）装不上——社区镜像当年能装是因为那时的 RPM 还是 el6 构建，官方的 el6 包只出到 2.7.6（无地图服务）。
- CentOS 7 已 EOL，Dockerfile 里已把 yum 源换成阿里云 centos-vault 7.9.2009（centos:7 官方镜像的 repo 是 altarch 路径，sed 已覆盖；清华源对部分 IP 段 403，备选可换回 tuna）。
- **绕过 systemd**：容器里 systemctl 不可用，入口脚本 `entrypoint.sh` 直接 `mysqld_safe` 拉起 MariaDB、执行 `initomservice.sh` 初始化 ovsrv 库、然后启动 omservice 二进制（它自身会 daemonize）。数据库初始 root 密码被官方脚本设为 `ovital`，与 `omservice.conf` 默认值一致。
- 要固定版本（如 4.0.3-2），改 Dockerfile 里 RPM 的 URL 即可，版本列表见 https://download.ovital.com/pub/ 。

## 六、备份与恢复

```bash
chmod +x backup.sh && ./backup.sh          # 备份到 ./backup/<时间戳>/
```

恢复：新建 `./data/mysql` 为空目录启动容器，然后：

```bash
cat backup/<时间戳>/mysql-all.sql | docker exec -i omservice mysql -uroot
tar xzf backup/<时间戳>/map.tar.gz -C ./data/
docker restart omservice
```

## 七、常见问题

- **控制台连不上**：查安全组/防火墙 1616；`docker logs omservice` 看服务是否起来；`docker exec omservice netstat -tnlp | grep 1616`
- **忘记控制台密码**：`docker exec omservice cat /etc/omservice.conf | grep LoginPwd`
- **修改控制台密码**：`docker exec omservice sed -i 's/^LoginPwd=.*/LoginPwd="新密码"/' /etc/omservice.conf && docker restart omservice`。注意：若未把 conf 挂载到宿主机，重建容器后密码回退为默认 123456，建议完成「一、部署」末尾的 conf 挂载步骤
- **HTTP 反向代理（含 1Panel 网站反代）连不上**：1616 是奥维私有 TCP 协议，不是 HTTP，七层反代（proxy_pass）无法承载。改用：① DNS A 记录指向服务器 IP，客户端直接填 `域名:1616`；② 或四层 TCP 转发（如 `socat TCP-LISTEN:端口,fork TCP:127.0.0.1:1616`），均无 TLS
- **客户端看不到自定义地图**：客户端版本需 ≥ V9.0.0；确认控制台里图层已设为「本地代理」并保存
- **卫星图加载不出/全黑**：按「四、代理打通」第 3 步的两层验证排查；确认投影类型选了「墨卡托全球」
- **单文件不能超过 1M**：本镜像已按官方要求配置 `max_allowed_packet=256M`（MariaDB 5.5）；若改库配置需重启容器

## 参考

- [奥维企业服务器部署手册 V3.3.0](https://www.gpsov.com/appdoc/index.php?id=45)
- [CentOS 部署官方文档](https://www.ovital.com/129507-2/)
- [企业服务器配置自定义地图服务](https://www.ovital.com/137249-2/)
- [添加在线自定义地图](https://www.ovital.com/131425-2/)
- [社区 Docker 镜像项目 Jetcser/omservice-docker](https://github.com/Jetcser/omservice-docker)
