# Valores y funciones comunes de los scripts de infraestructura (parte de Daniel).
# Cada script los carga con:  . (Join-Path $PSScriptRoot 'comun.ps1')
# Compatible con Windows PowerShell 5.1 (el que usa la app: powershell -File ...).

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$VB           = 'VBoxManage'
$Usuario      = 'root'
$Clave        = 'daniel1234'
$Dominio      = 'cloud.local'
$RedHost      = '192.168.10'
$IpHost       = '192.168.10.1'
$IpNs         = '192.168.10.10'
$VmNs         = 'ns'
$VmPlantilla  = 'ApacheServer'
$CarpetaVMs   = 'F:\VirtualBox\VMs'
$SalidaRemota = '/tmp/httpaas-salida.txt'
$Envoltorio   = '/usr/local/sbin/httpaas-ejecutar.sh'
$DiscoPlantilla = Join-Path $CarpetaVMs 'ApacheServer\ApacheServer.vdi'
$GrupoVMs     = '/HTTPaaS'
$MarcaInstancia = 'HTTPaaS/Instancia'

# Termina el script con codigo 1 (la app detecta el error por el codigo de salida).
function Fallar([string]$Mensaje) {
    Write-Output "ERROR: $Mensaje"
    exit 1
}

# Nombre del adaptador host-only de VirtualBox que tiene la IP 192.168.10.1 (o $null).
function Obtener-AdaptadorHostOnly {
    $nombre = $null
    foreach ($linea in (& $VB list hostonlyifs 2>$null)) {
        if ($linea -match '^Name:\s+(.+)$') { $nombre = $Matches[1].Trim() }
        elseif ($linea -match '^IPAddress:\s+(.+)$' -and $Matches[1].Trim() -eq $IpHost) { return $nombre }
    }
    return $null
}

# Estado de la VM (running, poweroff, saved...) o $null si no existe.
function Obtener-EstadoVM([string]$Vm) {
    $info = & $VB showvminfo $Vm --machinereadable 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($linea in $info) { if ($linea -match '^VMState="(.+)"$') { return $Matches[1] } }
    return 'desconocido'
}

# Espera hasta que las Guest Additions de la VM acepten comandos.
function Esperar-Invitado([string]$Vm, [int]$Segundos = 240) {
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        & $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/true *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

# Arranca la VM en segundo plano (si no esta corriendo) y espera a que responda.
function Iniciar-VM([string]$Vm) {
    $estado = Obtener-EstadoVM $Vm
    if (-not $estado) { Fallar "No existe la VM $Vm" }
    if ($estado -ne 'running') {
        Write-Output "Iniciando $Vm..."
        & $VB startvm $Vm --type headless *> $null
        if ($LASTEXITCODE -ne 0) { Fallar "No se pudo iniciar la VM $Vm" }
    }
    if (-not (Esperar-Invitado $Vm)) { Fallar "La VM $Vm no respondio por Guest Additions" }
}

# Apaga la VM desde adentro; si no se apaga a tiempo, la apaga a la fuerza.
function Apagar-VM([string]$Vm, [int]$Segundos = 90) {
    if ((Obtener-EstadoVM $Vm) -ne 'running') { return }
    & $VB guestcontrol $Vm start --username $Usuario --password $Clave --exe /usr/sbin/poweroff *> $null
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        if ((Obtener-EstadoVM $Vm) -eq 'poweroff') { return }
        Start-Sleep -Seconds 2
    }
    & $VB controlvm $Vm poweroff *> $null
    Start-Sleep -Seconds 3
}

# Copia un archivo del host a una carpeta de la VM. Reintenta hasta 6 veces porque,
# recien arrancada la VM, las Guest Additions a veces rechazan la copia.
function Copiar-AVM([string]$Vm, [string]$Archivo, [string]$Destino) {
    for ($i = 1; $i -le 6; $i++) {
        & $VB guestcontrol $Vm copyto --username $Usuario --password $Clave --target-directory $Destino $Archivo *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 5
    }
    Fallar "No se pudo copiar $Archivo a ${Vm}:$Destino"
}

# Ejecuta un comando en la VM a traves del envoltorio, que guarda la salida y el codigo
# en /tmp/httpaas-salida.txt (la ultima linea es EXIT=<codigo>).
# - Se lanza con "guestcontrol start" (no espera): "run" hace caer a VBoxManage 7.1.6 en
#   procesos que reconfiguran la VM (0xC0000374 / 0xC0000005).
# - Justo despues de arrancar la VM, "start" a veces no lanza nada: si el archivo no aparece,
#   se vuelve a lanzar cada 10 s (hasta 10 intentos). Como el envoltorio crea el archivo apenas
#   empieza, si el archivo existe el comando ya arranco y no se repite.
# - El resultado se lee con cat cada 2 s hasta que aparece EXIT=.
# Devuelve @{ Codigo = <int>; Salida = <texto> }.
function Leer-SalidaVM([string]$Vm) {
    return @(& $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/cat -- $SalidaRemota 2>$null)
}

