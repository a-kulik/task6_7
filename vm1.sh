#!/bin/bash
dir_pwd=$(dirname "$0")
dir_pwd=$(cd "$dir_pwd" && pwd)
source ${dir_pwd}/vm1.config
#-----------lan
echo -e "auto ${INTERNAL_IF}
iface ${INTERNAL_IF}  inet static
address $INT_IP" >> /etc/network/interfaces
$(/etc/init.d/networking restart > /dev/null)
if [ ${EXT_IP} = "DHCP" ]
then
$(dhclient $EXTERNAL_IF -r)
$(dhclient $EXTERNAL_IF)
elif [ ! `route | grep default |wc -l` -eq 0 ]
then
$(ip route del default > /dev/null)
$(ifconfig $EXTERNAL_IF $EXT_IP)
$(ip route add default via $EXT_GW dev $EXTERNAL_IF)
$(echo "nameserver 8.8.8.8" >> /etc/resolv.conf)
else
$(ifconfig $EXTERNAL_IF $EXT_IP)
$(ip route add default via $EXT_GW dev $EXTERNAL_IF)
$(echo "nameserver 8.8.8.8" >> /etc/resolv.conf)
fi
$(apt-get install vlan > /dev/null)
$(modprobe 8021q)
$(vconfig add ${INTERNAL_IF} ${VLAN} > /dev/null)
$(ip addr add ${VLAN_IP} dev ${INTERNAL_IF}.${VLAN})
$(ifconfig ${INTERNAL_IF}.${VLAN} up)
#-----------iptables
$(sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf)
$(sysctl -p > /dev/null)
$(iptables -t nat -A POSTROUTING --out-interface $EXTERNAL_IF  -j MASQUERADE)
$(iptables -A FORWARD --in-interface $INTERNAL_IF -j ACCEPT)
#-----------certs
namehost=`hostname -f 2> /dev/null`
if [ -z "$namehost" ]
then
namehost=`hostname -s`
fi
ipaddr=$(ifconfig ${EXTERNAL_IF} | grep -w inet | awk '{print $2}' | cut -d : -f2)
$(openssl genrsa -out /etc/ssl/certs/root-ca.key 4096 > /dev/null)
$(openssl req -new -x509 -days 365 -key /etc/ssl/certs/root-ca.key -out /etc/ssl/certs/root-ca.crt -subj "/CN=root-ca" > /dev/null)
$(openssl genrsa -out /etc/ssl/certs/web.key 4096 > /dev/null)
echo -e "[ req ]
default_bits = 4096
distinguished_name  = req_distinguished_name
req_extensions     = req_ext

[ req_distinguished_name ]

[ req_ext ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName          = IP:${ipaddr}" > ${dir_pwd}/conf.cnf
$(openssl req -new -key /etc/ssl/certs/web.key -config ${dir_pwd}/conf.cnf -reqexts req_ext -out /etc/ssl/certs/web.csr -subj "/CN=${namehost}" > /dev/null)
$(openssl x509 -req -days 365 -CA /etc/ssl/certs/root-ca.crt -CAkey /etc/ssl/certs/root-ca.key -set_serial 01 -extfile ${dir_pwd}/conf.cnf -extensions req_ext -in /etc/ssl/certs/web.csr -out /etc/ssl/certs/web.crt > /dev/null)
$(cat /etc/ssl/certs/root-ca.crt >> /etc/ssl/certs/web.crt)
$(rm ${dir_pwd}/conf.cnf)
#-----------nginx
$(apt-get install nginx -y > /dev/null)
echo -e "server {
        listen ${ipaddr}:80 default_server;
        return https://${ipaddr}:${NGINX_PORT};
}

server {
        listen ${ipaddr}:${NGINX_PORT} ssl default_server;
        
        ssl_prefer_server_ciphers  on;
        ssl_ciphers  'ECDH !aNULL !eNULL !SSLv2 !SSLv3';
        ssl_certificate  /etc/ssl/certs/web.crt;
        ssl_certificate_key  /etc/ssl/certs/web.key;

        root /var/www/html;
        index index.html index.htm index.nginx-debian.html;
        server_name _;
        location / {

                proxy_pass http://${APACHE_VLAN_IP}:80;
        }

}
" > /etc/nginx/sites-available/default
$(service nginx restart)


