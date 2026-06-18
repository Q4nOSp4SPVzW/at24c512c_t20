# T20 Sapphire SoC AT24C512C I2C EEPROM

Trion T20 BGA256 開発ボード向けの Sapphire SoC RV32 プロジェクトです。
Sapphire SoC の I2C ペリフェラルで AT24C512C (64KB I2C EEPROM) を制御します。

## バージョン

- ファームウェア: `v1.0.0`
- 日付: `2026-06-18`
- FW仮想レジスタベースアドレス: `0xF80FF000`

## ボード配線

| 信号 | ピン | GPIO | 説明 |
|------|------|------|------|
| UART RX | C3 | GPIOL_48 | UART受信 |
| UART TX | D3 | GPIOL_46 | UART送信 |
| I2C SCL | B1 | GPIOL_44 | I2Cクロック (オープンドレン) |
| I2C SDA | B2 | GPIOL_45 | I2Cデータ (オープンドレン) |
| SW4 | P2 | GPIOL_02 | ユーザースイッチ |
| LED[7:0] | - | GPIOR_* | ユーザーLED (アクティブLow) |
| クロック | L13 | GPIOR_157 | 50MHz → PLL → 100MHz |

### AT24C512C 接続

T20 ボードの I/O ヘッダ (B1, B2 ピン) から EEPROM ボードへ配線:

```
T20 ボード              EEPROM ボード
---------              -------------
B1 (SCL) ──────────── SCL
B2 (SDA) ──────────── SDA
3.3V     ──────────── VCC
GND      ──────────── GND
```

- SCL/SDA ラインには 4.7kΩ のプルアップ抵抗が必要
- AT24C512C の A2,A1,A0 ピンは GND に接続 (スレーブアドレス 0xA0)
- WP ピンは GND に接続 (書き込み許可)

## UART設定

- COM11
- 9600 bps
- データ8ビット、パリティなし、ストップビット1

## UARTコマンド

### 起動時の出力

電源オンまたはプログラム直後に以下のバナーが表示されます。

```
AT24C512C I2C EEPROM v1.0.0 2026-06-18
```

### EEPROM コマンド

#### `eew <addr16> <data>` — 1バイト書き込み

指定アドレス (0x0000〜0xFFFF) に1バイトを書き込みます。書き込み完了に5msかかります。

```
> eew 0x1000 0xAB
OK
```

#### `eer <addr16>` — 1バイト読み取り

指定アドレスから1バイトを読み取ります。

```
> eer 0x1000
0x00001000 = 0xAB
```

#### `eedump <addr16> <len>` — 複数バイトダンプ

指定アドレスから `len` バイト (最大64) を16バイト/行でダンプします。`len` 省略時は16。

```
> eedump 0x0000 32
00000000: 40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
00000010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

#### `eefill <addr16> <len> <data>` — 一括書き込み

指定アドレスから `len` バイト (最大128) を同じ値で埋めます。ページ書き込みを使用します。

```
> eefill 0x2000 16 0xFF
OK

> eedump 0x2000 16
00002000: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
```

#### `eetest` — テストパターン書き込み＆検証

アドレス 0x0000 に 0x40〜0x4F の16バイト連番を書き込み、読み返して一致を確認します。EEPROMの動作確認に便利。

```
> eetest
EEPROM test: write 16 bytes at 0x0000...
................
Reading back...
40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
PASS
```

#### `scan` — I2C バススキャン

アドレス 0x03〜0x77 を走査し、ACKを返すデバイスを一覧します。AT24C512C は通常 0x50 に応答します。

```
> scan
Scanning I2C bus 0x03..0x77...
Found: 0x50 (w:0xA0)
Scan done.
```

> **トラブルシュート:** `scan` で何も見つからない場合、配線・プルアップ抵抗・電圧を確認してください。

#### `iinit` — I2C コントローラ再初期化

I2Cペリフェラルの設定を再適用します。バスがスタックした場合の回復に使用します。

```
> iinit
OK
```

### LED/GPIO コマンド

#### `1` 〜 `6` — LED トグル

LED1〜LED6を個別にトグルします。LEDはアクティブLowなので、`1` を押すごとに点灯/消灯が切り替わります。

```
> 1
OK         # LED1 点灯

> 1
OK         # LED1 消灯
```

#### `a` — LED全点灯

LED1〜LED6 をすべて点灯します。

```
> a
OK
```

#### `c` — LED全消灯

LED1〜LED6 をすべて消灯します。

```
> c
OK
```

#### `s` — SW4 状態読み取り

ユーザースイッチ SW4 の押下状態を表示します (1=押下, 0=未押下)。

```
> s
0

