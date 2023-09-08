#! /bin/bash

# Installation sous Debian 12

# sudo -s
# apt update -y && apt install git -y
# git clone https://github.com/7ric/CPNV_LIN1.git
# chmod +x CPNV_LIN1/srv-lin1-01.sh && CPNV_LIN1/srv-lin1-01.sh

# Interface réseau WAN
WAN_NIC=$(ip -o -4 route show to default | awk '{print $5}')

# Interface réseau LAN
LAN_NIC=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2a;getline}' | grep -v $WAN_NIC)

IPMASK='255.255.255.0'
DOMAIN='lin1.local'
DNSIPADDRESS='10.10.10.11'

SRV01='srv-lin1-01'
SRV02='srv-lin1-02'
SRV03='nas-lin1-01'

IPSRV01='10.10.10.11'
IPSRV02='10.10.10.22'
IPSRV03='10.10.10.33'

# IPREVSRV01 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV01"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV01+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV01+="."
  fi
done

# IPREVSRV02 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV02"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV02+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV02+="."
  fi
done

# IPREVSRV03 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV03"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV03+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV03+="."
  fi
done

DHCP_IPSTART='10.10.10.110'
DHCP_IPSTOP='10.10.10.119'

######################################################################################
# Configure the network interfaces

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
address $IPSRV01
netmask $IPMASK

EOM

######################################################################################
# Prevent the DHCP client from rewriting the resolv.conf file
# remove options --> domain-name, domain-name-servers, domain-search, host-name

dhclient_FILE="/etc/dhcp/dhclient.conf"
cat <<EOM >$dhclient_FILE

option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;

send host-name = gethostname();
request subnet-mask, broadcast-address, time-offset, routers,
        dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,
        netbios-name-servers, netbios-scope, interface-mtu,
        rfc3442-classless-static-routes, ntp-servers;

EOM

######################################################################################
# Configure the hosts file

host_FILE="/etc/hosts"
cat <<EOM >$host_FILE

127.0.0.1       localhost
$IPSRV01       $SRV01.$DOMAIN

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

EOM

######################################################################################
# Configure the resolv.conf file

resolve_FILE="/etc/resolv.conf"
cat <<EOM >$resolve_FILE

domain $DOMAIN
search $DOMAIN
nameserver $IPSRV01
nameserver 1.1.1.1

EOM

######################################################################################
# Set the hostname

hostnamectl set-hostname $SRV01.$DOMAIN

######################################################################################
# Restart networking service, update and upgrade packages, and install OpenSSH server

systemctl restart networking.service
apt -y update && apt -y upgrade
apt install -y openssh-server

######################################################################################
# Enable IP forwarding and configure iptables for NAT

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

apt install -y iptables
iptables -t nat -A POSTROUTING -o $WAN_NIC -j MASQUERADE

# installation de iptables-persistent sans interaction

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

apt install -y iptables-persistent
/sbin/iptables-save > /etc/iptables/rules.v4

######################################################################################
# Install dnsmasq and configure it

apt -y install dnsmasq

dnsmasq_FILE="/etc/dnsmasq.conf"
cat <<EOM >$dnsmasq_FILE

address=/$SRV01.$DOMAIN/$SRV01/$IPSRV01
address=/$SRV02.$DOMAIN/$SRV02/$IPSRV02
address=/$SRV03.$DOMAIN/$SRV03/$IPSRV03

ptr-record=$IPREVSRV01.in-addr.arpa.,"$SRV01"
ptr-record=$IPREVSRV02.in-addr.arpa.,"$SRV02"
ptr-record=$IPREVSRV03.in-addr.arpa.,"$SRV03"

domain=$DOMAIN
dhcp-authoritative
dhcp-leasefile=/tmp/dhcp.leases
read-ethers

#Scope DHCP
dhcp-range=$DHCP_IPSTART,$DHCP_IPSTOP,12h

#Netmask
dhcp-option=1,$IPMASK

#DNS
dhcp-option=6,$DNSIPADDRESS

#Route
dhcp-option=3,$IPSRV01

#Bind Interface LAN
interface=$LAN_NIC

EOM

systemctl restart dnsmasq.service

######################################################################################

rm -r CPNV_LIN1/

