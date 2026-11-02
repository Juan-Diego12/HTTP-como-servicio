# Paso 1 (una sola vez): crea la red host-only 192.168.10.0/24 con el host en 192.168.10.1, sin DHCP.
. (Join-Path $PSScriptRoot '..\scripts\comun.ps1')

$adaptador = Obtener-AdaptadorHostOnly
if ($adaptador) {
    Write-Output "Ya existe el adaptador host-only con $IpHost : $adaptador"
} else {
    $salida = & $VB hostonlyif create 2>&1 | ForEach-Object { "$_" }
    $salida
    $nuevo = $null
    foreach ($linea in $salida) { if ($linea -match "Interface '(.+)' was successfully created") { $nuevo = $Matches[1] } }
    if (-not $nuevo) { Fallar 'No se pudo crear el adaptador host-only (abra PowerShell como administrador)' }
    & $VB hostonlyif ipconfig $nuevo --ip $IpHost --netmask 255.255.255.0
    if ($LASTEXITCODE -ne 0) { Fallar "No se pudo asignar $IpHost a $nuevo" }
    $adaptador = $nuevo
}

# Sin DHCP: cada VM recibe IP estatica (ns .10, instancias .30 en adelante).
& $VB dhcpserver remove --interface $adaptador *> $null

Write-Output ''
Write-Output "Adaptador host-only: $adaptador"
& $VB list hostonlyifs | Select-String -Pattern 'Name:|IPAddress:|NetworkMask:|Status:'
