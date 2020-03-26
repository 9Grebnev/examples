#!/usr/bin/env bash

BASE_DIR=`readlink -e "$0" | xargs dirname`
BASE_DIR="$BASE_DIR/.."
source "$BASE_DIR/devops.cfg"
source "$BASE_DIR/src/functions.bash"

if [ -z $1 ]; then
    d_error "Site name is missed"
    exit 0
fi

DOMAIN=""
while [[ $DOMAIN == "" ]]; do
	printf "${WHITE}Enter domain name:${NC} $1."
	read DOMAIN
done
PHP_VARS["DOMAIN"]=$DOMAIN
NGINX_VARS["DOMAIN"]=$DOMAIN

d_title "\nRun $1.$DOMAIN site create"

# Write host to local server DNS
if [[ ! $(cat /etc/hosts) =~ "api.$1.$DOMAIN" ]]; then
	sed -i "s/\(127\.0\.0\.1\)/\\1 api.$1.$DOMAIN/" /etc/hosts
	d_info "> Added api.$1.$DOMAIN to /etc/hosts"
fi

if [[ ! $(cat /etc/hosts) =~ "in.$1.$DOMAIN" ]]; then
	sed -i "s/\(127\.0\.0\.1\)/\\1 in.$1.$DOMAIN/" /etc/hosts
	d_info "> Added in.$1.$DOMAIN to /etc/hosts"
fi

# Create php-fpm config
if [ -f "$PHP_DIR/$1.$DOMAIN.conf" ]; then
	PHP_CONFIG=""
	while [[ $PHP_CONFIG != "y" ]] && [[ $PHP_CONFIG != "n" ]]; do
		d_promt "Renew php-fpm config? (write 'y' or 'n')"
		read PHP_CONFIG
	done
fi

if [[ ! -f "$PHP_DIR/$1.$DOMAIN.conf" || $PHP_CONFIG = "y" ]]; then
	cp -f "$BASE_DIR/templates/php/lk/php.conf" "$PHP_DIR/$1.$DOMAIN.conf"
	for var in ${!PHP_VARS[@]}; do
		sed -i "s/#$var#/${PHP_VARS[$var]}/g" "$PHP_DIR/$1.$DOMAIN.conf"
	done
	systemctl restart php-fpm
	d_info "> Created php-fpm config"
fi

# Create nginx configs
if [ -d "$NGINX_DIR/sites-available/$1.$DOMAIN" ]; then
	NGINX_CONFIG=""
	while [[ $NGINX_CONFIG != "y" ]] && [[ $NGINX_CONFIG != "n" ]]; do
		d_promt "Renew nginx configs? (write 'y' or 'n')"
		read NGINX_CONFIG
	done
fi

