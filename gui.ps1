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
        Title="AT24C256 EEPROM Control Panel" Height="560" Width="920"
        MinHeight="480" MinWidth="760"
        Background="#FF1E1E1E" WindowStartupLocation="CenterScreen">
    <Grid Margin="8">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="320"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- 左ペイン: 操作パネル (WrapPanel で2カラム配置) -->
        <ScrollViewer Grid.Row="0" Grid.Column="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Hidden">
            <StackPanel Margin="2">

                <!-- 接続パネル -->
                <GroupBox Header="Connection" Foreground="White" Margin="0,0,0,6" BorderBrush="#FF444444" Padding="4">
                    <StackPanel Margin="3">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                            <Label Content="Port:" Foreground="White" Width="40" Padding="0,2,0,2" VerticalAlignment="Center"/>
                            <TextBox x:Name="PortBox" Width="100" Text="$DefaultPort" Background="#FF333333" Foreground="White" BorderBrush="#FF555555" Padding="2,1,2,1"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Button x:Name="BtnConnect" Content="Connect" Width="95" Height="26" Margin="0,0,4,0" Background="#FF2D5F2D" Foreground="White"/>
                            <Button x:Name="BtnDisconnect" Content="Disconnect" Width="95" Height="26" Background="#FF5F2D2D" Foreground="White" IsEnabled="False"/>
                        </StackPanel>
                        <TextBlock x:Name="StatusText" Text="Disconnected" Foreground="#FFCCCCCC" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                    </StackPanel>
                </GroupBox>

                <!-- 1行目: LED + SW4 -->
                <Grid Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="6"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <GroupBox Grid.Column="0" Header="LED" Foreground="White" BorderBrush="#FF444444" Padding="4">
                        <StackPanel Margin="2">
                            <UniformGrid Columns="3" Margin="0,0,0,3">
                                <Button x:Name="Led1" Content="L1" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <Button x:Name="Led2" Content="L2" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <Button x:Name="Led3" Content="L3" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <Button x:Name="Led4" Content="L4" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <Button x:Name="Led5" Content="L5" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <Button x:Name="Led6" Content="L6" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                            </UniformGrid>
                            <UniformGrid Columns="2" Margin="0,0,0,0">
                                <Button x:Name="BtnLedAll" Content="All ON" Height="24" Margin="1" Background="#FF2D5F2D" Foreground="White" FontSize="11"/>
                                <Button x:Name="BtnLedClear" Content="All OFF" Height="24" Margin="1" Background="#FF5F2D2D" Foreground="White" FontSize="11"/>
                            </UniformGrid>
                        </StackPanel>
                    </GroupBox>
                    <GroupBox Grid.Column="2" Header="SW4" Foreground="White" BorderBrush="#FF444444" Padding="4">
                        <StackPanel Margin="2" VerticalAlignment="Center">
                            <TextBlock x:Name="Sw4Status" Text="---" FontSize="16" FontWeight="Bold" Foreground="#FFAAAAAA" HorizontalAlignment="Center" Margin="0,4,0,4"/>
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                                <Button x:Name="BtnSw4Refresh" Content="Refresh" Width="60" Height="24" Margin="0,0,4,0" Background="#FF333333" Foreground="White" FontSize="11"/>
                                <CheckBox x:Name="Sw4Poll" Content="Auto" Foreground="White" VerticalAlignment="Center" FontSize="11"/>
                            </StackPanel>
                        </StackPanel>
                    </GroupBox>
                </Grid>

                <!-- EEPROM読み書き -->
                <GroupBox Header="EEPROM Access" Foreground="White" Margin="0,0,0,6" BorderBrush="#FF444444" Padding="4">
                    <StackPanel Margin="3">
                        <Grid Margin="0,0,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Label Grid.Column="0" Content="Addr:" Foreground="White" Padding="0,2,4,2" VerticalAlignment="Center" FontSize="11"/>
                            <TextBox Grid.Column="1" x:Name="EeAddr" Text="0x0000" Background="#FF333333" Foreground="White" BorderBrush="#FF555555" Padding="2,1,2,1" FontSize="11"/>
                            <Label Grid.Column="2" Content="Data:" Foreground="White" Padding="4,2,4,2" VerticalAlignment="Center" FontSize="11"/>
                            <TextBox Grid.Column="3" x:Name="EeData" Text="0xAB" Background="#FF333333" Foreground="White" BorderBrush="#FF555555" Padding="2,1,2,1" FontSize="11"/>
                        </Grid>
                        <UniformGrid Columns="2" Margin="0,0,0,3">
                            <Button x:Name="BtnEeRead" Content="Read" Height="24" Margin="1" Background="#FF2D4F5F" Foreground="White" FontSize="11"/>
                            <Button x:Name="BtnEeWrite" Content="Write" Height="24" Margin="1" Background="#FF4F2D5F" Foreground="White" FontSize="11"/>
                        </UniformGrid>
                        <Grid Margin="0,0,0,3">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Label Grid.Column="0" Content="Len:" Foreground="White" Padding="0,2,4,2" VerticalAlignment="Center" FontSize="11"/>
                            <TextBox Grid.Column="1" x:Name="EeDumpLen" Text="16" Background="#FF333333" Foreground="White" BorderBrush="#FF555555" Padding="2,1,2,1" FontSize="11"/>
                            <Button Grid.Column="2" x:Name="BtnEeDump" Content="Dump" Width="60" Height="24" Margin="4,0,0,0" Background="#FF333333" Foreground="White" FontSize="11"/>
                        </Grid>
                        <UniformGrid Columns="3" Margin="0,0,0,0">
                            <Button x:Name="BtnEeTest" Content="Test" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                            <Button x:Name="BtnEeFill" Content="Fill" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                            <Button x:Name="BtnEeScan" Content="Scan" Height="24" Margin="1" Background="#FF333333" Foreground="White" FontSize="11"/>
                        </UniformGrid>
                    </StackPanel>
                </GroupBox>

                <!-- 1行: EEPROM Type + WDT + System -->
                <Grid Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="6"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="6"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <GroupBox Grid.Column="0" Header="Type" Foreground="White" BorderBrush="#FF444444" Padding="3">
                        <StackPanel Margin="2" VerticalAlignment="Center">
                            <RadioButton x:Name="Type256" Content="256" Foreground="White" GroupName="EeType" FontSize="11" Margin="0,1,0,1"/>
                            <RadioButton x:Name="Type512" Content="512" Foreground="White" GroupName="EeType" FontSize="11" Margin="0,1,0,1"/>
                        </StackPanel>
                    </GroupBox>
                    <GroupBox Grid.Column="2" Header="WDT" Foreground="White" BorderBrush="#FF444444" Padding="3">
                        <UniformGrid Columns="1" Margin="2">
                            <Button x:Name="BtnWdtOn" Content="ON" Height="22" Margin="0,1" Background="#FF2D5F2D" Foreground="White" FontSize="10"/>
                            <Button x:Name="BtnWdtPat" Content="PAT" Height="22" Margin="0,1" Background="#FF333333" Foreground="White" FontSize="10"/>
                            <Button x:Name="BtnWdtOff" Content="OFF" Height="22" Margin="0,1" Background="#FF5F2D2D" Foreground="White" FontSize="10"/>
                        </UniformGrid>
                    </GroupBox>
                    <GroupBox Grid.Column="4" Header="System" Foreground="White" BorderBrush="#FF444444" Padding="3">
                        <UniformGrid Columns="1" Margin="2">
                            <Button x:Name="BtnId" Content="ID" Height="22" Margin="0,1" Background="#FF333333" Foreground="White" FontSize="10"/>
                            <Button x:Name="BtnDump" Content="Dump" Height="22" Margin="0,1" Background="#FF333333" Foreground="White" FontSize="10"/>
                        </UniformGrid>
                    </GroupBox>
                </Grid>

            </StackPanel>
        </ScrollViewer>

        <!-- 右ペイン: ログ + コマンド入力 -->
        <Grid Grid.Row="0" Grid.Column="2">
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
            <Grid Grid.Row="1" Margin="0,4,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Label Grid.Column="0" Content="CMD:" Foreground="White" VerticalAlignment="Center" Padding="0,0,4,0"/>
                <TextBox Grid.Column="1" x:Name="CmdInput" Background="#FF333333" Foreground="White" BorderBrush="#FF555555" Padding="2,1,2,1"/>
                <Button Grid.Column="2" x:Name="BtnSend" Content="Send" Width="55" Height="26" Margin="4,0,0,0" Background="#FF2D5F2D" Foreground="White"/>
                <Button Grid.Column="3" x:Name="BtnClearLog" Content="Clear" Width="55" Height="26" Margin="4,0,0,0" Background="#FF333333" Foreground="White"/>
            </Grid>

            <!-- ステータスバー -->
            <TextBlock x:Name="BottomStatus" Grid.Row="2" Text="Ready" Foreground="#FF888888" Margin="0,4,0,0"/>
        </Grid>
    </Grid>
</Window>
"@

# -----------------------------------------------------------------------------
# UI構築
# -----------------------------------------------------------------------------
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# コントロール取得 (x: プレフィックスのため XmlNamespaceManager が必要)
$nsmgr = New-Object System.Xml.XmlNamespaceManager($xaml.NameTable)
$nsmgr.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")
$controls = @{}
$xaml.SelectNodes("//*[@x:Name]", $nsmgr) | ForEach-Object {
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
        $n = $sender.Content -replace "L",""
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
