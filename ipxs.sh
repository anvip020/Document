#!/bin/bash

# 转换单位为 Mbit
convert_to_mbit() {
    local input="$1"
    local value="${input//[^0-9.]/}"  # 提取数值部分
    local unit="${input//[0-9.]}"    # 提取单位部分

    # 如果没有单位，则默认使用 mbit
    if [ -z "$unit" ]; then
        unit="mbit"
    fi

    # 统一转换为小写
    unit=$(echo "$unit" | tr '[:upper:]' '[:lower:]')

    case "$unit" in
        kbit|kb|k)  # kbit -> Mbit
            echo "$(echo "$value / 1024" | bc -l)"
            ;;
        mbit|mb|m)  # mbit 保持不变
            echo "$value"
            ;;
        *)
            echo "❗ 错误的单位: $unit"
            exit 1
            ;;
    esac
}

# 用户输入选项和配置
echo "请选择操作："
echo "1) 添加限速规则（支持叠加 + 每IP限速，存在则替换）"
echo "2) 查询限速规则"
echo "3) 删除限速规则"
read -rp "请输入选项（1-3）: " OPTION

# =========================
# 添加限速规则（支持叠加，存在则替换）
# =========================
if [ "$OPTION" == "1" ]; then
    read -rp "请输入要限速的出口网卡名（如 eth0）: " IFACE

    # 初始化 HTB 根结构（仅首次执行）
    if ! tc qdisc show dev "$IFACE" | grep -q "htb"; then
        tc qdisc add dev "$IFACE" root handle 1: htb default 999
        tc class add dev "$IFACE" parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
        tc class add dev "$IFACE" parent 1:1 classid 1:999 htb rate 1000mbit ceil 1000mbit
        echo "✅ 已初始化 HTB 根结构。"
    else
        echo "✅ 已检测到 HTB 根结构，将追加规则。"
    fi

    # 添加限速规则
    while true; do
        read -rp "请输入源IP或CIDR（如 192.168.1.10 或 10.0.0.0/24），输入 done 完成: " IP
        if [ "$IP" == "done" ]; then
            echo "❗ 操作已完成，退出添加模式。"
            break
        fi

        read -rp "请输入该IP的上传限速（如 1mbit、500kbit），直接输入数字（如 30）表示 30mbit: " RATE

        # 如果没有单位，默认单位为 mbit
        if [[ ! "$RATE" =~ [a-zA-Z] ]]; then
            RATE="${RATE}mbit"
        fi

        # 转换输入的限速单位为 Mbit
        RATE_MBIT=$(convert_to_mbit "$RATE")

        # 生成唯一 CLASS ID（建议使用随机数或自增）
        RAND_ID=$((RANDOM % 900 + 100))  # 100~999

        # 检查是否已有限速规则
        EXISTING_CLASS=$(tc filter show dev "$IFACE" | grep -B 1 "$IP" | grep -o 'flowid 1:[0-9]*' | awk '{print $2}')

        if [ -n "$EXISTING_CLASS" ]; then
            # 如果有现有规则，先删除
            echo "❗ IP $IP 已有限速规则，正在替换旧规则（类ID：$EXISTING_CLASS）"
            tc filter del dev "$IFACE" protocol ip parent 1:0 prio 1 u32 match ip src "$IP" flowid "$EXISTING_CLASS" 2>/dev/null
            tc class del dev "$IFACE" classid "$EXISTING_CLASS" 2>/dev/null
        fi

        # 创建限速类
        tc class add dev "$IFACE" parent 1:1 classid 1:$RAND_ID htb rate "${RATE_MBIT}mbit" ceil "${RATE_MBIT}mbit"

        # 添加匹配规则
        if [[ "$IP" =~ "/" ]]; then
            IPADDR=$(echo "$IP" | cut -d/ -f1)
            NETMASK=$(ipcalc -m "$IP" | awk '{print $2}')
            tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 \
                match ip src "$IPADDR"/"$NETMASK" flowid 1:$RAND_ID
        else
            tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 u32 \
                match ip src "$IP" flowid 1:$RAND_ID
        fi

        echo "✅ 已为 $IP 设置限速 ${RATE_MBIT}mbit（类ID: 1:$RAND_ID）"
    done
fi
