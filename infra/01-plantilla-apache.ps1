# Paso 2 (una sola vez): plantilla ApacheServer.
#   - Clon COMPLETO de NP2-Base (snapshot base-limpia); NP2-Base no se modifica.
#   - Instala Apache y unzip por NAT y copia los scripts internos de las instancias.
#   - Deja la NIC 1 en host-only y el disco ApacheServer.vdi en modo multiconexion.
. (Join-Path $PSScriptRoot '..\scripts\comun.ps1')
$vm = $VmPlantilla
$dirVM = Join-Path $PSScriptRoot 'vm'

$adaptador = Obtener-AdaptadorHostOnly
if (-not $adaptador) { Fallar 'Primero ejecute 00-red-hostonly.ps1' }
if (Obtener-EstadoVM $vm) { Fallar "Ya existe la VM $vm" }

Write-Output "== Clon completo de NP2-Base (base-limpia) -> $vm"
& $VB clonevm NP2-Base --snapshot base-limpia --name $vm --basefolder $CarpetaVMs --register
if ($LASTEXITCODE -ne 0) { Fallar 'Fallo clonevm' }
& $VB modifyvm $vm --nic1 nat --nic2 none --memory 1024 --cpus 1 --description 'Plantilla HTTPaaS: Debian 13 + Apache. Disco ApacheServer.vdi en multiconexion.'

Write-Output "== Arrancando $vm con NAT para instalar paquetes"
Iniciar-VM $vm
foreach ($a in @('comun\httpaas-ejecutar.sh', 'apache\preparar-plantilla.sh', 'apache\configurar-instancia.sh', 'apache\desplegar-sitio.sh')) {
    Copiar-AVM $vm (Join-Path $dirVM $a) '/usr/local/sbin/'
}
& $VB guestcontrol $vm run --username $Usuario --password $Clave --exe /bin/chmod -- 755 /usr/local/sbin/httpaas-ejecutar.sh /usr/local/sbin/preparar-plantilla.sh /usr/local/sbin/configurar-instancia.sh /usr/local/sbin/desplegar-sitio.sh *> $null

Write-Output '== Instalando Apache (puede tardar unos minutos)'
$r = Ejecutar-EnVM $vm @('/usr/local/sbin/preparar-plantilla.sh')
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "preparar-plantilla.sh termino con codigo $($r.Codigo)" }

Write-Output "== Apagando $vm"
Apagar-VM $vm

Write-Output "== NIC 1 en host-only ($adaptador)"
& $VB modifyvm $vm --nic1 hostonly --hostonlyadapter1 $adaptador

Write-Output '== Disco en modo multiconexion'
$disco = $null
foreach ($linea in (& $VB showvminfo $vm --machinereadable)) {
    if ($linea -match '^"(.+)-(\d+)-(\d+)"="(.+\.vdi)"$') {
        $disco = @{ Ctl = $Matches[1]; Puerto = $Matches[2]; Disp = $Matches[3]; Ruta = $Matches[4] }
        break
    }
}
if (-not $disco) { Fallar "No se encontro el disco .vdi de $vm" }
& $VB storageattach $vm --storagectl $disco.Ctl --port $disco.Puerto --device $disco.Disp --medium none
& $VB modifymedium disk $disco.Ruta --type multiattach
if ($LASTEXITCODE -ne 0) { Fallar 'No se pudo cambiar el disco a multiattach' }
& $VB storageattach $vm --storagectl $disco.Ctl --port $disco.Puerto --device $disco.Disp --type hdd --mtype multiattach --medium $disco.Ruta

Write-Output ''
Write-Output "Disco plantilla: $($disco.Ruta)"
& $VB showmediuminfo disk $disco.Ruta | Select-String -Pattern '^UUID:|^Location:|^Type:|^Format'
Write-Output 'PLANTILLA ApacheServer LISTA'
