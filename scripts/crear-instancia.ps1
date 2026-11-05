# Contrato: crear-instancia.ps1 <nombre> <ip>
# Crea una VM nueva que usa el disco multiconexion ApacheServer.vdi, la arranca y le asigna
# hostname, IP estatica y su propio sitio de Apache (/var/www/<nombre>).
param([string]$Nombre, [string]$IP)
. (Join-Path $PSScriptRoot 'comun.ps1')

Validar-Nombre $Nombre
Validar-IP $IP

$adaptador = Obtener-AdaptadorHostOnly
if (-not $adaptador) { Fallar "No existe la red host-only $RedHost.0/24 (ejecute infra\00-red-hostonly.ps1)" }
if (Obtener-EstadoVM $Nombre) { Fallar "Ya existe una VM llamada '$Nombre'" }
if (Test-Connection $IP -Count 1 -Quiet) { Fallar "La IP $IP ya esta en uso" }

# Datos de la plantilla: disco multiconexion, firmware y controlador de almacenamiento.
$tipo = (& $VB showmediuminfo disk $DiscoPlantilla 2>$null | Select-String '^Type:') -replace '^Type:\s*', '' -replace '\s+$', ''
if ($tipo -ne 'multiattach') { Fallar "El disco $DiscoPlantilla no existe o no esta en modo multiconexion (Type: '$tipo')" }

$firmware = 'bios'; $ctlNombre = 'SATA'; $ctlTipo = 'IntelAhci'; $puerto = '0'; $dispositivo = '0'
foreach ($linea in (& $VB showvminfo $VmPlantilla --machinereadable)) {
    if ($linea -match '^firmware="(.+)"$') { $firmware = $Matches[1].ToLower() }
    elseif ($linea -match '^storagecontrollername0="(.+)"$') { $ctlNombre = $Matches[1] }
    elseif ($linea -match '^storagecontrollertype0="(.+)"$') { $ctlTipo = $Matches[1] }
    elseif ($linea -match '^"(.+)-(\d+)-(\d+)"=".+\.vdi"$') { $puerto = $Matches[2]; $dispositivo = $Matches[3] }
}
$bus = switch -Regex ($ctlTipo) { 'Ahci' { 'sata' } 'PIIX|ICH6' { 'ide' } 'NVMe' { 'pcie' } 'Virtio' { 'virtio' } 'Lsi|BusLogic' { 'scsi' } default { 'sata' } }

Write-Output "== Creando la VM $Nombre (grupo $GrupoVMs)"
& $VB createvm --name $Nombre --ostype Debian_64 --groups $GrupoVMs --basefolder $CarpetaVMs --register
if ($LASTEXITCODE -ne 0) { Fallar 'Fallo createvm' }
Marcar-Instancia $Nombre
& $VB modifyvm $Nombre --memory 512 --cpus 1 --firmware $firmware --rtcuseutc on `
    --nic1 hostonly --hostonlyadapter1 $adaptador --boot1 disk --boot2 none --boot3 none --boot4 none `
    --description "HTTPaaS: instancia $Nombre.$Dominio ($IP)"
if ($LASTEXITCODE -ne 0) { Fallar 'Fallo modifyvm' }

Write-Output "== Conectando el disco multiconexion $DiscoPlantilla"
& $VB storagectl $Nombre --name $ctlNombre --add $bus --controller $ctlTipo
if ($LASTEXITCODE -ne 0) { Fallar 'Fallo storagectl' }
& $VB storageattach $Nombre --storagectl $ctlNombre --port $puerto --device $dispositivo --type hdd --medium $DiscoPlantilla
if ($LASTEXITCODE -ne 0) { Fallar 'No se pudo conectar el disco multiconexion' }

Write-Output "== Arrancando $Nombre"
Iniciar-VM $Nombre

Write-Output "== Configurando hostname, IP y sitio de Apache"
# Se usa la version del repo (infra\vm\apache) y no la guardada en la plantilla.
$scriptLocal = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\infra\vm\apache\configurar-instancia.sh'))
Copiar-AVM $Nombre $scriptLocal '/var/tmp/'
$r = Ejecutar-EnVM $Nombre @('/bin/bash', '/var/tmp/configurar-instancia.sh', $Nombre, $IP)
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "configurar-instancia.sh termino con codigo $($r.Codigo)" }

Write-Output '== Verificacion desde Windows'
$ok = $false
for ($i = 0; $i -lt 10; $i++) { if (Test-Connection $IP -Count 1 -Quiet) { $ok = $true; break }; Start-Sleep -Seconds 2 }
if (-not $ok) { Fallar "La instancia no responde ping en $IP" }
$http = Probar-HTTP "http://$IP/"
Write-Output "Ping a $IP : OK"
Write-Output "HTTP http://$IP/ : $http"
if ($http -ne '200') { Fallar "Apache no respondio 200 en $IP (respondio $http)" }

Write-Output "OK: instancia $Nombre creada en $IP"
exit 0
