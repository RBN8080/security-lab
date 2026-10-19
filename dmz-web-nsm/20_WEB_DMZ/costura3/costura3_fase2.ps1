<#
 Costura 3 - Fase 2: el NAT de VMware (VMnet8) pasa TCP 80 del host a la WAN de pfSense.
 Ejecutar en PowerShell COMO ADMINISTRADOR:
   & 'D:\VMware_LAB\_lab\costura3\costura3_fase2.ps1'             # aplicar
   & 'D:\VMware_LAB\_lab\costura3\costura3_fase2.ps1' -Revertir   # deshacer
 Hace: respaldo de vmnetnat.conf en esta carpeta; anade '80 = 192.168.85.128:80' en [incomingtcp];
 regla de firewall SOLO TCP 80 para vmnat.exe (perfil Private; el firewall NO se apaga);
 reinicia "VMware NAT Service".
 OJO: el reinicio corta unos segundos la salida de las VMs y el tunel WireGuard de la Pi (vuelve solo).
 Tras esto la web se ve en la LAN real (http://192.168.1.23/); en internet AUN NO (falta el ZTE, Fase 3).
#>
param([switch]$Revertir)
$ErrorActionPreference = 'Stop'
$conf  = 'C:\ProgramData\VMware\vmnetnat.conf'
$dir   = 'D:\VMware_LAB\_lab\costura3'
$linea = '80 = 192.168.85.128:80'
$regla = 'Costura3 HTTP (TCP 80 -> pfSense)'
$vmnat = 'C:\Windows\SysWOW64\vmnat.exe'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Abre PowerShell como Administrador y vuelve a ejecutarlo.' }

$lineas = [IO.File]::ReadAllLines($conf)
Copy-Item $conf (Join-Path $dir ('vmnetnat.conf.bak.' + (Get-Date -Format 'yyyyMMdd_HHmmss')))

if ($Revertir) {
    $nuevas = @($lineas | Where-Object { $_.Trim() -ne $linea })
    [IO.File]::WriteAllText($conf, (($nuevas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    'REVERTIDO: linea quitada de [incomingtcp] y regla de firewall borrada.'
} else {
    if ($lineas -contains $linea) {
        'YA-ESTA: la linea ya existe en [incomingtcp].'
    } else {
        $i = [Array]::IndexOf($lineas, '[incomingtcp]')
        if ($i -lt 0) { throw 'No encuentro la seccion [incomingtcp].' }
        $nuevas = @($lineas[0..$i]) + $linea + @($lineas[($i + 1)..($lineas.Count - 1)])
        [IO.File]::WriteAllText($conf, (($nuevas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
        "ANADIDO en [incomingtcp]: $linea"
    }
    if (-not (Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $regla -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort 80 -Program $vmnat -Profile Private | Out-Null
        "REGLA de firewall creada: $regla"
    } else { 'REGLA de firewall ya existia.' }
}

'Reiniciando VMware NAT Service (corte de unos segundos)...'
Restart-Service 'VMware NAT Service'
Start-Sleep -Seconds 3

'=== Comprobacion'
'[incomingtcp] activo:'
$enSeccion = $false
foreach ($l in [IO.File]::ReadAllLines($conf)) {
    if ($l -match '^\[') { $enSeccion = ($l -eq '[incomingtcp]') ; continue }
    if ($enSeccion -and $l -match '^\s*\d+\s*=') { "   $l" }
}
'Puerto 80 escuchando en el host:'
Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { '   {0}:80  (PID {1}, {2})' -f $_.LocalAddress, $_.OwningProcess, (Get-Process -Id $_.OwningProcess).ProcessName }
'Regla de firewall:'
Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue | ForEach-Object { '   {0} | {1} | {2}' -f $_.DisplayName, $_.Action, $_.Enabled }
