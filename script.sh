#!/bin/bash
## Do not modify this file. You will lose the ability to install and auto-update!

set -e # Exit immediately if a command exits with a non-zero status
## $1 could be empty, so we need to disable this check
#set -u # Treat unset variables as an error and exit
set -o pipefail # Cause a pipeline to return the status of the last command that exited with a non-zero status
CDN="https://cdn.coollabs.io/coolify"
DATE=$(date +"%Y%m%d-%H%M%S")

VERSION="1.6"
DOCKER_VERSION="26.0"
# TODO: Ask for a user
CURRENT_USER=$USER

mkdir -p /data/delivery/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance,sentinel}
mkdir -p /data/delivery/ssh/{keys,mux}
mkdir -p /data/delivery/proxy/dynamic

chown -R 1001:root /data/delivery
chmod -R 700 /data/delivery

INSTALLATION_LOG_WITH_DATE="/data/delivery/source/installation-${DATE}.log"

exec > >(tee -a $INSTALLATION_LOG_WITH_DATE) 2>&1

OS_TYPE=$(grep -w "ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
ENV_FILE="/data/delivery/source/.env"

# Check if the OS is manjaro, if so, change it to arch
if [ "$OS_TYPE" = "manjaro" ] || [ "$OS_TYPE" = "manjaro-arm" ]; then
    OS_TYPE="arch"
fi

# Check if the OS is Asahi Linux, if so, change it to fedora
if [ "$OS_TYPE" = "fedora-asahi-remix" ]; then
    OS_TYPE="fedora"
fi

# Check if the OS is popOS, if so, change it to ubuntu
if [ "$OS_TYPE" = "pop" ]; then
    OS_TYPE="ubuntu"
fi

# Check if the OS is linuxmint, if so, change it to ubuntu
if [ "$OS_TYPE" = "linuxmint" ]; then
    OS_TYPE="ubuntu"
fi

#Check if the OS is zorin, if so, change it to ubuntu
if [ "$OS_TYPE" = "zorin" ]; then
    OS_TYPE="ubuntu"
fi

if [ "$OS_TYPE" = "arch" ] || [ "$OS_TYPE" = "archarm" ]; then
    OS_VERSION="rolling"
else
    OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
fi

# Install xargs on Amazon Linux 2023 - lol
if [ "$OS_TYPE" = 'amzn' ]; then
    dnf install -y findutils >/dev/null
fi

if [ $EUID != 0 ]; then
    echo "Please run as root"
    exit
fi

case "$OS_TYPE" in
arch | ubuntu | debian | raspbian | centos | fedora | rhel | ol | rocky | sles | opensuse-leap | opensuse-tumbleweed | almalinux | amzn | alpine) ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, Alpine Linux, or SLES based operating systems for now."
    exit
    ;;
esac

# Overwrite LATEST_VERSION if user pass a version number
if [ "$1" != "" ]; then
    LATEST_VERSION=$1
    LATEST_VERSION="${LATEST_VERSION,,}"
    LATEST_VERSION="${LATEST_VERSION#v}"
fi

echo -e "\033[0;35m"
cat << "EOF"
____       _ _                     
|  _ \  ___| (_)_   _____ _ __ _   _
| | | |/ _ \ | \ \ / / _ \ '__| | | |
| |_| |  __/ | |\ V /  __/ |  | |_| |
|____/ \___|_|_| \_/ \___|_|   \__, |
                               |___/
EOF
echo -e "\033[0m"
echo -e "Welcome to Delivery Installer!"
echo -e "This script will install everything for you. Sit back and relax."
echo -e "---------------------------------------------"
echo "| Operating System  | $OS_TYPE $OS_VERSION"
echo "| Docker            | $DOCKER_VERSION"
echo -e "---------------------------------------------\n"
echo -e "1. Installing required packages (curl, wget, git, jq). "

case "$OS_TYPE" in
arch)
    pacman -Sy --noconfirm --needed curl wget git jq >/dev/null || true
    ;;
alpine)
    sed -i '/^#.*\/community/s/^#//' /etc/apk/repositories
    apk update >/dev/null
    apk add curl wget git jq >/dev/null
    ;;
