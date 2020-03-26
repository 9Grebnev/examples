#!/usr/bin/env bash

BASE_DIR=`readlink -e "$0" | xargs dirname`
source "$BASE_DIR"/devops.cfg
source "$BASE_DIR/src/functions.bash"

echo -e "\n${LIGHTGREEN}SomeCompany DevOps system${NC}\n"

if [[ "$1" != "" ]]; then
 	CHOISE=$1;
else
	echo " 1. Install new site"
	echo " 2. Backup configs"
	echo " 0. Exit"
	echo ""
	d_promt "Your choise"
	read CHOISE
fi

case $CHOISE in
	1)
		d_promt "Enter site base name"
		read site
		bash $BASE_DIR/src/lk.install.bash $site
        ;;
    2)
        bash "$BASE_DIR/src/lk.configs.backup.bash"
        ;;
    0)
		exit 0
		;;
    *)
        echo "-"
        ;;
esac

exit 0