#!/bin/bash
stty erase ^H

stty -echo #
read -p "(sh):" sh
stty echo
echo
bash <(curl -Ls https://raw.githubusercontent.com/anvip020/openswan/main/$sh.sh)
