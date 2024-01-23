#!/bin/bash
 
# 记录清理前的可用空间
before=$(df -h / | awk '/\// {print $4}')
 
# 清理yum缓存
yum clean all
 
# 清理旧的日志文件
find /var/log -type f -name "*.log" -exec truncate --size 0 {} \;
 
# 清理回收站
echo "Emptying trash..."
rm -rf /root/.local/share/Trash/*/** &> /dev/null
 
# 清理历史命令记录
history -c
history -w
 
# 清理临时文件
rm -rf /tmp/*
rm -rf /var/tmp/*
 
# 清理旧的系统备份
rm -rf /var/backups/*
 
# 清理不再使用的软件包和依赖项
yum autoremove -y
 
# 清理旧的内核
package-cleanup --oldkernels --count=1 -y
 
# 清理缓存文件
find /var/cache -type f -exec rm -rf {} \;
 
# 清理用户缓存
for user in $(ls /home); do
  rm -rf /home/$user/.cache/*
done
 
# 清理邮件日志
find /var/mail -type f -exec truncate --size 0 {} \;
 
# 清理core文件
find / -name "core" -delete
 
# 清理旧的会话文件
find /var/lib/php/session -type f -delete
 
# 清理系统邮件队列
service postfix stop
rm -rf /var/spool/postfix/*
service postfix start
 
# 清理久未使用的软件包缓存
dnf clean packages -y
 
# 清理系统崩溃日志
rm -rf /var/crash/*
 
# 清理journalctl日志
journalctl --rotate
journalctl --vacuum-time=1d
 
# 清理系统缓存
sync && echo 3 > /proc/sys/vm/drop_caches
 
# 清理历史命令记录
# history -c
# history -w
 
# 清理 Docker 容器日志文件
docker rm -v $(docker ps -a -q)
rm -rf /var/lib/docker/containers/*/*-json.log
 
# 清理 Docker 镜像缓存
docker image prune -a --force
 
# 清理 Docker 无用的数据卷
docker volume prune --force
 
# 清理旧的 Docker 镜像
docker rmi $(docker images -f "dangling=true" -q)
 
# 计算清理了多少大小的文件
cleared=$(df -h / | awk '/\// {print $4}' | awk -v before="$before" '{print before - $1}')
 
# 记录清理后的可用空间
after=$(df -h / | awk '/\// {print $4}')
 
echo "清理前可用空间: $before"
echo "清理后可用空间: $after"
 
echo "磁盘清理完成。"