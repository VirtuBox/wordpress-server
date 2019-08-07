#!/usr/bin/env bash

################################################################################
##          Installation script for Plesk on Ubuntu                   ##
################################################################################
# Modified by VirtuBox
# Github repository : https://github.com/VirtuBox/ubuntu-plesk-server
# source : https://github.com/plesk/wordpress-edition

# Edit variables for Plesk pre-configuration

email='admin@test.tst'
passwd='Testadmin2019@'
name='admin'
agreement=true

# Plesk Activation Code - provide proper license for initialization, it will be replaced after cloning
# leave as null if not providing key
if [ "$1" = "-i" ]; then
    activation_key="$2"
fi

# Plesk UI View - can be set to Service Provider View (spv) or Power User View (puv)
plesk_ui=spv

# Turn on Fail2Ban, yes or no, Keep in mind you need to provide temp license for initialization for this to work
fail2ban=yes

# Turn on http2
http2=yes

# Turn on Cloning - Set to "on" if this it to make a Golden Image, set to "off" if for remote installation
clone=off

# Check if user is root

if [ "$(id -u)" != "0" ]; then
    echo "Error: You must be root to run this script, please use the root user to install the software."
    echo ""
    echo "Use 'su - root' to login as root"
    exit 1
fi

# Test to make sure all initialization values are set

if [[ -z "$email" || -z "$passwd" || -z "$name" || -z "$agreement" ]]; then
    echo 'One or more variables are undefined. Please check your initialization values.'
    exit 1
fi

##################################
# Welcome
##################################

echo ""
echo "Welcome to ubuntu-plesk-server-setup script."
echo ""

while [ "$#" -gt 0 ]; do
    case "$1" in
    -i | --interactive)
        interactive_install="y"
        ;;
    --travis)
        travis="y"
        ;;
    *) ;;
    esac
    shift
done

##################################
# Menu
##################################
echo "#####################################"
echo "             Warning                 "
echo "#####################################"
echo "This script will only allow ssh connection with ssh-keys"
echo "Make sure you have properly installed your public key in $HOME/.ssh/authorized_keys"
echo "#####################################"
sleep 1
if [ "$interactive_install" = "y" ]; then
    if [ ! -d /etc/mysql ]; then
        echo "#####################################"
        echo "MariaDB server"
        echo "#####################################"
        echo ""
        echo "Do you want to install MariaDB-server ? (y/n)"
        while [[ $mariadb_server_install != "y" && $mariadb_server_install != "n" ]]; do
            echo -e "Select an option [y/n]: "
            read -r mariadb_server_install
        done
        if [[ "$mariadb_server_install" == "y" || "$mariadb_client_install" == "y" ]]; then
            echo ""
            echo "What version of MariaDB Client/Server do you want to install, 10.1, 10.2 or 10.3 ?"
            while [[ $mariadb_version_install != "10.1" && $mariadb_version_install != "10.2" && $mariadb_version_install != "10.3" ]]; do
                echo -e "Select an option [10.1 / 10.2 / 10.3]: "
                read -r mariadb_version_install
            done
        fi
        sleep 1
    fi
else
    if [ -z "$mariadb_server_install" ]; then
        mariadb_version_install="y"
    fi
    if [ -z "$mariadb_version_install" ]; then
        mariadb_version_install="10.3"
    fi
fi
echo ""
echo "#####################################"
echo "Starting server setup in 5 seconds"
echo "use CTRL + C if you want to cancel installation"
echo "#####################################"
sleep 5

##################################
# Update packages
##################################

echo "##########################################"
echo " Updating Packages"
echo "##########################################"
if [ "$travis" != "y" ]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade \
        --option=Dpkg::options::=--force-confdef \
        --option=Dpkg::options::=-force-unsafe-io \
        --option=Dpkg::options::=--force-confold \
        --assume-yes --quiet
    apt-get autoremove -y --purge
    apt-get autoclean -y
fi

##################################
# Useful packages
##################################

echo "##########################################"
echo " Installing useful packages"
echo "##########################################"

DEBIAN_FRONTEND=noninteractive apt-get \
    --option=Dpkg::options::=--force-confmiss \
    --option=Dpkg::options::=--force-confold \
    --assume-yes install haveged curl git unzip zip htop nload nmon ntp gnupg gnupg2 wget pigz tree ccze mycli -y

