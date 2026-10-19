<#
 Costura 3 - Alarma de la DMZ: lo que Debian (10.10.20.40) INTENTA y pfSense le BLOQUEA.
 Uso (PowerShell normal en el host; no hace falta administrador):
   & 'D:\VMware_LAB\_lab\costura3\ver_alarma_dmz.ps1'               # en vivo (Ctrl+C para salir)
   & 'D:\VMware_LAB\_lab\costura3\ver_alarma_dmz.ps1' -Ultimas 30   # solo las ultimas 30
 Tipos:
   CONTENCION = intento hacia casa / lab / NAS (regla 1791590554). Con la web expuesta y sin
                que tu lo provoques, significa que alguien esta DENTRO de la DMZ.
   SALIDA     = intento hacia internet (bloqueo por defecto). Normal si usas el escritorio
                de Debian; con la web expuesta y sin usarlo, sospechoso.
 Solo lee el log de pfSense (por la Pi 5); no cambia nada. Horas convertidas a hora local.
#>
param([int]$Ultimas = 0)

$cmd = if ($Ultimas -gt 0) { 'tail -n 20000 /var/log/filter.log' } else { 'tail -n 0 -f /var/log/filter.log' }
$cultura = [Globalization.CultureInfo]::InvariantCulture

function Formatear([string]$linea) {
    if ($linea -notmatch 'em2,match,block') { return }
    $c = ($linea -split ': ', 2)[1] -split ','
    $utc = [datetime]::ParseExact(($linea.Substring(0, 15) -replace '\s+', ' '), 'MMM d HH:mm:ss', $cultura)
    $hora = [TimeZoneInfo]::ConvertTimeFromUtc($utc, [TimeZoneInfo]::Local).ToString('HH:mm:ss')
    $tipo = if ($c[3] -eq '1791590554') { 'CONTENCION' } else { 'SALIDA    ' }
    $puerto = if ($c[16] -in 'tcp', 'udp') { ':' + $c[21] } else { '' }
    '{0}  {1}  {2} -> {3}{4} ({5})' -f $hora, $tipo, $c[18], $c[19], $puerto, $c[16]
}

if ($Ultimas -gt 0) {
    ssh rpi5 "ssh pfsense '$cmd'" | ForEach-Object { Formatear $_ } | Select-Object -Last $Ultimas
} else {
    'Alarma DMZ en vivo (Ctrl+C para salir). Esperando bloqueos...'
    ssh rpi5 "ssh pfsense '$cmd'" | ForEach-Object { Formatear $_ }
}
