#!/bin/bash
# Uso: dns-registrar.sh <nombre> <ip>   (agrega o reemplaza el registro A con nsupdate + TSIG)
set -e
NOMBRE="$1"; IP="$2"; DOMINIO="cloud.local"
[[ "$NOMBRE" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || { echo "Nombre invalido: '$NOMBRE'"; exit 2; }
[[ "$IP" =~ ^192\.168\.10\.[0-9]{1,3}$ ]] || { echo "IP invalida: '$IP'"; exit 2; }

nsupdate -k /etc/bind/ddns.key <<EOF
server 127.0.0.1
zone $DOMINIO
update delete $NOMBRE.$DOMINIO. A
update add $NOMBRE.$DOMINIO. 300 A $IP
send
EOF

RESPUESTA=$(dig @127.0.0.1 +short "$NOMBRE.$DOMINIO" A)
if [ "$RESPUESTA" != "$IP" ]; then
    echo "La verificacion fallo: $NOMBRE.$DOMINIO responde '$RESPUESTA'"
    exit 1
fi
echo "REGISTRADO: $NOMBRE.$DOMINIO -> $IP"
