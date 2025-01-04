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
    local size=$(du -sh "$1" 2>/dev/null | cut -f1)
    if [ -z "$size" ]; then
        echo "0B"
    else
        echo "$size"
    fi
}

# 函数：计算清理前后的差异
calculate_freed_space() {
    local before=$1
    local after=$2
    local path=$3
    
    # 确保输入不为空
    before=${before:-"0B"}
    after=${after:-"0B"}
    
    before_bytes=$(numfmt --from=iec "${before}" 2>/dev/null || echo 0)
    after_bytes=$(numfmt --from=iec "${after}" 2>/dev/null || echo 0)
    freed_bytes=$((before_bytes - after_bytes))
    freed_human=$(numfmt --to=iec "${freed_bytes}" 2>/dev/null || echo "0B")
    
    if [ "$freed_bytes" -gt 0 ]; then
        echo -e "${GREEN}$path 释放了: $freed_human${NC}"
    fi
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
# 宝塔面板备份目录
backup_dirs=(
    "/www/backup"              # 网站备份
    "/www/backup/database"     # 数据库备份
    "/www/backup/site"         # 网站备份
    "/www/backup/path"         # 目录备份
    "/www/backup/cloud"        # 云端备份
    "/www/server/panel/backup" # 面板备份
    "/www/server/panel/logs"   # 面板日志
    "/www/wwwlogs"            # 网站日志
    "/www/server/data"        # 数据库文件
)

for dir in "${backup_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "检查目录: $dir"
        before_size=$(get_size "$dir")
        # 清理备份文件
        find "$dir" -type f \( -name "*.bak" -o -name "*.old" -o -name "*.backup" -o -name "*.[0-9]" -o -name "*.tar" -o -name "*.tar.gz" -o -name "*.zip" -o -name "*.sql" -o -name "*.log" \) -mtime +10 -delete -print 2>/dev/null
        after_size=$(get_size "$dir")
        calculate_freed_space "$before_size" "$after_size" "$dir 备份文件"
    fi
done

# 清理网站备份（保留最近30天）
if [ -d "/www/backup/site" ]; then
    echo "清理网站备份..."
    before_size=$(get_size "/www/backup/site")
    find /www/backup/site -type f -mtime +30 -delete -print 2>/dev/null
    after_size=$(get_size "/www/backup/site")
    calculate_freed_space "$before_size" "$after_size" "网站备份"
fi

# 清理数据库备份（保留最近30天）
if [ -d "/www/backup/database" ]; then
    echo "清理数据库备份..."
    before_size=$(get_size "/www/backup/database")
    find /www/backup/database -type f -mtime +30 -delete -print 2>/dev/null
    after_size=$(get_size "/www/backup/database")
    calculate_freed_space "$before_size" "$after_size" "数据库备份"
fi

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
# 只保留最近1天的日志，最大大小50M
journalctl --vacuum-time=1d --vacuum-size=50M
# 强制清理所有日志
rm -rf /var/log/journal/*
after_size=$(get_size /var/log/journal)
calculate_freed_space "$before_size" "$after_size" "Systemd日志"

# 清理messages当前日志
echo "清理当前messages日志..."
if [ -f "/var/log/messages" ]; then
    truncate -s 0 /var/log/messages
fi

# 清理secure当前日志
if [ -f "/var/log/secure" ]; then
    truncate -s 0 /var/log/secure
fi

# 清理maillog当前日志
if [ -f "/var/log/maillog" ]; then
    truncate -s 0 /var/log/maillog
fi

# 清理cron当前日志
if [ -f "/var/log/cron" ]; then
    truncate -s 0 /var/log/cron
fi

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
# 禁用core dump
echo "kernel.core_pattern=/dev/null" > /etc/sysctl.d/disable-coredump.conf
echo "kernel.core_uses_pid=0" >> /etc/sysctl.d/disable-coredump.conf
echo "fs.suid_dumpable=0" >> /etc/sysctl.d/disable-coredump.conf
sysctl -p /etc/sysctl.d/disable-coredump.conf

# 清理已存在的core dump文件
echo "清理已存在的core dump文件..."
core_files=$(find / -type f -name "core" -o -name "core.*" 2>/dev/null)
if [ -n "$core_files" ]; then
    before_size=$(get_size "$core_files")
    rm -f $core_files
    echo "已删除core dump文件"
fi

# 清理系统崩溃目录
crash_dirs=("/var/crash" "/var/lib/systemd/coredump" "/var/spool/abrt")
for dir in "${crash_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "清理目录: $dir"
        before_size=$(get_size "$dir")
        rm -rf "${dir:?}"/*
        after_size=$(get_size "$dir")
        calculate_freed_space "$before_size" "$after_size" "崩溃转储"
    fi
done

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
