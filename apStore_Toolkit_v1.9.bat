@echo off
setlocal EnableExtensions EnableDelayedExpansion
title apStore - Toolkit v1.9 (Config-driven)

:: ===== Auto-elevazione UAC =====
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

:: ===== Estrai il blocco PowerShell dopo ':#PS1' =====
set "PSFILE=%TEMP%\apStore_Toolkit_Run.ps1"
for /f "delims=:" %%A in ('findstr /n /c:":#PS1" "%~f0"') do set "LINE=%%A"
if not defined LINE (
  echo [ERRORE] Marker :#PS1 non trovato in %~f0
  pause & exit /b 1
)
set /a SKIP=%LINE%
more +%SKIP% "%~f0" > "%PSFILE%"
if not exist "%PSFILE%" (
  echo [ERRORE] Impossibile creare lo script temporaneo: %PSFILE%
  pause & exit /b 1
)

:: ===== Avvia PowerShell (passa argomenti del BAT) =====
set "APSTORE_HOME=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PSFILE%" %*
exit /b

:#PS1
param(
  [switch]$Hold,     # lascia la finestra aperta alla fine
  [switch]$Auto,     # esegui tutto senza prompt, con AutoReboot
  [switch]$Silent,   # come Auto ma senza menu
  [switch]$Resume    # ripresa dopo riavvio
)

$ErrorActionPreference = 'Stop'

# ====== Globali/base ======
$Global:Version = 'v1.9'

if ($env:APSTORE_HOME) {
  # Usa sempre la cartella del .bat originale
  $Global:ScriptDir = $env:APSTORE_HOME
} else {
  # Fallback: cartella dello script PS temporaneo
  $Global:ScriptDir = Split-Path -Parent $PSCommandPath
}

Write-Host "[INFO] ScriptDir = $Global:ScriptDir"

$Global:ProfilesDir    = Join-Path $Global:ScriptDir 'profiles'
$Global:LogsDir        = 'C:\Windows\Logs\apStore_Toolkit'
$Global:SelectedConfig = $null
$Global:AutoReboot     = $false
$Global:SkipKB         = @()
$Global:IncludeDrivers = $false
$Global:PresetPackages = @('7zip','googlechrome','firefox','notepadplusplus','git','vscode','vlc')

New-Item -ItemType Directory -Force -Path $Global:ProfilesDir | Out-Null
New-Item -ItemType Directory -Force -Path $Global:LogsDir    | Out-Null

# ====== Util ======
function Write-Info($m){ Write-Host "[INFO]  $m" }
function Write-Warn($m){ Write-Warning $m }
function Write-Err ($m){ Write-Error   $m }
function Ensure-Key($p){ if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null } }

function Start-Log(){
  try{
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Global:LogFile = Join-Path $Global:LogsDir "toolkit-$ts.log"
    Start-Transcript -Path $Global:LogFile -Append | Out-Null
  }catch{}
}
function Stop-Log(){ try{ Stop-Transcript | Out-Null }catch{} }

# ====== Ripresa post-riavvio ======
function Ensure-ResumeScript([string]$ArgsToPass){
  $bat = Get-ChildItem -Path $Global:ScriptDir -Filter "apStore_Toolkit*.bat" | Select-Object -First 1
  if(-not $bat){ $bat = Get-ChildItem -Path $Global:ScriptDir -Filter "*.bat" | Select-Object -First 1 }
  if(-not $bat){ return $null }

  $resumeDir = Join-Path $Global:ScriptDir "resume"
  New-Item $resumeDir -ItemType Directory -Force | Out-Null
  $resumeCmd = Join-Path $resumeDir "resume.cmd"

  $content = @"
@echo off
cd /d "$($Global:ScriptDir)"
"$($bat.FullName)" $ArgsToPass
"@
  $content | Set-Content -Path $resumeCmd -Encoding ASCII
  return $resumeCmd
}