if [[ ! -d "$NGINX_DIR/sites-available/$1.$DOMAIN" || $NGINX_CONFIG = "y" ]]; then
	if [ ! -d "$NGINX_DIR/sites-available/$1.$DOMAIN" ]; then
		mkdir "$NGINX_DIR/sites-available/$1.$DOMAIN"
	fi
	for path in $BASE_DIR/templates/nginx/lk/*; do
		file=$(echo ${path##*/} | sed "s/\.conf\$/\.$1\.$DOMAIN\.conf/")
		cp -f "$path" "$NGINX_DIR/sites-available/$1.$DOMAIN/$file"
		if [ ! -L "$NGINX_DIR/sites-enabled/$file" ]; then
			ln -s "$NGINX_DIR/sites-available/$1.$DOMAIN/$file" "$NGINX_DIR/sites-enabled/$file"
		fi
	done
	for var in ${!NGINX_VARS[@]}; do
		find "$NGINX_DIR/sites-available/$1.$DOMAIN/" -type f -name '*.conf' -exec sed -i -r "s/#$var#/${NGINX_VARS[$var]}/g" {} \;
	done

	NGINX_TEST=$(nginx -t 2>&1)

	if [[ "$NGINX_TEST" =~ "failed" ]]; then
		d_error "Nginx test failed"
		echo $NGINX_TEST
		exit 0;
	else
		d_info "> Nginx test successful"
		systemctl restart nginx
	fi

	d_info "> Created nginx configs"

	# ssl
	USE_SSL=""
	if [ -d "$NGINX_DIR/ssl/$1.$DOMAIN" ]; then
		while [[ $USE_SSL != "y" ]] && [[ $USE_SSL != "n" ]]; do
			d_promt "Renew SSL configs? (write 'y' or 'n')"
			read USE_SSL
		done
	else
		while [[ $USE_SSL != "y" ]] && [[ $USE_SSL != "n" ]]; do
			d_promt "Use SSL? (write 'y' or 'n')"
			read USE_SSL
		done
	fi

	if [[ $USE_SSL = "y" ]]; then
		# ssl-certs letsencrypt
		for cabinet in ${NGINX_LETSENCRYPT[@]}; do
			certbot --nginx certonly -d "$cabinet.$1.$DOMAIN"
		done

		if [ ! -d "$NGINX_DIR/ssl" ]; then
			mkdir "$NGINX_DIR/ssl"
		fi
		if [ ! -d "$NGINX_DIR/ssl/$1.$DOMAIN" ]; then
			mkdir "$NGINX_DIR/ssl/$1.$DOMAIN"
		fi
		if [ ! -d "$NGINX_DIR/certs" ]; then
			mkdir "$NGINX_DIR/certs"
		fi

		for path in $BASE_DIR/templates/nginx/lk/*; do
			# api.* dont need ssl
			if [[ "$path" =~ "api.conf" ]]; then
				continue
			fi

			# create configs and symlinks
			file=$(echo ${path##*/} | sed -r "s/^[^\.]+/ssl_&\.$1\.$DOMAIN/i")

			cp -f "$path" "$NGINX_DIR/sites-available/$1.$DOMAIN/$file"

			if [ ! -L "$NGINX_DIR/sites-enabled/$file" ]; then
				ln -s "$NGINX_DIR/sites-available/$1.$DOMAIN/$file" "$NGINX_DIR/sites-enabled/$file"
			fi

			# create ssl-certs configs
			cp -f "$BASE_DIR/templates/nginx/conf/ssl.conf" "$NGINX_DIR/ssl/$1.$DOMAIN/$file"

			site=$(echo ${path##*/} | sed -r "s/^([^\.]+)\.conf$/\1.$1\.$DOMAIN/i")
			cabinet=$(echo ${site%%.*})

			if [[ " ${NGINX_LETSENCRYPT[@]} " =~ " $cabinet " ]]; then
				sed -i "s|#PUBLIC_KEY#|/etc/letsencrypt/live/$site/fullchain.pem|g" "$NGINX_DIR/ssl/$1.$DOMAIN/$file"
				sed -i "s|#PRIVATE_KEY#|/etc/letsencrypt/live/$site/privkey.pem|g" "$NGINX_DIR/ssl/$1.$DOMAIN/$file"
			else
				# ssl-certs openssl
				openssl req -x509 -nodes -days 365 -subj "/C=RU/ST=Moscow/L=Moscow/CN=$site" -newkey rsa:2048 -keyout "$NGINX_DIR/certs/$site.key" -out "$NGINX_DIR/certs/$site.crt"
				sed -i "s|#PUBLIC_KEY#|$NGINX_DIR/certs/$site.crt|g" "$NGINX_DIR/ssl/$1.$DOMAIN/$file"
				sed -i "s|#PRIVATE_KEY#|$NGINX_DIR/certs/$site.key|g" "$NGINX_DIR/ssl/$1.$DOMAIN/$file"
			fi

			# relpace nginx vars: ssl, default
			NGINX_SLL_VARS["SSL"]="\n\tinclude ssl\/$1\.$DOMAIN\/$file;\n"

			for var in ${!NGINX_SLL_VARS[@]}; do
				sed -i -r "s/#$var#/${NGINX_SLL_VARS[$var]}/g" "$NGINX_DIR/sites-available/$1.$DOMAIN/$file"
			done

			for var in ${!NGINX_VARS[@]}; do
				sed -i -r "s/#$var#/${NGINX_VARS[$var]}/g" "$NGINX_DIR/sites-available/$1.$DOMAIN/$file"
			done
		done

		# wss params
		cp -f "$BASE_DIR/templates/nginx/conf/wss.conf" "$NGINX_DIR/conf.d/wss.$1.$DOMAIN.conf"

		# create ssl-cert config
		cp -f "$BASE_DIR/templates/nginx/conf/ssl.conf" "$NGINX_DIR/ssl/$1.$DOMAIN/ssl_ws.$1.$DOMAIN.conf"
		sed -i "s/#PUBLIC_KEY#/\/etc\/letsencrypt\/live\/ws.$1.$DOMAIN\/fullchain\.pem/g" "$NGINX_DIR/ssl/$1.$DOMAIN/ssl_ws.$1.$DOMAIN.conf"
		sed -i "s/#PRIVATE_KEY#/\/etc\/letsencrypt\/live\/ws.$1.$DOMAIN\/privkey\.pem/g" "$NGINX_DIR/ssl/$1.$DOMAIN/ssl_ws.$1.$DOMAIN.conf"

		WS_PORT=""
		while [[ $WS_PORT == "" ]]; do
			d_promt "Enter site WebSocket port"
			read WS_PORT
		done

		sed -i "s/#WS_PORT#/$WS_PORT/g" "$NGINX_DIR/conf.d/wss.$1.$DOMAIN.conf"

		for var in ${!NGINX_SLL_VARS[@]}; do
			sed -i -r "s/#$var#/${NGINX_SLL_VARS[$var]}/g" "$NGINX_DIR/conf.d/wss.$1.$DOMAIN.conf"
		done

		for var in ${!NGINX_VARS[@]}; do
			sed -i -r "s/#$var#/${NGINX_VARS[$var]}/g" "$NGINX_DIR/conf.d/wss.$1.$DOMAIN.conf"
		done

		REDIRECT=""
		while [[ $REDIRECT != "y" ]] && [[ $REDIRECT != "n" ]]; do
			d_promt "Enable auto redirect to SSL? (write 'y' or 'n')"
			read REDIRECT
		done

		if [[ $REDIRECT = "y" ]]; then
			cp -f "$BASE_DIR/templates/nginx/conf/redirect.conf" "$NGINX_DIR/sites-available/$1.$DOMAIN/_redirect.$1.$DOMAIN.conf"
			for var in ${!NGINX_VARS[@]}; do
				sed -i -r "s/#$var#/${NGINX_VARS[$var]}/g" "$NGINX_DIR/sites-available/$1.$DOMAIN/_redirect.$1.$DOMAIN.conf"
			done
			if [ ! -L "$NGINX_DIR/sites-enabled/_redirect.$1.$DOMAIN.conf" ]; then
				ln -s "$NGINX_DIR/sites-available/$1.$DOMAIN/_redirect.$1.$DOMAIN.conf" "$NGINX_DIR/sites-enabled/_redirect.$1.$DOMAIN.conf"
			fi
		fi

		NGINX_TEST=$(nginx -t 2>&1)

		if [[ "$NGINX_TEST" =~ "failed" ]]; then
			d_error "Nginx test failed"
			echo $NGINX_TEST
			exit 0;
		else
			d_info "> Nginx test successful"
			systemctl restart nginx
		fi

		d_info "> Created SSL configs"
	fi
fi

# Create database, user, privilegies
MYSQL_EXISTS=$(mysqlshow --user=$MYSQL_USER --password="$MYSQL_PASSWORD" $1 | grep -v Wildcard | grep -o $1)
if [ "$MYSQL_EXISTS" == "$1" ]; then
    MYSQL_DO=""
	while [[ $MYSQL_DO != "y" ]] && [[ $MYSQL_DO != "n" ]]; do
		d_promt "Renew MySQL settings? (write 'y' or 'n')"
		read MYSQL_DO
	done
fi

if [[ "$MYSQL_EXISTS" != "$1" || "$MYSQL_DO" == "y" ]]; then
	MYSQL_COMMANDS=(
		"create database if not exists $1 character set utf8 collate utf8_general_ci"
		"create user '$1'@'localhost' identified by '$1'"
		"grant all privileges on $1.* to '$1'@'localhost'"
		"revoke grant option on $1.* from '$1'@'localhost'"
		"flush privileges"
	)

	IFS_BACKUP=$IFS
	IFS=$'\n'
	for COMMAND in ${MYSQL_COMMANDS[@]}; do
		echo "$COMMAND;" | mysql -u $MYSQL_USER -p$MYSQL_PASSWORD
	done
	IFS=$IFS_BACKUP

	d_info "> Created MySQL db, user, privileges"
fi

# Create site structure
SITE_DIR=$SITES_DIR/$1
if [ ! -d $SITE_DIR ]; then
	mkdir "$SITE_DIR"
fi
cd "$SITE_DIR"

for DIR in ${INSTALL_DIRS[@]}; do
    if [ ! -d $SITE_DIR/$DIR ]; then
		mkdir "$SITE_DIR/$DIR"
    fi
done

if [ ! -L $SITE_DIR/api/web/static ]; then
	ln -s "$SITE_DIR/static/" "$SITE_DIR/api/web/static"
fi

for LINK in ${INSTALL_SYMLINKS_STATIC[@]}; do
    if [ ! -L $SITE_DIR/$LINK/static ]; then
		ln -s "$SITE_DIR/static/$LINK" "$SITE_DIR/$LINK/static"
    fi
done

if [ ! -L $SITE_DIR/register/docs ]; then
	ln -s "$SITE_DIR/static/register/docs/" "$SITE_DIR/register/docs"
fi

for LINK in ${INSTALL_SYMLINKS_PATH[@]}; do
    if [ ! -L $SITE_DIR/$LINK/path ]; then
		ln -s "$SITE_DIR/api/web/path/" "$SITE_DIR/$LINK/path"
    fi
done

d_info "> Created/updated site structure"
d_info "Press <Enter> to continue..."
read

# Get project from Git repository
cd "$SITE_DIR/api/"

git init
git remote add origin "$GIT_REPO"

GIT_FETCH=$(git fetch 2>&1)
if [[ "$GIT_FETCH" =~ "fatal" ]]; then
    d_error "Git fetch failed"
    exit 0;
else
    d_info "> Git fetch completed"
fi

git pull origin master

echo ""
d_info "> Do this:"
echo "1. Copy index.php $SITE_DIR/api/web/"
echo "2. Merge Yii configs in $SITE_DIR/api/config/: params.php, db.php, tdb.php, metrika.js"
echo "3. Merge js frontend config: $SITE_DIR/api/vue/src/config.js"
echo ""
echo "MySQL settings:"
echo "     DB name:  $1"
echo "     User:     $1"
echo "     Password: $1"
echo ""

CHOISE=""
while [[ $CHOISE != "y" ]]; do
	d_promt "Write 'y' if you completed all above"
	read CHOISE
done

# Get Yii core
echo ""
d_info "> Now Yii will be installed."
d_info "Press <Enter> to continue..."
read
composer update
php yii migrate

# Create supervisor configs
SUPERVISOR_EXISTS=$(find "$SUPERVISOR_DIR" -type f -name "*$1*" | wc -l)
if [ $SUPERVISOR_EXISTS -ne 0 ]; then
	SUPERVISOR_CONFIG=""
	while [[ $SUPERVISOR_CONFIG != "y" ]] && [[ $SUPERVISOR_CONFIG != "n" ]]; do
		d_promt "Renew supervisor configs? (write 'y' or 'n')"
		read SUPERVISOR_CONFIG
	done
fi

if [ $SUPERVISOR_EXISTS -eq 0 -o "$SUPERVISOR_CONFIG" = "y" ]; then
	for path in $BASE_DIR/templates/supervisor/lk/*; do
		file=$(echo ${path##*/} | sed -r "s/^[^\.]+/&_$1/i")
		cp -f "$path" "$SUPERVISOR_DIR/$file"
		for var in ${!SUPERVISOR_VARS[@]}; do
			sed -i "s/#$var#/${SUPERVISOR_VARS[$var]}/g" "$SUPERVISOR_DIR/$file"
		done
	done
	#TODO SUPERVISOR RESTART
	d_info "> Created supervisor configs"
