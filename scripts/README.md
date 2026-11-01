# Scripts de infraestructura (contrato)

La aplicación los ejecuta en modo real (`MODO=real`) con:

    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\<script>.ps1 <argumentos>

| Script | Argumentos | Qué hace |
|---|---|---|
| `crear-instancia.ps1` | `<nombre> <ip>` | Crea la VM desde ApacheServer.vdi, ajusta hostname e IP y la arranca |
| `registrar-dns.ps1` | `<nombre> <ip>` | Agrega el registro A `<nombre>.cloud.local` con nsupdate |
| `desplegar.ps1` | `<nombre> <ruta.zip>` | Copia el .zip, lo descomprime en el directorio web y recarga Apache |
| `eliminar.ps1` | `<nombre>` | Apaga y borra la VM y quita el registro DNS |

Reglas del contrato:

- Código de salida `0` = éxito; cualquier otro = error (con `exit 1` en PowerShell).
- Lo que el script escribe en la salida se guarda en el log de la app, y las últimas líneas se muestran en el dashboard cuando hay error.
- La ruta del .zip llega absoluta y puede contener espacios (va como un solo argumento).
- La app nunca ejecuta dos scripts al mismo tiempo.
- Si los scripts son `.bat`, se arranca la app con `SCRIPTS_EXT=.bat`.
