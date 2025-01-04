#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}此脚本必须以root权限运行${NC}"
   exit 1
fi

# 函数：获取目录或文件大小
get_size() {
    du -sh "$1" 2>/dev/null | cut -f1
}

# 函数：计算清理前后的差异
calculate_freed_space() {
    local before=$1
    local after=$2
    local path=$3
    
    before_bytes=$(numfmt --from=iec "$before")
    after_bytes=$(numfmt --from=iec "$after")
    freed_bytes=$((before_bytes - after_bytes))
    freed_human=$(numfmt --to=iec "$freed_bytes")
    
    echo -e "${GREEN}$path 释放了: $freed_human${NC}"
}

# 函数：安全清理目录
safe_clean_dir() {
    local dir=$1
    local exclude=$2
    if [ -d "$dir" ]; then
        before_size=$(get_size "$dir")
        if [ -n "$exclude" ]; then
            find "$dir" -type f ! -name "$exclude" -delete 2>/dev/null
        else
            find "$dir" -type f -delete 2>/dev/null
        fi
        after_size=$(get_size "$dir")
        calculate_freed_space "$before_size" "$after_size" "$dir"
    fi
}

echo "开始系统清理..."
echo "清理时间: $(date)"

# 记录总体清理前的可用空间
total_before=$(df -h / | awk '/\// {print $4}')

# 1. 清理系统缓存（优化后的方案）
echo "清理系统缓存..."
# 只清理pagecache，不清理dentries和inodes，避免影响系统性能
sync
echo 1 > /proc/sys/vm/drop_caches

# 2. 清理软件包相关（扩展）
echo "清理软件包相关..."
before_size=$(get_size /var/cache/yum)
# 清理YUM缓存
yum clean all
# 清理旧版本软件包
package-cleanup --oldkernels --count=2 -y
# 清理孤立包
package-cleanup --leaves -y
# 清理重复包
package-cleanup --dupes -y
# 清理依赖性问题
yum autoremove -y
after_size=$(get_size /var/cache/yum)
calculate_freed_space "$before_size" "$after_size" "软件包缓存"

# 3. 清理系统日志（扩展）
echo "清理系统日志..."
before_size=$(get_size /var/log)

# 清理系统轮转日志
echo "清理系统轮转日志..."
find /var/log -type f -name "messages-*" -mtime +3 -delete
find /var/log -type f -name "secure-*" -mtime +3 -delete
find /var/log -type f -name "maillog-*" -mtime +3 -delete
find /var/log -type f -name "spooler-*" -mtime +3 -delete
find /var/log -type f -name "boot.log-*" -mtime +3 -delete
find /var/log -type f -name "cron-*" -mtime +3 -delete
find /var/log -type f -name "yum.log-*" -mtime +3 -delete
find /var/log -type f -name "dmesg.old" -mtime +3 -delete

# 压缩旧日志
find /var/log -type f -name "*.log" -mtime +3 -exec gzip {} \;

# 删除超过10天的压缩日志
find /var/log -type f -name "*.gz" -mtime +3 -delete
# 清理journal日志
journalctl --vacuum-size=100M
# 清理audit日志
find /var/log/audit/ -type f -name "audit.log.*" -mtime +7 -delete
after_size=$(get_size /var/log)
calculate_freed_space "$before_size" "$after_size" "系统日志"