> s
1
```

#### `g` — GPIO レジスタダンプ

GPIO の入力・出力・出力許可レジスタを表示します。

```
> g
GPIO_IN = 0x0
GPIO_OUT= 0x0
GPIO_OE = 0x7F
```

### その他

#### `id` — ファームウェア情報

バージョン、日付、レジスタ配置を表示します。

```
> id
ID INFO
FW      = v1.0.0 AT24C512C
DATE    = 2026-06-18
ID      = 0x41543235
VERSION = 0x00010000
DATEHEX = 0x20260618
FW_BASE = 0xF80FF000
I2C_REG = 0xF8016000
I2CINIT = 0x1
```

#### `dump` — 全ステータスダンプ

`id` + `g` + UART/WDT エラー状態をまとめて表示します。

```
> dump
ID INFO
FW      = v1.0.0 AT24C512C
DATE    = 2026-06-18
ID      = 0x41543235
VERSION = 0x00010000
DATEHEX = 0x20260618
FW_BASE = 0xF80FF000
I2C_REG = 0xF8016000
I2CINIT = 0x1
GPIO_IN = 0x0
GPIO_OUT= 0x0
GPIO_OE = 0x7F
UART_ST = 0x0
WDT_EN  = 0x0
WDT_HANG= 0x0
LASTERR = 0x0
```

#### `err?` — 直前のエラー

最後に発生したエラーコードを表示します。`0` はエラーなし。

```
> err?
LASTERR = 0x0
```

エラー一覧:

| コード | 意味 |
|--------|------|
| `0x0` | エラーなし |
| `0x1` | 不明なコマンド |
| `0x2` | 引数エラー |
| `0x3` | 読み取り専用 |
| `0x4` | コマンド行が長すぎる |
| `0x5` | I2C NACK / 通信失敗 |
| `0x6` | アドレス範囲外 |

#### `help` — コマンド一覧

```
> help
=== EEPROM ===
eew <addr16> <data>  write byte
eer <addr16>          read byte
eedump <addr16> <len> dump (max 64)
eefill <addr16> <len> <data> fill (max 128)
eetest                test pattern
scan                  I2C bus scan
iinit                 reinit I2C
=== LED/GPIO ===
1-6 a c s g           LED/SW4 control
=== Misc ===
id dump err? help     info/status
wdt on/off/pat/hang   watchdog
m <addr>              read32
w <addr> <data>       write32
```

#### `m <addr>` — 32ビット MMIO 読み取り

メモリマップドレジスタを32ビット単位で読み取ります。デバッグ用。

```
> m 0xF8016000
F8016000 = 0x0
```

#### `w <addr> <data>` — 32ビット MMIO 書き込み

メモリマップドレジスタへ32ビット書き込みます。ファームウェア仮想レジスタ (0xF80FF000〜) は読み取り専用。

```
> w 0xF8015000 0x7F
OK
```

#### `wdt on|off|pat|hang` — ウォッチドッグ制御

ウォッチドッグタイマの有効化・無効化・ハートビート・停止を切り替えます。

```
> wdt on
OK

> wdt pat
OK

> wdt hang
WDT heartbeat stopped; reset expected in ~3s

> wdt off
OK
```

## 典型的なセッション例

初回起動からEEPROMへの書き込み・読み出しまでの一連の流れ:

```
AT24C512C I2C EEPROM v1.0.0 2026-06-18

> scan
Scanning I2C bus 0x03..0x77...
Found: 0x50 (w:0xA0)
Scan done.

> eetest
EEPROM test: write 16 bytes at 0x0000...
................
Reading back...
40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
PASS

> eew 0x1000 0xAB
OK

> eer 0x1000
0x00001000 = 0xAB

> eefill 0x2000 32 0x55
OK

> eedump 0x0000 48
00000000: 40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
00000010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00000020: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

> eedump 0x2000 32
00002000: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55
00002010: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55

> id
ID INFO
FW      = v1.0.0 AT24C512C
DATE    = 2026-06-18
ID      = 0x41543235
VERSION = 0x00010000
DATEHEX = 0x20260618
FW_BASE = 0xF80FF000
I2C_REG = 0xF8016000
I2CINIT = 0x1
```

## ファームウェア仮想レジスタ

- `0xF80FF000`: ID、`"AT25"` (`0x41543235`)
- `0xF80FF004`: バージョン、`0x00010000`
- `0xF80FF008`: 日付、`0x20260618`
- `0xF80FF00C`: 直前のエラー

## I2C 設定

- 周波数: 100kHz (Standard Mode)
- スレーブアドレス: 0xA0 (7-bit: 0x50, A2A1A0=000)
- アドレス幅: 16-bit (64KB)
- ページサイズ: 128バイト
- ライターイクルタイム: 5ms

## 必要な環境

| ソフトウェア | バージョン | インストール先（固定） |
|---|---|---|
| [Efinity IDE](https://www.efinixinc.com/support/efinity.php) | 2026.1 | `C:\Efinity\2026.1\` |
| Efinity RISC-V IDE (ツールチェーン) | 2026.1 | `C:\Efinity\efinity-riscv-ide-2026.1\` |

> **注意:** `build_sw.ps1` のツールチェーンパスが上記パスにハードコードされています。

## ビルドと書き込み手順

```powershell
.\build_sw.ps1   # ファームウェアのビルドとROMバイナリ配備
.\build.ps1      # Efinity FPGAビルド（合成・配置配線）
.\program.ps1    # FPGAへ書き込み
```
