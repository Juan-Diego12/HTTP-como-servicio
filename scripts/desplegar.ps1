# Contrato: desplegar.ps1 <nombre> <ruta.zip>
# Copia el .zip a la instancia, lo descomprime en /var/www/<nombre> y recarga Apache.
# La ruta llega absoluta y puede tener espacios; se copia con un nombre fijo para evitar problemas.
param([string]$Nombre, [string]$RutaZip)
. (Join-Path $PSScriptRoot 'comun.ps1')

Validar-Nombre $Nombre
if (-not $RutaZip -or -not (Test-Path -LiteralPath $RutaZip -PathType Leaf)) { Fallar "No existe el archivo '$RutaZip'" }
if (-not (Obtener-EstadoVM $Nombre)) { Fallar "No existe la instancia '$Nombre'" }
if (-not (Es-Instancia $Nombre)) { Fallar "La VM '$Nombre' no es una instancia HTTPaaS" }

Iniciar-VM $Nombre

$tamano = [math]::Round((Get-Item -LiteralPath $RutaZip).Length / 1KB, 1)
Write-Output "== Copiando $([IO.Path]::GetFileName($RutaZip)) ($tamano KB) a $Nombre"
$copia = Join-Path $env:TEMP 'httpaas-sitio.zip'
Copy-Item -LiteralPath $RutaZip -Destination $copia -Force
Copiar-AVM $Nombre $copia '/var/tmp/'
Remove-Item $copia -Force -ErrorAction SilentlyContinue

Write-Output "== Publicando en /var/www/$Nombre"
$r = Ejecutar-EnVM $Nombre @('/usr/local/sbin/desplegar-sitio.sh', $Nombre, '/var/tmp/httpaas-sitio.zip')
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "desplegar-sitio.sh termino con codigo $($r.Codigo)" }

$url = "http://$Nombre.$Dominio/"
$http = Probar-HTTP $url
Write-Output "HTTP $url : $http"
if ($http -ne '200') { Write-Output "AVISO: $url respondio $http (revise que el .zip tenga index.html y que el nombre este registrado en el DNS)" }

Write-Output "OK: contenido publicado en $url"
exit 0