# 4. 清理用户相关（扩展）
echo "清理用户相关..."
# 清理所有用户的临时文件和缓存
for user_home in /home/* /root; do
    if [ -d "$user_home" ]; then
        # 清理浏览器缓存
        safe_clean_dir "$user_home/.cache/google-chrome"
        safe_clean_dir "$user_home/.cache/mozilla"
        # 清理缩略图缓存
        safe_clean_dir "$user_home/.cache/thumbnails"
        # 清理垃圾箱
        safe_clean_dir "$user_home/.local/share/Trash"
        # 清理下载目录超过10天的文件
        find "$user_home/Downloads" -type f -mtime +10 -delete 2>/dev/null
    fi
done

# 5. 清理系统临时文件（扩展）
echo "清理系统临时文件..."
before_size=$(get_size /var/tmp)
# 清理超过7天的临时文件
find /tmp -type f -atime +7 -delete
find /var/tmp -type f -atime +7 -delete
# 清理会话文件
find /var/lib/php/session -type f -delete
# 清理系统崩溃转储
rm -rf /var/crash/*
after_size=$(get_size /var/tmp)
calculate_freed_space "$before_size" "$after_size" "临时文件"

# 6. 清理邮件系统（如果存在）
if systemctl is-active --quiet postfix; then
    echo "清理邮件系统..."
    before_size=$(get_size /var/spool/postfix)
    postsuper -d ALL
    after_size=$(get_size /var/spool/postfix)
    calculate_freed_space "$before_size" "$after_size" "邮件系统"
fi

# 7. 清理备份文件
echo "清理旧备份文件..."
# 清理超过10天的备份
find / -type f \( -name "*.bak" -o -name "*.old" -o -name "*.backup" \) -mtime +10 -delete 2>/dev/null

# 8. 清理Linux内核相关
echo "清理内核相关..."
before_size=$(get_size /boot)
# 保留最新的两个内核
package-cleanup --oldkernels --count=2 -y
# 清理旧的initramfs镜像
find /boot -name "initramfs-*" -type f -not -name "$(uname -r)" -delete
after_size=$(get_size /boot)
calculate_freed_space "$before_size" "$after_size" "内核相关"

# 9. 清理systemd日志（优化）
echo "清理systemd日志..."
before_size=$(get_size /var/log/journal)
# 只保留最近3天的日志，最大大小100M
journalctl --vacuum-time=3d --vacuum-size=100M
after_size=$(get_size /var/log/journal)
calculate_freed_space "$before_size" "$after_size" "Systemd日志"

# 10. 清理软件源缓存
echo "清理软件源缓存..."
before_size=$(get_size /var/cache/yum)
# 清理已下载的软件包
find /var/cache/yum -type f -name "*.rpm" -delete
# 清理软件源元数据
yum clean metadata
after_size=$(get_size /var/cache/yum)
calculate_freed_space "$before_size" "$after_size" "软件源缓存"

# 11. 清理系统快照（如果使用LVM）
if command -v lvs &> /dev/null; then
    echo "清理LVM快照..."
    lvs | grep "snap" | awk '{print $1}' | while read snap; do
        lvremove -f $snap
    done
fi

# 12. 清理vi备份文件
echo "清理vi备份文件..."
find / -type f -name ".*.sw[a-p]" -delete 2>/dev/null
find / -type f -name ".*~" -delete 2>/dev/null
find / -type f -name ".*\.un~" -delete 2>/dev/null

# 13. 清理系统core dump
echo "清理系统core dump..."
echo "kernel.core_pattern=|/bin/false" > /etc/sysctl.d/disable-coredump.conf
sysctl -p /etc/sysctl.d/disable-coredump.conf

# 显示系统空间使用情况分析
echo -e "\n=== 系统空间使用情况分析 ==="

# 显示最大的目录（前20个）
echo -e "\n最大的20个目录:"
du -hx --max-depth=3 / 2>/dev/null | sort -rh | head -n 20

# 显示大文件（>100MB）
echo -e "\n大文件列表（>100MB）:"
find / -xdev -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5,5rh

# 显示老旧文件（超过30天未访问）
echo -e "\n老旧文件（超过30天未访问）:"
find / -xdev -type f -atime +30 -size +10M -exec ls -lh {} \; 2>/dev/null | sort -k5,5rh

# 显示文件系统使用情况
echo -e "\n文件系统使用情况:"
df -h | grep -v "tmpfs"

# 显示inode使用情况
echo -e "\ninode使用情况:"
df -i | grep -v "tmpfs"

# 建议的清理操作
echo -e "\n=== 建议的清理操作 ==="
echo "1. 检查并清理以上列出的大文件"
echo "2. 考虑压缩或归档超过30天未访问的文件"
echo "3. 检查是否需要卸载大型未使用的软件包"
echo "4. 考虑使用logrotate配置更激进的日志轮转策略"
echo "5. 检查是否有异常增长的日志文件"
echo "6. 考虑迁移不常用的大文件到备份存储"

# 清理完成提示
echo -e "\n清理完成!"
echo "清理前可用空间: $total_before"
echo "清理后可用空间: $(df -h / | awk '/\// {print $4}')"
