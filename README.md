# HTTPaaS: servicio administrado de páginas y aplicaciones web

Nota parcial 3, Computación en la Nube 2026-2, Universidad del Quindío.

Aplicación web en Go que funciona como punto de acceso y orquestador: recibe la solicitud de un nuevo
servidor Apache, crea su máquina virtual desde el disco multiconexión `ApacheServer.vdi`, la registra en la
zona `cloud.local.` del servidor Bind9 y publica el contenido `.zip` del usuario. El dashboard muestra las
instancias con su enlace, IP, hostname, fecha y estado.

## Estructura

```
main.go                     arranque y configuración
internal/orquestador/       validaciones, IPs, estados, persistencia JSON y llamadas a los scripts
internal/web/               API JSON
web/static/                 interfaz (HTML, CSS y JavaScript)
scripts/                    scripts de infraestructura (contrato en scripts/README.md)
data/instancias.json        estado de las instancias (se crea al ejecutar)
uploads/                    .zip recibidos (se crea al ejecutar)
```

## Ejecución

Requiere Go 1.22 o superior. Desde la raíz del repositorio:

```powershell
go run .                         # modo simulado (por defecto), sin VMs
$env:MODO="real"; go run .       # modo real: llama a los scripts de scripts/
```

Abrir http://127.0.0.1:8080.

| Variable | Por defecto | Uso |
|---|---|---|
| `MODO` | `simulado` | `simulado` o `real` |
| `PORT` | `8080` | puerto de la app |
| `DOMINIO` | `cloud.local` | dominio de la zona |
| `RED` | `192.168.10` | red host-only; las instancias usan `.30` a `.254` |
| `SCRIPTS_DIR` | `scripts` | carpeta de los scripts |
| `SCRIPTS_EXT` | `.ps1` | `.ps1` o `.bat` |
| `SCRIPTS_TIMEOUT` | `25` | minutos máximos por script |
| `VBOXMANAGE` | el del PATH | ruta de VBoxManage (modo real) |

## Ciclo de vida de una instancia

```
Aceptar -> creando -> lista -> (Publicar) -> publicando -> publicada
                  \-> error              \-> vuelve a lista/publicada con el mensaje de error
Eliminar -> eliminando -> (se borra de la lista)   o   error
```

- **Aceptar** valida el nombre (hostname RFC 1123 en minúsculas, único y no reservado). En modo real también verifica que no exista una VM con ese nombre en VirtualBox (sin distinguir mayúsculas). Asigna la primera IP del rango que no use otra instancia y que no responda ping, y ejecuta `crear-instancia` y `registrar-dns`.
- **Publicar** valida el `.zip` (formato, que no esté vacío y sin rutas peligrosas) y ejecuta `desplegar`.
- **Eliminar** ejecuta `eliminar` y quita la instancia de la lista.
- Las operaciones de infraestructura se ejecutan en segundo plano y de una en una; el dashboard se actualiza cada 2 segundos.
- El estado se guarda en `data/instancias.json` y se recupera al reiniciar la app. Si la app se cerró a mitad de una operación, esa instancia queda marcada con un mensaje para repetirla. En modo real, al arrancar se comprueba que las VMs de las instancias sigan existiendo.
- Si un script falla, el dashboard muestra su línea `ERROR: ...`; si `desplegar` termina con una línea `AVISO: ...`, se muestra como aviso.

## Modo simulado

Reemplaza los scripts por una simulación (2 segundos por operación) y publica el contenido en
`/sim/<nombre>/`, así que los enlaces funcionan sin VMs ni DNS. Para probar los errores, use nombres que
contengan `fallacrear`, `falladns`, `fallapub` o `fallaelim`.
