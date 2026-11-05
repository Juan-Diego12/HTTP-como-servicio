#!/bin/bash
# Uso: configurar-instancia.sh <nombre> <ip>
# Se ejecuta en cada instancia nueva: hostname, identidad unica, IP estatica y sitio propio de Apache.
set -e
NOMBRE="$1"; IP="$2"
DOMINIO="cloud.local"; DNS="192.168.10.10"

[[ "$NOMBRE" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || { echo "Nombre invalido: '$NOMBRE'"; exit 2; }
[[ "$IP" =~ ^192\.168\.10\.[0-9]{1,3}$ ]] || { echo "IP invalida: '$IP'"; exit 2; }
IFACE=$(ls /sys/class/net | grep -v '^lo$' | head -1)

echo "== Hostname $NOMBRE"
hostnamectl set-hostname "$NOMBRE"
cat > /etc/hosts <<EOF
127.0.0.1	localhost
127.0.1.1	$NOMBRE.$DOMINIO $NOMBRE
::1		localhost ip6-localhost ip6-loopback
EOF

echo "== Identidad unica (machine-id y llaves SSH)"
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
systemctl restart ssh || true

echo "== Red: $IP/24 en $IFACE, DNS $DNS"
cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $IP/24
EOF
printf 'nameserver %s\nsearch %s\n' "$DNS" "$DOMINIO" > /etc/resolv.conf
ifdown "$IFACE" 2>/dev/null || true
ip addr flush dev "$IFACE"
ifup "$IFACE"
ip link set "$IFACE" up
for i in $(seq 1 15); do
    ip -br link show "$IFACE" | grep -q ' UP ' && break
    sleep 1
done

echo "== Sitio de Apache: /var/www/$NOMBRE"
mkdir -p "/var/www/$NOMBRE"
cat > "/var/www/$NOMBRE/index.html" <<EOF
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>$NOMBRE.$DOMINIO</title></head>
<body><h1>$NOMBRE.$DOMINIO</h1><p>Instancia lista. Aun no se ha publicado contenido.</p></body></html>
EOF
chown -R www-data:www-data "/var/www/$NOMBRE"
cat > "/etc/apache2/sites-available/$NOMBRE.conf" <<EOF
<VirtualHost *:80>
    ServerName $NOMBRE.$DOMINIO
    ServerAlias $IP
    DocumentRoot /var/www/$NOMBRE
    <Directory /var/www/$NOMBRE>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/$NOMBRE-error.log
    CustomLog \${APACHE_LOG_DIR}/$NOMBRE-access.log combined
</VirtualHost>
EOF
a2dissite -q 000-default || true
a2ensite -q "$NOMBRE"
apache2ctl configtest
systemctl reload apache2

echo "== Verificacion"
hostname
ip -4 -br addr show "$IFACE"
systemctl is-active apache2
echo "INSTANCIA $NOMBRE CONFIGURADA"
