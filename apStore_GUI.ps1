[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ====== Setup base ======
# Cartella dove si trova questo script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Percorso del toolkit .bat
$Global:ToolkitPath = Join-Path $ScriptDir 'apStore_Toolkit.bat'

# ====== Carica WPF ======
Add-Type -AssemblyName PresentationFramework

# XAML della finestra
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="apStore Toolkit" Height="230" Width="420"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="apStore Toolkit" FontSize="20" FontWeight="Bold" />
      <TextBlock Text="Automazione setup e post-installazione" FontSize="12" Foreground="Gray"/>
    </StackPanel>

    <!-- Pulsanti -->
    <StackPanel Grid.Row="1">
      <Button Name="btnRunAll" Height="35" Margin="0,0,0,5" Content="Esegui TUTTO (da config)" />
      <Button Name="btnOpenConfig" Height="30" Margin="0,0,0,5" Content="Apri config attivo" />
      <Button Name="btnExit" Height="30" Margin="0,10,0,0" Content="Esci" />
    </StackPanel>

    <!-- Status -->
    <StackPanel Grid.Row="2" Margin="0,10,0,0">
      <TextBlock Name="txtStatus" Text="Pronto." FontSize="11" />
    </StackPanel>
  </Grid>
</Window>
"@

# Carica il XAML
[xml]$xml = $xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Recupera i controlli
$btnRunAll    = $window.FindName("btnRunAll")
$btnOpenConfig= $window.FindName("btnOpenConfig")
$btnExit      = $window.FindName("btnExit")
$txtStatus    = $window.FindName("txtStatus")

function Set-Status($msg){
  $txtStatus.Text = $msg
}

# Trova il config attivo (stessa logica del toolkit)
function Get-ActiveConfig {
  $candidates = @(
    (Join-Path $ScriptDir 'config-apstore.txt'),
    (Join-Path $ScriptDir 'config-base.txt'),
    (Join-Path $ScriptDir 'config.txt')
  )
  foreach($c in $candidates){
    if(Test-Path $c){ return $c }
  }
  return $null
}

# ====== Eventi pulsanti ======

# Esegui TUTTO
$btnRunAll.Add_Click({
  if(-not (Test-Path $Global:ToolkitPath)){
    [System.Windows.MessageBox]::Show(
      "Non trovo apStore_Toolkit.bat in:`n$($Global:ToolkitPath)`nControlla il percorso.",
      "apStore Toolkit",
      [System.Windows.MessageBoxButton]::OK,
      [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    return
  }

  Set-Status "Avvio toolkit in modalità automatica..."
  try{
    # Esegue il .bat con parametro -Auto (usa il tuo motore esistente)
    Start-Process -FilePath $Global:ToolkitPath -ArgumentList "-Auto" -Verb RunAs | Out-Null
    Set-Status "Toolkit avviato. Controlla la finestra del toolkit."
  }catch{
    Set-Status "Errore durante l'avvio: $($_.Exception.Message)"
  }
})

# Apri config attivo
$btnOpenConfig.Add_Click({
  $cfg = Get-ActiveConfig
  if(-not $cfg){
    [System.Windows.MessageBox]::Show(
      "Nessun file config trovato in:`n$ScriptDir",
      "apStore Toolkit",
      [System.Windows.MessageBoxButton]::OK,
      [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
    return
  }

  try{
    Set-Status "Apro il config: $(Split-Path $cfg -Leaf)"
    Start-Process notepad.exe $cfg | Out-Null
  }catch{
    Set-Status "Errore durante l'apertura del config: $($_.Exception.Message)"
  }
})

# Esci
$btnExit.Add_Click({
  $window.Close()
})

# Mostra finestra
$window.ShowDialog() | Out-Null
