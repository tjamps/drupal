#!/bin/bash
#
# Automate installation of xhprof on a Drupal development machine.
#
# Tested on : Ubuntu Server 14.04.1 LTS
#

echo "Installing xhprof requires a vhost to be created."
echo "You are now required to give a hostname for the vhost".
echo "If you press Enter immediatly, the value between square brackets will be used."
read -er -p "Host name [xhprof.$(hostname)] : " HOST_NAME
if [ -z "$HOST_NAME" ]; then
    HOST_NAME="xhprof.$(hostname)"
fi

VHOST_FILE="/etc/apache2/sites-available/$HOST_NAME.conf"
if [ -f "$VHOST_FILE" ]; then
    echo "Error: the file $VHOST_FILE already exists."
    exit 1
fi


echo # For optics ;)
echo "The installation will now begin. You will be asked your password because sudo is used."
echo -n "Press Enter to continue..."
read -r -n 1 -s
echo # For optics ;)

cd

# Install extension
sudo apt-get update && sudo apt-get install build-essential php5-dev
wget http://pecl.php.net/get/xhprof-0.9.4.tgz
tar xf xhprof-0.9.4.tgz
cd xhprof-0.9.4/extension
phpize
./configure
make
sudo make install
(
    echo '[xhprof]'
    echo 'extension=xhprof.so'
    echo 'xhprof.output_dir="/tmp/xhprof"'
) | sudo tee /etc/php5/mods-available/xhprof.ini > /dev/null

sudo php5enmod xhprof
sudo service apache2 restart

cd
sudo mv xhprof-0.9.4 /usr/share

(
    echo "<VirtualHost *:80>"
    echo "    ServerName $HOST_NAME"
    echo "    DocumentRoot /usr/share/xhprof-0.9.4/xhprof_html"
    echo "    <Directory /usr/share/xhprof-0.9.4/xhprof_html>"
    echo "        Options -Indexes"
    echo "        AllowOverride all"
    echo "        Require all granted"
    echo "    </Directory>"
    echo ""    
    echo "    ErrorLog \${APACHE_LOG_DIR}/$HOST_NAME.error.log"
    echo ""    
    echo "    CustomLog \${APACHE_LOG_DIR}/$HOST_NAME.access.log combined"
    echo "</VirtualHost>"
    echo ""
) | sudo tee "$VHOST_FILE" > /dev/null

sudo a2ensite $HOST_NAME
sudo service apache2 restart


echo # For optics ;)
echo # For optics ;)
echo # For optics ;)

IP=$(ip -4 -o addr show eth0 | awk '{ print $4; }' | cut -d/ -f1)

if php -m | grep -qi xhprof; then
    echo 'Success !'
    echo 'Go to Admin > Configuration > Devel Settings and check the "Enable profiling of all page views and drush requests."'
    echo 'Use the following values in the form : '
    echo '  xhprof directory: /usr/share/xhprof-0.9.4'
    echo "  XHProf URL  : $HOST_NAME"
    echo
    echo -e "You also need to add this line to your /etc/hosts : $IP\t$HOST_NAME"
else
    echo 'Something went wrong :s...'
fi
