#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# Valores por defecto 
HOSTNAME="localhost"
USERNAME="admin"
PASSWORD="pavo842"
DBPASSWORD="pavo842"
EMAIL="test@example.com"

for i in "$@"; do
    case $i in
        --hostname=*)
        HOSTNAME="${i#*=}" 
        ;;
        --username=*)
        USERNAME="${i#*=}"
        ;;
        --password=*)
        PASSWORD="${i#*=}"
        ;;
        --email=*)
        EMAIL="${i#*=}"
        ;;
        *)
        ;;
    esac
done

# Instalación de dependencias
apt-get update
apt-get upgrade -y
apt-get install -y php8.1 php8.1-cli php8.1-common php8.1-imap php8.1-redis php8.1-snmp php8.1-xml php8.1-zip php8.1-mbstring php8.1-curl php8.1-gd php8.1-mysql apache2 mariadb-server certbot unzip

# Creación de la base de datos y usuario
mysql -e "CREATE DATABASE nextcloud;GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost' IDENTIFIED BY '$DBPASSWORD';FLUSH PRIVILEGES;"

# Montaje del almacenamiento de archivos
mkdir -p /disco
echo "/dev/sdb1  /disco    ext4    defaults    0 0" >> /etc/fstab
mount /disco

# Descarga de Nextcloud
cd /var/www/html
wget https://download.nextcloud.com/server/releases/nextcloud-28.0.3.zip
unzip nextcloud-28.0.3.zip
chown -R root:root nextcloud
cd nextcloud

# Instalación de Nextcloud
php occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud" --database-pass "$DBPASSWORD" --admin-user "$USERNAME" --admin-pass "$PASSWORD" --data-dir /disco
sed -i "s/0 => 'localhost',/0 => '$HOSTNAME',/g" ./config/config.php
sed -i "s/  'overwrite.cli.url' => 'https:\/\/localhost',/  'overwrite.cli.url' => 'http:\/\/$HOSTNAME',/g" ./config/config.php

cd ..
chown -R www-data:www-data nextcloud
chown -R www-data:www-data /disco

# Configuración de Apache
tee -a /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>
ServerName $HOSTNAME
DocumentRoot /var/www/html/nextcloud

<Directory /var/www/html/nextcloud/>
 Require all granted
 Options FollowSymlinks MultiViews
 AllowOverride All
 <IfModule mod_dav.c>
 Dav off
 </IfModule>
</Directory>

ErrorLog /var/log/apache2/$HOSTNAME.error_log
CustomLog /var/log/apache2/$HOSTNAME.access_log common
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite

# Obtención de un certificado de Let's Encrypt
certbot run -d $HOSTNAME --agree-tos --apache -m $EMAIL -n
systemctl restart apache2