function Existe-SalidaVM([string]$Vm) {
    $r = & $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/ls -- $SalidaRemota 2>$null
    return (($r -join ' ') -match [regex]::Escape($SalidaRemota))
}

function Ejecutar-EnVM([string]$Vm, [string[]]$Comando, [int]$Segundos = 900) {
    # El archivo de una ejecucion anterior debe desaparecer antes de lanzar el comando;
    # si no, se leeria ese resultado viejo como si fuera el nuevo.
    $limpio = $false
    for ($i = 0; $i -lt 6; $i++) {
        & $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/rm -- -f $SalidaRemota *> $null
        Start-Sleep -Seconds 1
        if (-not (Existe-SalidaVM $Vm) -and -not (Existe-SalidaVM $Vm)) { $limpio = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $limpio) { return @{ Codigo = 99; Salida = "No se pudo borrar el resultado anterior en $Vm ($SalidaRemota)" } }

    $argumentos = @('guestcontrol', $Vm, 'start', '--username', $Usuario, '--password', $Clave,
                    '--exe', '/bin/bash', '--', $Envoltorio) + $Comando
    & $VB @argumentos *> $null

    $inicio = Get-Date
    $ultimoIntento = Get-Date
    $intentos = 1
    $confirmado = $false
    $lineas = @()
    while (((Get-Date) - $inicio).TotalSeconds -lt $Segundos) {
        Start-Sleep -Seconds 2
        $lineas = Leer-SalidaVM $Vm
        if ($lineas -match '^EXIT=\d+$') { break }
        if (-not $confirmado) {
            if (Existe-SalidaVM $Vm) {
                $confirmado = $true
            } elseif (((Get-Date) - $ultimoIntento).TotalSeconds -ge 10 -and $intentos -lt 10) {
                # Doble comprobacion antes de relanzar (por si se perdio la salida de ls).
                Start-Sleep -Seconds 1
                if (Existe-SalidaVM $Vm) { $confirmado = $true }
                else {
                    & $VB @argumentos *> $null
                    $intentos++
                    $ultimoIntento = Get-Date
                }
            }
        }
    }
    if (-not ($lineas -match '^EXIT=\d+$')) {
        return @{ Codigo = 99; Salida = "No se obtuvo el resultado del comando en $Vm (intentos de lanzamiento: $intentos, tiempo maximo $Segundos s)" }
    }

    # Se borra el resultado ya leido para que nunca se confunda con el de la siguiente ejecucion.
    & $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/rm -- -f $SalidaRemota *> $null

    $codigo = 99
    foreach ($linea in $lineas) { if ($linea -match '^EXIT=(\d+)$') { $codigo = [int]$Matches[1] } }
    $salida = ($lineas | Where-Object { $_ -notmatch '^EXIT=\d+$' }) -join "`n"
    return @{ Codigo = $codigo; Salida = $salida }
}

# Validaciones comunes de los argumentos del contrato.
function Validar-Nombre([string]$Nombre) {
    if ($Nombre -cnotmatch '^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$') { Fallar "Nombre de host invalido: '$Nombre'" }
}
function Validar-IP([string]$IP) {
    if ($IP -notmatch '^192\.168\.10\.(\d{1,3})$' -or [int]$Matches[1] -lt 30 -or [int]$Matches[1] -gt 254) {
        Fallar "IP invalida: '$IP' (debe estar entre $RedHost.30 y $RedHost.254)"
    }
}

# Marca y consulta: solo las VMs creadas por crear-instancia.ps1 llevan esta marca,
# asi eliminar.ps1 nunca borra una VM ajena aunque tenga el mismo nombre.
function Marcar-Instancia([string]$Vm) {
    & $VB setextradata $Vm $MarcaInstancia 1 *> $null
}
function Es-Instancia([string]$Vm) {
    $valor = & $VB getextradata $Vm $MarcaInstancia 2>$null
    return (($valor -join ' ') -match 'Value:\s*1')
}

# Espera a que la VM quede apagada (o la apaga a la fuerza).
function Forzar-Apagado([string]$Vm, [int]$Segundos = 30) {
    $estado = Obtener-EstadoVM $Vm
    if ($estado -eq 'running' -or $estado -eq 'paused' -or $estado -eq 'stuck') {
        & $VB controlvm $Vm poweroff *> $null
    }
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        $estado = Obtener-EstadoVM $Vm
        if ($estado -ne 'running' -and $estado -ne 'stopping' -and $estado -ne 'paused') { return }
        Start-Sleep -Seconds 2
    }
}

# Codigo HTTP de una URL vista desde Windows (000 si no responde).
function Probar-HTTP([string]$Url) {
    $codigo = & curl.exe --noproxy '*' -s -o NUL -m 10 -w '%{http_code}' $Url 2>$null
    if (-not $codigo) { $codigo = '000' }
    return "$codigo"
}

