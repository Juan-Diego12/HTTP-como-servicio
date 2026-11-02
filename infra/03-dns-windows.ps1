# Paso 4 (una sola vez, PowerShell como ADMINISTRADOR): que Windows resuelva *.cloud.local con ns.
#   - Regla NRPT: las consultas de .cloud.local van a 192.168.10.10 sin tocar el DNS del Wi-Fi.
#   - Ademas se pone 192.168.10.10 como DNS del adaptador host-only.
. (Join-Path $PSScriptRoot '..\scripts\comun.ps1')

$ip = Get-NetIPAddress -IPAddress $IpHost -ErrorAction SilentlyContinue
if (-not $ip) { Fallar "No hay ningun adaptador con $IpHost (ejecute 00-red-hostonly.ps1)" }
Set-DnsClientServerAddress -InterfaceIndex $ip.InterfaceIndex -ServerAddresses $IpNs

Get-DnsClientNrptRule | Where-Object { $_.Namespace -contains ".$Dominio" } | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
Add-DnsClientNrptRule -Namespace ".$Dominio" -NameServers $IpNs
Clear-DnsClientCache

Get-DnsClientNrptRule | Format-Table Namespace, NameServers -AutoSize
Get-DnsClientServerAddress -InterfaceIndex $ip.InterfaceIndex -AddressFamily IPv4 | Format-Table InterfaceAlias, ServerAddresses -AutoSize
Resolve-DnsName "ns.$Dominio"
