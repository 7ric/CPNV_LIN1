#! /bin/bash

# apt update -y
# apt install git -y
# git clone https://github.com/7ric/CPNV_LIN1.git
# chmod +x CPNV_LIN1/srv-lin1-01.sh
# cd CPNV_LIN1/
# ./srv-lin1-01.sh

#WAN
WAN_NIC=$(ip -o -4 route show to default | awk '{print $5}')

#LAN
LAN_NIC=ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2a;getline}' | grep -v $WAN_NIC

HOSTNAME='srv-lin1-01'
IPV4ADDRESS='10.10.10.11'
IPMASK='255.255.255.0'
DOMAIN='lin1.local'
DNSIPADDRESS='10.10.10.11'

######################################################################################

net_FILE="/etc/network/interfaces"
cat <<EOM >$net_FILE

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The WAN network interface
auto $WAN_NIC
iface $WAN_NIC inet dhcp

# The LAN network interface
auto $LAN_NIC
iface $LAN_NIC inet static
address $IPV4ADDRESS
netmask $IPMASK

EOM

######################################################################################

host_FILE="/etc/hosts"
cat <<EOM >$host_FILE

127.0.0.1       localhost
127.0.1.1       $HOSTNAME.$DOMAIN

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

EOM

######################################################################################

resolve_FILE="/etc/resolv.conf"
cat <<EOM >$resolve_FILE

domain $DOMAIN
search $DOMAIN
nameserver 127.0.0.1
nameserver 1.1.1.1

EOM

######################################################################################

hostnamectl set-hostname $HOSTNAME.$DOMAIN

######################################################################################

systemctl restart networking.service
apt -y update && apt -y upgrade

######################################################################################

echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

apt install -y iptables
iptables -t nat -A POSTROUTING -o ens32 -j MASQUERADE

apt install -y iptables-persistent
/sbin/iptables-save > /etc/iptables/rules.v4

######################################################################################

apt -y install dnsmasq

dnsmasq_FILE="/etc/dnsmasq.conf"
cat <<EOM >$dnsmasq_FILE

address=/srv-lin1-01.lin1.local/srv-lin1-01/10.10.10.11
address=/srv-lin1-02.lin1.local/srv-lin1-02/10.10.10.22
address=/nas-lin1-01.lin1.local/nas-lin1-01/10.10.10.33

ptr-record=11.10.10.10.in-addr.arpa.,"srv-lin1-01"
ptr-record=22.10.10.10.in-addr.arpa.,"srv-lin1-02"
ptr-record=33.10.10.10.in-addr.arpa.,"nas-lin1-01"

EOM

systemctl restart dnsmasq.service

######################################################################################


