# Paso 3 (una sola vez): servidor DNS ns (Bind9) en 192.168.10.10.
#   - Clon ENLAZADO de DNS-Plantilla (snapshot paquetes: ya trae bind9 y dnsutils); DNS-Plantilla no se modifica.
#   - Zona cloud.local. con actualizacion dinamica por nsupdate + llave TSIG.
. (Join-Path $PSScriptRoot '..\scripts\comun.ps1')
$vm = $VmNs
$dirVM = Join-Path $PSScriptRoot 'vm'

$adaptador = Obtener-AdaptadorHostOnly
if (-not $adaptador) { Fallar 'Primero ejecute 00-red-hostonly.ps1' }
if (Obtener-EstadoVM $vm) { Fallar "Ya existe la VM $vm" }

Write-Output "== Clon enlazado de DNS-Plantilla (paquetes) -> $vm"
& $VB clonevm DNS-Plantilla --snapshot paquetes --options link --name $vm --basefolder $CarpetaVMs --register
if ($LASTEXITCODE -ne 0) { Fallar 'Fallo clonevm' }
& $VB modifyvm $vm --nic1 hostonly --hostonlyadapter1 $adaptador --nic2 none --memory 512 --cpus 1 --description 'HTTPaaS: servidor DNS Bind9, zona cloud.local, 192.168.10.10'

Iniciar-VM $vm
foreach ($a in @('comun\httpaas-ejecutar.sh', 'ns\preparar-ns.sh', 'ns\dns-registrar.sh', 'ns\dns-eliminar.sh')) {
    Copiar-AVM $vm (Join-Path $dirVM $a) '/usr/local/sbin/'
}
& $VB guestcontrol $vm run --username $Usuario --password $Clave --exe /bin/chmod -- 755 /usr/local/sbin/httpaas-ejecutar.sh /usr/local/sbin/preparar-ns.sh /usr/local/sbin/dns-registrar.sh /usr/local/sbin/dns-eliminar.sh *> $null

Write-Output '== Configurando Bind9'
$r = Ejecutar-EnVM $vm @('/usr/local/sbin/preparar-ns.sh')
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "preparar-ns.sh termino con codigo $($r.Codigo)" }

Write-Output ''
Write-Output '== Prueba desde Windows'
Test-Connection $IpNs -Count 2
Resolve-DnsName "ns.$Dominio" -Server $IpNs -DnsOnly
Write-Output 'SERVIDOR ns LISTO'
