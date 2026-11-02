# Contrato: registrar-dns.ps1 <nombre> <ip>
# Agrega (o reemplaza) el registro A <nombre>.cloud.local en el servidor ns usando nsupdate con llave TSIG.
param([string]$Nombre, [string]$IP)
. (Join-Path $PSScriptRoot 'comun.ps1')

Validar-Nombre $Nombre
Validar-IP $IP

Iniciar-VM $VmNs
$r = Ejecutar-EnVM $VmNs @('/usr/local/sbin/dns-registrar.sh', $Nombre, $IP)
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "No se pudo registrar $Nombre.$Dominio en el DNS (codigo $($r.Codigo))" }

Write-Output "OK: $Nombre.$Dominio -> $IP"
exit 0
