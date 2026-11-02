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

# Copia un archivo del host a una carpeta de la VM.
function Copiar-AVM([string]$Vm, [string]$Archivo, [string]$Destino) {
    & $VB guestcontrol $Vm copyto --username $Usuario --password $Clave --target-directory $Destino $Archivo *> $null
    if ($LASTEXITCODE -ne 0) { Fallar "No se pudo copiar $Archivo a ${Vm}:$Destino" }
}

# Ejecuta un comando en la VM a traves del envoltorio, que guarda la salida y el codigo
# en /tmp/httpaas-salida.txt (la ultima linea es EXIT=<codigo>).
# El comando se lanza con "guestcontrol start" (no espera) y luego se consulta el archivo
# con cat cada 2 segundos hasta que aparece EXIT=. Asi se evita que VBoxManage 7.1.6 se caiga
# esperando procesos largos ("run" termina con 0xC0000374 / 0xC0000005).
# Devuelve @{ Codigo = <int>; Salida = <texto> }.
function Leer-SalidaVM([string]$Vm) {
    return @(& $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/cat -- $SalidaRemota 2>$null)
}

function Ejecutar-EnVM([string]$Vm, [string[]]$Comando, [int]$Segundos = 900) {
    & $VB guestcontrol $Vm run --username $Usuario --password $Clave --exe /bin/rm -- -f $SalidaRemota *> $null

    $argumentos = @('guestcontrol', $Vm, 'start', '--username', $Usuario, '--password', $Clave,
                    '--exe', '/bin/bash', '--', $Envoltorio) + $Comando
    & $VB @argumentos *> $null

    $inicio = Get-Date
    $relanzado = $false
    $lineas = @()
    while (((Get-Date) - $inicio).TotalSeconds -lt $Segundos) {
        Start-Sleep -Seconds 2
        $lineas = Leer-SalidaVM $Vm
        if ($lineas -match '^EXIT=\d+$') { break }
        # Si a los 20 s el archivo ni siquiera existe, el comando no arranco: se lanza una vez mas.
        $existe = $lineas.Count -gt 0 -and -not (($lineas -join ' ') -match [regex]::Escape("cat: $SalidaRemota"))
        if (-not $existe -and -not $relanzado -and ((Get-Date) - $inicio).TotalSeconds -gt 20) {
            & $VB @argumentos *> $null
            $relanzado = $true
        }
    }
    if (-not ($lineas -match '^EXIT=\d+$')) {
        return @{ Codigo = 99; Salida = "No se obtuvo el resultado del comando en $Vm (tiempo maximo $Segundos s)" }
    }

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