# ntp time
systemctl enable ntp

# increase history size
export HISTSIZE=10000

##################################
# clone repository
##################################
echo "###########################################"
echo " Cloning Ubuntu-nginx-web-server repository"
echo "###########################################"

if [ ! -d "$HOME/ubuntu-nginx-web-server" ]; then
    git clone https://github.com/VirtuBox/ubuntu-nginx-web-server.git "$HOME/ubuntu-nginx-web-server"
else
    git -C "$HOME/ubuntu-nginx-web-server" pull origin master
fi

##################################
# Secure SSH server
##################################

# get current ssh port
CURRENT_SSH_PORT=$(grep "Port" /etc/ssh/sshd_config | awk -F " " '{print $2}')

# download secure sshd_config
cp -f $HOME/ubuntu-nginx-web-server/etc/ssh/sshd_config /etc/ssh/sshd_config

# change ssh default port
sed -i "s/Port 22/Port $CURRENT_SSH_PORT/" /etc/ssh/sshd_config

# restart ssh service
service ssh restart

##################################
# Sysctl tweaks +  open_files limits
##################################
echo "##########################################"
echo " Applying Linux Kernel tweaks"
echo "##########################################"

cp -f $HOME/ubuntu-nginx-web-server/etc/sysctl.d/60-ubuntu-nginx-web-server.conf /etc/sysctl.d/60-ubuntu-nginx-web-server.conf
sysctl -e -p /etc/sysctl.d/60-ubuntu-nginx-web-server.conf
cp -f $HOME/ubuntu-nginx-web-server/etc/security/limits.conf /etc/security/limits.conf

# Redis transparent_hugepage
echo never > /sys/kernel/mm/transparent_hugepage/enabled

# additional systcl configuration with network interface name
# get network interface names like eth0, ens18 or eno1
# for each interface found, add the following configuration to sysctl
NET_INTERFACES_WAN=$(ip -4 route get 8.8.8.8 | grep -oP "dev [^[:space:]]+ " | cut -d ' ' -f 2)
{
    echo ""
    echo "# do not autoconfigure IPv6 on $NET_INTERFACES_WAN"
    echo "net.ipv6.conf.$NET_INTERFACES_WAN.autoconf = 0"
    echo "net.ipv6.conf.$NET_INTERFACES_WAN.accept_ra = 0"
    echo "net.ipv6.conf.$NET_INTERFACES_WAN.accept_ra = 0"
    echo "net.ipv6.conf.$NET_INTERFACES_WAN.autoconf = 0"
    echo "net.ipv6.conf.$NET_INTERFACES_WAN.accept_ra_defrtr = 0"
} >> /etc/sysctl.d/60-ubuntu-nginx-web-server.conf

##################################
# Add MariaDB 10.3 repository
##################################

if [[ "$mariadb_server_install" == "y" || "$mariadb_client_install" == "y" ]]; then
    if [ ! -f /etc/apt/sources.list.d/mariadb.list ]; then
        echo ""
        echo "##########################################"
        echo " Adding MariaDB $mariadb_version_install repository"
        echo "##########################################"

        wget -qO mariadb_repo_setup https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
        chmod +x mariadb_repo_setup
        ./mariadb_repo_setup --mariadb-server-version=$mariadb_version_install --skip-maxscale -y
        rm mariadb_repo_setup
        apt-get update -qq

    fi

fi

##################################
# MariaDB 10.3 install
##################################

# install mariadb server non-interactive way
if [ "$mariadb_server_install" = "y" ]; then
    if [ ! -d /etc/mysql ]; then
        echo ""
        echo "##########################################"
        echo " Installing MariaDB server $mariadb_version_install"
        echo "##########################################"

        # generate random password
        MYSQL_ROOT_PASS=""
        export DEBIAN_FRONTEND=noninteractive                             # to avoid prompt during installation
        debconf-set-selections <<<"mariadb-server-${mariadb_version_install} mysql-server/root_password password ${MYSQL_ROOT_PASS}"
        debconf-set-selections <<<"mariadb-server-${mariadb_version_install} mysql-server/root_password_again password ${MYSQL_ROOT_PASS}"
        # install mariadb server
        DEBIAN_FRONTEND=noninteractive apt-get install -qq mariadb-server # -qq implies -y --force-yes
        ## mysql_secure_installation non-interactive way
        # remove anonymous users
        mysql -e "DROP USER ''@'localhost'" >/dev/null 2>&1
        mysql -e "DROP USER ''@'$(hostname)'" >/dev/null 2>&1
        # remove test database
        mysql -e "DROP DATABASE test" >/dev/null 2>&1
        # flush privileges
        mysql -e "FLUSH PRIVILEGES"
    fi
