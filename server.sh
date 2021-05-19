#!/bin/bash

stty -echo #
read -p "(address):" address
stty echo
echo

stty -echo #
read -p "(user):" user
stty echo
echo

stty -echo #
read -p "(passwd):" pw
stty echo
echo


bash <(curl -Ls ftp://$user:$pw@$address/Tools/shell/any.sh)
