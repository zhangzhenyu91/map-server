# 方案 B：基于官方 omservice RPM 自建镜像
# 注意：当前官方 RPM（omservice-latest ≈ 3.3.3-3）需要 glibc 2.17 / GLIBCXX_3.4.14，
# CentOS 6.10 只有 glibc 2.12，装不上（社区镜像 oakdb/omservice 是当年 el6 时代构建的）。
# 因此自建镜像必须用 CentOS 7。
FROM centos:7

# CentOS 7 已 EOL，官方 mirror.centos.org 已下线，换阿里云 centos-vault 7.9.2009 源
# （centos:7 官方镜像的 repo 文件里写的是 altarch 路径，两种都替换；
#   清华源 centos-vault 对部分 IP 段返回 403，故默认用阿里云，备选清华
#   https://mirrors.tuna.tsinghua.edu.cn/centos-vault/7.9.2009）
RUN sed -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=http://mirror.centos.org/centos/$releasever|baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009|g' \
        -e 's|^#baseurl=http://mirror.centos.org/altarch/$releasever|baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009|g' \
        -e 's|^#baseurl=http://mirror.centos.org/$contentdir/$releasever|baseurl=https://mirrors.aliyun.com/centos-vault/7.9.2009|g' \
        -i.bak /etc/yum.repos.d/CentOS-*.repo \
    && yum makecache \
    # EPEL7 归档源（提供 proxychains-ng：omservice 不认 HTTP_PROXY 环境变量，用它强制走代理）
    && printf '[epel]\nname=EPEL7-archive\nbaseurl=https://mirrors.aliyun.com/epel-archive/7/x86_64/\nenabled=1\ngpgcheck=0\n' \
        > /etc/yum.repos.d/epel.repo \
    # CentOS7 官方配套数据库为 MariaDB
    && yum install -y mariadb-server proxychains-ng \
    # 官方文档推荐地址（当前指向 3.3.3-3）；如需固定/更新版本可改为如：
    # https://download.ovital.com/pub/omservice-4.0.3-2.x86_64.rpm
    && rpm -ivh https://download.ovital.com/pub/omservice-latest.x86_64.rpm \
    && yum clean all

# initomservice.sh 对 MariaDB 5.5 强制检查 max_allowed_packet（否则单文件存储不能超过 1M）
RUN grep -q "max_allowed_packet=256M" /etc/my.cnf \
    || sed -i '/\[mysqld\]/a max_allowed_packet=256M' /etc/my.cnf

# 容器内没有可用的 systemd，绕过它：
# - MariaDB 用 mysqld_safe 直接拉起
# - omservice 二进制自身会 daemonize（官方 systemd 单元就是直接 ExecStart 它）
COPY entrypoint.sh /opt/omservice-start.sh
RUN chmod +x /opt/omservice-start.sh

EXPOSE 1616
CMD ["/opt/omservice-start.sh"]
