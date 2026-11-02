#!/bin/bash
# Uso: desplegar-sitio.sh <nombre> <ruta-del-zip-en-la-vm>
# Reemplaza el contenido de /var/www/<nombre> por el del .zip y recarga Apache.
set -e
NOMBRE="$1"; ZIP="$2"; DESTINO="/var/www/$NOMBRE"

[ -f "$ZIP" ] || { echo "No existe el archivo $ZIP"; exit 2; }
[ -d "$DESTINO" ] || { echo "No existe $DESTINO (la instancia no esta configurada)"; exit 2; }

TMP=$(mktemp -d)
unzip -q "$ZIP" -d "$TMP"

# Si todo viene dentro de una sola carpeta (se comprimio la carpeta), se usa su contenido.
ORIGEN="$TMP"
if [ "$(ls -A "$TMP" | wc -l)" -eq 1 ] && [ -d "$TMP/$(ls -A "$TMP")" ]; then
    ORIGEN="$TMP/$(ls -A "$TMP")"
fi

find "$DESTINO" -mindepth 1 -delete
cp -a "$ORIGEN"/. "$DESTINO"/
chown -R www-data:www-data "$DESTINO"
find "$DESTINO" -type d -exec chmod 755 {} +
find "$DESTINO" -type f -exec chmod 644 {} +
rm -rf "$TMP" "$ZIP"
systemctl reload apache2

echo "== Contenido publicado en $DESTINO"
ls -la "$DESTINO"
echo "CONTENIDO PUBLICADO EN $NOMBRE"
