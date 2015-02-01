#!/bin/bash

function is_os_ubuntu {
    { 
        type -t lsb_release || return 1
        lsb_release -si | grep -i ubuntu && return 0    
        return 1
    } > /dev/null 2>&1
}

function is_user_root {
    [ "$(id -u)" -eq 0 ] || return 1
    return 0 
}

function is_postgres_installed {
    {
       id -u postgres || return 1
       type -t createdb || return 1
       type -t createuser || return 1
       return 0 
    } > /dev/null 2>&1
}

function postgresql_user_exists {
    sudo -i -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'" | grep -q 1 && return 0
    return 1
}

function ask_sure {
    while read -r -n 1 -s ANSWER;
    do
        if [[ $ANSWER = [YyNn] ]]; then
            [[ $ANSWER = [Yy] ]] && RETVAL=0
            [[ $ANSWER = [Nn] ]] && RETVAL=1
            break
        fi
    done
    
    echo # For optics ;)
    
    return $RETVAL
}


function fetch_drupal7_latest_dl_link {
    wget -q -O - https://www.drupal.org/project/drupal | grep -P -o 'http://ftp.drupal.org/files/projects/drupal-7.\d+.tar.gz'
}

function extract_d7_minor_version_from_dl_link {
    basename "$1" | cut -d. -f2
}


# Creation user SQL
# Creation BDD
# Download Drupal
# Inflate archive
# Remove archive
# Download french translation
# Remove *.txt files
# Creation vhost Apache
if ! is_os_ubuntu; then
    echo "Error: this script is only Ubuntu-compatible."
    exit 1
fi

if ! is_user_root; then
    echo "Error: this script must be run with root privileges."
    exit 2
fi

if ! is_postgres_installed; then
    echo "Error: this script needs Postgresql to run."
    exit 3
fi

read -er -p "Project name : " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: the project must be named."
    exit 3
fi

read -er -p "Server name [$PROJECT_NAME.$(hostname)] : " SERVER_NAME
if [ -z "$SERVER_NAME" ]; then
    SERVER_NAME="$PROJECT_NAME.$(hostname)"
fi

read -er -p "Installation directory [$(pwd)] : " INSTALL_DIR
if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR=$(pwd)
fi

read -er -p "Postgresql user to create [${PROJECT_NAME}sql] : " PGSQL_USER
if [ -z "$PGSQL_USER" ]; then
    PGSQL_USER="${PROJECT_NAME}sql"
fi

read -er -p "Postgresql database to create [$PROJECT_NAME] : " PGSQL_DB
if [ -z "$PGSQL_DB" ]; then
    PGSQL_DB="$PROJECT_NAME"
fi

INSTALL_DIR=$(echo "$INSTALL_DIR" | sed -e 's/\/*$//') # Remove trailing slashes
PROJECT_DIR="$INSTALL_DIR/$PROJECT_NAME" 
VHOST_FILENAME="/etc/apache2/sites-available/$SERVER_NAME.conf"

echo
echo "Drupal will be deployed in the following directory : $PROJECT_DIR"
echo "The project will use the following server name : $SERVER_NAME"
echo "The following Postgresql user will be created : $PGSQL_USER"
echo "The following Postgresql database will be created : $PGSQL_DB"
echo "The following virtual host file will be created : $VHOST_FILENAME"
echo
echo -n "Are these information valid [y/n] ? "
if ! ask_sure; then
    echo "Aborting."
    exit 8
fi

echo # For optics ;)


# Check installation directory
if [ ! -e "$INSTALL_DIR" ]; then
    echo -n "$INSTALL_DIR does not exist. Do you want to create it [y/n] ? "
    if ask_sure; then
        if ! mkdir "$INSTALL_DIR" > /dev/null 2>&1; then
            echo "Error: cannot create $INSTALL_DIR directory."
            exit 4
        fi
    else
        echo "Error: cannot deploy Drupal into non existing directory."
        exit 5
    fi
elif [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: $INSTALL_DIR is not a directory."
    exit 6 
fi

# Check project directory
if [ ! -e "$PROJECT_DIR" ]; then
    echo -n "$PROJECT_DIR does not exist. Do you want to create it [y/n] ? "
    if ask_sure; then
        if ! mkdir "$PROJECT_DIR" > /dev/null 2>&1; then
            echo "Error: cannot create $PROJECT_DIR directory."
            exit 4
        fi
    else
        echo "Error: cannot deploy Drupal into non existing directory."
        exit 5
    fi
elif [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: $PROJECT_DIR is not a directory."
    exit 5
elif [ "$(ls -A "$PROJECT_DIR")" ]; then
    echo "Error: $PROJECT_DIR is not an empty directory."
    exit 6
fi

# Check Postgresql user
if postgresql_user_exists "$PGSQL_USER"; then
    echo "Error: $PGSQL_USER is already a Postgresql user."
    exit 10
fi
echo "Creating Postgresql user $PGSQL_USER..."
sudo -i -u postgres createuser --pwprompt --encrypted --no-createrole --no-createdb "$PGSQL_USER"
echo "Creating Postgresql database $PGSQL_DB with owner $PGSQL_USER..."
sudo -i -u postgres createdb --encoding=UTF8 --owner="$PGSQL_USER" "$PGSQL_DB"

# Download Drupal
echo "Downloading Drupal..."
D7_DL_LINK=$(fetch_drupal7_latest_dl_link)
wget "$D7_DL_LINK" -O /tmp/drupal.tar.gz

echo "Inflating archive..."
D7_MINOR_VERSION=$(extract_d7_minor_version_from_dl_link "$D7_DL_LINK")
tar xf /tmp/drupal.tar.gz -C /tmp

echo "Copying files..."
cp -r "/tmp/drupal-7.$D7_MINOR_VERSION/." "$PROJECT_DIR"

if [ -d "/tmp/drupal-7.$D7_MINOR_VERSION" ]; then
    rm -Rf "/tmp/drupal-7.$D7_MINOR_VERSION"
fi 

echo "Downloading French translation..."
wget "http://ftp.drupal.org/files/translations/7.x/drupal/drupal-7.$D7_MINOR_VERSION.fr.po" -O "$PROJECT_DIR/profiles/standard/translations/drupal-7.$D7_MINOR_VERSION.fr.po"

echo "Generating Apache virtual host file $VHOST_FILENAME..."
cat > "$VHOST_FILENAME" <<EOM
<VirtualHost *:80>
    ServerName $SERVER_NAME
    DocumentRoot $PROJECT_DIR
    
    <Directory $PROJECT_DIR>
        Options -Indexes
        AllowOverride all
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/$SERVER_NAME.error.log
    CustomLog \${APACHE_LOG_DIR}/$SERVER_NAME.access.log combined
</VirtualHost>
EOM
a2ensite "$SERVER_NAME"
service apache2 reload


echo # For optics ;)
echo # For optics ;)
echo # For optics ;)

echo "Drupal has been deployed in $PROJECT_DIR directory."
echo "Database $PGSQL_DB with owner $PGSQL_USER has been created."
IP=$(ip -4 -o addr show eth0 | awk '{ print $4; }' | cut -d/ -f1)
echo -e "Add the following line to your /etc/hosts file : $IP\t$SERVER_NAME"
echo 'Done.'

