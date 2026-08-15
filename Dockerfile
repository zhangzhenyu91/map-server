# 方案 B：基于官方最新 omservice RPM 自建镜像
# 参考社区项目 https://github.com/Jetcser/omservice-docker 的 Dockerfile
# 官方说明：omservice Linux 版仅支持 CentOS 6/7；CentOS7 容器有 systemd 问题，
# 故沿用社区方案使用 CentOS 6.10 + initscripts(service 脚本) 运行。
FROM centos:6.10

# 换用清华大学 centos-vault 6.10 软件仓库（CentOS 6 官方源已下线）
RUN sed -e "s|^mirrorlist=|#mirrorlist=|g" \
        -e "s|^#baseurl=http://mirror.centos.org/centos/\$releasever|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-vault/6.10|g" \
        -e "s|^#baseurl=http://mirror.centos.org/\$contentdir/\$releasever|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-vault/6.10|g" \
        -i.bak /etc/yum.repos.d/CentOS-*.repo \
    && yum makecache \
    && yum install -y initscripts mysql-server \
    # 安装官方最新版奥维企业服务器（也可固定版本号，如 omservice-3.3.3-2.x86_64.rpm）
    && rpm -ivh https://download.ovital.com/pub/omservice-latest.x86_64.rpm \
    && yum clean all

# 官方要求：my.cnf 增加 max_long_data_size=268435456（否则单文件存储不能超过 1M）
RUN grep -q "max_long_data_size=268435456" /etc/my.cnf \
    || sed -i '/\[mysqld\]/a max_long_data_size=268435456' /etc/my.cnf

# 容器启动脚本：起 MySQL -> 首次初始化奥维数据库 -> 起 omservice -> 保持前台
RUN printf '#!/bin/sh\n\
service mysqld start\n\
chkconfig mysqld on\n\
if [ ! -d /var/lib/mysql/ovsrv ]; then echo -e "\\n" | /usr/local/bin/initomservice.sh; fi\n\
service omservice start\n\
chkconfig omservice on\n\
tail -f /dev/null\n' > /opt/omservice-start.sh \
    && chmod +x /opt/omservice-start.sh

EXPOSE 1616
CMD ["/opt/omservice-start.sh"]
