#!/bin/bash
# Envoltorio: ejecuta el comando recibido y guarda su salida y su codigo en /tmp/httpaas-salida.txt.
# Los scripts de PowerShell traen ese archivo con "guestcontrol copyfrom".
SALIDA=/tmp/httpaas-salida.txt
"$@" > "$SALIDA" 2>&1
CODIGO=$?
echo "EXIT=$CODIGO" >> "$SALIDA"
exit $CODIGO