ubuntu | debian | raspbian)
    apt-get update -y >/dev/null
    apt-get install -y curl wget git jq >/dev/null
    ;;
centos | fedora | rhel | ol | rocky | almalinux | amzn)
    if [ "$OS_TYPE" = "amzn" ]; then
        dnf install -y wget git jq >/dev/null
    else
        if ! command -v dnf >/dev/null; then
            yum install -y dnf >/dev/null
        fi
        if ! command -v curl >/dev/null; then
            dnf install -y curl >/dev/null
        fi
        dnf install -y wget git jq >/dev/null
    fi
    ;;
sles | opensuse-leap | opensuse-tumbleweed)
    zypper refresh >/dev/null
    zypper install -y curl wget git jq >/dev/null
    ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
    exit
    ;;
esac


echo -e "2. Check OpenSSH server configuration. "

# Detect OpenSSH server
SSH_DETECTED=false
if [ -x "$(command -v systemctl)" ]; then
    if systemctl status sshd >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    elif systemctl status ssh >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    fi
elif [ -x "$(command -v service)" ]; then
    if service sshd status >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    elif service ssh status >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    fi
fi


if [ "$SSH_DETECTED" = "false" ]; then
    echo " - OpenSSH server not detected. Installing OpenSSH server."
    case "$OS_TYPE" in
    arch)
        pacman -Sy --noconfirm openssh >/dev/null
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    alpine)
        apk add openssh >/dev/null
        rc-update add sshd default >/dev/null 2>&1
        service sshd start >/dev/null 2>&1
        ;;
    ubuntu | debian | raspbian)
        apt-get update -y >/dev/null
        apt-get install -y openssh-server >/dev/null
        systemctl enable ssh >/dev/null 2>&1
        systemctl start ssh >/dev/null 2>&1
        ;;
    centos | fedora | rhel | ol | rocky | almalinux | amzn)
        if [ "$OS_TYPE" = "amzn" ]; then
            dnf install -y openssh-server >/dev/null
        else
            dnf install -y openssh-server >/dev/null
        fi
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    sles | opensuse-leap | opensuse-tumbleweed)
        zypper install -y openssh >/dev/null
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    *)
        echo "###############################################################################"
        echo "WARNING: Could not detect and install OpenSSH server - this does not mean that it is not installed or not running, just that we could not detect it."
        echo -e "Please make sure it is installed and running, otherwise Delivery cannot connect to the host system. \n"
        echo "###############################################################################"
        exit 1
        ;;
    esac
    echo " - OpenSSH server installed successfully."
    SSH_DETECTED=true
fi

# Detect SSH PermitRootLogin
SSH_PERMIT_ROOT_LOGIN=$(sshd -T | grep -i "permitrootlogin" | awk '{print $2}') || true
if [ "$SSH_PERMIT_ROOT_LOGIN" = "yes" ] || [ "$SSH_PERMIT_ROOT_LOGIN" = "without-password" ] || [ "$SSH_PERMIT_ROOT_LOGIN" = "prohibit-password" ]; then
    echo " - SSH PermitRootLogin is enabled."
else
    echo " - SSH PermitRootLogin is disabled."
fi

echo -e "8. Checking for SSH key for localhost access."
if [ ! -f ~/.ssh/authorized_keys ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    touch ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

set +e
IS_DELIVERY_VOLUME_EXISTS=$(docker volume ls | grep delivery-db | wc -l)
set -e

if [ "$IS_DELIVERY_VOLUME_EXISTS" -eq 0 ]; then
    echo " - Generating SSH key."
    ssh-keygen -t ed25519 -a 100 -f /data/delivery/ssh/keys/id.$CURRENT_USER@host.docker.internal -q -N "" -C delivery
    chown 1001 /data/delivery/ssh/keys/id.$CURRENT_USER@host.docker.internal
    sed -i "/delivery/d" ~/.ssh/authorized_keys
    cat /data/delivery/ssh/keys/id.$CURRENT_USER@host.docker.internal.pub >> ~/.ssh/authorized_keys
    rm -f /data/delivery/ssh/keys/id.$CURRENT_USER@host.docker.internal.pub
fi

chown -R 1001:root /data/delivery
chmod -R 700 /data/delivery
