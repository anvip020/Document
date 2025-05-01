#!/bin/bash

# 配置默认网卡
IFACE="eth0"
ROOT_QDISC="1:"

# 添加限速规则
add_limit() {
    read -rp "请输入源IP或CIDR（如 192.168.1.10 或 10.0.0.0/24），输入 done 完成: " IP
    while [ "$IP" != "done" ]; do
        read -rp "请输入该IP的上传限速（如 1mbit、500kbit），直接输入数字（如 30）表示 30mbit: " RATE

        # 检查输入的速率
        if [[ "$RATE" =~ ^[0-9]+$ ]]; then
            RATE="${RATE}mbit"  # 自动补全单位
        fi

        # 添加限速规则
        tc class add dev "$IFACE" parent 1: classid 1:"$((RANDOM % 1000))" htb rate "$RATE"
        tc filter add dev "$IFACE" parent 1:0 protocol ip prio 1 u32 match ip src "$IP" flowid 1:"$((RANDOM % 1000))"
        echo "✅ 已为 $IP 设置限速 $RATE"

        read -rp "请输入源IP或CIDR（如 192.168.1.10 或 10.0.0.0/24），输入 done 完成: " IP
    done
}

# 查询限速规则
query_limit() {
    read -rp "请输入要查询限速规则的网卡名（如 eth0）: " IFACE
    echo "正在列出当前的限速规则..."
    tc filter show dev "$IFACE" 2>/dev/null
}

# 删除限速规则
delete_limit() {
    read -rp "请输入要删除限速规则的网卡名（如 eth0）: " IFACE
    echo "正在列出当前的限速规则..."
    tc filter show dev "$IFACE" 2>/dev/null

    read -rp "请输入要删除的 IP 或 CIDR（例如：10.0.0.3 或 10.0.0.0/24），输入 done 完成: " IP
    if [ "$IP" == "done" ]; then
        echo "❗ 操作已完成，退出删除模式。"
    else
        # 查找与该 IP 相关的类 ID
        CLASS_IDS=$(tc filter show dev "$IFACE" | grep -B 1 "$IP" | grep -o 'flowid 1:[0-9]*' | awk '{print $2}')

        if [ -n "$CLASS_IDS" ]; then
            # 如果找到了相关的类 ID，则逐一删除
            for CLASS_ID in $CLASS_IDS; do
                echo "❗ 正在删除限速规则（类ID：$CLASS_ID）"
                tc filter del dev "$IFACE" protocol ip parent 1:0 prio 1 u32 match ip src "$IP" flowid "$CLASS_ID"
                tc class del dev "$IFACE" classid "$CLASS_ID"
                echo "✅ 已删除 IP $IP 的限速规则（类ID：$CLASS_ID）。"
            done
        else
            echo "❗ 未找到与 $IP 相关的限速规则。"
        fi
    fi
}

# 显示操作菜单
menu() {
    echo "请选择操作："
    echo "1) 添加限速规则（支持叠加 + 每IP限速，存在则替换）"
    echo "2) 查询限速规则"
    echo "3) 删除限速规则"
    read -rp "请输入选项（1-3）: " OPTION

    case $OPTION in
        1)
            add_limit
            ;;
        2)
            query_limit
            ;;
        3)
            delete_limit
            ;;
        *)
            echo "❗ 无效的选项，请重新选择。"
            menu
            ;;
    esac
}

# 主函数，进入菜单
menu
