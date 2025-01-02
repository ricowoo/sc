#!/bin/bash
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# 保存完整的规则集到临时文件
nft list ruleset > /tmp/nftables_backup.nft

# 修改备份文件，移除计数器的值
sed -i 's/counter packets [0-9]* bytes [0-9]*/counter/g' /tmp/nftables_backup.nft

# 清空所有规则
nft flush ruleset

# 重新加载修改后的规则（计数器会从0开始）
nft -f /tmp/nftables_backup.nft

# 删除临时文件
rm -f /tmp/nftables_backup.nft

# 显示更新后的规则集
nft list ruleset
