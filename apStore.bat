@echo off
setlocal EnableExtensions EnableDelayedExpansion
title apStore Toolkit v1.8 - Automazione Windows Completa

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
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%PSFILE%"
exit /b

:#PS1
<# =====================================================================
  apStore Toolkit v1.8
  Autore: Antonio Piccolo — apstore.net
  Ultimo aggiornamento: 30/10/2025
  --------------------------------------------------------------------
  Moduli inclusi:
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
$ErrorActionPreference='Stop'

# === Variabili Globali ===
$Global:ToolkitVersion = 'v1.8'
$Global:ConfigDir = Split-Path -Parent $PSCommandPath
$Global:LastConfigFile = Join-Path $Global:ConfigDir '.lastconfig'
$Global:ProfilesRoot = Join-Path $Global:ConfigDir 'profiles'
New-Item $ProfilesRoot -ItemType Directory -Force | Out-Null

# === Utility ===
function Write-Info($m){ Write-Host "[INFO]  $m" }
function Write-Warn($m){ Write-Warning $m }
function Write-Err ($m){ Write-Error $m }
function Ensure-Folder($p){ if(-not(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

# === Config Management ===
function List-ConfigFiles(){ Get-ChildItem -Path $Global:ConfigDir -Filter 'config*.txt' -File -ErrorAction SilentlyContinue }
function Get-ActiveConfigName(){ if($Global:SelectedConfigPath -and (Test-Path $Global:SelectedConfigPath)){ return (Split-Path $Global:SelectedConfigPath -Leaf) } else { return "(nessun profilo)" } }
function Save-LastConfig(){ if($Global:SelectedConfigPath){ Set-Content -Path $Global:LastConfigFile -Value $Global:SelectedConfigPath -Encoding UTF8 } }
function Load-LastConfig(){ if(Test-Path $Global:LastConfigFile){ $p=Get-Content -Raw $Global:LastConfigFile; if(Test-Path $p){ $Global:SelectedConfigPath=$p; Write-Info "Ultimo profilo: $(Split-Path $p -Leaf)" } } }

function Select-ConfigFile(){
  $list = List-ConfigFiles
  if(-not $list){ Write-Warn "Nessun file config trovato in $Global:ConfigDir"; return }
  Write-Host ""
  Write-Host "------------------ Profili di Configurazione ------------------" -ForegroundColor Cyan
  $i=1; foreach($f in $list){ Write-Host ("[{0}] {1}" -f $i, $f.Name); $i++ }
  Write-Host "[B] Indietro"
  $s = Read-Host "Seleziona profilo (numero)"
  if($s.ToUpper() -eq 'B'){ return }
  if($s -match '^\d+$'){
    $idx=[int]$s
    if($idx -ge 1 -and $idx -le $list.Count){
      $Global:SelectedConfigPath=$list[$idx-1].FullName
      Save-LastConfig
      Write-Info "Profilo selezionato: $(Split-Path $Global:SelectedConfigPath -Leaf)"
    }
  }
}

# === Intestazione ===
function Show-Header(){
  Write-Host ""
  Write-Host ("apStore Toolkit {0}" -f $Global:ToolkitVersion) -ForegroundColor Cyan
  Write-Host ("Autore: Antonio Piccolo — apstore.net") -ForegroundColor DarkCyan
  Write-Host ("Ultimo aggiornamento: 30/10/2025") -ForegroundColor DarkGray
  Write-Host ("Config attiva: {0}" -f (Get-ActiveConfigName)) -ForegroundColor Green
  Write-Host "-----------------------------------------------------------------"
}

# === Gestione Utenti (versione avanzata) ===
function Get-AdminsHash(){
  $h=@{}; try{ (Get-LocalGroupMember -Group 'Administrators') | ForEach-Object{ $n=$_.Name -replace '^[^\\]+\\',''; $h[$n]=$true } }catch{}; return $h
}
function Show-LocalUsers(){
  try{
    $admins = Get-AdminsHash
    $users  = Get-LocalUser | Sort-Object Name
    Write-Host ""
    Write-Host ("{0,-22} {1,-6} {2,-5}" -f "Utente","Attivo","Admin") -ForegroundColor Yellow
    foreach($u in $users){
      $isAdmin=$(if($admins.ContainsKey($u.Name)){"Yes"}else{"No"})
      $enabled=$(if($u.Enabled){"Yes"}else{"No"})
      Write-Host ("{0,-22} {1,-6} {2,-5}" -f $u.Name,$enabled,$isAdmin)
    }
  }catch{ Write-Warn $_.Exception.Message }
}
function Ensure-LocalUserFull([string]$Old,[string]$New,[string]$Password,[bool]$Admins,[bool]$NeverExp){
  if([string]::IsNullOrWhiteSpace($Password)){ throw "Password non specificata." }
  if($Old -and $New -and $Old -ne $New){
    try{ Rename-LocalUser -Name $Old -NewName $New }catch{}
  }
  $name=if($New){$New}else{$Old}
  $sec=ConvertTo-SecureString $Password -AsPlainText -Force
  $u=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
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
    $c=Menu-Utenti
    switch($c.ToUpper()){
      'L'{Show-LocalUsers}
      '1'{$n=Read-Host "Nome utente";$p=Read-Host "Password";Ensure-LocalUserFull -Old $n -New $n -Password $p -Admins:$true -NeverExp:$true}
      '2'{$n=Read-Host "Nome";$p=Read-Host "Nuova password";Ensure-LocalUserFull -Old $n -New $n -Password $p -Admins:$false -NeverExp:$true}
      '3'{$n=Read-Host "Nome";Add-LocalGroupMember -Group "Administrators" -Member $n -ErrorAction SilentlyContinue}
      'B'{break UT}
    }
  }
}

# === Sistema ===
function System-SetChromeDefault(){ try{ Start-Process "chrome.exe" "--make-default-browser" }catch{} }
function System-DisableSleep(){ powercfg -x -standby-timeout-ac 0; powercfg -x -standby-timeout-dc 0; powercfg -h off }

# === Aggiornamenti ===
function WU-ScanInstall([switch]$WithDrivers,[switch]$OnlyDrivers){
  try{
    $session=New-Object -ComObject Microsoft.Update.Session
    $searcher=$session.CreateUpdateSearcher()
    $sr=$searcher.Search('IsInstalled=0 and IsHidden=0')
    $list=@()
    foreach($u in $sr.Updates){
      $isDriver=$false; foreach($c in $u.Categories){ if($c.Name -match 'Driver'){ $isDriver=$true; break } }
      if($OnlyDrivers -and $isDriver){ $list+=$u }
      elseif($WithDrivers){ $list+=$u }
      elseif(-not $isDriver){ $list+=$u }
    }
    $toInstall=New-Object -ComObject Microsoft.Update.UpdateColl
    foreach($u in $list){ [void]$toInstall.Add($u) }
    $inst=$session.CreateUpdateInstaller(); $inst.Updates=$toInstall; $r=$inst.Install()
    if($r.RebootRequired){ Write-Warn "Riavvio richiesto." }
  }catch{ Write-Err $_.Exception.Message }
}
function Update-Apps(){ Write-Info "Aggiorno App (winget/choco simulato)..." }

function Menu-Updates(){
  Write-Host ""
  Write-Host "[1] Driver"
  Write-Host "[2] OS"
  Write-Host "[3] App"
  Write-Host "[4] Tutto"
  Write-Host "[B] Indietro"
  return (Read-Host "Seleziona")
}
function Updates-Loop(){
  :UPD while($true){
    $s=Menu-Updates
    switch($s){
      '1'{WU-ScanInstall -OnlyDrivers}
      '2'{WU-ScanInstall}
      '3'{Update-Apps}
      '4'{Update-Apps;WU-ScanInstall -WithDrivers}
      'B'{break UPD}
    }
  }
}

# === Run-All ===
function Run-All(){
  Write-Info "Esecuzione completa..."
  try{ Update-Apps }catch{}
  try{ System-SetChromeDefault }catch{}
  try{ System-DisableSleep }catch{}
  try{ WU-ScanInstall -WithDrivers }catch{}
  Write-Host "=== Operazioni completate ===" -ForegroundColor Green
}

# === Menu Principale ===
function Main-Menu(){
  Show-Header
  Write-Host "[1] Gestione Utenti"
  Write-Host "[2] Installazione Programmi"
  Write-Host "[3] Personalizzazione"
  Write-Host "[4] Aggiornamenti"
  Write-Host "[6] Sistema"
  Write-Host "[5] Esegui Tutto"
  Write-Host "[9] Cambia profilo config"
  Write-Host "[0] Esci"
  return (Read-Host "Scelta")
}

# === Avvio ===
Load-LastConfig
if(-not $Global:SelectedConfigPath){
  $list=List-ConfigFiles
  if($list -and $list.Count -eq 1){ $Global:SelectedConfigPath=$list[0].FullName; Save-LastConfig }
}
:MAIN while($true){
  $c=Main-Menu
  switch($c){
    '1'{Utenti-Loop}
    '4'{Updates-Loop}
    '6'{System-DisableSleep}
    '5'{Run-All}
    '9'{Select-ConfigFile}
    '0'{break MAIN}
  }
}
