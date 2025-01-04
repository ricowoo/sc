#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 添加重要系统目录保护
protected_dirs=(
    "/bin"
    "/sbin"
    "/usr/bin"
    "/usr/sbin"
    "/usr/local/bin"
    "/usr/local/sbin"
    "/etc/passwd"
    "/etc/shadow"
    "/etc/group"
    "/etc/gshadow"
    "/etc/ssh"
    "/boot"
    "/www/server"  # 宝塔面板核心目录
    "/www/server/panel"
    "/www/server/nginx/conf"
    "/www/server/php/*/etc"
    "/www/server/mysql/conf"
)

# 添加安全检查函数
check_protected_path() {
    local path="$1"
    for protected in "${protected_dirs[@]}"; do
        if [[ "$path" == "$protected"* ]]; then
            echo -e "${RED}警告: 试图清理受保护目录 $path${NC}"
            return 1
        fi
    done
    return 0
}

# 添加系统检查
pre_clean_check() {
    echo -e "${YELLOW}执行系统检查...${NC}"
    
    # 检查系统负载
    load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1)
    if (( $(echo "$load > 2.0" | bc -l) )); then
        echo -e "${RED}系统负载过高 (${load}), 建议稍后再试${NC}"
        exit 1
    fi
    
    # 检查磁盘空间
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 95 ]; then
        echo -e "${RED}警告: 磁盘空间严重不足 (${disk_usage}%), 建议立即清理${NC}"
    fi
    
    # 检查重要服务
    services=("nginx" "mysqld" "php-fpm" "redis" "memcached")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}服务 $service 运行正常${NC}"
        fi
    done
}

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

# 错误处理函数
handle_error() {
    local line_number=$1
    local error_code=$2
    echo -e "${RED}警告: 在第 $line_number 行发生错误 (错误码: $error_code)${NC}"
    echo -e "${YELLOW}继续执行其他清理任务...${NC}"
}

# 替换原有的错误处理
trap 'handle_error ${LINENO} $?' ERR

# 添加执行状态检查函数
check_command() {
    local cmd="$1"
    local msg="$2"
    
    echo -e "${YELLOW}执行: $msg${NC}"
    if ! eval "$cmd"; then
        echo -e "${RED}警告: $msg 失败，继续执行其他任务${NC}"
        return 1
    fi
    return 0
}

# 函数：安全清理目录
safe_clean_dir() {
    local dir=$1
    local exclude=$2
    
    if ! check_protected_path "$dir"; then
        return 1
    fi
    
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}目录不存在: $dir${NC}"
        return 1
    fi
    
    echo -e "${GREEN}清理目录: $dir${NC}"
    before_size=$(get_size "$dir")
    if [ -n "$exclude" ]; then
        find "$dir" -type f ! -name "$exclude" -delete 2>/dev/null || true
    else
        find "$dir" -type f -delete 2>/dev/null || true
    fi
    after_size=$(get_size "$dir")
    calculate_freed_space "$before_size" "$after_size" "$dir"
}

# 修改 find 命令，添加保护
safe_find() {
    local dir=$1
    local pattern=$2
    local days=$3
    local action=${4:-"-delete"}
    
    if ! check_protected_path "$dir"; then
        return 1
    fi
    
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}目录不存在: $dir${NC}"
        return 1
    fi
    
    echo -e "${GREEN}清理目录: $dir${NC}"
    find "$dir" -type f -regextype posix-extended -regex "$pattern" -mtime +"$days" $action 2>/dev/null || true
}

echo -e "${GREEN}开始系统清理...${NC}"
echo "清理时间: $(date)"

# 执行系统检查
pre_clean_check

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
echo -e "${GREEN}清理系统轮转日志...${NC}"
check_command "safe_find '/var/log' 'messages-.*' 3" "清理messages日志"
check_command "safe_find '/var/log' 'secure-.*' 3" "清理secure日志"
check_command "safe_find '/var/log' 'maillog-.*' 3" "清理maillog日志"
check_command "safe_find '/var/log' 'spooler-.*' 3" "清理spooler日志"
check_command "safe_find '/var/log' 'boot\.log-.*' 3" "清理boot日志"
check_command "safe_find '/var/log' 'cron-.*' 3" "清理cron日志"
check_command "safe_find '/var/log' 'yum\.log-.*' 3" "清理yum日志"
check_command "safe_find '/var/log' 'dmesg\.old' 3" "清理dmesg日志"

