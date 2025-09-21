#!/bin/sh

# 增强版动态MAC更新脚本
CONFIG=miaplus
DYNAMIC_MAC_CACHE="/tmp/miaplus_dynamic_mac.cache"
LOCK_FILE="/tmp/miaplus_update.lock"
LOG_FILE="/tmp/miaplus_update.log"

# 防止并发执行
if [ -f "$LOCK_FILE" ]; then
    echo "Update already in progress"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

uci_get_by_type() {
    local index=0
    [ -n "$4" ] && index=$4
    local ret=$(uci get $CONFIG.@$1[$index].$2 2>/dev/null)
    echo ${ret:=$3}
}

# 获取主机名对应的所有MAC地址
get_macs_by_hostname() {
    local hostname="$1"
    local macs=""

    # 从 ARP 表查找所有匹配项
    macs=$(grep -i "$hostname" /proc/net/arp 2>/dev/null | awk '{print $4}' | tr '\n' ' ')

    # DHCP leases
    if [ -f "/tmp/dhcp.leases" ]; then
        dhcp_macs=$(grep -i "$hostname" /tmp/dhcp.leases | awk '{print $2}' | tr '\n' ' ')
        macs="$macs $dhcp_macs"
    fi

    # ping + 再查 ARP
    if [ -z "$macs" ]; then
        ping -c 1 -W 2 "$hostname" >/dev/null 2>&1
        sleep 1
        arp_macs=$(grep -i "$hostname" /proc/net/arp | awk '{print $4}' | tr '\n' ' ')
        macs="$macs $arp_macs"
    fi

    # hostapd_cli
    if [ -z "$macs" ] && [ -f "/var/run/hostapd/wlan0" ]; then
        sta_macs=$(hostapd_cli -i wlan0 all_sta 2>/dev/null | grep "^[0-9a-f]" | awk '{print $1}')
        macs="$macs $sta_macs"
    fi

    # 格式化，去重
    echo "$macs" | tr ' ' '\n' | grep -E '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' | sort -u | tr '\n' ' '
}

# 如果服务未启用直接退出
enable=$(uci get miaplus.@basic[0].enable 2>/dev/null)
[ -z "$enable" ] && enable=0
[ "$enable" -eq 0 ] && exit 0

echo "# Dynamic MAC Cache - $(date)" > "$DYNAMIC_MAC_CACHE.tmp"
echo "==== $(date '+%F %T') Dynamic MAC Update Start ====" >> "$LOG_FILE"

updated_count=0
failed_count=0

# 先备份旧缓存（供比较用）
cp "$DYNAMIC_MAC_CACHE" "$DYNAMIC_MAC_CACHE.old" 2>/dev/null || touch "$DYNAMIC_MAC_CACHE.old"

for i in $(seq 0 100); do
    enable=$(uci_get_by_type macbind enable '' $i)
    mactype=$(uci_get_by_type macbind mactype '' $i)
    hostname=$(uci_get_by_type macbind hostname '' $i)
    template=$(uci_get_by_type macbind template '' $i)

    if [ -z "$enable" ] || [ -z "$mactype" ] || [ -z "$template" ]; then
        break
    fi

    if [ "$enable" = "1" ] && [ "$mactype" = "dynamic" ] && [ -n "$hostname" ]; then
        macs=$(get_macs_by_hostname "$hostname")

        if [ -n "$macs" ]; then
            echo "$hostname|$macs|$template" >> "$DYNAMIC_MAC_CACHE.tmp"
            echo "FOUND $hostname -> $macs" >> "$LOG_FILE"
            logger -t miaplus "Updated MAC for $hostname: $macs"
            updated_count=$((updated_count + 1))
        else
            # 保留旧缓存中的值，避免误封
            old_line=$(grep "^$hostname|" "$DYNAMIC_MAC_CACHE.old" 2>/dev/null || true)
            if [ -n "$old_line" ]; then
                echo "$old_line" >> "$DYNAMIC_MAC_CACHE.tmp"
                echo "MISS $hostname -> keep old entry: $old_line" >> "$LOG_FILE"
                logger -t miaplus "MAC not found for $hostname, kept old value"
            else
                echo "MISS $hostname -> no MAC found" >> "$LOG_FILE"
                logger -t miaplus "Warning: Cannot find MAC for hostname: $hostname"
            fi
            failed_count=$((failed_count + 1))
        fi
    fi
done

# 比较新旧缓存，有变化才替换并 reload
if ! cmp -s "$DYNAMIC_MAC_CACHE.tmp" "$DYNAMIC_MAC_CACHE.old"; then
    mv "$DYNAMIC_MAC_CACHE.tmp" "$DYNAMIC_MAC_CACHE"
    logger -t miaplus "Dynamic MAC cache changed, reloading rules"
    /etc/init.d/miaplus reload >/dev/null 2>&1
    echo "CACHE UPDATED -> iptables reloaded" >> "$LOG_FILE"
else
    rm -f "$DYNAMIC_MAC_CACHE.tmp"
    echo "CACHE UNCHANGED -> skip reload" >> "$LOG_FILE"
fi

echo "==== Update Done: $updated_count updated, $failed_count failed ====" >> "$LOG_FILE"
rm -f "$DYNAMIC_MAC_CACHE.old"

