#!/bin/bash -e

interface_name=enp35s0 #enp2s0
vpn_server_ip=1.2.3.4

#install wireguard for centos 7
yum install -y yum-utils epel-release
yum-config-manager --setopt=centosplus.includepkgs=kernel-plus --enablerepo=centosplus --save
sed -e 's/^DEFAULTKERNEL=kernel$/DEFAULTKERNEL=kernel-plus/' -i /etc/sysconfig/kernel
yum install -y kernel-plus wireguard-tools

#install forticlient
yum install -y openfortivpn

#install vpnc
yum install -y vpnc

#intall bind
yum install -y bind bind-utils

#intall qrencode
yum install -y qrencode

#install firewall-cmd
yum install -y firewalld
systemctl enable firewalld

reboot

#set NAT configs
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
sysctl -p /etc/sysctl.d/99-sysctl.conf

#configure DNS
systemctl start named
systemctl enable named

mkdir -p /var/log/named
chown named /var/log/named

cat <<EOT > /etc/named.conf
options {
        listen-on port 53 { any; };
        listen-on-v6 port 53 { none; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        recursing-file  "/var/named/data/named.recursing";
        secroots-file   "/var/named/data/named.secroots";
        allow-query     { localhost; 11.11.0.1/24; };
        recursion yes;
        allow-recursion { localhost; 11.11.0.1/24; };
        forwarders { 1.1.1.1; 8.8.8.8; };
        version "DNS Server";
        dnssec-enable no;
        dnssec-validation no;
        managed-keys-directory "/var/named/dynamic";
        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";

zone "domain1.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.1; 10.10.10.2; };
};

zone "domain2.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.3; 10.10.10.4; };
};

zone "domain3.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.5; 10.10.10.6; };
};

zone "domain4.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.7; 10.10.10.8; };
};

zone "domain5.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.9; 10.10.10.10; };
};

zone "domain6.com" IN {
        type forward;
        forward only;
        forwarders { 10.10.10.11; 10.10.10.12; };
};

zone "." IN {
        type hint;
        file "named.ca";
};

logging {
        channel default_file {
                file "/var/log/named/default.log" versions 3 size 5m;
                severity dynamic;
                print-time yes;
        };
        category default { default_file; };
};
EOT

systemctl restart named

#generate wireguard keys
umask 077
wg genkey | tee server_private_key | wg pubkey > server_public_key
wg genkey | tee client1_private_key | wg pubkey > client1_public_key
wg genkey | tee client2_private_key | wg pubkey > client2_public_key

#configure wireguard server
mkdir -p /etc/wireguard
cat <<EOT > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(cat server_private_key)
Address = 11.11.0.1/24
ListenPort = 51820

[Peer]
PublicKey = $(cat client1_public_key)
AllowedIps = 11.11.0.2/32

[Peer]
PublicKey = $(cat client2_public_key)
AllowedIps = 11.11.0.3/32
EOT

systemctl enable wg-quick@wg0.service
systemctl daemon-reload
systemctl start wg-quick@wg0

#configure forticlient vpn connection
cat <<EOT > /usr/lib/systemd/system/openfortivpn.service
[Unit]
Description=OpenFortiVPN Service

After=network-online.target
Wants=network-online.target

StartLimitIntervalSec=10
StartLimitBurst=5

Documentation=man:openfortivpn(1)

[Service]
User=root
Type=simple

ExecStart=/usr/bin/openfortivpn vpn.domain.com:12345 -u... -p... --persistent=3
Restart=on-failure

DeviceAllow=/dev/ppp
ReadWritePaths=/var/run

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=openfortivpn

KillSignal=SIGTERM

PrivateTmp=yes
DevicePolicy=closed

ProtectSystem=strict
ProtectHome=read-only
ProtectHostname=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes

RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
MemoryDenyWriteExecute=yes
LockPersonality=yes

SystemCallFilter=@system-service @network-io

[Install]
WantedBy=multi-user.target
EOT

