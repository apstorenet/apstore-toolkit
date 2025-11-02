@echo off
setlocal EnableExtensions EnableDelayedExpansion
title apStore Toolkit v1.8.1 - Automazione Windows Completa

:: ==== Auto-elevazione UAC ====
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

:: ==== Estrai blocco PowerShell ====
set "PSFILE=%TEMP%\apStore_Toolkit_Run.ps1"
for /f "delims=:" %%A in ('findstr /n /c:":#PS1" "%~f0"') do set "LINE=%%A"
if not defined LINE (
  echo [ERRORE] Marker :#PS1 non trovato in %~f0
  pause & exit /b 1
)
set /a SKIP=%LINE%
more +%SKIP% "%~f0" > "%PSFILE%"
if not exist "%PSFILE%" (
  echo [ERRORE] Impossibile creare lo script: %PSFILE%
  pause & exit /b 1
)

:: Avvia PowerShell (bypass policy). No -NoExit per evitare tabelle corrotte se si chiude con CTRL+C
powershell -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
exit /b


:#PS1
<# =====================================================================
  apStore Toolkit v1.8.1 (hotfix)
  Autore: Antonio Piccolo - apstore.net
  Ultimo aggiornamento: 02/11/2025
  --------------------------------------------------------------------
  Moduli:
   [1] Gestione Utenti
   [2] Installazione Programmi (Chocolatey)
   [3] Personalizzazione (homepage + wallpaper)
   [4] Aggiornamenti (Driver / OS / App / Tutto)
   [6] Sistema (Chrome predef., disabilita sospensione)
   [5] Esegui TUTTO
   [9] Cambia profilo config
   [0] Esci
===================================================================== #>

param([switch]$Hold)
$ErrorActionPreference = 'Stop'

# === Globali ===
$Global:ToolkitVersion = 'v1.8.1'
$Global:ConfigDir      = Split-Path -Parent $PSCommandPath
$Global:LastConfigFile = Join-Path $Global:ConfigDir '.lastconfig'
$Global:ProfilesRoot   = Join-Path $Global:ConfigDir 'profiles'
New-Item $Global:ProfilesRoot -ItemType Directory -Force | Out-Null