fi

##################################
# MariaDB tweaks
##################################

if [ "$mariadb_server_install" = "y" ]; then
    echo "##########################################"
    echo " Optimizing MariaDB configuration"
    echo "##########################################"

    cp -f $HOME/ubuntu-nginx-web-server/etc/mysql/my.cnf /etc/mysql/my.cnf

    # stop mysql service to apply new InnoDB log file size
    service mysql stop

    # mv previous log file
    mv /var/lib/mysql/ib_logfile0 /var/lib/mysql/ib_logfile0.bak
    mv /var/lib/mysql/ib_logfile1 /var/lib/mysql/ib_logfile1.bak

    # increase mariadb open_files_limit
    cp -f $HOME/ubuntu-nginx-web-server/etc/systemd/system/mariadb.service.d/limits.conf /etc/systemd/system/mariadb.service.d/limits.conf

    # reload daemon
    systemctl daemon-reload

    # restart mysql
    service mysql start

fi

######### Do not edit below this line ###################
#########################################################

# Download Plesk AutoInstaller

echo "Downloading Plesk Auto-Installer"
wget -O plesk-installer https://installer.plesk.com/plesk-installer
echo

# Make Installed Executable

echo "Making Plesk Auto-Installer Executable"
chmod +x ./plesk-installer
echo

# Install Plesk testing with Required Components

echo "Starting Plesk Installation"
if ! { ./plesk-installer install testing --components panel bind fail2ban \
    l10n pmm mysqlgroup docker repair-kit \
    roundcube spamassassin postfix dovecot \
    proftpd awstats mod_fcgid webservers git \
    nginx php7.2 php7.3 config-troubleshooter \
    psa-firewall cloudflare wp-toolkit letsencrypt \
    imunifyav sslit; }; then
    echo
    echo "An error occurred! The installation of Plesk failed. Please see logged lines above for error handling!"
    exit 1
fi
#./plesk-installer --select-product-id plesk --select-release-latest --installation-type Recommended

# Enable VPS Optimized Mode
echo "Enable VPS Optimized Mode"
plesk bin vps_optimized --turn-on
echo

# If Ruby and NodeJS are needed then run install Plesk using the following command:
# ./plesk-installer install plesk --preset Recommended --with fail2ban modsecurity spamassassin mailman psa-firewall pmm health-monitor passenger ruby nodejs gems-preecho
echo ""
echo ""

# Initalize Plesk before Additional Configuration
# https://docs.plesk.com/en-US/onyx/cli-linux/using-command-line-utilities/init_conf-server-configuration.37843/

# Install Plesk Activation Key if provided
# https://docs.plesk.com/en-US/onyx/cli-linux/using-command-line-utilities/license-license-keys.71029/

if [[ -n "$activation_key" ]]; then
    echo "Starting initialization process of your Plesk server"
    /usr/sbin/plesk bin init_conf --init -email "$email" -passwd "$passwd" -name "$name" -license_agreed "$agreement"
    echo "Installing Plesk Activation Code"
    /usr/sbin/plesk bin license --install "$activation_key"
    echo
else
    echo "Starting initialization process of your Plesk server"
    /usr/sbin/plesk bin init_conf --init -email "$email" -passwd "$passwd" -name "$name" -license_agreed "$agreement" -trial_license true
fi

# Configure Service Provider View On

if [ "$plesk_ui" = "spv" ]; then
    echo "Setting to Service Provider View"
    /usr/sbin/plesk bin poweruser --off
    echo
else
    echo "Setting to Power user View"
    /usr/sbin/plesk bin poweruser --on
    echo
fi

# Make sure Plesk UI and Plesk Update ports are allowed

