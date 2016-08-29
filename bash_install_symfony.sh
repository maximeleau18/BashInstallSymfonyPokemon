#!/bin/bash
# Bash Installing LAMP, Symphony2 and Pokemon Project
#
# Maxime LEAU
# maxime.leau@imie-rennes.fr
# 28/08/2016
#
# BINARY VARS (DEFAULT VALUES)
CURL_BIN='/usr/bin/curl'
COMPOSER_BIN='/usr/local/bin/composer'
A2ENSITE_BIN='/usr/sbin/a2ensite'
A2DISSITE_BIN='/usr/sbin/a2dissite'
PHP_BIN='/usr/bin/php'

# OTHER VAR
MYSQL_ROOT_PWD=''
GIT_REPO='https://github.com/maximeleau18/PokemonSymfony.git'
HTTPDUSER='www-data'
APP_CONSOLE='/var/www/pokemonSymfony'
ERR=0

echo $'####Installation Symfony Pokemon\n####Develop by Maxime LEAU\n####From https://github.com/maximeleau18/PokemonSymfony.git\n'
echo 'Setup Configuration...';

# Ask database root password
# Check user input
for i in `seq 1 3`;
do
	read -s -p 'Enter MySQL root password : ' MYSQL_ROOT_PWD_INPUT;
	echo ;
	read -s -p 'Confirm password : ' MYSQL_ROOT_PWD_CONF;
	echo ;
	
	if [ $MYSQL_ROOT_PWD_INPUT == $MYSQL_ROOT_PWD_CONF ]; then
		MYSQL_ROOT_PWD="$MYSQL_ROOT_PWD_INPUT"
		if [ -z $MYSQL_ROOT_PWD ]; then
			echo 'Password can not be empty.'
		else
			ERR=0
			break		
		fi
	else
		echo 'Passwords do not match.'
	fi
	ERR=1
	let "j = (3 - i)" 
	if [ $j -gt 0 ]; then
		echo $j ' essaie(s) restant(s)'
	fi
done

if [ $ERR -ne 0 ]; then
	exit $ERR
fi


# update package list
apt-get update

# install dependencies
apt-get install --assume-yes curl

# Install php5-curl needed by Symphony2
apt-get install --assume-yes php5-curl

# Download and Setup LAMP Server
debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PWD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PWD"
apt-get install --assume-yes mysql-server apache2 libapache2-mod-php5 php5 php5-mysql

# Update Binary Vars
CURL_BIN=$(which curl)
A2ENSITE_BIN=$(which a2ensite)
A2DISSITE_BIN=$(which a2dissite)
PHP_BIN=$(which php)


# Download and Setup composer
if [ -x $CURL_BIN ]; then
   echo "Installation de composer..."
   curl -sS https://getcomposer.org/installer | php -- --filename=composer --install-dir=/usr/local/bin/
else
   echo "Missing curl binary"
   exit 2
fi

# Update Binary Var
COMPOSER_BIN=$(which composer)

# Download and Install Git
apt-get install --assume-yes git
echo "Installing git..."

# If repository ever exists
if [ -d "$APP_CONSOLE" ] ; then
	rm -R "$APP_CONSOLE"
	echo "Remove old pokemonSymfony repository"
	mkdir "$APP_CONSOLE"
else
	mkdir "$APP_CONSOLE"
fi

# Remove ssl verification
git config --global http.sslverify false

# Clone the repository of pokemonSymfony
git clone "$GIT_REPO" "$APP_CONSOLE"
echo "Clone repository pokemonSymfony..."

# Edit VHost Configuration File
cat >/etc/apache2/sites-available/pokemonSymfony <<EOL
<VirtualHost *:80>
    ServerAdmin maxime.leau@imie-rennes.fr
    DocumentRoot "$APP_CONSOLE/web"
    DirectoryIndex app_dev.php
    #ServerName localhost
    #ServerAlias www.dummy-host.example.com
    ErrorLog /var/log/apache2/pokemonSymfony-error.log
    CustomLog /var/log/apache2/pokemonSymfony-access.log combined

<Directory "$APP_CONSOLE/web">
    #AddDefaultCharset utf-8
    Order Allow,Deny
    #Deny from all
    #Require all granted
    AllowOverride all
    Allow from all
</Directory>
</VirtualHost>
EOL

echo "Create VHost Apache2"

# Update pokemonSymfony Project
if [ -x $COMPOSER_BIN ]; then
	cd $APP_CONSOLE
   $COMPOSER_BIN update --no-scripts --verbose --prefer-dist --no-progress
else
   echo "Missing composer binary";
   exit 3
fi

# Bootstrap Symfony
if [ -x $PHP_BIN ]; then
   echo "Bootsraping..."
   $PHP_BIN "$APP_CONSOLE/vendor/sensio/distribution-bundle/Sensio/Bundle/DistributionBundle/Resources/bin/build_bootstrap.php" "$APP_CONSOLE/app"
else
   echo "Missing php binary";
   exit 4
fi

# Set parameters.yml
cat >"$APP_CONSOLE/app/config/parameters.yml" <<EOL
parameters:
    database_driver:   pdo_mysql
    database_host:     127.0.0.1
    database_port:     3306
    database_name:     pokemonSymfony
    database_user:     root
    database_password: $MYSQL_ROOT_PWD

    mailer_transport:  smtp
    mailer_host:       127.0.0.1
    mailer_user:       ~
    mailer_password:   ~

    locale:            fr
    secret:            aeznjv_èzenvç_ezanrlfvcçzenfvc
EOL

echo "Update parameters.yml..."

# Configure Apache2
# Disable default site
if [ -x $A2DISSITE_BIN ]; then
   $A2DISSITE_BIN 000-default
   echo "Disable default site"
fi

# Enable pokemonSymfony site
if [ -x $A2DISSITE_BIN ]; then
   $A2ENSITE_BIN pokemonSymfony
   echo "Enable pokemonSymfony site"
fi

# Restart Apache2
service apache2 restart

# Install setfacl to grant rights to www-data
apt-get install --assume-yes acl

# Fixing permissions for app/cache and app/logs
setfacl -R -m u:"$HTTPDUSER":rwX -m u:`whoami`:rwX "$APP_CONSOLE/app/cache" "$APP_CONSOLE/app/logs"
setfacl -dR -m u:"$HTTPDUSER":rwX -m u:`whoami`:rwX "$APP_CONSOLE/app/cache" "$APP_CONSOLE/app/logs"

# Create Database pokemonSymfony
$PHP_BIN $APP_CONSOLE app/console doctrine:database:drop -n --force
$PHP_BIN $APP_CONSOLE app/console doctrine:database:create
$PHP_BIN $APP_CONSOLE app/console doctrine:schema:create
$PHP_BIN $APP_CONSOLE app/console doctrine:fixtures:load -n

# Clearing Symphony app cache
$PHP_BIN $APP_CONSOLE app/console cache:clear --env=prod
$PHP_BIN $APP_CONSOLE app/console cache:clear --env=dev

# Launch browser to http://localhost/app_dev.php/api/doc
sudo -u deploy iceweasel http://localhost/app_dev.php/api/doc