# 压缩旧日志
echo -e "${GREEN}压缩旧日志...${NC}"
check_command "safe_find '/var/log' '.*\.log' 3 '-exec gzip {} \;'" "压缩日志文件"

# 删除超过3天的压缩日志
echo -e "${GREEN}清理压缩日志...${NC}"
check_command "safe_find '/var/log' '.*\.gz' 3" "清理压缩日志"

# 清理journal日志
echo -e "${GREEN}清理journal日志...${NC}"
check_command "journalctl --vacuum-time=1d --vacuum-size=50M" "清理journal日志"

# 清理当前日志文件
echo -e "${GREEN}清理当前日志文件...${NC}"
current_logs=(
    "/var/log/messages"
    "/var/log/secure"
    "/var/log/maillog"
    "/var/log/cron"
)

for log in "${current_logs[@]}"; do
    if [ -f "$log" ]; then
        echo -e "${YELLOW}清理: $log${NC}"
        check_command "truncate -s 0 $log" "清理 $log"
    fi
done

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
# 宝塔面板和系统备份目录
backup_dirs=(
    # 宝塔面板相关
    "/www/backup"              # 网站备份
    "/www/backup/database"     # 数据库备份
    "/www/backup/site"         # 网站备份
    "/www/backup/path"         # 目录备份
    "/www/backup/cloud"        # 云端备份
    "/www/server/panel/backup" # 面板备份
    "/www/server/panel/logs"   # 面板日志
    "/www/wwwlogs"            # 网站日志
    "/www/server/data"        # 数据库文件
    
    # 系统常见备份目录
    "/backup"                 # 系统备份
    "/var/backup"            # 系统备份
    "/usr/local/backup"      # 本地备份
    "/opt/backup"            # 可选备份
    "/root/backup"           # root用户备份
    "/home/backup"           # 用户备份
    "/var/www/backup"        # Web备份
    "/usr/backup"            # 程序备份
    "/etc/backup"            # 配置备份
    "/tmp/backup"            # 临时备份
)

# 备份文件类型
backup_files_pattern="\.bak$|\.old$|\.backup$|\.[0-9]+$|\.tar$|\.tar\.gz$|\.tgz$|\.zip$|\.sql$|\.log$|\.gz$|\.xz$|\.bz2$|\.7z$|\.rar$|~$|\.swp$|\.swo$|\.swn$|\.bak\.[0-9]+$|\.save$|\.backup\.[0-9]+$|\.copy$"

for dir in "${backup_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "检查目录: $dir"
        before_size=$(get_size "$dir")
        # 清理超过30天的备份文件
        safe_find "$dir" "$backup_files_pattern" 30 -delete -print 2>/dev/null
        after_size=$(get_size "$dir")
        calculate_freed_space "$before_size" "$after_size" "$dir 备份文件"
    fi
done

# 全局搜索特定备份文件（仅在特定目录下）
echo "检查系统其他备份文件..."
global_search_dirs=(
    "/etc"
    "/var"
    "/usr/local"
    "/opt"
    "/root"
    "/home"
)

for dir in "${global_search_dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "检查目录: $dir"
        before_size=$(get_size "$dir")
        # 清理超过30天的备份文件
        safe_find "$dir" "$backup_files_pattern" 30 -delete -print 2>/dev/null
        after_size=$(get_size "$dir")
        calculate_freed_space "$before_size" "$after_size" "$dir 备份文件"
    fi
done

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
safe_find "/" "\..*\.sw[a-p]" 0
safe_find "/" "\..*~" 0
safe_find "/" "\..*\.un~" 0

# 13. 清理系统core dump
echo "清理系统core dump..."
# 禁用core dump
echo "kernel.core_pattern=/dev/null" > /etc/sysctl.d/disable-coredump.conf
echo "kernel.core_uses_pid=0" >> /etc/sysctl.d/disable-coredump.conf
echo "fs.suid_dumpable=0" >> /etc/sysctl.d/disable-coredump.conf
sysctl -p /etc/sysctl.d/disable-coredump.conf

# 清理已存在的core dump文件
echo "清理已存在的core dump文件..."
safe_find "/" "core|core\.*" 0

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
for dir in "${backup_dirs[@]}"; do
    if [ -d "$dir" ] && check_protected_path "$dir"; then
        find "$dir" -type f -atime +30 -size +10M -exec ls -lh {} \; 2>/dev/null
    fi
done

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
