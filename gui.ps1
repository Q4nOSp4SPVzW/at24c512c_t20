# AT24C256 EEPROM Control GUI (WPF)
# 使用法: .\gui.ps1
#
# Sapphire SoCファームウェアの全機能をGUIから操作するダッシュボード
# - COMポート接続/切断
# - LED操作 (1-6 トグル / 全点灯 / 全消灯)
# - SW4状態リアルタイム表示
# - EEPROM読み書き (1バイト/ダンプ/フィル/テスト)
# - EEPROMタイプ切替 (256/512)
# - WDT制御 (on/off/pat)
# - システム情報表示 (id/dump)
# - ログ表示 + 生コマンド入力

param(
    [string]$DefaultPort = "COM11"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# -----------------------------------------------------------------------------
# WPF アセンブリ読み込み
# -----------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# -----------------------------------------------------------------------------
# シリアル通信ヘルパ
# -----------------------------------------------------------------------------
$script:serial = $null
$script:connected = $false

function Send-Command {
    param([string]$Cmd, [int]$WaitMs = 400)
    if (-not $script:connected) { return "" }
    try { $null = $script:serial.ReadExisting() } catch {}
    $script:serial.WriteLine($Cmd)
    Start-Sleep -Milliseconds $WaitMs
    $response = ""
    try { $response = $script:serial.ReadExisting() } catch {}
    $emptyCount = 0
    while ($emptyCount -lt 2) {
        Start-Sleep -Milliseconds 150
        $chunk = ""
        try { $chunk = $script:serial.ReadExisting() } catch {}
        if ($chunk) { $response += $chunk; $emptyCount = 0 }
        else { $emptyCount++ }
    }
    # コマンドエコーと空行を除去
    $lines = ($response -split "[\r\n]+" | Where-Object { $_.Trim() -ne "" -and $_.Trim() -ne $Cmd })
    return ($lines -join "`r`n")
}

function Connect-Serial {
    param([string]$Port)
    try {
        $script:serial = New-Object System.IO.Ports.SerialPort $Port,9600,None,8,One
        $script:serial.ReadTimeout = 5000
        $script:serial.WriteTimeout = 5000
        $script:serial.Open()
        Start-Sleep -Milliseconds 300
        $script:serial.DiscardInBuffer()
        $script:connected = $true
        return $true
    } catch {
        $script:connected = $false
        return $false
    }
}

function Disconnect-Serial {
    if ($script:serial) {
        try { $script:serial.Close() } catch {}
        $script:serial = $null
    }
    $script:connected = $false
}

# -----------------------------------------------------------------------------
# XAML UI定義
# -----------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AT24C256 EEPROM Control Panel" Height="700" Width="900"
        Background="#FF1E1E1E" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="280"/>
            <ColumnDefinition Width="10"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- 左ペイン: 操作パネル -->
        <ScrollViewer Grid.Row="0" Grid.RowSpan="2" Grid.Column="0" VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="5">

                <!-- 接続パネル -->
                <GroupBox Header="Connection" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <StackPanel Margin="5">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Label Content="Port:" Foreground="White" Width="40"/>
                            <TextBox x:Name="PortBox" Width="100" Text="$DefaultPort" Background="#FF333333" Foreground="White" BorderBrush="#FF555555"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Button x:Name="BtnConnect" Content="Connect" Width="100" Height="28" Margin="0,0,5,0" Background="#FF2D5F2D" Foreground="White"/>
                            <Button x:Name="BtnDisconnect" Content="Disconnect" Width="100" Height="28" Background="#FF5F2D2D" Foreground="White" IsEnabled="False"/>
                        </StackPanel>
                        <TextBlock x:Name="StatusText" Text="Disconnected" Foreground="#FFCCCCCC" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                    </StackPanel>
                </GroupBox>

                <!-- LED操作パネル -->
                <GroupBox Header="LED Control" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <StackPanel Margin="5">
                        <UniformGrid Columns="3" Margin="0,0,0,5">
                            <Button x:Name="Led1" Content="LED1" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="Led2" Content="LED2" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="Led3" Content="LED3" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="Led4" Content="LED4" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="Led5" Content="LED5" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="Led6" Content="LED6" Height="28" Margin="2" Background="#FF333333" Foreground="White"/>
                        </UniformGrid>
                        <UniformGrid Columns="2" Margin="0,0,0,5">
                            <Button x:Name="BtnLedAll" Content="All ON" Height="28" Margin="2" Background="#FF2D5F2D" Foreground="White"/>
                            <Button x:Name="BtnLedClear" Content="All OFF" Height="28" Margin="2" Background="#FF5F2D2D" Foreground="White"/>
                        </UniformGrid>
                    </StackPanel>
                </GroupBox>

                <!-- SW4状態 -->
                <GroupBox Header="SW4 Status" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <StackPanel Margin="5" Orientation="Horizontal" HorizontalAlignment="Center">
                        <TextBlock x:Name="Sw4Status" Text="---" FontSize="20" FontWeight="Bold" Foreground="#FFAAAAAA" VerticalAlignment="Center"/>
                        <Button x:Name="BtnSw4Refresh" Content="Refresh" Width="70" Height="28" Margin="10,0,0,0" Background="#FF333333" Foreground="White"/>
                        <CheckBox x:Name="Sw4Poll" Content="Auto" Foreground="White" Margin="10,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                </GroupBox>

                <!-- EEPROM読み書き -->
                <GroupBox Header="EEPROM Access" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <StackPanel Margin="5">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Label Content="Addr:" Foreground="White" Width="45"/>
                            <TextBox x:Name="EeAddr" Width="80" Text="0x0000" Background="#FF333333" Foreground="White" BorderBrush="#FF555555"/>
                            <Label Content="Data:" Foreground="White" Width="45" Margin="5,0,0,0"/>
                            <TextBox x:Name="EeData" Width="60" Text="0xAB" Background="#FF333333" Foreground="White" BorderBrush="#FF555555"/>
                        </StackPanel>
                        <UniformGrid Columns="2" Margin="0,0,0,5">
                            <Button x:Name="BtnEeRead" Content="Read Byte" Height="26" Margin="2" Background="#FF2D4F5F" Foreground="White"/>
                            <Button x:Name="BtnEeWrite" Content="Write Byte" Height="26" Margin="2" Background="#FF4F2D5F" Foreground="White"/>
                        </UniformGrid>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                            <Label Content="Len:" Foreground="White" Width="45"/>
                            <TextBox x:Name="EeDumpLen" Width="60" Text="16" Background="#FF333333" Foreground="White" BorderBrush="#FF555555"/>
                            <Button x:Name="BtnEeDump" Content="Dump" Width="70" Height="26" Margin="5,0,0,0" Background="#FF333333" Foreground="White"/>
                        </StackPanel>
                        <UniformGrid Columns="3" Margin="0,0,0,5">
                            <Button x:Name="BtnEeTest" Content="Test" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="BtnEeFill" Content="Fill" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                            <Button x:Name="BtnEeScan" Content="Scan" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                        </UniformGrid>
                    </StackPanel>
                </GroupBox>

                <!-- EEPROMタイプ -->
                <GroupBox Header="EEPROM Type" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <StackPanel Margin="5" Orientation="Horizontal" HorizontalAlignment="Center">
                        <RadioButton x:Name="Type256" Content="AT24C256 (32KB)" Foreground="White" Margin="0,0,10,0" GroupName="EeType"/>
                        <RadioButton x:Name="Type512" Content="AT24C512C (64KB)" Foreground="White" GroupName="EeType"/>
                    </StackPanel>
                </GroupBox>

                <!-- WDT -->
                <GroupBox Header="Watchdog" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <UniformGrid Columns="3" Margin="5">
                        <Button x:Name="BtnWdtOn" Content="ON" Height="26" Margin="2" Background="#FF2D5F2D" Foreground="White"/>
                        <Button x:Name="BtnWdtPat" Content="PAT" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                        <Button x:Name="BtnWdtOff" Content="OFF" Height="26" Margin="2" Background="#FF5F2D2D" Foreground="White"/>
                    </UniformGrid>
                </GroupBox>

                <!-- システム情報 -->
                <GroupBox Header="System" Foreground="White" Margin="0,0,0,8" BorderBrush="#FF444444">
                    <UniformGrid Columns="2" Margin="5">
                        <Button x:Name="BtnId" Content="ID" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                        <Button x:Name="BtnDump" Content="Dump" Height="26" Margin="2" Background="#FF333333" Foreground="White"/>
                    </UniformGrid>
                </GroupBox>

            </StackPanel>
        </ScrollViewer>

        <!-- 右ペイン: ログ + コマンド入力 -->
        <Grid Grid.Row="0" Grid.RowSpan="2" Grid.Column="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- ログエリア -->
            <TextBox x:Name="LogArea" Grid.Row="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                     Background="#FF0C0C0C" Foreground="#FFD4D4D4" FontFamily="Consolas" FontSize="12"
                     BorderBrush="#FF444444" HorizontalScrollBarVisibility="Auto"/>

            <!-- 生コマンド入力 -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,5,0,0">
                <Label Content="CMD:" Foreground="White" VerticalAlignment="Center"/>
                <TextBox x:Name="CmdInput" Width="500" Background="#FF333333" Foreground="White" BorderBrush="#FF555555"/>
                <Button x:Name="BtnSend" Content="Send" Width="60" Height="26" Margin="5,0,0,0" Background="#FF2D5F2D" Foreground="White"/>
                <Button x:Name="BtnClearLog" Content="Clear" Width="60" Height="26" Margin="5,0,0,0" Background="#FF333333" Foreground="White"/>
            </StackPanel>

            <!-- ステータスバー -->
            <TextBlock x:Name="BottomStatus" Grid.Row="2" Text="Ready" Foreground="#FF888888" Margin="0,5,0,0"/>
        </Grid>
    </Grid>
</Window>
"@

# -----------------------------------------------------------------------------
# UI構築
# -----------------------------------------------------------------------------
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# コントロール取得
$controls = @{}
$xaml.SelectNodes("//*[@x:Name]") | ForEach-Object {
    $controls[$_.Name] = $window.FindName($_.Name)
}

# -----------------------------------------------------------------------------
# ログ出力ヘルパ
# -----------------------------------------------------------------------------
function Log-Write {
    param([string]$Text, [string]$Color = "#D4D4D4")
    if ($controls.LogArea) {
        $time = (Get-Date).ToString("HH:mm:ss")
        $controls.LogArea.Dispatcher.Invoke([Action]{
            $controls.LogArea.AppendText("[$time] $Text`r`n")
            $controls.LogArea.ScrollToEnd()
        })
    }
}

function Log-Command {
    param([string]$Cmd)
    Log-Write ">> $Cmd" "#4EC9B0"
}

function Log-Response {
    param([string]$Resp)
    if ($Resp) {
        foreach ($line in ($Resp -split "`r`n")) {
            if ($line.Trim()) { Log-Write "   $line" "#D4D4D4" }
        }
    }
}

function Log-Error {
    param([string]$Msg)
    Log-Write "!! $Msg" "#F44747"
}

function Update-Status {
    param([string]$Text)
    $controls.StatusText.Dispatcher.Invoke([Action]{
        $controls.StatusText.Text = $Text
    })
}

# -----------------------------------------------------------------------------
# 接続/切断
# -----------------------------------------------------------------------------
$controls.BtnConnect.Add_Click({
    $port = $controls.PortBox.Text.Trim()
    Log-Write "Connecting to $port ..." "#4EC9B0"
    if (Connect-Serial -Port $port) {
        Log-Write "Connected to $port" "#4EC9B0"
        Update-Status "Connected ($port)"
        $controls.BtnConnect.IsEnabled = $false
        $controls.BtnDisconnect.IsEnabled = $true
        $controls.StatusText.Foreground = "#FF4EC9B0"
    } else {
        Log-Error "Failed to connect to $port"
        Update-Status "Connection failed"
    }
})

$controls.BtnDisconnect.Add_Click({
    Disconnect-Serial
    Log-Write "Disconnected" "#F44747"
    Update-Status "Disconnected"
    $controls.BtnConnect.IsEnabled = $true
    $controls.BtnDisconnect.IsEnabled = $false
    $controls.StatusText.Foreground = "#FFCCCCCC"
})

# -----------------------------------------------------------------------------
# コマンド送信ヘルパ (UI用)
# -----------------------------------------------------------------------------
function Execute-Command {
    param([string]$Cmd, [int]$WaitMs = 400)
    if (-not $script:connected) {
        Log-Error "Not connected"
        return ""
    }
    Log-Command $Cmd
    $resp = Send-Command -Cmd $Cmd -WaitMs $WaitMs
    Log-Response $resp
    return $resp
}

# -----------------------------------------------------------------------------
# LED操作
# -----------------------------------------------------------------------------
$ledButtons = @($controls.Led1, $controls.Led2, $controls.Led3, $controls.Led4, $controls.Led5, $controls.Led6)
for ($i = 0; $i -lt 6; $i++) {
    $num = $i + 1
    $ledButtons[$i].Add_Click({
        param($sender, $e)
        $n = $sender.Content -replace "LED",""
        Execute-Command $n
    })
}

$controls.BtnLedAll.Add_Click({ Execute-Command "a" })
$controls.BtnLedClear.Add_Click({ Execute-Command "c" })

# -----------------------------------------------------------------------------
# SW4状態
# -----------------------------------------------------------------------------
function Refresh-Sw4 {
    if (-not $script:connected) { return }
    $resp = Send-Command -Cmd "s" -WaitMs 300
    $lines = ($resp -split "[\r\n]+" | Where-Object { $_.Trim() -ne "" -and $_.Trim() -ne "s" })
    $val = ($lines | Select-Object -Last 1)
    if ($val) {
        $val = $val.Trim()
        $controls.Sw4Status.Dispatcher.Invoke([Action]{
            if ($val -eq "1") {
                $controls.Sw4Status.Text = "PRESSED"
                $controls.Sw4Status.Foreground = "#FF4EC9B0"
            } elseif ($val -eq "0") {
                $controls.Sw4Status.Text = "RELEASED"
                $controls.Sw4Status.Foreground = "#FFCCCCCC"
            } else {
                $controls.Sw4Status.Text = "???"
                $controls.Sw4Status.Foreground = "#FFF44747"
            }
        })
    }
}

$controls.BtnSw4Refresh.Add_Click({ Refresh-Sw4 })

# SW4 自動ポーリング (タイマー)
$sw4Timer = New-Object System.Windows.Threading.DispatcherTimer
$sw4Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$sw4Timer.Add_Tick({
    if ($script:connected -and $controls.Sw4Poll.IsChecked) {
        Refresh-Sw4
    }
})

$controls.Sw4Poll.Add_Checked({ $sw4Timer.Start() })
$controls.Sw4Poll.Add_Unchecked({ $sw4Timer.Stop() })

# -----------------------------------------------------------------------------
# EEPROM読み書き
# -----------------------------------------------------------------------------
$controls.BtnEeRead.Add_Click({
    $addr = $controls.EeAddr.Text.Trim()
    $resp = Execute-Command "eer $addr" 500
})

$controls.BtnEeWrite.Add_Click({
    $addr = $controls.EeAddr.Text.Trim()
    $data = $controls.EeData.Text.Trim()
    Execute-Command "eew $addr $data" 600
})

$controls.BtnEeDump.Add_Click({
    $addr = $controls.EeAddr.Text.Trim()
    $len = $controls.EeDumpLen.Text.Trim()
    if (-not $len) { $len = "16" }
    Execute-Command "eedump $addr $len" 600
})

$controls.BtnEeTest.Add_Click({
    $resp = Execute-Command "eetest" 2500
    if ($resp -match "PASS") {
        $controls.BottomStatus.Text = "EEPROM test: PASS"
    } elseif ($resp -match "FAIL") {
        $controls.BottomStatus.Text = "EEPROM test: FAIL"
    }
})

$controls.BtnEeFill.Add_Click({
    $addr = $controls.EeAddr.Text.Trim()
    $len = $controls.EeDumpLen.Text.Trim()
    $data = $controls.EeData.Text.Trim()
    if (-not $len) { $len = "16" }
    Execute-Command "eefill $addr $len $data" 600
})

$controls.BtnEeScan.Add_Click({
    Execute-Command "scan" 5000
})

# -----------------------------------------------------------------------------
# EEPROMタイプ切替
# -----------------------------------------------------------------------------
$controls.Type256.Add_Checked({
    if ($script:connected) { Execute-Command "eetype 256" }
})
$controls.Type512.Add_Checked({
    if ($script:connected) { Execute-Command "eetype 512" }
})

# -----------------------------------------------------------------------------
# WDT制御
# -----------------------------------------------------------------------------
$controls.BtnWdtOn.Add_Click({ Execute-Command "wdt on" })
$controls.BtnWdtPat.Add_Click({ Execute-Command "wdt pat" })
$controls.BtnWdtOff.Add_Click({ Execute-Command "wdt off" })

# -----------------------------------------------------------------------------
# システム情報
# -----------------------------------------------------------------------------
$controls.BtnId.Add_Click({ Execute-Command "id" 500 })
$controls.BtnDump.Add_Click({ Execute-Command "dump" 600 })

# -----------------------------------------------------------------------------
# 生コマンド入力
# -----------------------------------------------------------------------------
function Send-RawCommand {
    $cmd = $controls.CmdInput.Text.Trim()
    if ($cmd) {
        Execute-Command $cmd 600
        $controls.CmdInput.Text = ""
    }
}

$controls.BtnSend.Add_Click({ Send-RawCommand })

# CmdInput_KeyDown イベントハンドラを追加
$cmdInputKeyHandler = {
    param($sender, $e)
    if ($e.Key -eq "Enter") {
        Send-RawCommand
    }
}
$controls.CmdInput.Add_KeyDown($cmdInputKeyHandler)

$controls.BtnClearLog.Add_Click({
    $controls.LogArea.Clear()
})

# -----------------------------------------------------------------------------
# ウィンドウクローズ処理
# -----------------------------------------------------------------------------
$window.Add_Closing({
    if ($sw4Timer.IsEnabled) { $sw4Timer.Stop() }
    Disconnect-Serial
})

# -----------------------------------------------------------------------------
# 起動
# -----------------------------------------------------------------------------
Log-Write "AT24C256 EEPROM Control Panel ready" "#4EC9B0"
Log-Write "Select COM port and click Connect" "#888888"
$controls.Type256.IsChecked = $true
$window.ShowDialog() | Out-Null
