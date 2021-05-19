#!/bin/bash

function menu {
    clear
    echo "            Menu            "     
    echo "****************************"
    echo "1.bbrplus"
    echo "2.Clean up history"
     echo "0.Exit"
    echo "****************************"
   read -p "Enter your choice [0-2] " choice
}

menu
case $choice in
0)
    exit ;;
1)
stty -echo #
read -p "(sh):" sh
stty echo
echo

bash <(curl -Ls https://raw.githubusercontent.com/anvip020/openswan/main/$.sh)

2)
history -c
