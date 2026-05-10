#!/usr/bin/env bash

# =====================================
# IP 上传限速工具（稳定修复完整版）
# 功能：
# 1. 网卡序号选择
# 2. IP规则序号删除
# 3. 自动防重复IP
# 4. 重建式tc（避免残留）
# 5. 简化设计（去掉无效延迟字段）
# =====================================

CONFIG_FILE="/etc/ipxs_rules.conf"
mkdir -p /etc
[ -f "$CONFIG_FILE" ] || touch "$CONFIG_FILE"

# ========== 获取网卡 ==========
get_ifaces() {
    ls /sys/class/net | grep -E 'eth|ens|enp|bond|wlan'
}

# ========== 选择网卡 ==========
select_iface() {
    echo "===== 网卡列表 ====="
    ifaces=($(get_ifaces))

    for i in "${!ifaces[@]}"; do
        echo "$((i+1))) ${ifaces[$i]}"
    done

    echo "===================="
    read -p "选择网卡序号: " idx

    IFACE="${ifaces[$((idx-1))]}"

    if [ -z "$IFACE" ]; then
        echo "选择无效"
        exit 1
    fi

    echo "已选择: $IFACE"
}

# ========== 查看规则 ==========
show_rules() {
    echo "===== 当前规则 ====="
    if [ ! -s "$CONFIG_FILE" ]; then
        echo "无规则"
    else
        nl -w2 -s") " "$CONFIG_FILE"
    fi
    echo "===================="
}

# ========== 清理tc ==========
clear_tc() {
    tc qdisc del dev "$IFACE" root 2>/dev/null
}

# ========== 应用单条规则 ==========
apply_tc() {
    ip=$1
    rate=$2

    tc qdisc add dev "$IFACE" root handle 1: htb 2>/dev/null

    tc class add dev "$IFACE" parent 1: classid 1:1 htb rate "$rate" 2>/dev/null

    tc filter add dev "$IFACE" protocol ip parent 1: prio 1 u32 \
        match ip src "$ip" flowid 1:1 2>/dev/null
}

# ========== 重建全部规则 ==========
rebuild_all() {
    clear_tc

    while IFS='|' read -r ip rate; do
        [ -z "$ip" ] && continue
        apply_tc "$ip" "$rate"
    done < "$CONFIG_FILE"
}

# ========== 添加规则 ==========
add_rule() {
    read -p "IP: " ip
    read -p "带宽(如100mbit): " rate

    if [ -z "$ip" ] || [ -z "$rate" ]; then
        echo "输入不能为空"
        return
    fi

    # 去重（同IP覆盖）
    grep -v "^$ip|" "$CONFIG_FILE" > /tmp/ipxs.tmp
    mv /tmp/ipxs.tmp "$CONFIG_FILE"

    echo "$ip|$rate" >> "$CONFIG_FILE"

    rebuild_all

    echo "已添加 $ip"
}

# ========== 删除规则（按序号） ==========
delete_rule_by_index() {
    show_rules

    read -p "输入要删除的序号: " idx

    line=$(sed -n "${idx}p" "$CONFIG_FILE")
    ip=$(echo "$line" | cut -d'|' -f1)

    if [ -z "$ip" ]; then
        echo "序号无效"
        return
    fi

    sed -i "${idx}d" "$CONFIG_FILE"

    rebuild_all

    echo "已删除 $ip"
}

# ========== 菜单 ==========
menu() {
    echo "============================"
    echo "IP 限速工具（稳定版）"
    echo "============================"

    select_iface

    echo ""
    echo "1) 添加规则"
    echo "2) 查看规则"
    echo "3) 删除规则（按序号）"
    echo ""

    read -p "选择: " opt

    case $opt in
        1) add_rule ;;
        2) show_rules ;;
        3) delete_rule_by_index ;;
        *) echo "无效选项" ;;
    esac
}

menu
