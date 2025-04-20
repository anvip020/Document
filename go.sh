#!/bin/bash

# =======================
# 用户密码输入
# =======================
read -s -p "请输入安装密码: " input
echo

# =======================
encrypted_url="U2FsdGVkX1/VVcQ8Ar0UuK0mD2kGvqvuGFXF0W+IbKL0OhP7Vtn7WJtZ9VZoFAgu5B6hFzUCu09iXX27X+mZ4g=="

# =======================
# 解密
# =======================
url=$(echo "$encrypted_url" | openssl enc -aes-256-cbc -a -d -salt -pass pass:"$input" 2>/dev/null)

# =======================
# 验证和执行
# =======================
if [[ -z "$url" ]]; then
  echo "密码错误或解密失败，退出。"
  exit 1
fi

echo "验证成功，开始执行安装脚本..."
bash <(curl -Ls "$url")
