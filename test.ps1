# EEPROM テストバッチ
# 使用法: .\test.ps1 [-Port COM11]
#
# AT24C512C/AT24C256 I2C EEPROM の全コマンド包括テストを実行し、
# 各テストの内容と結果を表示する。
#
# Requirements:
#   - FPGA 書き込み済み (program.ps1 実行済み)
#   - ボードが USB シリアルで接続されている

param(
    [string]$Port = "COM11"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# -----------------------------------------------------------------------------
# テスト定義
# -----------------------------------------------------------------------------
# 各テストは以下の要素を持つ:
#   Name  : テスト名
#   Check : チェック内容 (表示用)
#   Cmd   : 送信コマンド
#   WaitMs: 応答待ち時間
#   Pass  : 結果判定用正規表現 (?s) で改行をまたぐ
#   Drain : (省略可) 1=事前バッファドレイン追加
# -----------------------------------------------------------------------------

$Tests = @(
    # =========================================================================
    # グループ1: 起動状態・情報表示
    # =========================================================================
    @{
        Name  = "err? (エラー状態確認)"
        Check = "前回エラーがクリアされているか (LASTERR=0x0 期待)"
        Cmd   = "err?"
        WaitMs= 400
        Pass  = "LASTERR = 0x0"
    },
    @{
        Name  = "id (ファームウェア情報表示)"
        Check = "バージョン/日付/ID/EEPROMタイプが正しく表示されるか"
        Cmd   = "id"
        WaitMs= 800
        Pass  = "EE TYPE = AT24C256 32KB"
    },
    @{
        Name  = "dump (全ステータスダンプ)"
        Check = "ID+GPIO+UART/WDT状態がまとめて表示されるか"
        Cmd   = "dump"
        WaitMs= 600
        Pass  = "(?s)ID INFO.*GPIO_IN.*LASTERR"
    },
    @{
        Name  = "help (コマンド一覧表示)"
        Check = "EEPROM/LED/GPIO/Misc の全コマンドカテゴリが表示されるか"
        Cmd   = "help"
        WaitMs= 600
        Pass  = "(?s)=== EEPROM ===.*=== LED/GPIO ===.*=== Misc ==="
    },
    # =========================================================================
    # グループ2: EEPROMタイプ切替 (実チップAT24C256に合わせて256で開始)
    # =========================================================================
    @{
        Name  = "eetype 256 (EEPROMタイプ切替: 32KB)"
        Check = "AT24C256 モードに切替 (ページ64B, 最大0x7FFF) — 実チップに合わせる"
        Cmd   = "eetype 256"
        WaitMs= 400
        Pass  = "AT24C256 32KB page=64"
    },
    # =========================================================================
    # グループ3: 単バイト読み書き
    # =========================================================================
    @{
        Name  = "eew 0x1000 0xAB (1バイト書き込み)"
        Check = "アドレス0x1000 に 0xAB を書き込めるか"
        Cmd   = "eew 0x1000 0xAB"
        WaitMs= 600
        Pass  = "OK"
    },
    @{
        Name  = "eer 0x1000 (1バイト読み取り)"
        Check = "アドレス0x1000 から 0xAB が読めるか (書き込み/読み出しの一貫性)"
        Cmd   = "eer 0x1000"
        WaitMs= 500
        Pass  = "= 0x000000AB"
    },
    # =========================================================================
    # グループ4: ページ書き込み・ダンプ (64Bページ)
    # =========================================================================
    @{
        Name  = "eefill 0x2000 16 0x55 (ページ書き込み 16バイト同一値)"
        Check = "アドレス0x2000 に 0x55 を16バイト連続書き込みできるか"
        Cmd   = "eefill 0x2000 16 0x55"
        WaitMs= 600
        Pass  = "OK"
    },
    @{
        Name  = "eedump 0x2000 16 (ページ書き込み確認)"
        Check = "アドレス0x2000 の16バイトがすべて 0x55 になっているか"
        Cmd   = "eedump 0x2000 16"
        WaitMs= 600
        Pass  = "55 55 55 55 55 55 55 55"
    },
    # =========================================================================
    # グループ5: テストパターン
    # =========================================================================
    @{
        Name  = "eetest (16バイト書き込み/読み戻し一致性)"
        Check = "0x0000 に 0x40..0x4F を書き、読み戻して一致するか"
        Cmd   = "eetest"
        WaitMs= 2500
        Pass  = "PASS"
    },
    @{
        Name  = "eedump 0x0000 16 (データ保持確認)"
        Check = "アドレス0x0000 の16バイトが eetest の書き込み値を保持しているか"
        Cmd   = "eedump 0x0000 16"
        WaitMs= 600
        Pass  = "40 41 42 43 44 45 46 47"
    },
    # =========================================================================
    # グループ6: memtest (32KB/64Bページモード)
    # =========================================================================
    @{
        Name  = "memtest quick (データバステスト)"
        Check = "0x0000/0x4000/0x8000/0xC000 の4アドレス x 0x00/0xFF/0x55/0xAA の4パターン"
        Cmd   = "memtest quick"
        WaitMs= 2500
        Pass  = "Quick test PASS"
    },
    @{
        Name  = "memtest page 0x3000 (1ページ64B x 4パターン)"
        Check = "0x3000 ページ(64B)に 0x00/0xFF/0x55/0xAA を順に書いて検証"
        Cmd   = "memtest page 0x3000"
        WaitMs= 4000
        Pass  = "Page test PASS"
        Drain = 1
    },
    @{
        Name  = "memtest range 0x4000 64 (範囲テスト 64B)"
        Check = "0x4000 から64バイトにアドレス依存パターンを書いて検証 (1バイトずつ書くため約6秒)"
        Cmd   = "memtest range 0x4000 64"
        WaitMs= 7000
        Pass  = "Range test PASS"
        Drain = 1
    },
    # =========================================================================
    # グループ7: NVM保持テスト
    # =========================================================================
    @{
        Name  = "nvm save (初期パターン書き込み)"
        Check = "EEPROM末尾 (0x7FF0) に magic=0xA5, counter=0 を書けるか"
        Cmd   = "nvm save"
        WaitMs= 800
        Pass  = "OK"
        Drain = 1
    },
    @{
        Name  = "nvm load (保持データ読み出し)"
        Check = "書き込んだ magic/counter/checksum が整合しているか (Status=OK)"
        Cmd   = "nvm load"
        WaitMs= 800
        Pass  = "Status   = OK"
        Drain = 1
    },
    @{
        Name  = "nvm inc (カウンタ+1)"
        Check = "counter を 0→1 にインクリメントして保存できるか"
        Cmd   = "nvm inc"
        WaitMs= 800
        Pass  = "New counter = 0x00000001"
        Drain = 1
    },
    @{
        Name  = "nvm load (インクリメント後確認)"
        Check = "counter が 0x1 に更新されているか"
        Cmd   = "nvm load"
        WaitMs= 800
        Pass  = "Counter  = 0x00000001"
        Drain = 1
    },
    @{
        Name  = "nvm clear (テスト領域クリア)"
        Check = "EEPROM末尾の4バイトを 0x00 でクリアできるか"
        Cmd   = "nvm clear"
        WaitMs= 800
        Pass  = "cleared"
    },
    # =========================================================================
    # グループ8: I2C バス
    # =========================================================================
    @{
        Name  = "iinit (I2Cコントローラ再初期化)"
        Check = "I2Cペリフェラルの設定を再適用できるか"
        Cmd   = "iinit"
        WaitMs= 500
        Pass  = "OK"
        Drain = 1
    },
    @{
        Name  = "scan (I2Cバススキャン)"
        Check = "EEPROM が 0x50 (w:0xA0) に応答するか"
        Cmd   = "scan"
        WaitMs= 5000
        Pass  = "Found:.*w:0x000000A0"
        Drain = 1
    },
    # =========================================================================
    # グループ9: LED/GPIO
    # =========================================================================
    @{
        Name  = "LED個別/全点灯/全消灯 (目視確認)"
        Check = "LED1〜6 の個別トグル・全点灯・全消灯を目視確認"
        Mode  = "ledvisual"
        Cmd   = ""
        WaitMs= 400
        Pass  = ""
    },
    @{
        Name  = "s (SW4 状態変化検出: 0→押下→離下)"
        Check = "SW4 を押すと 1、離すと 0 に変化するか (自動ポーリング)"
        Mode  = "sw4poll"
        Cmd   = "s"
        WaitMs= 300
        Pass  = ""
    },
    @{
        Name  = "g (GPIO レジスタダンプ)"
        Check = "GPIO_IN/GPIO_OUT/GPIO_OE の3レジスタが表示されるか"
        Cmd   = "g"
        WaitMs= 500
        Pass  = "(?s)GPIO_IN.*GPIO_OUT.*GPIO_OE"
    },
    # =========================================================================
    # グループ10: ウォッチドッグ
    # =========================================================================
    @{
        Name  = "wdt on (ウォッチドッグ有効化)"
        Check = "WDT を有効化しハートビートを開始できるか"
        Cmd   = "wdt on"
        WaitMs= 400
        Pass  = "OK"
    },
    @{
        Name  = "wdt pat (ハートビート)"
        Check = "WDT にハートビートを送れるか"
        Cmd   = "wdt pat"
        WaitMs= 400
        Pass  = "OK"
    },
    @{
        Name  = "wdt off (ウォッチドッグ無効化)"
        Check = "WDT を無効化できるか"
        Cmd   = "wdt off"
        WaitMs= 400
        Pass  = "OK"
    },
    # =========================================================================
    # グループ11: MMIO read/write (FW仮想レジスタ)
    # =========================================================================
    @{
        Name  = "m 0xF80FF000 (FW仮想レジスタ: ID読み取り)"
        Check = "FW_ID レジスタから 0x41543235 ('AT25') が読めるか"
        Cmd   = "m 0xF80FF000"
        WaitMs= 400
        Pass  = "= 41543235"
    },
    @{
        Name  = "m 0xF80FF004 (FW仮想レジスタ: バージョン読み取り)"
        Check = "FW_VERSION レジスタから 0x00010000 (v1.0.0) が読めるか"
        Cmd   = "m 0xF80FF004"
        WaitMs= 400
        Pass  = "= 00010000"
    },
    # =========================================================================
    # グループ12: エラー処理
    # =========================================================================
    @{
        Name  = "eetype (引数エラー: 引数なし)"
        Check = "引数なし eetype が BAD_ARG (ERR 2) を返すか"
        Cmd   = "eetype"
        WaitMs= 400
        Pass  = "ERR 00000002"
    },
    @{
        Name  = "eetype 999 (引数エラー: 無効なタイプ)"
        Check = "無効な EEPROM タイプ 999 が BAD_ARG (ERR 2) を返すか"
        Cmd   = "eetype 999"
        WaitMs= 400
        Pass  = "ERR 00000002"
    },
    @{
        Name  = "unknowncmd (不明なコマンド)"
        Check = "未定義コマンドが UNKNOWN_CMD (ERR 1) を返すか"
        Cmd   = "unknowncmd"
        WaitMs= 400
        Pass  = "ERR 00000001"
    },
    # =========================================================================
    # グループ13: 64KBモード切替＋テスト (単バイトのみ、ページ書き込みは64B制限)
    # =========================================================================
    @{
        Name  = "eetype 512 (EEPROMタイプ切替: 64KB)"
        Check = "AT24C512C モードに切替可能か (ページ128B, 最大0xFFFF)"
        Cmd   = "eetype 512"
        WaitMs= 400
        Pass  = "AT24C512C 64KB page=128"
    },
    @{
        Name  = "memtest quick (データバステスト 64KBモード)"
        Check = "512モードでも 0x0000/0x4000/0x8000/0xC000 でデータバステストが通るか"
        Cmd   = "memtest quick"
        WaitMs= 2500
        Pass  = "Quick test PASS"
    },
    # =========================================================================
    # グループ14: 後片付け (256モードに戻す)
    # =========================================================================
    @{
        Name  = "eetype 256 (実チップに合わせて256に戻す)"
        Check = "テスト後は実チップAT24C256に合わせて256モードに戻す"
        Cmd   = "eetype 256"
        WaitMs= 400
        Pass  = "AT24C256 32KB page=64"
    }
)

# -----------------------------------------------------------------------------
# メイン
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " AT24C256 I2C EEPROM 全コマンドテスト" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Port    : $Port"
Write-Host "Baudrate: 9600 8N1"
Write-Host "Tests   : $($Tests.Count) 項目"
Write-Host ""

$serial = New-Object System.IO.Ports.SerialPort $Port,9600,None,8,One
$serial.ReadTimeout  = 10000
$serial.WriteTimeout = 5000
$serial.Open()
Start-Sleep -Milliseconds 300
$serial.DiscardInBuffer()

# 最初にEEPROMを既知状態にする (eetype 256 — 実チップに合わせる)
$serial.WriteLine("eetype 256")
Start-Sleep -Milliseconds 400
$null = $serial.ReadExisting()

$passed = 0
$failed = 0
$failedNames = @()
$testNum = 0

foreach ($t in $Tests) {
    $testNum++

    # 事前バッファドレイン (前テストの残り出力を破棄)
    if ($t.Drain) {
        Start-Sleep -Milliseconds 300
        try { $null = $serial.ReadExisting() } catch {}
    }

    Write-Host ("[{0}/{1}] {2}" -f $testNum, $Tests.Count, $t.Name) -ForegroundColor White
    Write-Host "      CHECK: $($t.Check)" -ForegroundColor DarkGray
    Write-Host "      CMD  : $($t.Cmd)" -ForegroundColor DarkGray

    # -------------------------------------------------------------------------
    # SW4 ポーリングモード: 押下→離下を自動検出
    # -------------------------------------------------------------------------
    if ($t.Mode -eq "sw4poll") {
        # SW4状態読み取りヘルパ: バッファクリア→s送信→応答から最終の0/1を抽出
        function Read-Sw4 {
            try { $null = $serial.ReadExisting() } catch {}
            Start-Sleep -Milliseconds 50
            try { $null = $serial.ReadExisting() } catch {}
            $serial.WriteLine("s")
            Start-Sleep -Milliseconds 400
            $resp = ""
            try { $resp = $serial.ReadExisting() } catch {}
            # 改行で分割し、空行とエコー"s"を除去
            $lines = ($resp -split "[\r\n]+" | Where-Object { $_.Trim() -ne "" -and $_.Trim() -ne "s" })
            $last = ($lines | Select-Object -Last 1)
            if ($last) { return $last.Trim() } else { return "" }
        }

        # 初期状態読み取り
        $initialState = Read-Sw4
        Write-Host "      初期状態: $initialState" -ForegroundColor DarkGray

        # 押下待ち (0→1)
        Write-Host "      SW4 を押してください..." -ForegroundColor Magenta -NoNewline
        $deadline = (Get-Date).AddSeconds(30)
        $pressed = $false
        while ((Get-Date) -lt $deadline) {
            $val = Read-Sw4
            if ($val -eq "1") { $pressed = $true; break }
        }
        if ($pressed) {
            Write-Host " 押下検出 (1)" -ForegroundColor Green
        } else {
            Write-Host " タイムアウト" -ForegroundColor Red
            Write-Host "      RESULT: FAIL" -ForegroundColor Red
            $failed++
            $failedNames += $t.Name
            Write-Host ""
            continue
        }

        # 離下待ち (1→0)
        Write-Host "      SW4 を離してください..." -ForegroundColor Magenta -NoNewline
        $deadline = (Get-Date).AddSeconds(30)
        $released = $false
        while ((Get-Date) -lt $deadline) {
            $val = Read-Sw4
            if ($val -eq "0") { $released = $true; break }
        }
        if ($released) {
            Write-Host " 離下検出 (0)" -ForegroundColor Green
            Write-Host "      RESULT: PASS" -ForegroundColor Green
            $passed++
        } else {
            Write-Host " タイムアウト" -ForegroundColor Red
            Write-Host "      RESULT: FAIL" -ForegroundColor Red
            $failed++
            $failedNames += $t.Name
        }
        Write-Host ""
        continue
    }

    # -------------------------------------------------------------------------
    # LED目視確認モード: 順次点灯→ユーザー確認→全点灯→全消灯
    # -------------------------------------------------------------------------
    if ($t.Mode -eq "ledvisual") {
        # 1. 全消灯 (初期化)
        $serial.WriteLine("c")
        Start-Sleep -Milliseconds 400
        try { $null = $serial.ReadExisting() } catch {}

        # 2. LED1〜6 を順に点灯 → ユーザー確認
        $ledFail = $false
        for ($ledNum = 1; $ledNum -le 6; $ledNum++) {
            $serial.WriteLine("$ledNum")
            Start-Sleep -Milliseconds 400
            try { $null = $serial.ReadExisting() } catch {}
            Write-Host "      LED$ledNum 点灯 → ボードの LED$ledNum が点灯していますか? [y/n] " -ForegroundColor Magenta -NoNewline
            $answer = Read-Host
            if ($answer.Trim() -notmatch "^[yY]") {
                $ledFail = $true
                Write-Host "      LED$ledNum : FAIL" -ForegroundColor Red
                break
            } else {
                Write-Host "      LED$ledNum : OK" -ForegroundColor Green
            }
        }

        if (-not $ledFail) {
            # 3. 全点灯
            $serial.WriteLine("a")
            Start-Sleep -Milliseconds 400
            try { $null = $serial.ReadExisting() } catch {}
            Write-Host "      全点灯 → LED1〜6 がすべて点灯していますか? [y/n] " -ForegroundColor Magenta -NoNewline
            $answer = Read-Host
            if ($answer.Trim() -notmatch "^[yY]") {
                $ledFail = $true
                Write-Host "      全点灯 : FAIL" -ForegroundColor Red
            } else {
                Write-Host "      全点灯 : OK" -ForegroundColor Green
            }
        }

        if (-not $ledFail) {
            # 4. 全消灯
            $serial.WriteLine("c")
            Start-Sleep -Milliseconds 400
            try { $null = $serial.ReadExisting() } catch {}
            Write-Host "      全消灯 → LED1〜6 がすべて消灯していますか? [y/n] " -ForegroundColor Magenta -NoNewline
            $answer = Read-Host
            if ($answer.Trim() -notmatch "^[yY]") {
                $ledFail = $true
                Write-Host "      全消灯 : FAIL" -ForegroundColor Red
            } else {
                Write-Host "      全消灯 : OK" -ForegroundColor Green
            }
        }

        # 念のため全消灯
        $serial.WriteLine("c")
        Start-Sleep -Milliseconds 400
        try { $null = $serial.ReadExisting() } catch {}

        if ($ledFail) {
            Write-Host "      RESULT: FAIL" -ForegroundColor Red
            $failed++
            $failedNames += $t.Name
        } else {
            Write-Host "      RESULT: PASS" -ForegroundColor Green
            $passed++
        }
        Write-Host ""
        continue
    }

    $serial.WriteLine($t.Cmd)
    Start-Sleep -Milliseconds $t.WaitMs

    # ループ読み取り: 連続2回空で終了、最大3秒
    $response = ""
    try { $response = $serial.ReadExisting() } catch {}
    $retryDeadline = (Get-Date).AddSeconds(3)
    $emptyCount = 0
    while ((Get-Date) -lt $retryDeadline -and $emptyCount -lt 2) {
        Start-Sleep -Milliseconds 200
        $chunk = ""
        try { $chunk = $serial.ReadExisting() } catch {}
        if ($chunk) { $response += $chunk; $emptyCount = 0 }
        else { $emptyCount++ }
    }

    # コマンドエコーと空行を除去
    $lines = ($response -split "`r`n" | Where-Object { $_.Trim() -ne "" -and $_.Trim() -ne $t.Cmd })
    $body = ($lines -join "`r`n").Trim()

    if ($body -match $t.Pass) {
        Write-Host "      RESULT: PASS" -ForegroundColor Green
        $passed++
    } else {
        # 出力が長い場合は先頭200文字だけ表示
        $disp = if ($body.Length -gt 200) { $body.Substring(0,200) + "..." } else { $body }
        Write-Host "      OUTPUT: $disp" -ForegroundColor Yellow
        Write-Host "      EXPECT : $($t.Pass)" -ForegroundColor DarkYellow
        Write-Host "      RESULT: FAIL" -ForegroundColor Red
        $failed++
        $failedNames += $t.Name
    }
    Write-Host ""
}

$serial.Close()

# -----------------------------------------------------------------------------
# サマリ
# -----------------------------------------------------------------------------
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " テスト結果サマリ" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host (" 総テスト数 : {0}" -f $Tests.Count)
Write-Host (" PASS       : {0}" -f $passed) -ForegroundColor Green
Write-Host (" FAIL       : {0}" -f $failed) -ForegroundColor $(if ($failed) {'Red'} else {'Gray'})
if ($failedNames.Count -gt 0) {
    Write-Host ""
    Write-Host " 失敗したテスト:" -ForegroundColor Red
    foreach ($n in $failedNames) {
        Write-Host "   - $n" -ForegroundColor Red
    }
}
Write-Host ""
if ($failed -eq 0) {
    Write-Host " *** ALL TESTS PASSED ***" -ForegroundColor Green
} else {
    Write-Host " *** SOME TESTS FAILED ***" -ForegroundColor Red
}
Write-Host ""
