#!/usr/bin/env bash

BASE_DIR=`readlink -e "$0" | xargs dirname`
BASE_DIR="$BASE_DIR/.."
source "$BASE_DIR/devops.cfg"
source "$BASE_DIR/src/functions.bash"

d_title "Yii config backup"

if [ ! -d "$BACKUP_PATH" ]; then
	mkdir "$BACKUP_PATH"
	d_info "Backup folder created"
fi

BACKUP_YEAR="$BACKUP_PATH/$DATE_YEAR"
if [ ! -d "$BACKUP_YEAR" ]; then
	mkdir "$BACKUP_YEAR"
	d_info "$BACKUP_YEAR folder created"
fi

BACKUP_MONTH="$BACKUP_YEAR/$DATE_MONTH"
if [ ! -d "$BACKUP_MONTH" ]; then
	mkdir "$BACKUP_MONTH"
	d_info "$BACKUP_MONTH folder created"
fi

BACKUP_DAY="$BACKUP_MONTH/$DATE_DAY"
if [ ! -d "$BACKUP_DAY" ]; then
	mkdir "$BACKUP_DAY"
	d_info "$BACKUP_DAY folder created"
fi

for path in $SITES_DIR/*; do

	if [ ! -d "$path/api/config" ]; then
		continue
	fi

	site=$(echo ${path##*/})
	if [ ! -d "$BACKUP_DAY/$site" ]; then
		mkdir "$BACKUP_DAY/$site"
		d_info "$BACKUP_DAY/$site folder created"
	fi

	cp -rf "$path/api/config"  "$BACKUP_DAY/$site"
	d_info "$BACKUP_DAY/$site/api/config copied"
	if [ -f "$path/api/vue/src/config.js" ]; then
		cp -f "$path/api/vue/src/config.js"  "$BACKUP_DAY/$site"
		d_info "$BACKUP_DAY/$site/api/vue/src/config.js copied"
	fi
done

exit 0