#!/bin/bash
dir_pwd=$(dirname "$0")
dir_pwd=$(cd "$dir_pwd" && pwd)
source ${dir_pwd}/vm2.config
echo -e "auto ${INTERNAL_IF}
iface ${INTERNAL_IF}  inet static
address $INT_IP" >> /etc/network/interfaces
$(/etc/init.d/networking restart > /dev/null)
if [ ! `route | grep default |wc -l` -eq 0 ]
then
$(ip route del default > /dev/null)
$(ip route add default via $GW_IP dev ${INTERNAL_IF})
else
$(ip route add default via $GW_IP dev ${INTERNAL_IF})
fi
$(echo "nameserver 8.8.8.8" >> /etc/resolv.conf)
$(apt-get install vlan > /dev/null)
$(modprobe 8021q)
$(vconfig add $INTERNAL_IF $VLAN > /dev/null)
$(ip addr add  ${APACHE_VLAN_IP} dev ${INTERNAL_IF}.${VLAN})
$(ifconfig ${INTERNAL_IF}.${VLAN} up)
$(apt-get install apache2 -y > /dev/null)
APACHE_IP=$(echo "${APACHE_VLAN_IP}" | cut -d / -f1)
$(sed -i "s@Listen 80@Listen ${APACHE_IP}:80@"  /etc/apache2/ports.conf)
$(/etc/init.d/apache2 restart > /dev/null)