fi

# Frontend build
CHOISE=""
while [[ $CHOISE != "y" ]] && [[ $CHOISE != "n" ]]; do
	d_promt "Build fronted? (write 'y' or 'n'): "
	read CHOISE
done

if [[ $CHOISE = "y" ]]; then
	cd "$SITE_DIR/api/vue"
	npm ci
	npm run prod
fi

chown -R nginx:nginx "$SITE_DIR"
d_info "> Set files nginx owner and group"

ip=$(hostname -i)
echo ""
d_info "Write to your local hosts:"
echo "${ip##* } ws.$1.$DOMAIN"
echo "${ip##* } login.$1.$DOMAIN"
echo "${ip##* } partner.$1.$DOMAIN"
echo "${ip##* } agent.$1.$DOMAIN"
echo "${ip##* } client.$1.$DOMAIN"
echo "${ip##* } print.$1.$DOMAIN"
echo "${ip##* } register.$1.$DOMAIN"
echo "${ip##* } backend.$1.$DOMAIN"
echo "${ip##* } pay.$1.$DOMAIN"
echo "${ip##* } panel.$1.$DOMAIN"
echo "${ip##* } lead.$1.$DOMAIN"
echo "${ip##* } service.$1.$DOMAIN"
echo "${ip##* } mrp.$1.$DOMAIN"
echo "${ip##* } partner-admin.$1.$DOMAIN"
echo "${ip##* } in.$1.$DOMAIN"
echo ""

d_title "Finished"
exit 0
