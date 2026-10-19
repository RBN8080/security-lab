<#
 HTTPS - Fase 2: el NAT de VMware (VMnet8) pasa TCP 443 del host a la WAN de pfSense.
 Ejecutar en PowerShell COMO ADMINISTRADOR:
   & 'D:\VMware_LAB\_lab\https\fase2_https.ps1'             # aplicar
   & 'D:\VMware_LAB\_lab\https\fase2_https.ps1' -Revertir   # deshacer
 Hace: respaldo de vmnetnat.conf; anade '443 = 192.168.85.128:443' en [incomingtcp];
 regla de firewall SOLO TCP 443 para vmnat.exe (perfil Private); reinicia "VMware NAT Service".
 OJO: el reinicio corta unos segundos la salida de las VMs y el tunel WireGuard de la Pi (vuelve solo).
#>
param([switch]$Revertir)
$ErrorActionPreference = 'Stop'
$conf  = 'C:\ProgramData\VMware\vmnetnat.conf'
$dir   = 'D:\VMware_LAB\_lab\https'
$linea = '443 = 192.168.85.128:443'
$regla = 'Costura3 HTTPS (TCP 443 -> pfSense)'
$vmnat = 'C:\Windows\SysWOW64\vmnat.exe'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Abre PowerShell como Administrador y vuelve a ejecutarlo.' }

$lineas = [IO.File]::ReadAllLines($conf)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
Copy-Item $conf (Join-Path $dir ('vmnetnat.conf.bak.' + (Get-Date -Format 'yyyyMMdd_HHmmss')))

if ($Revertir) {
    $nuevas = @($lineas | Where-Object { $_.Trim() -ne $linea })
    [IO.File]::WriteAllText($conf, (($nuevas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    'REVERTIDO: linea 443 quitada de [incomingtcp] y regla de firewall borrada.'
} else {
    if ($lineas -contains $linea) {
        'YA-ESTA: la linea 443 ya existe en [incomingtcp].'
    } else {
        $i = [Array]::IndexOf($lineas, '[incomingtcp]')
        if ($i -lt 0) { throw 'No encuentro la seccion [incomingtcp].' }
        $nuevas = @($lineas[0..$i]) + $linea + @($lineas[($i + 1)..($lineas.Count - 1)])
        [IO.File]::WriteAllText($conf, (($nuevas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
        "ANADIDO en [incomingtcp]: $linea"
    }
    if (-not (Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $regla -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort 443 -Program $vmnat -Profile Private | Out-Null
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
'Puerto 443 escuchando en el host:'
Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { '   {0}:443  (PID {1}, {2})' -f $_.LocalAddress, $_.OwningProcess, (Get-Process -Id $_.OwningProcess).ProcessName }
'Regla de firewall:'
Get-NetFirewallRule -DisplayName $regla -ErrorAction SilentlyContinue | ForEach-Object { '   {0} | {1} | {2}' -f $_.DisplayName, $_.Action, $_.Enabled }
