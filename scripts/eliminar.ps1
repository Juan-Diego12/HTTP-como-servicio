# Contrato: eliminar.ps1 <nombre>
# Apaga y borra la VM de la instancia (solo si fue creada por crear-instancia.ps1) y quita su
# registro DNS. Si la VM o el registro ya no existen, no es error: la app tambien lo llama para
# limpiar instancias que quedaron a medias.
param([string]$Nombre)
. (Join-Path $PSScriptRoot 'comun.ps1')

Validar-Nombre $Nombre
if ($Nombre -eq $VmNs -or $Nombre -eq $VmPlantilla.ToLower()) { Fallar "'$Nombre' es parte de la infraestructura y no se puede eliminar" }

if (Obtener-EstadoVM $Nombre) {
    if (Es-Instancia $Nombre) {
        Write-Output "== Apagando $Nombre"
        Forzar-Apagado $Nombre
        Write-Output "== Borrando la VM $Nombre y su disco diferencial (ApacheServer.vdi se conserva)"
        & $VB unregistervm $Nombre --delete
        if ($LASTEXITCODE -ne 0) {
            Start-Sleep -Seconds 3
            & $VB unregistervm $Nombre --delete
            if ($LASTEXITCODE -ne 0) { Fallar "No se pudo borrar la VM $Nombre" }
        }
    } else {
        Write-Output "AVISO: existe una VM '$Nombre' que no es una instancia HTTPaaS; no se borra"
    }
} else {
    Write-Output "La VM $Nombre no existe (nada que borrar)"
}

Write-Output "== Quitando $Nombre.$Dominio del DNS"
Iniciar-VM $VmNs
$r = Ejecutar-EnVM $VmNs @('/usr/local/sbin/dns-eliminar.sh', $Nombre)
Write-Output $r.Salida
if ($r.Codigo -ne 0) { Fallar "No se pudo quitar $Nombre.$Dominio del DNS (codigo $($r.Codigo))" }

if (-not (Test-Path $DiscoPlantilla)) { Fallar "ATENCION: no se encuentra $DiscoPlantilla" }
Write-Output "Plantilla intacta: $DiscoPlantilla"
Write-Output "OK: instancia $Nombre eliminada"
exit 0
