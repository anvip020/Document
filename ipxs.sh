#!/bin/bash

# 检查依赖
if ! command -v ipcalc &>/dev/null; then
    echo "❗ 需要安装 ipcalc：sudo apt install ipcalc"
    exit 1
fi

# 将输入的单位转换为 Mbit
convert_to_mbit() {
    local input="$1"
    local value="${input//[^0-9.]/}"  # 提取数值部分
    local unit="${input//[0-9.]}"    # 提取单位部分

    case "$unit" in
        kbit|Kbit|Kb|KB)  # Kbit -> Mbit
            echo "$(echo "$value / 1024" | bc -l)"
            ;;
        mbit|Mbit|Mb|MB)  # Mbit 保持不变
            echo "$value"
            ;;
        *)
            echo "❗ 错误的单位: $unit"
            exit 1
            ;;
    esac
}

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

    # 逐个添加 IP 和速率
    while true; do
        read -rp "请输入源IP或CIDR（如 192.168.1.10 或 10.0.0.0/24），输入 done 完成: " IP
        [ "$IP" == "done" ] && break

        read -rp "请输入该IP的上传限速（如 1mbit、500kbit）: " RATE

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

# =========================
# 查询当前限速规则
# =========================
elif [ "$OPTION" == "2" ]; then
    read -rp "请输入要查询的出口网卡名（如 eth0）: " IFACE

    # 获取当前限速规则（包括 IP 和 flowid）
    echo "📋 当前限速规则列表："
    tc filter show dev "$IFACE" | grep -B 1 "match ip src" | while read -r line; do
        if [[ "$line" == *"flowid"* ]]; then
            FLOWID=$(echo "$line" | awk '{print $2}')
            IP=$(echo "$line" | grep -oP 'src \K[0-9.]+')
            echo "IP: $IP, 类ID: $FLOWID"
        fi
    done

# =========================
# 删除限速规则
# =========================
elif [ "$OPTION" == "3" ]; then
    read -rp "请输入要删除限速规则的出口网卡名（如 eth0）: " IFACE
    
    # 获取所有现有的过滤规则并显示
    FILTERS=$(tc filter show dev "$IFACE" | grep -B 1 "match ip src" | grep -o 'flowid 1:[0-9]*' | awk '{print $2}')
    IPS=$(tc filter show dev "$IFACE" | grep -B 1 "match ip src" | grep -oP 'src \K[0-9.]+')

    if [ -z "$FILTERS" ]; then
        echo "❗ 没有找到限速规则。"
        exit 1
    fi

    echo "📋 当前限速规则列表："
    paste <(echo "$IPS") <(echo "$FILTERS")  # 显示 IP 和 flowid 的对应关系
    echo "请选择要删除的规则，输入 IP 地址（如 192.168.1.100）:"
    read -rp "请输入要删除的源IP地址: " IP_TO_DELETE

    # 找到对应的 flowid
    FLOWID_TO_DELETE=$(echo "$FILTERS" | grep -n "$IP_TO_DELETE" | cut -d: -f1)
    if [ -z "$FLOWID_TO_DELETE" ]; then
        echo "❗ 未找到匹配的 IP 地址：$IP_TO_DELETE"
        exit 1
    fi

    FLOWID_TO_DELETE=$(echo "$FILTERS" | sed -n "${FLOWID_TO_DELETE}p")
    
    # 删除指定的过滤规则和类
    tc filter del dev "$IFACE" protocol ip parent 1:0 prio 1 u32 match ip src "$IP_TO_DELETE" flowid "$FLOWID_TO_DELETE"
    tc class del dev "$IFACE" classid "$FLOWID_TO_DELETE"

    echo "✅ 类ID $FLOWID_TO_DELETE 和 IP 地址 $IP_TO_DELETE 的限速规则已删除。"

else
    echo "❌ 无效选项，请输入 1、2 或 3。"
    exit 1
fi