systemctl enable openfortivpn
systemctl daemon-reload
systemctl start openfortivpn

#configure ipsec vpn connection
cat <<EOT > /etc/vpnc/default.conf
IPSec gateway 1.2.3.4
IPSec ID GROUPNAME
IPSec secret secret123
Xauth username ...
Xauth password ...
EOT

cat <<EOT > /usr/lib/systemd/system/vpnc.service
[Unit]
Description=VPNC connection
After=network-online.target
Wants=network-online.target

StartLimitIntervalSec=10
StartLimitBurst=5

Documentation=man:vpnc

[Service]
User=root
Type=simple

ExecStart=/usr/sbin/vpnc --no-detach
ExecStop=/usr/sbin/vpnc-disconnect
Restart=always

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=vpnc

KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOT

systemctl enable vpnc
systemctl daemon-reload
systemctl start vpnc

#configure firewall
IPprefix_by_netmask() {
 ipcalc -p 1.1.1.1 $1 | sed -n 's/^PREFIX=\(.*\)/\/\1/p'
}

firewall-cmd --permanent --zone=public --add-interface=$interface_name
firewall-cmd --permanent --zone=public --add-port=12345/udp
firewall-cmd --permanent --zone=public --add-port=22/tcp

firewall-cmd --permanent --new-zone=wg
firewall-cmd --permanent --zone=wg --add-interface=wg0
firewall-cmd --permanent --zone=wg --add-port=22/tcp
firewall-cmd --permanent --zone=wg --add-port=53/tcp
firewall-cmd --permanent --zone=wg --add-port=53/udp

firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -o tun0 -j MASQUERADE
netstat -rn | grep tun0 | awk -F ' ' '{print $1, $3}' | while read -a line; do firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i wg0 -o tun0  -j ACCEPT -d "${line[0]}$(IPprefix_by_netmask "${line[1]}")"; done
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i tun0 -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT

firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -o ppp0 -j MASQUERADE
netstat -rn | grep ppp0 | awk -F ' ' '{print $1, $3}' | while read -a line; do firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -i wg0 -o ppp0  -j ACCEPT -d "${line[0]}$(IPprefix_by_netmask "${line[1]}")"; done
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i ppp0 -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT

firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -o $interface_name -j MASQUERADE
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 2 -i wg0 -o $interface_name  -j ACCEPT
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i $interface_name -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT

firewall-cmd --complete-reload

#generate client configs
cat <<EOT > client1_wg.conf
[Interface]
PrivateKey = $(cat client1_private_key)
Address = 11.11.0.2/32
DNS = 11.11.0.1

[Peer]
PublicKey = $(cat server_public_key)
AllowedIPs = 0.0.0.0/0
Endpoint = $vpn_server_ip:12345
EOT

cat <<EOT > client2_wg.conf
[Interface]
PrivateKey = $(cat client2_private_key)
Address = 11.11.0.3/32
DNS = 11.11.0.1

[Peer]
PublicKey = $(cat server_public_key)
AllowedIPs = 0.0.0.0/0
Endpoint = $vpn_server_ip:12345
EOT

cat client1_wg.conf | qrencode -o - -l M -t UTF8
cat client2_wg.conf | qrencode -o - -l M -t UTF8


#########
yum install -y git gcc
git clone https://gitlab.com/prips/prips.git
cd prips
make

netstat -rn | grep tun0 | awk -F ' ' '{print $1, $3}' | while read -a line; do ./prips "${line[0]}$(IPprefix_by_netmask "${line[1]}")" >> ips-tun0; done
netstat -rn | grep ppp0 | awk -F ' ' '{print $1, $3}' | while read -a line; do ./prips "${line[0]}$(IPprefix_by_netmask "${line[1]}")" >> ips-ppp0; done

sort ips-ppp0 -o ips-ppp0
sort ips-tun0 -o ips-tun0
comm -12 ips-ppp0 ips-tun0


#########

iptables -X
iptables -F
iptables -Z





