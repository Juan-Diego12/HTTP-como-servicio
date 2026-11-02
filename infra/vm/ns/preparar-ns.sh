#!/bin/bash
# Se ejecuta una vez en la VM ns: IP estatica, zona cloud.local. y actualizacion dinamica con TSIG.
set -e
DOMINIO="cloud.local"; IP="192.168.10.10"
ZONA="/var/lib/bind/db.$DOMINIO"
IFACE=$(ls /sys/class/net | grep -v '^lo$' | head -1)

echo "== Hostname ns"
hostnamectl set-hostname ns
cat > /etc/hosts <<EOF
127.0.0.1	localhost
127.0.1.1	ns.$DOMINIO ns
::1		localhost ip6-localhost ip6-loopback
EOF

echo "== Red: $IP/24 en $IFACE"
rm -f /etc/network/interfaces.d/*
cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $IP/24
EOF
printf 'nameserver 127.0.0.1\nsearch %s\n' "$DOMINIO" > /etc/resolv.conf
ifdown "$IFACE" 2>/dev/null || true
ip addr flush dev "$IFACE"
ifup "$IFACE"

echo "== Llave TSIG ddns-key"
tsig-keygen -a hmac-sha256 ddns-key > /etc/bind/ddns.key
chown root:bind /etc/bind/ddns.key
chmod 640 /etc/bind/ddns.key

echo "== Opciones de Bind9 (autoritativo, sin recursion)"
cat > /etc/bind/named.conf.options <<'EOF'
options {
    directory "/var/cache/bind";
    listen-on { any; };
    listen-on-v6 { none; };
    allow-query { any; };
    recursion no;
    dnssec-validation auto;
};
EOF

echo "== Zona $DOMINIO (en /var/lib/bind para que bind pueda escribir el journal)"
cat > /etc/bind/named.conf.local <<EOF
include "/etc/bind/ddns.key";

zone "$DOMINIO" {
    type master;
    file "$ZONA";
    allow-update { key "ddns-key"; };
};
EOF
cat > "$ZONA" <<EOF
\$TTL 300
@   IN  SOA ns.$DOMINIO. admin.$DOMINIO. (
        1       ; serial
        3600    ; refresh
        900     ; retry
        604800  ; expire
        300 )   ; minimum
@   IN  NS  ns.$DOMINIO.
ns  IN  A   $IP
EOF
rm -f "$ZONA.jnl"
chown bind:bind "$ZONA"

named-checkconf
named-checkzone "$DOMINIO" "$ZONA"
systemctl enable named
systemctl restart named
sleep 2

echo "== Verificacion"
systemctl is-active named
ip -4 -br addr show "$IFACE"
dig @127.0.0.1 +short "ns.$DOMINIO" A
dig @127.0.0.1 "$DOMINIO" SOA +noall +answer
echo "SERVIDOR ns PREPARADO"
