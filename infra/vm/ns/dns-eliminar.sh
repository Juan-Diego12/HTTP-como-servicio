#!/bin/bash
# Uso: dns-eliminar.sh <nombre>   (quita el registro A; si no existe, no es error)
set -e
NOMBRE="$1"; DOMINIO="cloud.local"
[[ "$NOMBRE" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || { echo "Nombre invalido: '$NOMBRE'"; exit 2; }

nsupdate -k /etc/bind/ddns.key <<EOF
server 127.0.0.1
zone $DOMINIO
update delete $NOMBRE.$DOMINIO. A
send
EOF

RESPUESTA=$(dig @127.0.0.1 +short "$NOMBRE.$DOMINIO" A)
if [ -n "$RESPUESTA" ]; then
    echo "La verificacion fallo: $NOMBRE.$DOMINIO todavia responde '$RESPUESTA'"
    exit 1
fi
echo "ELIMINADO: $NOMBRE.$DOMINIO"
