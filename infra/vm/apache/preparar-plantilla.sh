#!/bin/bash
# Se ejecuta una vez en la plantilla ApacheServer (con NAT): instala Apache y deja la red sin IP.
set -e
export DEBIAN_FRONTEND=noninteractive

echo "== Instalando apache2 y unzip"
apt-get update -q
apt-get install -y -q apache2 unzip
systemctl enable apache2
echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf -q servername

echo "== Pagina por defecto"
cat > /var/www/html/index.html <<'EOF'
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>HTTPaaS</title></head>
<body><h1>Plantilla HTTPaaS (ApacheServer)</h1></body></html>
EOF

echo "== Nombre de host de la plantilla"
hostnamectl set-hostname apacheserver
cat > /etc/hosts <<'EOF'
127.0.0.1	localhost
127.0.1.1	apacheserver
::1		localhost ip6-localhost ip6-loopback
EOF

echo "== Red: interfaz sin IP (cada instancia recibe la suya al crearse)"
IFACE=$(ls /sys/class/net | grep -v '^lo$' | head -1)
rm -f /etc/network/interfaces.d/*
cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

allow-hotplug $IFACE
iface $IFACE inet manual
EOF

apt-get clean
echo "== Verificacion"
apache2 -v
systemctl is-enabled apache2
unzip -v | head -1
ls -l /usr/local/sbin/
echo "PLANTILLA PREPARADA (interfaz $IFACE)"
