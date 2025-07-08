#!/bin/bash
# 网卡上行限速管理脚本（支持添加/删除/查看限速）

echo "=== 网卡限速配置工具 ==="
echo "1. 添加限速"
echo "2. 删除限速"
echo "3. 查看当前限速"
read -p "请选择操作（1 / 2 / 3）: " ACTION

if [[ "$ACTION" != "1" && "$ACTION" != "2" && "$ACTION" != "3" ]]; then
  echo "❌ 错误：无效选项"
  exit 1
fi

wg

read -p "请输入网卡名称（如 wg00/eth0）: " DEV
if [[ -z "$DEV" ]]; then
  echo "❌ 错误：网卡名称不能为空"
  exit 1
fi

LIMIT_SCRIPT="/usr/local/bin/tc_limit_${DEV}.sh"
SERVICE_NAME="tc-limit-${DEV}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

# === 操作 3：查看当前限速 ===
if [[ "$ACTION" == "3" ]]; then
  echo "🔍 正在查看 $DEV 当前限速配置..."
  sudo tc qdisc show dev "$DEV"
  sudo tc class show dev "$DEV"
  exit 0
fi

# 通用：清理旧配置
echo "🔄 正在清除旧配置..."
sudo tc qdisc del dev "$DEV" root 2>/dev/null && echo "✅ 已清除 tc 限速规则" || echo "ℹ️ 无限速规则或已删除"

if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
  sudo systemctl stop "$SERVICE_NAME"
  sudo systemctl disable "$SERVICE_NAME"
  sudo rm -f "$SERVICE_PATH"
  echo "✅ 已移除 systemd 服务：$SERVICE_NAME"
fi

sudo rm -f "$LIMIT_SCRIPT"

# === 操作 1：添加限速 ===
if [[ "$ACTION" == "1" ]]; then
  read -p "请输入上行限速值（单位 Mbps，例如 10）: " RATE
  if ! [[ "$RATE" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误：限速值必须是整数（Mbps）"
    exit 1
  fi

  # 写入限速脚本
  cat > "$LIMIT_SCRIPT" <<EOF
#!/bin/bash
tc qdisc del dev $DEV root 2>/dev/null
tc qdisc add dev $DEV root handle 1: htb default 30
tc class add dev $DEV parent 1: classid 1:1 htb rate ${RATE}mbit ceil ${RATE}mbit
tc class add dev $DEV parent 1:1 classid 1:30 htb rate ${RATE}mbit ceil ${RATE}mbit
EOF

  chmod +x "$LIMIT_SCRIPT"

  # 写入 systemd 服务
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

  sudo systemctl daemon-reexec
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl start "$SERVICE_NAME"

  echo "✅ 上行限速 ${RATE}Mbps 已应用于 $DEV"
  echo "✅ 重启后自动生效"
fi

# === 操作 2：删除限速 ===
if [[ "$ACTION" == "2" ]]; then
  echo "✅ 限速已从 $DEV 移除"
fi