function Register-RunOnce([string]$ArgsToPass){
  $cmd = Ensure-ResumeScript $ArgsToPass
  if(-not $cmd){ return }
  $key = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name "apStoreToolkitResume" -Value "`"$cmd`"" -PropertyType String -Force | Out-Null
}

# ====== Config (INI minimale) ======
function Detect-Config(){
  $candidates = @(
    "$($Global:ScriptDir)\config-apstore.txt"
    "$($Global:ScriptDir)\config-base.txt"
    "$($Global:ScriptDir)\config.txt"
  )
  foreach($c in $candidates){
    if(Test-Path $c){
      $Global:SelectedConfig = $c
      break
    }
  }
  if($null -eq $Global:SelectedConfig){
    Write-Warn "Nessun file config trovato nella cartella dello script."
  } else {
    Write-Info ("Config selezionato: {0}" -f (Split-Path $Global:SelectedConfig -Leaf))
  }
}

function Parse-Section([string]$raw,[string]$name){
  $m = [regex]::Match($raw,"(?ms)^\[$([regex]::Escape($name))\](.+?)(^\[|$)")
  if($m.Success){ return $m.Groups[1].Value } else { return $null }
}

function Load-Config(){
  if(-not $Global:SelectedConfig){ return }
  $raw = Get-Content -Raw -Path $Global:SelectedConfig

  # HOMEPAGE
$hp = Parse-Section $raw 'HOMEPAGE'
if($hp){
  $urls = [regex]::Match($hp,'(?m)^\s*Urls\s*=\s*(.+)$')
  $homeMatch = [regex]::Match($hp,'(?m)^\s*Home\s*=\s*(.+)$')
  $Global:HomeUrls = @()
  if($urls.Success){
    $Global:HomeUrls = ($urls.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  $Global:HomeSingle = $null
  if($homeMatch.Success){ $Global:HomeSingle = $homeMatch.Groups[1].Value.Trim() }
}

  # PROGRAMS
  $pg = Parse-Section $raw 'PROGRAMS'
  if($pg){
    $ch = [regex]::Match($pg,'(?m)^\s*Choco\s*=\s*(.+)$')
    if($ch.Success){
      $Global:PresetPackages = ($ch.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
  }

  # SYSTEM
  $sy = Parse-Section $raw 'SYSTEM'
  if($sy){
    $ds = [regex]::Match($sy,'(?m)^\s*DisableSleep\s*=\s*(.+)$')
    $cd = [regex]::Match($sy,'(?m)^\s*SetChromeDefault\s*=\s*(.+)$')
    $Global:DisableSleep = $false
    $Global:SetChromeDefault = $false
    if($ds.Success){ $Global:DisableSleep = @('true','1','yes','on').Contains($ds.Groups[1].Value.Trim().ToLower()) }
    if($cd.Success){ $Global:SetChromeDefault = @('true','1','yes','on').Contains($cd.Groups[1].Value.Trim().ToLower()) }
  }

  # UPDATES
  $up = Parse-Section $raw 'UPDATES'
  if($up){
    $ar = [regex]::Match($up,'(?m)^\s*AutoReboot\s*=\s*(.+)$')
    $sk = [regex]::Match($up,'(?m)^\s*SkipKB\s*=\s*(.+)$')
    $dr = [regex]::Match($up,'(?m)^\s*IncludeDrivers\s*=\s*(.+)$')
    if($ar.Success){ $Global:AutoReboot = @('true','1','yes','on').Contains($ar.Groups[1].Value.Trim().ToLower()) }
    if($sk.Success){
      $Global:SkipKB = ($sk.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if($dr.Success){ $Global:IncludeDrivers = @('true','1','yes','on').Contains($dr.Groups[1].Value.Trim().ToLower()) }
  }
}

# ====== Moduli: Sistema ======
function System-SetChromeDefault(){
  try{
    Write-Info "Imposto Chrome predefinito..."
    $chrome = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
    if(-not $chrome){
      $c1 = "$Env:ProgramFiles\Google\Chrome\Application\chrome.exe"
      $c2 = "$Env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
      foreach($p in @($c1,$c2)){ if(Test-Path $p){ $chrome=$p; break } }
    }
    if(-not $chrome){ Write-Warn "Chrome non trovato. Salto."; return }
    Start-Process -FilePath $chrome -ArgumentList "--make-default-browser" -WindowStyle Normal
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".shtml" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".xht" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".xhtml" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
"@
    $tmp = Join-Path $env:TEMP "apStore_DefaultApps_Chrome.xml"
    $xml | Set-Content -Path $tmp -Encoding UTF8
    Start-Process -FilePath dism.exe -ArgumentList "/Online","/Import-DefaultAppAssociations:$tmp" -Wait -NoNewWindow | Out-Null
  }catch{ Write-Warn $_.Exception.Message }
}

function System-DisableSleep(){
  try{
    Write-Info "Disabilito sospensione e ibernazione..."
    powercfg -x -standby-timeout-ac 0 | Out-Null
    powercfg -x -standby-timeout-dc 0 | Out-Null
    powercfg -h off | Out-Null
  }catch{ Write-Warn $_.Exception.Message }
}

# ====== Moduli: Personalizzazione ======
function Apply-Homepages-FromConfig(){
  if(-not $Global:HomeUrls -or $Global:HomeUrls.Count -eq 0){ Write-Warn "Nessuna URL in config."; return }
  $single = if([string]::IsNullOrWhiteSpace($Global:HomeSingle)){ $Global:HomeUrls[0] } else { $Global:HomeSingle }

  $chrome = "HKCU:\Software\Policies\Google\Chrome"; Ensure-Key $chrome
  New-ItemProperty -Path $chrome -Name HomepageIsNewTabPage -Value 0 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $chrome -Name RestoreOnStartup   -Value 4 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $chrome -Name RestoreOnStartupURLs -Value $Global:HomeUrls -PropertyType MultiString -Force | Out-Null
  if($single){ New-ItemProperty -Path $chrome -Name HomepageLocation -Value $single -PropertyType String -Force | Out-Null }

  $edge = "HKCU:\Software\Policies\Microsoft\Edge"; Ensure-Key $edge
  New-ItemProperty -Path $edge -Name HomepageIsNewTabPage -Value 0 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $edge -Name RestoreOnStartup   -Value 4 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $edge -Name RestoreOnStartupURLs -Value $Global:HomeUrls -PropertyType MultiString -Force | Out-Null
  if($single){ New-ItemProperty -Path $edge -Name HomepageLocation -Value $single -PropertyType String -Force | Out-Null }

  $ffBase = "HKCU:\Software\Policies\Mozilla\Firefox"; Ensure-Key $ffBase
  $ffHome = Join-Path $ffBase "Homepage"; Ensure-Key $ffHome
  New-ItemProperty -Path $ffHome -Name StartPage -Value "homepage" -PropertyType String -Force | Out-Null
  if($single){ New-ItemProperty -Path $ffHome -Name URL -Value $single -PropertyType String -Force | Out-Null }

  Write-Info "Homepage impostate (riavvia i browser)."
}

# ====== Moduli: Apps ======
function Ensure-Choco(){
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if($choco){ return $true }
  Write-Info "Installo Chocolatey..."
  try{
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $install = "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.ServicePointManager::SecurityProtocol] -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    powershell -NoProfile -ExecutionPolicy Bypass -Command $install
    Start-Sleep -Seconds 3
    return (Get-Command choco.exe -ErrorAction SilentlyContinue) -ne $null
  }catch{ Write-Warn $_.Exception.Message; return $false }
}

function Install-ChocoPackages([string[]]$Pkgs){
  if(-not $Pkgs -or $Pkgs.Count -eq 0){ Write-Warn "Nessun pacchetto da installare."; return }
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if(-not $choco){
    if(-not (Ensure-Choco)){ throw "Chocolatey non installato." }
    $choco = Get-Command choco.exe -ErrorAction Stop
  }
  foreach($p in $Pkgs){
    Write-Info ("Installo: {0}" -f $p)
    $proc = Start-Process -FilePath $choco.Source -ArgumentList @('install', $p, '-y', '--no-progress','--ignore-checksums') -NoNewWindow -PassThru -Wait
    if($proc.ExitCode -ne 0){ Write-Warn ("ExitCode {0} per {1}" -f $proc.ExitCode,$p) }
  }
  Write-Info "Installazione pacchetti completata."
}

function Update-Apps(){
  Write-Info "Aggiorno applicazioni (winget/choco)..."
  if(Get-Command winget -ErrorAction SilentlyContinue){
    try{
      winget upgrade --all --silent --accept-package-agreements --accept-source-agreements | Out-Null
    }catch{ Write-Warn "Winget update: $_" }
  }
  if(Get-Command choco -ErrorAction SilentlyContinue){
    try{
      choco upgrade all -y --no-progress --ignore-checksums | Out-Null
    }catch{ Write-Warn "Choco update: $_" }
  }
  Write-Info "Aggiornamento App completato."
}

# ====== Moduli: Windows Update (COM) ======
function WU-ScanInstall(
  [switch]$OnlyScan,
  [switch]$WithDrivers,
  [string[]]$SkipKB,
  [switch]$AutoReboot,
  [switch]$OnlyDrivers
){
  try{
    Write-Info 'Uso Windows Update COM nativo.'
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $criteria = 'IsInstalled=0 and IsHidden=0'
    $sr = $searcher.Search($criteria)
    if(-not $sr -or $sr.Updates.Count -eq 0){ Write-Info "Nessun aggiornamento disponibile."; return }

    $queue = New-Object 'System.Collections.Generic.List[Object]'
    for($i=0;$i -lt $sr.Updates.Count;$i++){
      $u=$sr.Updates.Item($i)
      $isDriver=$false
      foreach($c in $u.Categories){
        if($c.Name -match 'Driver|Drivers'){ $isDriver=$true; break }
      }
      # Skip KB
      if($SkipKB -and $SkipKB.Count -gt 0){
        $title=$u.Title; $hit=$false
        foreach($k in $SkipKB){
          $n=($k -replace '[^\d]','')
          if($n -and $title -match ("KB{0}" -f $n)){ $hit=$true; break }
        }
        if($hit){ continue }
      }
      if($OnlyDrivers){
        if($isDriver){ $queue.Add($u) }
      } elseif($WithDrivers){
        $queue.Add($u)
      } elseif(-not $isDriver){
        $queue.Add($u)
      }
    }

    $total = $queue.Count
    if($total -eq 0){ Write-Info "Nessun aggiornamento dopo i filtri."; return }
    if($OnlyScan){ Write-Info ("Trovati {0} aggiornamenti." -f $total); return }

    # Download
    $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach($u in $queue){ if(-not $u.IsDownloaded){ [void]$toDownload.Add($u) } }
    if($toDownload.Count -gt 0){
      Write-Info ("Download: {0}" -f $toDownload.Count)
      $d=$session.CreateUpdateDownloader(); $d.Updates=$toDownload; $null=$d.Download()
    }

    # Install
    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach($u in $queue){ [void]$toInstall.Add($u) }
    Write-Info ("Installazione: {0}" -f $toInstall.Count)
    $inst=$session.CreateUpdateInstaller(); $inst.Updates=$toInstall
    $res=$inst.Install()
    if($res.RebootRequired){
      Write-Warn "Riavvio richiesto."
      if($AutoReboot){
        Write-Info "AutoReboot attivo: preparo ripresa e riavvio."
        Register-RunOnce "-Resume -Auto"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
      }
    } else {
      Write-Info "Installazione completata senza riavvio."
    }
  }catch{ Write-Err $_.Exception.Message }
}

# ====== Menu ======
function Menu-Main(){
  Write-Host ""
  Write-Host "================ apStore Toolkit $($Global:Version) ================" -ForegroundColor Cyan
  Write-Host "[1] Installazione Programmi (Chocolatey)"
  Write-Host "[2] Personalizzazione (Homepage da config)"
  Write-Host "[3] Sistema (Chrome default / disabilita sospensione)"
  Write-Host "[4] Aggiornamenti (Driver / OS / App / Tutto)"
  Write-Host "[8] Apri config attivo (Notepad)"
  Write-Host "[5] Esegui TUTTO (rispetta il config)"
  Write-Host "[0] Esci"
  Write-Host "---------------------------------------------------------"
  return (Read-Host "Seleziona")
}

function Menu-Updates(){
  Write-Host ""
  Write-Host "---------------------- Aggiornamenti ----------------------" -ForegroundColor Cyan
  Write-Host ("AutoReboot={0}  IncludeDrivers={1}  SkipKB={2}" -f $Global:AutoReboot, $Global:IncludeDrivers, ($(if($Global:SkipKB){$Global:SkipKB -join ','}else{'(none)'})))
  Write-Host "[1] Driver (solo driver via Windows Update)"
  Write-Host "[2] OS (solo aggiornamenti di sistema, niente driver)"
  Write-Host "[3] App (Store/Winget/Choco)"
  Write-Host "[4] TUTTO (App + OS + Driver secondo config)"
  Write-Host "[B] Indietro"
  Write-Host "-----------------------------------------------------------"
  return (Read-Host "Seleziona")
}

# ====== Flussi ======
function Run-All(){
  Write-Info "Esecuzione completa avviata."

  # 1) App (preset da config)
  try{
    Write-Info ("Pacchetti preset: {0}" -f ($Global:PresetPackages -join ", "))
    Install-ChocoPackages -Pkgs $Global:PresetPackages
  }catch{ Write-Warn $_.Exception.Message }

  # 2) Sistema
  try{ if($Global:SetChromeDefault){ System-SetChromeDefault } }catch{ Write-Warn $_.Exception.Message }
  try{ if($Global:DisableSleep){ System-DisableSleep } }catch{ Write-Warn $_.Exception.Message }

  # 3) Personalizzazione
  try{ Apply-Homepages-FromConfig }catch{ Write-Warn $_.Exception.Message }

  # 4) Aggiornamenti (OS + opz. Driver) rispettando config
  try{
    WU-ScanInstall -WithDrivers:$Global:IncludeDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB
  }catch{ Write-Warn $_.Exception.Message }

  Write-Host ""
  Write-Host "=== Esecuzione completa terminata ===" -ForegroundColor Green
}

function Updates-Loop(){
  :U while($true){
    $u = Menu-Updates
    switch($u.ToUpper()){
      '1' { WU-ScanInstall -OnlyDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB }
      '2' { WU-ScanInstall -WithDrivers:$false -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB }
      '3' { Update-Apps }
      '4' { Update-Apps; WU-ScanInstall -WithDrivers:$Global:IncludeDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB; Write-Host "`n=== Aggiornamenti COMPLETI eseguiti ===" -ForegroundColor Green }
      'B' { break U }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# ====== AVVIO ======
Detect-Config
Load-Config
Start-Log

if($Resume){ Write-Info "Ripresa post-riavvio attiva." }

if($Auto -or $Silent){
  Run-All
  Stop-Log
  if($Hold){ Read-Host "Operazioni concluse. INVIO per chiudere" }
  exit
}

:MAIN while($true){
  $c = Menu-Main
  switch($c){
    '1' { Install-ChocoPackages -Pkgs $Global:PresetPackages }
    '2' { Apply-Homepages-FromConfig }
    '3' {
           if($Global:SetChromeDefault){ System-SetChromeDefault } else { Write-Warn "SetChromeDefault=false (config)." }
           if($Global:DisableSleep){ System-DisableSleep } else { Write-Warn "DisableSleep=false (config)." }
         }
    '4' { Updates-Loop }
    '5' { Run-All }
    '8' { if($Global:SelectedConfig){ Start-Process notepad.exe $Global:SelectedConfig } else { Write-Warn "Nessun config attivo." } }
    '0' { break MAIN }
    default { Write-Host "Scelta non valida." }
  }
}

Stop-Log
if($Hold){ Read-Host "Operazioni concluse. INVIO per chiudere" }
