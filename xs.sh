#!/bin/bash
# 一体化 WireGuard 网卡上行限速 + systemd 开机自启脚本
# 支持添加限速和删除限速

echo "=== WireGuard 网卡上行限速设置工具 ==="

# 提供操作选项：添加限速或删除限速
echo "请选择操作："
echo "1. 添加限速"
echo "2. 删除限速"
read -p "请输入操作选项（1 或 2）: " ACTION

if [[ "$ACTION" != "1" && "$ACTION" != "2" ]]; then
  echo "❌ 错误：无效选项"
  exit 1
fi


# 输入网卡名
read -p "请输入要限速的网卡名（例如 wg00）: " DEV
if [[ -z "$DEV" ]]; then
  echo "❌ 错误：网卡名不能为空"
  exit 1
fi

# 输入限速值（仅在添加限速时需要）
if [[ "$ACTION" == "1" ]]; then
  read -p "请输入上行限速值（单位 Mbps，例如 30）: " RATE
  if ! [[ "$RATE" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误：限速值必须是整数（Mbps）"
    exit 1
  fi
fi

# 定义脚本和 systemd 服务路径
LIMIT_SCRIPT="/usr/local/bin/tc_limit_${DEV}.sh"
SERVICE_NAME="tc-limit-${DEV}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

# 删除旧配置（添加限速和删除限速时都会清除旧配置）
echo "🔄 正在删除旧配置..."
if [[ -f "$LIMIT_SCRIPT" ]]; then
  rm -f "$LIMIT_SCRIPT"
  echo "✅ 已删除旧限速脚本：$LIMIT_SCRIPT"
fi

if systemctl is-enabled "$SERVICE_NAME" > /dev/null 2>&1; then
  systemctl stop "$SERVICE_NAME"
  systemctl disable "$SERVICE_NAME"
  rm -f "$SERVICE_PATH"
  echo "✅ 已删除旧 systemd 服务：$SERVICE_NAME"
fi

# 删除 tc 配置（如果限速规则存在）
echo "🔄 正在清除 tc 限速规则..."
sudo tc qdisc del dev "$DEV" root 2>/dev/null
if [[ $? -eq 0 ]]; then
  echo "✅ 已清除 tc 限速规则：$DEV"
else
  echo "⚠️ 未找到 tc 限速规则，可能已经被清除"
fi

if [[ "$ACTION" == "1" ]]; then
  # 创建新的限速执行脚本
  cat > "$LIMIT_SCRIPT" <<EOF
#!/bin/bash
# 自动生成的限速脚本：针对 $DEV 上行限速 ${RATE}Mbps
tc qdisc del dev $DEV root 2>/dev/null
tc qdisc add dev $DEV root handle 1: htb default 30
tc class add dev $DEV parent 1: classid 1:1 htb rate ${RATE}mbit ceil ${RATE}mbit
tc class add dev $DEV parent 1:1 classid 1:30 htb rate ${RATE}mbit ceil ${RATE}mbit
EOF

  chmod +x "$LIMIT_SCRIPT"
  echo "✅ 已生成限速脚本：$LIMIT_SCRIPT"

  # 创建新的 systemd 服务
  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=TC 限速服务 ($DEV @ ${RATE}Mbps)
After=network.target

[Service]
Type=oneshot
ExecStart=$LIMIT_SCRIPT
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载 systemd，启用服务
  systemctl daemon-reexec
  systemctl enable "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME"

  echo "✅ Systemd 服务已创建并启用：$SERVICE_NAME"
  echo "✅ $DEV 上行限速 ${RATE}Mbps 已生效，重启后自动应用"
elif [[ "$ACTION" == "2" ]]; then
  echo "✅ $DEV 上行限速已被禁用"
fi