echo "Setting Firewall to allow proper ports."
iptables -I INPUT -p tcp --dport 21 -j ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -p tcp --dport 465 -j ACCEPT
iptables -I INPUT -p tcp --dport 993 -j ACCEPT
iptables -I INPUT -p tcp --dport 995 -j ACCEPT
iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
iptables -I INPUT -p tcp --dport 8447 -j ACCEPT
iptables -I INPUT -p tcp --dport 8880 -j ACCEPT

echo

# Enable Modsecurity
# https://docs.plesk.com/en-US/onyx/administrator-guide/server-administration/web-application-firewall-modsecurity.73383/

#echo "Turning on Modsecurity WAF Rules"
#plesk bin server_pref --update-web-app-firewall -waf-rule-engine on -waf-rule-set tortix -waf-rule-set-update-period daily -waf-config-preset tradeoff
#echo

# Enable Fail2Ban and Jails
# https://docs.plesk.com/en-US/onyx/cli-linux/using-command-line-utilities/ip_ban-ip-address-banning-fail2ban.73594/

if [ "$fail2ban" = "yes" ]; then
    echo "Configuring Fail2Ban and its Jails"
    /usr/sbin/plesk bin ip_ban --enable
    /usr/sbin/plesk bin ip_ban --enable-jails ssh
    /usr/sbin/plesk bin ip_ban --enable-jails recidive
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-proftpd
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-postfix
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-dovecot
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-roundcube
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-apache-badbot
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-panel
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-wordpress
    /usr/sbin/plesk bin ip_ban --enable-jails plesk-apache
    echo
fi

# Turn on http2
# https://docs.plesk.com/en-US/onyx/administrator-guide/web-servers/apache-and-nginx-web-servers-linux/http2-support-in-plesk.76461/

if [ "$http2" = "yes" ]; then
    echo "Activating http2"
    /usr/sbin/plesk bin http2_pref --enable
    echo
fi

# Enable PCI Compliance
/usr/sbin/plesk sbin pci_compliance_resolver --enable all

# Install Bundle Extensions
# https://docs.plesk.com/en-US/onyx/cli-linux/using-command-line-utilities/extension-extensions.71031/

echo "Installing Requested Plesk Extensions"
echo
echo "Installing SEO Toolkit"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/2ae9cd0b-bc5c-4464-a12d-bd882c651392-xovi/download
echo
echo "Installing Revisium Antivirus for Websites"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/b71916cf-614e-4b11-9644-a5fe82060aaf-revisium-antivirus/download
echo ""
echo "Installing Plesk Migration Manager"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/bebc4866-d171-45fb-91a6-4b139b8c9a1b-panel-migrator/download
echo
echo "Installing Code Editor"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/e789f164-5896-4544-ab72-594632bcea01-rich-editor/download
echo
echo "Installing MagicSpam"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/b49f9b1b-e8cf-41e1-bd59-4509d92891f7-magicspam/download
echo
echo "Installing Panel.ini Extension"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/05bdda39-792b-441c-9e93-76a6ab89c85a-panel-ini-editor/download
echo
echo "Installing Schedule Backup list Extension"
/usr/sbin/plesk bin extension --install-url https://ext.plesk.com/packages/17ffcf2a-8e8f-4cb2-9265-1543ff530984-scheduled-backups-list/download
echo
echo "Set custom panel.ini config"
wget https://raw.githubusercontent.com/VirtuBox/ubuntu-plesk-onyx/master/usr/local/psa/admin/conf/panel.ini -O /usr/local/psa/admin/conf/panel.ini
echo

# Prepair for Cloning
# https://docs.plesk.com/en-US/onyx/cli-linux/using-command-line-utilities/cloning-server-cloning-settings.71035/

if [ "$clone" = "on" ]; then
    echo "Setting Plesk Cloning feature."
    /usr/sbin/plesk bin cloning --update -prepare-public-image true -reset-license true -skip-update true
    echo "Plesk initialization will be wiped on next boot. Ready for Cloning."
else
    echo "Here is your login"
    /usr/sbin/plesk login
fi

echo
echo "Your Plesk WordPress Edition is complete."
echo "Thank you for using the WordPress Edition Cookbook"
echo