@echo off
setlocal EnableExtensions EnableDelayedExpansion
title apStore - Toolkit v1.9.2 (config + progress)

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

:: Avvia PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PSFILE%" -Hold
exit /b

:#PS1
param(
  [switch]$Hold
)

$ErrorActionPreference = 'Stop'

# ===== Globali/base =====
$Global:Version          = 'v1.9.2'
$Global:ScriptDir        = Split-Path -Parent $PSCommandPath
$Global:LogsDir          = 'C:\Windows\Logs\apStore_Toolkit'
$Global:SelectedConfig   = $null

$Global:HomeUrls         = @()
$Global:HomeSingle       = $null
# Preset di default: RustDesk incluso
$Global:PresetPackages   = @('7zip','googlechrome','firefox','notepadplusplus','git','vscode','vlc','rustdesk')
$Global:DisableSleep     = $false
$Global:SetChromeDefault = $false
$Global:AutoReboot       = $false
$Global:SkipKB           = @()
$Global:IncludeDrivers   = $false

$Global:WallDestRoot     = 'C:\Windows\Web\apStore'
$Global:WallpaperPath    = $null
$Global:WallpaperStyle   = 10   # 0=center, 2=stretch, 6=fit, 10=fill

New-Item -ItemType Directory -Force -Path $Global:LogsDir      | Out-Null
New-Item -ItemType Directory -Force -Path $Global:WallDestRoot | Out-Null

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

# ===== Barra di avanzamento testuale =====
function Show-Progress($current, $total, $label){
  if($total -le 0){ $total = 1 }
  $pct  = [int](($current / $total) * 100)
  if($pct -lt 0){ $pct = 0 }
  if($pct -gt 100){ $pct = 100 }
  $bars = [int]([math]::Round($pct / 5.0))
  $bar  = ('#' * $bars).PadRight(20, '.')
  Write-Host ("`r[{0}] {1,3}%  {2}   " -f $bar, $pct, $label) -NoNewline
  if($pct -eq 100){ Write-Host "" }
}