# === Utils ===
function Write-Info($m){ Write-Host "[INFO]  $m" }
function Write-Warn($m){ Write-Warning $m }
function Write-Err ($m){ Write-Error $m }
function Ensure-Folder($p){ if(-not(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

# === Config files ===
function List-ConfigFiles(){ Get-ChildItem -Path $Global:ConfigDir -Filter 'config*.txt' -File -ErrorAction SilentlyContinue }
function Get-ActiveConfigName(){
  if($Global:SelectedConfigPath -and (Test-Path $Global:SelectedConfigPath)){
    return (Split-Path $Global:SelectedConfigPath -Leaf)
  }
  return "(nessun profilo)"
}
function Save-LastConfig(){
  try{
    if($Global:SelectedConfigPath){
      Set-Content -Path $Global:LastConfigFile -Value $Global:SelectedConfigPath -Encoding UTF8
    }
  }catch{}
}
function Load-LastConfig(){
  try{
    if(Test-Path $Global:LastConfigFile){
      $p = Get-Content -Raw $Global:LastConfigFile
      if(Test-Path $p){
        $Global:SelectedConfigPath = $p
        Write-Info ("Ultimo profilo: {0}" -f (Split-Path $p -Leaf))
      }
    }
  }catch{}
}
function Select-ConfigFile(){
  $list = List-ConfigFiles
  if(-not $list){ Write-Warn ("Nessun file config trovato in {0}" -f $Global:ConfigDir); return }
  Write-Host ""
  Write-Host "------------------ Profili di Configurazione ------------------" -ForegroundColor Cyan
  $i=1; foreach($f in $list){ Write-Host ("[{0}] {1}" -f $i, $f.Name); $i++ }
  Write-Host "[B] Indietro"
  $s = Read-Host "Seleziona profilo (numero)"
  if($s.ToUpper() -eq 'B'){ return }
  if($s -match '^\d+$'){
    $idx = [int]$s
    if($idx -ge 1 -and $idx -le $list.Count){
      $Global:SelectedConfigPath = $list[$idx-1].FullName
      Save-LastConfig
      Write-Info ("Profilo selezionato: {0}" -f (Split-Path $Global:SelectedConfigPath -Leaf))
    } else { Write-Warn "Scelta non valida." }
  } else { Write-Warn "Scelta non valida." }
}

# === Header ===
function Show-Header(){
  Write-Host ""
  Write-Host ("apStore Toolkit {0}" -f $Global:ToolkitVersion) -ForegroundColor Cyan
  Write-Host "Autore: Antonio Piccolo - apstore.net" -ForegroundColor DarkCyan
  Write-Host "Ultimo aggiornamento: 02/11/2025" -ForegroundColor DarkGray
  Write-Host ("Config attiva: {0}" -f (Get-ActiveConfigName)) -ForegroundColor Green
  Write-Host "-----------------------------------------------------------------"
}

# === Gestione Utenti ===
function Get-AdminsHash(){
  $h=@{}; try{ (Get-LocalGroupMember -Group 'Administrators') | ForEach-Object{
    $n = $_.Name -replace '^[^\\]+\\',''
    $h[$n] = $true
  } }catch{}; return $h
}
function Show-LocalUsers(){
  try{
    $admins = Get-AdminsHash
    $users  = Get-LocalUser | Sort-Object Name
    Write-Host ""
    Write-Host ("{0,-24} {1,-6} {2,-5}" -f "Utente","Attivo","Admin") -ForegroundColor Yellow
    foreach($u in $users){
      $isAdmin = $(if($admins.ContainsKey($u.Name)){"Yes"}else{"No"})
      $enabled = $(if($u.Enabled){"Yes"}else{"No"})
      Write-Host ("{0,-24} {1,-6} {2,-5}" -f $u.Name,$enabled,$isAdmin)
    }
  }catch{ Write-Warn $_.Exception.Message }
}
function Ensure-LocalUserFull([string]$Old,[string]$New,[string]$Password,[bool]$Admins,[bool]$NeverExp){
  if([string]::IsNullOrWhiteSpace($Password)){ throw "Password non specificata." }
  if($Old -and $New -and $Old -ne $New){
    try{ Rename-LocalUser -Name $Old -NewName $New }catch{}
  }
  $name = if($New){$New}else{$Old}
  $sec  = ConvertTo-SecureString $Password -AsPlainText -Force
  $u    = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
  if($u){ Set-LocalUser -Name $name -Password $sec -ErrorAction SilentlyContinue }
  else{ New-LocalUser -Name $name -Password $sec -FullName $name -AccountNeverExpires:$true -PasswordNeverExpires:$NeverExp | Out-Null }
  if($Admins){ Add-LocalGroupMember -Group "Administrators" -Member $name -ErrorAction SilentlyContinue }
}
function Menu-Utenti(){
  Write-Host ""
  Write-Host "[L] Lista utenti locali"
  Write-Host "[1] Crea o rinomina utente"
  Write-Host "[2] Imposta password"
  Write-Host "[3] Aggiungi ad Administrators"
  Write-Host "[B] Indietro"
  return (Read-Host "Seleziona")
}
function Utenti-Loop(){
  :UT while($true){
    Show-LocalUsers
    $c = Menu-Utenti
    switch($c.ToUpper()){
      'L' { Show-LocalUsers }
      '1' {
        $n = Read-Host "Nome utente"
        $p = Read-Host "Password"
        Ensure-LocalUserFull -Old $n -New $n -Password $p -Admins:$true -NeverExp:$true
      }
      '2' {
        $n = Read-Host "Nome"
        $p = Read-Host "Nuova password"
        Ensure-LocalUserFull -Old $n -New $n -Password $p -Admins:$false -NeverExp:$true
      }
      '3' {
        $n = Read-Host "Nome"
        try{ Add-LocalGroupMember -Group "Administrators" -Member $n -ErrorAction Stop; Write-Info "Aggiunto." }catch{ Write-Warn $_.Exception.Message }
      }
      'B' { break UT }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# === Installazione Programmi (Chocolatey) ===
$Global:PresetPackages = @("7zip","googlechrome","firefox","notepadplusplus","git","vscode","vlc")
function Ensure-Choco(){
  $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
  if($choco){ Write-Info ("Chocolatey presente: {0}" -f $choco.Source); return $true }
  Write-Info "Installo Chocolatey..."
  try{
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $install = "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol=[System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    powershell -NoProfile -ExecutionPolicy Bypass -Command $install
    Start-Sleep -Seconds 3
    return (Get-Command choco.exe -ErrorAction SilentlyContinue) -ne $null
  }catch{ Write-Err $_.Exception.Message; return $false }
}
function Install-ChocoPackages([string[]]$Pkgs){
  if(-not (Ensure-Choco)){ throw "Chocolatey non installato." }
  $choco = (Get-Command choco.exe -ErrorAction Stop).Source
  foreach($p in $Pkgs){
    if([string]::IsNullOrWhiteSpace($p)){ continue }
    Write-Info ("Installo: {0}" -f $p)
    $proc = Start-Process -FilePath $choco -ArgumentList @('install', $p, '-y', '--no-progress', '--ignore-checksums') -NoNewWindow -PassThru -Wait
    if($proc.ExitCode -ne 0){ Write-Warn ("ExitCode {0} per {1}" -f $proc.ExitCode,$p) }
  }
  Write-Info "Installazione pacchetti completata."
}
function Menu-App(){
  Write-Host ""
  Write-Host "---------------- Installazione Programmi (Chocolatey) ---------------" -ForegroundColor Cyan
  Write-Host "[1] Installa pacchetti di base (preset)"
  Write-Host "[2] Installa pacchetti scelti a mano"
  Write-Host "[B] Indietro"
  Write-Host "---------------------------------------------------------------------"
  return (Read-Host "Seleziona")
}
function App-Loop(){
  :APP while($true){
    $c = Menu-App
    switch($c.ToUpper()){
      '1' { Install-ChocoPackages -Pkgs $Global:PresetPackages }
      '2' {
        $inp = Read-Host "Inserisci pacchetti separati da virgola (es: anydesk,putty,winrar)"
        if([string]::IsNullOrWhiteSpace($inp)){ Write-Warn "Nessun pacchetto inserito."; break }
        $pk = ($inp -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Install-ChocoPackages -Pkgs $pk
      }
      'B' { break APP }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# === Personalizzazione (Home + Wallpaper) ===
function Apply-Homepages($Profile){
  $urls = $Profile.HomeUrls
  $single = if([string]::IsNullOrWhiteSpace($Profile.HomeSingle)){ $urls[0] } else { $Profile.HomeSingle }
  if(-not $urls -or $urls.Count -eq 0){ throw "Nessuna URL nel profilo." }
  $chrome = "HKCU:\Software\Policies\Google\Chrome"; Ensure-Folder $chrome
  New-ItemProperty -Path $chrome -Name HomepageIsNewTabPage -Value 0 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $chrome -Name RestoreOnStartup   -Value 4 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $chrome -Name RestoreOnStartupURLs -Value $urls -PropertyType MultiString -Force | Out-Null
  if($single){ New-ItemProperty -Path $chrome -Name HomepageLocation -Value $single -PropertyType String -Force | Out-Null }
  $edge = "HKCU:\Software\Policies\Microsoft\Edge"; Ensure-Folder $edge
  New-ItemProperty -Path $edge -Name HomepageIsNewTabPage -Value 0 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $edge -Name RestoreOnStartup   -Value 4 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $edge -Name RestoreOnStartupURLs -Value $urls -PropertyType MultiString -Force | Out-Null
  if($single){ New-ItemProperty -Path $edge -Name HomepageLocation -Value $single -PropertyType String -Force | Out-Null }
  $ffBase = "HKCU:\Software\Policies\Mozilla\Firefox"; Ensure-Folder $ffBase
  $ffHome = Join-Path $ffBase "Homepage"; Ensure-Folder $ffHome
  New-ItemProperty -Path $ffHome -Name StartPage -Value "homepage" -PropertyType String -Force | Out-Null
  if($single){ New-ItemProperty -Path $ffHome -Name URL -Value $single -PropertyType String -Force | Out-Null }
  Write-Info "Homepage impostate per l'utente corrente (riavvia i browser)."
}
function Apply-WallpaperByPath([string]$Path,[int]$Style=10){
  if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)){ throw "Immagine non trovata: $Path" }
  $destRoot = 'C:\Windows\Web\apStore'; Ensure-Folder $destRoot
  $destFile = Join-Path $destRoot ("apStore_wallpaper.jpg")
  Copy-Item -Path $Path -Destination $destFile -Force
  $regCP = "HKCU:\Control Panel\Desktop"
  Set-ItemProperty -Path $regCP -Name Wallpaper      -Value $destFile
  Set-ItemProperty -Path $regCP -Name WallpaperStyle -Value ([string]$Style)
  Set-ItemProperty -Path $regCP -Name TileWallpaper  -Value "0"
  rundll32.exe user32.dll,UpdatePerUserSystemParameters
  Write-Info ("Wallpaper applicato: {0}" -f $destFile)
}

# === Aggiornamenti ===
function Update-Apps(){
  $did=$false
  if(Get-Command winget -ErrorAction SilentlyContinue){
    Write-Info "Aggiorno App con Winget (Store)..."
    try{ winget upgrade --all --silent --accept-package-agreements --accept-source-agreements | Out-Null; $did=$true }catch{}
  }
  if(Get-Command choco -ErrorAction SilentlyContinue){
    Write-Info "Aggiorno App Chocolatey..."
    try{ choco upgrade all -y --no-progress --ignore-checksums | Out-Null; $did=$true }catch{}
  }
  if(-not $did){ Write-Warn "Nessun gestore pacchetti disponibile (winget/choco)." }
}
function WU-ScanInstall([switch]$OnlyScan,[switch]$WithDrivers,[string[]]$SkipKB,[switch]$AutoReboot,[switch]$OnlyDrivers){
  try{
    Write-Info 'Uso Windows Update COM nativo.'
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $criteria = 'IsInstalled=0 and IsHidden=0'
    $sr = $searcher.Search($criteria)
    if(-not $sr -or $sr.Updates.Count -eq 0){ Write-Info "Nessun aggiornamento disponibile."; return }

    $list = New-Object 'System.Collections.Generic.List[Object]'
    for($i=0;$i -lt $sr.Updates.Count;$i++){
      $u=$sr.Updates.Item($i)
      $isDriver=$false; foreach($c in $u.Categories){ if($c.Name -match 'Driver|Drivers'){ $isDriver=$true; break } }
      if($SkipKB -and $SkipKB.Count -gt 0){
        $title=$u.Title; $hit=$false
        foreach($k in $SkipKB){ $n=($k -replace '[^\d]',''); if($n -and $title -match ("KB{0}" -f $n)){ $hit=$true; break } }
        if($hit){ continue }
      }
      if($OnlyDrivers){
        if($isDriver){ $list.Add($u) | Out-Null }
        continue
      }
      if($WithDrivers){ $list.Add($u) | Out-Null; continue }
      if(-not $isDriver){ $list.Add($u) | Out-Null }
    }

    if($list.Count -eq 0){ Write-Info "Nessun aggiornamento dopo i filtri."; return }
    if($OnlyScan){ return }

    $toDownload=New-Object -ComObject Microsoft.Update.UpdateColl
    foreach($u in $list){ if(-not $u.IsDownloaded){ [void]$toDownload.Add($u) } }
    if($toDownload.Count -gt 0){
      Write-Info ("Download: {0}" -f $toDownload.Count)
      $d=$session.CreateUpdateDownloader(); $d.Updates=$toDownload; $null=$d.Download()
    }

    $toInstall=New-Object -ComObject Microsoft.Update.UpdateColl
    foreach($u in $list){ [void]$toInstall.Add($u) }
    Write-Info ("Installazione: {0}" -f $toInstall.Count)
    $inst=$session.CreateUpdateInstaller(); $inst.Updates=$toInstall
    $res=$inst.Install()
    if($res.RebootRequired){
      Write-Warn "Riavvio richiesto."
      if($AutoReboot){ Restart-Computer -Force }
    } else {
      Write-Info "Installazione completata senza riavvio."
    }
  }catch{ Write-Err $_.Exception.Message }
}
function Menu-Updates(){
  Write-Host ""
  Write-Host "---------------------- Aggiornamenti ----------------------" -ForegroundColor Cyan
  Write-Host "[1] Driver (solo driver via Windows Update)"
  Write-Host "[2] OS (solo aggiornamenti di sistema, niente driver)"
  Write-Host "[3] App (Store + Winget + Chocolatey)"
  Write-Host "[4] TUTTO (App + OS + Driver)"
  Write-Host "[B] Indietro"
  Write-Host "-----------------------------------------------------------"
  return (Read-Host "Seleziona")
}
function Updates-Loop(){
  :UPD while($true){
    $s = Menu-Updates
    switch($s.ToUpper()){
      '1' { WU-ScanInstall -OnlyDrivers -AutoReboot:$false }
      '2' { WU-ScanInstall -WithDrivers:$false -AutoReboot:$false }
      '3' { Update-Apps }
      '4' { Update-Apps; WU-ScanInstall -WithDrivers:$true -AutoReboot:$false; Write-Host "`n=== Aggiornamenti COMPLETI eseguiti (App + OS + Driver) ===" -ForegroundColor Green }
      'B' { break UPD }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# === Sistema ===
function System-SetChromeDefault(){
  try{
    $chrome = (Get-Command chrome.exe -ErrorAction SilentlyContinue).Source
    if(-not $chrome){
      $paths = @("$Env:ProgramFiles\Google\Chrome\Application\chrome.exe","$Env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe")
      foreach($p in $paths){ if(Test-Path $p){ $chrome = $p; break } }
    }
    if(-not $chrome){ throw "Chrome non trovato." }
    Start-Process -FilePath $chrome -ArgumentList "--make-default-browser" -Verb Open -WindowStyle Normal
    Start-Sleep -Seconds 2
    $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".htm"  ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="http"  ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https" ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
"@
    $tmp = Join-Path $env:TEMP "apStore_DefaultApps_Chrome.xml"
    $xml | Set-Content -Path $tmp -Encoding UTF8
    Start-Process -FilePath dism.exe -ArgumentList "/Online","/Import-DefaultAppAssociations:$tmp" -NoNewWindow -Wait | Out-Null
    Write-Info "Chrome impostato (su Windows 11 potrebbe servire conferma nella UI)."
  }catch{ Write-Warn $_.Exception.Message }
}
function System-DisableSleep(){
  try{
    Write-Info "Disabilito sospensione (AC/DC) e ibernazione..."
    powercfg -x -standby-timeout-ac 0 | Out-Null
    powercfg -x -standby-timeout-dc 0 | Out-Null
    powercfg -h off | Out-Null
    Write-Info "Sospensione disabilitata e ibernazione OFF."
  }catch{ Write-Warn $_.Exception.Message }
}
function Menu-System(){
  Write-Host ""
  Write-Host "------------------------ Sistema ------------------------" -ForegroundColor Cyan
  Write-Host "[1] Imposta Chrome come browser predefinito"
  Write-Host "[2] Disabilita sospensione (AC/DC) e ibernazione"
  Write-Host "[B] Indietro"
  Write-Host "---------------------------------------------------------"
  return (Read-Host "Seleziona")
}
function System-Loop(){
  :SYS while($true){
    $c = Menu-System
    switch($c.ToUpper()){
      '1' { System-SetChromeDefault }
      '2' { System-DisableSleep }
      'B' { break SYS }
      default { Write-Host "Scelta non valida." }
    }
  }
}

# === Esegui TUTTO ===
function Run-All(){
  Write-Info "Esecuzione completa..."
  try{ Install-ChocoPackages -Pkgs $Global:PresetPackages }catch{ Write-Warn $_.Exception.Message }
  try{ System-SetChromeDefault }catch{ Write-Warn $_.Exception.Message }
  try{ System-DisableSleep }catch{ Write-Warn $_.Exception.Message }
  try{
    # Personalizzazione da config attiva (se presente)
    if($Global:SelectedConfigPath -and (Test-Path $Global:SelectedConfigPath)){
      $cfg = Get-Content -Raw $Global:SelectedConfigPath
      $urls = @()
      if($cfg -match '(?m)^\[HOMEPAGE\]'){
        $m = [regex]::Match($cfg,'(?ms)^\[HOMEPAGE\](.+?)(^\[|$)')
        if($m.Success){
          $block=$m.Groups[1].Value
          $u=[regex]::Match($block,'(?m)^\s*Urls\s*=\s*(.+)$')
          $h=[regex]::Match($block,'(?m)^\s*Home\s*=\s*(.+)$')
          if($u.Success){ $urls = ($u.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() }) }
          $home = $(if($h.Success){ $h.Groups[1].Value.Trim() }else{ if($urls){ $urls[0] } })
          if($urls){ Apply-Homepages ([pscustomobject]@{ HomeUrls=$urls; HomeSingle=$home }) }
        }
      }
    }
  }catch{ Write-Warn $_.Exception.Message }
  try{ Update-Apps }catch{ Write-Warn $_.Exception.Message }
  try{ WU-ScanInstall -WithDrivers:$true -AutoReboot:$false }catch{ Write-Warn $_.Exception.Message }
  Write-Host ""
  Write-Host "=== Operazioni completate ===" -ForegroundColor Green
}

# === Menu Principale ===
function Main-Menu(){
  Show-Header
  Write-Host "[1] Gestione Utenti"
  Write-Host "[2] Installazione Programmi (Chocolatey)"
  Write-Host "[3] Personalizzazione (homepage + wallpaper)"
  Write-Host "[4] Aggiornamenti (Driver / OS / App / Tutto)"
  Write-Host "[6] Sistema  (Chrome predef., disabilita sospensione)"
  Write-Host "[5] Esegui TUTTO"
  Write-Host "[9] Cambia profilo config"
  Write-Host "[0] Esci"
  Write-Host "-----------------------------------------------------------------"
  return (Read-Host "Seleziona opzione")
}

# === Avvio ===
# Autoselezione profilo
Load-LastConfig
if(-not $Global:SelectedConfigPath){
  $list = List-ConfigFiles
  if($list -and $list.Count -eq 1){
    $Global:SelectedConfigPath = $list[0].FullName
    Save-LastConfig
    Write-Info ("Profilo auto-selezionato: {0}" -f $list[0].Name)
  } elseif(Test-Path (Join-Path $Global:ConfigDir 'config-apstore.txt')){
    $Global:SelectedConfigPath = (Join-Path $Global:ConfigDir 'config-apstore.txt')
    Save-LastConfig
    Write-Info "Profilo auto-selezionato: config-apstore.txt"
  } elseif(Test-Path (Join-Path $Global:ConfigDir 'config.txt')){
    $Global:SelectedConfigPath = (Join-Path $Global:ConfigDir 'config.txt')
    Save-LastConfig
    Write-Info "Profilo auto-selezionato: config.txt"
  }
}

:MAIN while($true){
  $choice = Main-Menu
  switch($choice){
    '1' { Utenti-Loop }
    '2' { App-Loop }
    '3' { Write-Host "Gestione profili personalizzazione via menu non interattivo. Usa Esegui TUTTO oppure config." }
    '4' { Updates-Loop }
    '6' { System-Loop }
    '5' { Run-All }
    '9' { Select-ConfigFile }
    '0' { break MAIN }
    default { Write-Host "Scelta non valida." }
  }
}