# ===== CONFIG =====
function Detect-Config(){
  $candidates = @(
    (Join-Path $Global:ScriptDir 'config-apstore.txt'),
    (Join-Path $Global:ScriptDir 'config-base.txt'),
    (Join-Path $Global:ScriptDir 'config.txt')
  )

  foreach($c in $candidates){
    if(Test-Path $c){
      $Global:SelectedConfig = $c
      break
    }
  }

  if($Global:SelectedConfig){
    Write-Info ("Config selezionato: {0}" -f (Split-Path $Global:SelectedConfig -Leaf))
  } else {
    Write-Warn "Nessun file config trovato nella cartella dello script."
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
    $home = [regex]::Match($hp,'(?m)^\s*Home\s*=\s*(.+)$')
    if($urls.Success){
      $Global:HomeUrls = ($urls.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if($home.Success){
      $Global:HomeSingle = $home.Groups[1].Value.Trim()
    }
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
    if($ds.Success){
      $v = $ds.Groups[1].Value.Trim().ToLower()
      $Global:DisableSleep = @('true','1','yes','on').Contains($v)
    }
    if($cd.Success){
      $v = $cd.Groups[1].Value.Trim().ToLower()
      $Global:SetChromeDefault = @('true','1','yes','on').Contains($v)
    }
  }

  # UPDATES
  $up = Parse-Section $raw 'UPDATES'
  if($up){
    $ar = [regex]::Match($up,'(?m)^\s*AutoReboot\s*=\s*(.+)$')
    $sk = [regex]::Match($up,'(?m)^\s*SkipKB\s*=\s*(.+)$')
    $dr = [regex]::Match($up,'(?m)^\s*IncludeDrivers\s*=\s*(.+)$')
    if($ar.Success){
      $v = $ar.Groups[1].Value.Trim().ToLower()
      $Global:AutoReboot = @('true','1','yes','on').Contains($v)
    }
    if($sk.Success){
      $Global:SkipKB = ($sk.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if($dr.Success){
      $v = $dr.Groups[1].Value.Trim().ToLower()
      $Global:IncludeDrivers = @('true','1','yes','on').Contains($v)
    }
  }

  # WALLPAPER
  $wp = Parse-Section $raw 'WALLPAPER'
  if($wp){
    $p  = [regex]::Match($wp,'(?m)^\s*Path\s*=\s*(.+)$')
    $st = [regex]::Match($wp,'(?m)^\s*Style\s*=\s*(.+)$')
    if($p.Success){
      $Global:WallpaperPath = $p.Groups[1].Value.Trim()
    }
    if($st.Success){
      $val = $st.Groups[1].Value.Trim()
      if($val -match '^\d+$'){ $Global:WallpaperStyle = [int]$val }
      else{
        switch($val.ToLower()){
          'center'  { $Global:WallpaperStyle = 0 }
          'stretch' { $Global:WallpaperStyle = 2 }
          'fit'     { $Global:WallpaperStyle = 6 }
          'fill'    { $Global:WallpaperStyle = 10 }
        }
      }
    }
  }
}

# ===== SISTEMA =====
function System-SetChromeDefault(){
  try{
    Write-Info "Imposto Chrome come browser predefinito..."
    $chrome = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
    if(-not $chrome){
      $c1 = "$Env:ProgramFiles\Google\Chrome\Application\chrome.exe"
      $c2 = "$Env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
      foreach($p in @($c1,$c2)){ if(Test-Path $p){ $chrome=$p; break } }
    }
    if(-not $chrome){
      Write-Warn "Chrome non trovato. Salto."
      return
    }
    Start-Process -FilePath $chrome -ArgumentList "--make-default-browser" -WindowStyle Normal

    $xmlLines = @(
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<DefaultAssociations>',
      '  <Association Identifier=".htm" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier=".shtml" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier=".xht" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier=".xhtml" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier="http" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />',
      '</DefaultAssociations>'
    )
    $tmp = Join-Path $env:TEMP "apStore_DefaultApps_Chrome.xml"
    Set-Content -Path $tmp -Value $xmlLines -Encoding UTF8
    Start-Process -FilePath dism.exe -ArgumentList "/Online","/Import-DefaultAppAssociations:$tmp" -Wait -NoNewWindow | Out-Null
  }catch{
    Write-Warn $_.Exception.Message
  }
}

function System-DisableSleep(){
  try{
    Write-Info "Disabilito sospensione e ibernazione..."
    powercfg -x -standby-timeout-ac 0 | Out-Null
    powercfg -x -standby-timeout-dc 0 | Out-Null
    powercfg -h off | Out-Null
  }catch{
    Write-Warn $_.Exception.Message
  }
}

# ===== PERSONALIZZAZIONE =====
function Apply-Homepages-FromConfig(){
  if(-not $Global:HomeUrls -or $Global:HomeUrls.Count -eq 0){
    Write-Warn "Nessuna URL definita nel config."
    return
  }
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

  Write-Info "Homepage impostate."
}

function Apply-Wallpaper-FromConfig(){
  if([string]::IsNullOrWhiteSpace($Global:WallpaperPath) -or -not (Test-Path $Global:WallpaperPath)){
    Write-Warn "Wallpaper non impostato o file non trovato: $($Global:WallpaperPath)"
    return
  }

  try{
    $src = (Resolve-Path $Global:WallpaperPath).Path
    $ext = [IO.Path]::GetExtension($src)
    if(-not $ext){ $ext = '.jpg' }
    $dest = Join-Path $Global:WallDestRoot ("apStore_wallpaper" + $ext)

    Copy-Item -Path $src -Destination $dest -Force

    $regCP = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $regCP -Name Wallpaper      -Value $dest
    Set-ItemProperty -Path $regCP -Name WallpaperStyle -Value ([string]$Global:WallpaperStyle)
    Set-ItemProperty -Path $regCP -Name TileWallpaper  -Value "0"

    try { rundll32.exe user32.dll,UpdatePerUserSystemParameters } catch {}

    Write-Info ("Wallpaper applicato: {0} (Style={1})" -f $dest, $Global:WallpaperStyle)
  }catch{
    Write-Warn "Errore applicando wallpaper: $_"
  }
}

# ===== APPS =====
function Ensure-Choco(){
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if($choco){ return $true }
  Write-Info "Installo Chocolatey..."
  try{
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $install = "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    powershell -NoProfile -ExecutionPolicy Bypass -Command $install
    Start-Sleep -Seconds 3
    return (Get-Command choco.exe -ErrorAction SilentlyContinue) -ne $null
  }catch{
    Write-Warn $_.Exception.Message
    return $false
  }
}

function Install-ChocoPackages([string[]]$Pkgs){
  if(-not $Pkgs -or $Pkgs.Count -eq 0){
    Write-Warn "Nessun pacchetto da installare."
    return
  }
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if(-not $choco){
    if(-not (Ensure-Choco)){ throw "Chocolatey non installato." }
    $choco = Get-Command choco.exe -ErrorAction Stop
  }

  $total = $Pkgs.Count
  for($i=0; $i -lt $total; $i++){
    $p = $Pkgs[$i]
    Show-Progress ($i) $total ("Preparazione: $p")
    $args = @('install', $p, '-y', '--no-progress','--ignore-checksums')
    $proc = Start-Process -FilePath $choco.Source -ArgumentList $args -NoNewWindow -PassThru -Wait
    if($proc.ExitCode -ne 0){
      Write-Warn ("ExitCode {0} per {1}" -f $proc.ExitCode,$p)
    }
    Show-Progress ($i+1) $total ("Installato: $p")
  }
  Write-Info "Installazione pacchetti completata."
}

function Update-Apps(){
  Write-Info "Aggiorno applicazioni (winget / choco)..."
  $steps = @()
  if(Get-Command winget -ErrorAction SilentlyContinue){ $steps += 'winget' }
  if(Get-Command choco  -ErrorAction SilentlyContinue){ $steps += 'choco' }
  $total = $steps.Count
  if($total -eq 0){
    Write-Warn "Nessun gestore pacchetti trovato."
    return
  }

  $i = 0
  if($steps -contains 'winget'){
    Show-Progress $i $total "Winget upgrade..."
    try{
      winget upgrade --all --silent --accept-package-agreements --accept-source-agreements | Out-Null
    }catch{
      Write-Warn "Winget update: $_"
    }
    $i++; Show-Progress $i $total "Winget completato"
  }
  if($steps -contains 'choco'){
    Show-Progress $i $total "Choco upgrade..."
    try{
      choco upgrade all -y --no-progress --ignore-checksums | Out-Null
    }catch{
      Write-Warn "Choco update: $_"
    }
    $i++; Show-Progress $i $total "Choco completato"
  }
  Write-Info "Aggiornamento app completato."
}

# ===== WINDOWS UPDATE =====
function WU-ScanInstall(
  [switch]$OnlyScan,
  [switch]$WithDrivers,
  [string[]]$SkipKB,
  [switch]$AutoReboot,
  [switch]$OnlyDrivers
){
  try{
    Write-Info "Uso Windows Update COM nativo."
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $criteria = 'IsInstalled=0 and IsHidden=0'
    $sr = $searcher.Search($criteria)
    if(-not $sr -or $sr.Updates.Count -eq 0){
      Write-Info "Nessun aggiornamento disponibile."
      return
    }

    $queue = New-Object 'System.Collections.Generic.List[Object]'
    for($i=0;$i -lt $sr.Updates.Count;$i++){
      $u=$sr.Updates.Item($i)
      $isDriver=$false
      foreach($c in $u.Categories){ if($c.Name -match 'Driver|Drivers'){ $isDriver=$true; break } }

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
      }elseif($WithDrivers){
        $queue.Add($u)
      }else{
        if(-not $isDriver){ $queue.Add($u) }
      }
    }

    $total = $queue.Count
    if($total -eq 0){
      Write-Info "Nessun aggiornamento dopo i filtri."
      return
    }

    if($OnlyScan){
      Write-Info ("Trovati {0} aggiornamenti (solo scansione)." -f $total)
      return
    }

    # Download per elemento
    $dlCount = 0
    for($i=0; $i -lt $total; $i++){
      $u = $queue[$i]
      $titleShort = $u.Title
      if($titleShort.Length -gt 50){ $titleShort = $titleShort.Substring(0,50) + "..." }

      if(-not $u.IsDownloaded){
        Show-Progress $i $total ("Download: " + $titleShort)
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$coll.Add($u)
        $down = $session.CreateUpdateDownloader()
        $down.Updates = $coll
        $null = $down.Download()
        $dlCount++
      }
      Show-Progress ($i+1) $total ("Download: " + $titleShort)
    }
    if($dlCount -gt 0){
      Write-Info ("Download completati: {0}/{1}" -f $dlCount,$total)
    } else {
      Write-Info "Tutti gli aggiornamenti erano già scaricati."
    }

    # Installazione per elemento
    Write-Info ("Installazione: {0}" -f $total)
    for($i=0; $i -lt $total; $i++){
      $u = $queue[$i]
      $titleShort = $u.Title
      if($titleShort.Length -gt 50){ $titleShort = $titleShort.Substring(0,50) + "..." }

      Show-Progress $i $total ("Installo: " + $titleShort)
      $coll = New-Object -ComObject Microsoft.Update.UpdateColl
      [void]$coll.Add($u)
      $inst = $session.CreateUpdateInstaller()
      $inst.Updates = $coll
      $res = $inst.Install()
      Show-Progress ($i+1) $total ("Installato: " + $titleShort)
    }

    # rileva eventuale richiesta di riavvio
    $needsReboot = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) -ne $null
    if($needsReboot){
      Write-Warn "Riavvio richiesto."
      if($AutoReboot){
        Write-Info "AutoReboot=TRUE: riavvio tra 5 secondi..."
        Start-Sleep -Seconds 5
        Restart-Computer -Force
      }
    }else{
      Write-Info "Installazione completata senza riavvio."
    }
  }catch{
    Write-Err $_.Exception.Message
  }
}

# ===== MENU =====
function Menu-Main(){
  Write-Host ""
  Write-Host "================ apStore Toolkit $($Global:Version) ================" -ForegroundColor Cyan
  Write-Host "[1] Installazione Programmi (Chocolatey)"
  Write-Host "[2] Personalizzazione (Homepage + Wallpaper da config)"
  Write-Host "[3] Sistema (Chrome default / sospensione)"
  Write-Host "[4] Aggiornamenti (Driver / OS / App / Tutto)"
  Write-Host "[5] Esegui TUTTO (rispetta il config)"
  Write-Host "[0] Esci"
  Write-Host "-------------------------------------------------------------------"
  return (Read-Host "Seleziona")
}

function Menu-Updates(){
  Write-Host ""
  Write-Host "---------------------- Aggiornamenti ----------------------" -ForegroundColor Cyan
  Write-Host ("AutoReboot={0}  IncludeDrivers={1}  SkipKB={2}" -f $Global:AutoReboot, $Global:IncludeDrivers, ($(if($Global:SkipKB){$Global:SkipKB -join ','}else{'(nessuna)'})))
  Write-Host "[1] Driver (solo driver via Windows Update)"
  Write-Host "[2] OS (solo aggiornamenti di sistema, niente driver)"
  Write-Host "[3] App (Winget / Choco)"
  Write-Host "[4] TUTTO (App + OS + Driver secondo config)"
  Write-Host "[B] Indietro"
  Write-Host "-----------------------------------------------------------"
  return (Read-Host "Seleziona")
}

function Updates-Loop(){
  :U while($true){
    $u = Menu-Updates
    switch($u.ToUpper()){
      '1' { WU-ScanInstall -OnlyDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB }
      '2' { WU-ScanInstall -WithDrivers:$false -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB }
      '3' { Update-Apps }
      '4' {
        Update-Apps
        WU-ScanInstall -WithDrivers:$Global:IncludeDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB
        Write-Host "`n=== Aggiornamenti COMPLETI eseguiti ===" -ForegroundColor Green
      }
      'B' { break U }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# ===== ESEGUI TUTTO =====
function Run-All(){
  Write-Info "Esecuzione completa avviata."

  # Punto di ripristino
  try {
    Write-Info "Creo un punto di ripristino..."
    $desc = "apStore Toolkit - " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    Checkpoint-Computer -Description $desc -RestorePointType "MODIFY_SETTINGS"
    Write-Info "Punto di ripristino creato con successo."
  } catch {
    Write-Warn "Impossibile creare il punto di ripristino (servizio disattivo o privilegi insufficienti)."
  }

  try{
    Write-Info ("Pacchetti preset: {0}" -f ($Global:PresetPackages -join ", "))
    Install-ChocoPackages -Pkgs $Global:PresetPackages
  }catch{ Write-Warn $_.Exception.Message }

  try{
    if($Global:SetChromeDefault){ System-SetChromeDefault } else { Write-Warn "SetChromeDefault=false (config)." }
    if($Global:DisableSleep){ System-DisableSleep } else { Write-Warn "DisableSleep=false (config)." }
  }catch{ Write-Warn $_.Exception.Message }

  try{
    Apply-Homepages-FromConfig
    Apply-Wallpaper-FromConfig
  }catch{ Write-Warn $_.Exception.Message }

  try{
    WU-ScanInstall -WithDrivers:$Global:IncludeDrivers -AutoReboot:$Global:AutoReboot -SkipKB:$Global:SkipKB
  }catch{ Write-Warn $_.Exception.Message }

  Write-Host ""
  Write-Host "=== Esecuzione completa terminata ===" -ForegroundColor Green
}

# ===== AVVIO =====
Detect-Config
Load-Config
Start-Log

:MAIN while($true){
  $c = Menu-Main
  switch($c){
    '1' { Install-ChocoPackages -Pkgs $Global:PresetPackages }
    '2' {
      Apply-Homepages-FromConfig
      Apply-Wallpaper-FromConfig
    }
    '3' {
      if($Global:SetChromeDefault){ System-SetChromeDefault } else { Write-Warn "SetChromeDefault=false (config)." }
      if($Global:DisableSleep){ System-DisableSleep } else { Write-Warn "DisableSleep=false (config)." }
    }
    '4' { Updates-Loop }
    '5' { Run-All }
    '0' { break MAIN }
    default { Write-Host "Scelta non valida." }
  }
}

Stop-Log
if($Hold -or $true){ Read-Host "Operazioni concluse. Premi INVIO per chiudere" }
