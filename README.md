# T20 Sapphire SoC AT24C512C I2C EEPROM

Trion T20 BGA256 開発ボード向けの Sapphire SoC RV32 プロジェクトです。
Sapphire SoC の I2C ペリフェラルで AT24C512C (64KB I2C EEPROM) を制御します。

## バージョン

- ファームウェア: `v1.0.0`
- 日付: `2026-06-18`
- FW仮想レジスタベースアドレス: `0xF80FF000`

## Sapphire SoC 構成

Efinity Sapphire SoC IP (v3.4.0) を使用。Efinity IP Manager で生成した `ip/soc/` 配下の設定に基づく。

### CPU コア

| 項目 | 設定 |
|------|------|
| アーキテクチャ | RISC-V RV32IM (Zicsr + Zifencei) |
| 圧縮命令 (C) | 無効 |
| アトミック (A) | 無効 |
| 浮動小数点 (F/D) | 無効 |
| MMU / Supervisor | 無効 |
| Custom Instruction | 無効 |
| Barrel Shifter | 無効 |
| MUL/DIV 高速拡張 | 無効 |
| CSR 構成 | Reduced CSR |
| コア数 | 1 |
| 動作周波数 | 100 MHz (50MHz オシレータ → PLL → 100MHz) |
| デバッグ | RISC-V Debug (ハードブレークポイント 0) |

### キャッシュ

| 項目 | 設定 |
|------|------|
| I-Cache | 4KB / 1way / 64B per line |
| D-Cache | 4KB / 1way / 64B per line |

### メモリマップ

| 種別 | ベースアドレス | サイズ | 備考 |
|------|---------------|--------|------|
| 内蔵RAM (RAM_A) | `0xF9000000` | 16KB | ファームウェア + スタック |
| AXI Slave | `0x01000000` | 16MB | RTLでダミー応答 (未使用) |
| ペリフェラル空間 | `0xF8000000` | 16MB | 下記ペリフェラルを配置 |
| CLINT | `0xF8B00000` | 64KB | タイマ・割り込み |
| PLIC | `0xF8C00000` | 4MB | 外部割り込みコントローラ |

### ペリフェラル

| ペリフェラル | 有効 | ベースアドレス | サイズ | 詳細 |
|--------------|:----:|---------------|--------|------|
| UART0 | ✅ | `0xF8010000` | 64B | TX/RX FIFO 128, 9600bps 8N1 (FW設定) |
| UART1 | ❌ | - | - | 無効 |
| UART2 | ❌ | - | - | 無効 |
| SPI0 | ✅ | `0xF8014000` | 4KB | Cmd/Rsp FIFO 256, 8bit, SS 1 (未使用) |
| SPI1 / SPI2 | ❌ | - | - | 無効 |
| I2C0 | ✅ | `0xF8016000` | 256B | 100kHz Standard Mode, AT24C512C 接続 |
| I2C1 / I2C2 | ❌ | - | - | 無効 |
| GPIO0 | ✅ | `0xF8015000` | 256B | 8bit, LED[6:0] 出力 / SW4 入力 |
| GPIO1 | ❌ | - | - | 無効 |
| Watchdog (WDT0) | ✅ | `0xF8017000` | 256B | prescaler 24bit, timeout 16bit, 2 counters |
| Timer0/1/2 | ❌ | - | - | 無効 |
| APB Slave0 | ✅ | `0xF8100000` | 64KB | 未使用 (RTLでダミー) |

### 割り込み

| 割り込み | ID | 有効 | 接続先 |
|----------|:--:|:----:|--------|
| UART0 | 1 | ✅ | PLIC |
| SPI0 | 4 | ✅ | PLIC (未使用) |
| I2C0 | 8 | ✅ | PLIC |
| GPIO0 (bit0) | 12 | ✅ | PLIC |
| GPIO0 (bit1) | 13 | ✅ | PLIC |
| Watchdog | 32 | ✅ | PLIC (panic) |
| USER_0 (外部) | 16 | ✅ | RTLで `1'b0` 固定 |
| USER_1〜7 | 17,22-27 | ❌ | 無効 |

> ファームウェアはポーリング方式で動作し、PLIC割り込みは未使用です。

### RTL トップ接続

```
                clk_100m (PLL出力)
                    │
        ┌───────────┴───────────┐
        │   Sapphire SoC (soc)  │
        │                       │
   UART │ ◄──── uart_rx_i (C3)  │
        │ ────► uart_tx_o (D3)  │
        │                       │
    I2C │ ◄──► i2c_scl_io (B1) │ ──► AT24C512C SCL
        │ ◄──► i2c_sda_io (B2) │ ──► AT24C512C SDA
        │                       │
   GPIO │ ◄──── sw4_i (P2)      │
        │ ────► led_o[7:0]      │ ──► ユーザーLED
        │                       │
   AXI  │ ────► (ダミー応答)    │
        │                       │
        └───────────────────────┘
```

- I2C SCL/SDA はオープンドレン双方向 (RTLで `1'bz` / `1'b0` 切替)
- LED[7] はFabric回路で独立点滅 (CPUクラッシュ時も継続)
- AXI Master はRTLでダミー応答 (FPGA内未接続の周辺アクセス用)

### LED の動作

ユーザーLED 8個は3つの源に分かれています:

| LED | 駆動元 | 動作 |
|-----|--------|------|
| LED0 | CPU ファームウェア | メインループ内で約0.5秒周期でトグル (CPU生存確認用) |
| LED1〜6 | CPU ファームウェア | UARTコマンド `1`〜`6` / `a` / `c` で制御 |
| LED7 | FPGA Fabric (ハードウェア) | 27bitカウンタで約1.5Hz点滅 (CPUクラッシュ時も継続) |

RTL での接続:

```verilog
assign led_o = {~blink_cnt[25], ~gpio_write[6:0]};
//              ↑LED7=HW点滅     ↑LED6:0=CPU GPIO出力
```

ファームウェアでのLED0点滅:

```c
if (cpu_blink_cnt >= CPU_BLINK_PERIOD) {
    led ^= 0x01u;   // LED0 トグル
    led_write();
}
```

**ハング判別**: LED7が点滅しているのにLED0が止まっている場合、CPUがクラッシュまたはハングアップしています。

### FPGA リソース使用量・タイミング

> 同一のSapphire SoC構成を持つベースプロジェクト (`sapphire_uart_led_t20`) でのビルド結果を参照値として記載。I2Cピンを外部接続に変更した影響はLE数個程度で微小。

#### タイミング (Efinity STA, C4 speed grade)

| 項目 | 値 | 判定 |
|------|----|:----:|
| 制約クロック | `clk_100m` 10.000ns (100MHz) | - |
| Setup Slack | +0.681 ns | ✅ |
| Hold Slack | +0.086 ns | ✅ |
| 達成最高周波数 | 107.3 MHz (9.319ns) | ✅ |
| クリティカルパス | CPUコア内 `memory_to_writeBack` → `mult` (6ロジックレベル) | - |

100MHz制約に対して **0.681ns のSetup余裕** があり、タイミング違反なし。

#### リソース使用量 (T20F256)

| リソース | 使用数 | 総数 | 使用率 |
|----------|--------|------|--------|
| Logic Elements (LE) | 6,308 | 19,728 | 31.97% |
| 　LUTs/Adders | 4,679 | 19,728 | 23.72% |
| 　Registers | 3,348 | 13,920 | 24.05% |
| Memory Blocks | 43 | 204 | 21.08% |
| Multipliers (DSP) | 4 | 36 | 11.11% |
| 入力ピン | 3 | 438 | 0.68% |
| 出力ピン | 9 | 1,001 | 0.90% |
| クロック | 1 | 16 | 6.25% |

T20F256 (19,728 LE) に対して **約32%** のリソースを消費。残り約68%をユーザー回路に使用可能。

#### Sapphire SoC 内訳 (主要ブロック)

SoC全体で6,308LE中、大部分がCPUコアとペリフェラルで消費:

| ブロック | 内容 | 主なリソース |
|----------|------|-------------|
| CPU コア (VexRiscv派生) | RV32IM パイプライン、レジスタファイル、割込処理 | LE多数 + RAM 4ブロック (レジスタファイル) |
| I-Cache | 4KB / 1way / 64B per line | RAM 8ブロック (タグ+データ) |
| D-Cache | 4KB / 1way / 64B per line | RAM 10ブロック (タグ+データ) |
| 内蔵RAM (RAM_A) | 16KB ファームウェア格納 | RAM 32ブロック |
| UART0 | TX/RX FIFO 各128 | RAM 2ブロック |
| SPI0 | Cmd/Rsp FIFO 各256 | RAM 2ブロック |
| I2C0 | I2Cコントローラ | LE少量 |
| GPIO0 | 8bit 入出力 | LE少量 |
| Watchdog | 24bit プリスケーラ、16bit タイマ | LE少量 |
| PLIC / CLINT | 割込コントローラ、タイマ | LE中量 |
| AXI Bridge | マスタブリッジ (ダミー応答) | LE中量 |
| 乗算器 (MUL) | RV32M用 32bit乗算 | DSP 4ブロック |

> **ユーザー回路**: トップモジュールのLED点滅・SW4デバウンス・AXIダミー応答で追加消費するLEは約50以下。SoC本体がリソースの大部分を占める。

#### メモリ (RAM) 使用量の内訳

Trion T20 のメモリブロックは1個あたり 4,096 bits (512 bytes)。全43ブロック中の用途別内訳:

| 用途 | ブロック数 | バイト数 | ビット数 | 備考 |
|------|:---------:|:--------:|:--------:|------|
| 内蔵RAM (RAM_A) | 32 | 16,384 | 131,072 | ファームウェア + スタック (16KB) |
| D-Cache データ/タグ | 10 | 5,120 | 40,960 | 4KB データ + タグ (1way) |
| I-Cache データ/タグ | 9 | 4,608 | 36,864 | 4KB データ + タグ (1way) |
| レジスタファイル | 4 | 2,048 | 16,384 | 32本 × 32bit (2ポート) |
| SPI0 FIFO | 2 | 1,024 | 8,192 | Cmd/Rsp 各256エントリ |
| UART0 FIFO | 2 | 1,024 | 8,192 | TX/RX 各128エントリ |
| **合計** | **59** | **30,208** | **241,664** | T20F256 全204ブロック中 28.92% |

> - **ファームウェア領域**: RAM_A 16KBのうち、ファームウェア本体約10KB + スタック512bytes (`linker.ld` で `__stack_size = 512`)
> - **I2C0/GPIO0/WDT**: RAMブロック未使用 (LEのみで実装)
> - **残り145ブロック** (約72KB) をユーザー回路のBRAMに使用可能

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

- ボードのUSBシリアルポート (OSで割り当てられたCOM番号)
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
0x00001000 = 0x000000AB
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

#### `memtest` — EEPROM メモリテスト

EEPROMのデータ・アドレス・パターン整合性を検証します。サブコマンドで規模を選択:

| 書式 | 内容 | 書き込み回数 | 所要時間 |
|------|------|------------|---------|
| `memtest` | クイックテスト (4アドレス×4パターン) | 16回 | ~0.1秒 |
| `memtest quick` | 同上 | 16回 | ~0.1秒 |
| `memtest page <addr16>` | 1ページ×4パターン | (ページサイズ×4)回 | ~3秒 |
| `memtest range <addr16> <len>` | 指定範囲(最大1024B)のアドレス依存テスト | len回 | len×5ms |
| `memtest full` | 全領域×3パターン | ~1536回 | ~10秒 |

> ページサイズは `eetype` で選択中のEEPROMタイプに依存します (AT24C256: 64B, AT24C512C: 128B)。
>
> **注意:** `full` はEEPROMの書き換え寿命(AT24C256/AT24C512C: 100万回/セル)を消費します。頻繁な実行は避けてください。

クイックテスト例 (0x0000, 0x4000, 0x8000, 0xC000 の各アドレスで 0x00/0xFF/0x55/0xAA を書いて読む):

```
> memtest
Quick test: 4 addresses x 4 patterns...
  [0x0000] OK
  [0x4000] OK
  [0x8000] OK
  [0xC000] OK
Quick test PASS
```

ページテスト例 (128バイトに 0x00/0xFF/0x55/0xAA を順に書いて検証):

```
> memtest page 0x0000
Page test: 128 bytes at 0x0000...
....
Page test PASS
```

範囲テスト例 (256バイトにアドレス下位バイトを書いて検証):

```
> memtest range 0x0000 256
Range test: 0x100 bytes at 0x0000...
....
Range test PASS
```

フルテスト例 (64KB全領域を 0x00/0xFF/0x55 の3パターンで検証):

```
> memtest full
Full test: 64KB x 3 patterns (page write)...
WARNING: ~3000 write cycles. Do not run frequently.

Pattern 0x00: writing...
................
Verifying...
................

Pattern 0xFF: writing...
................
Verifying...
................

Pattern 0x55: writing...
................
Verifying...
................

Full test PASS
```

#### `nvm` — 不揮発性保持テスト

電源を切ってもデータが残るか (EEPROMの本来機能) を確認するテストです。EEPROM末尾にマジック・カウンタ・チェックサムを書き込み、電源サイクル後の保持を検証します。テスト領域のアドレスは `eetype` で選択中のEEPROMタイプに依存します (AT24C256: 0x7FF0, AT24C512C: 0xFFF0)。

| サブコマンド | 内容 |
|--------------|------|
| `nvm save` | 初期パターン書き込み (magic=0xA5, counter=0) |
| `nvm load` | 読み出して magic・counter・checksum を表示・検証 |
| `nvm inc` | counter を +1 して保存 |
| `nvm clear` | テスト領域を 0x00 でクリア |

EEPROM のレイアウト (4バイト):

```
(base+0): Magic    (0xA5)
(base+1): Counter  (16bit, big-endian)
(base+3): Checksum (Magic ^ Counter)
```

> `base` は `eeprom_max_addr - 15` (AT24C256: 0x7FF0, AT24C512C: 0xFFF0)

**テスト手順:**

```
ステップ1: 初期書き込み
> nvm save
Saving NVM pattern...
OK
Power off the board, then power on and run 'nvm load'.

ステップ2: 電源OFF → 電源ON

ステップ3: 保持確認
> nvm load
Loading NVM pattern...
  Magic    = 0x000000A5
  Counter  = 0x00000000
  Checksum = 0x000000A5
  Status   = OK
Retention OK.

ステップ4: カウンタを増やす
> nvm inc
Loading NVM pattern...
  Magic    = 0x000000A5
  Counter  = 0x00000000
  Checksum = 0x000000A5
  Status   = OK
Incrementing and saving...
New counter = 0x00000001
Power off, power on, and run 'nvm load' to verify.

ステップ5: 電源OFF → 電源ON

ステップ6: カウンタが保持されているか確認
> nvm load
Loading NVM pattern...
  Magic    = 0x000000A5
  Counter  = 0x00000001
  Checksum = 0x000000A4
  Status   = OK
Retention OK.
```

`Status = OK` になれば、電源サイクル後もデータが正しく保持されています。`INVALID` (magic不一致) または `CORRUPT` (checksum不一致) の場合はデータ破損を示します。

#### `scan` — I2C バススキャン

アドレス 0x03〜0x77 を走査し、ACKを返すデバイスを一覧します。各アドレスを **2回試行** し、両方ともACKの場合のみ報告します (フェイクACKの排除)。AT24C256 は 0x50 に応答します。

```
> scan
Scanning I2C bus 0x03..0x77...
Found: 0x00000050 (w:0x000000A0)
Scan done.
```

> **トラブルシュート:** `scan` で何も見つからない場合、配線・プルアップ抵抗・電圧を確認してください。
>
> **複数デバイスが検出される場合:** 1個のEEPROMでもアドレスプレフィックス方式の違いで複数アドレスに応答することがあります。例えば 0x50 と 0x58 の両方が見つかる場合、チップが 1Mbit(128KB) EEPROM (M24M01/CAT24M01系) で、A16 をデバイスアドレスbitに押し込む方式の可能性があります。AT24C256 (32KB) / AT24C512C (64KB) は `1010xxx` (0x50〜0x57) のみ応答する仕様です。

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
GPIO_IN = 0x00000000
GPIO_OUT= 0x00000001
GPIO_OE = 0x0000007F
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
I2CINIT = 0x00000001
EE TYPE = AT24C512C 64KB
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
I2CINIT = 0x00000001
EE TYPE = AT24C512C 64KB
GPIO_IN = 0x00000000
GPIO_OUT= 0x00000001
GPIO_OE = 0x0000007F
UART_ST = 0x00008000
WDT_EN  = 0x00000000
WDT_HANG= 0x00000000
LASTERR = 0x00000000
```

#### `err?` — 直前のエラー

最後に発生したエラーコードを表示します。`0x00000000` はエラーなし。

```
> err?
LASTERR = 0x00000000
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
memtest [quick|page <a>|range <a> <l>|full]
nvm save|load|inc|clear   retention test
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
F8016000 = 00000000
```

> FW仮想レジスタ (0xF80FF000〜) は固定値を返します:
> ```
> > m 0xF80FF000
> F80FF000 = 41543235
> ```

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
Found: 0x00000050 (w:0x000000A0)
Scan done.

> eetest
EEPROM test: write 16 bytes at 0x0000...
................
Reading back...
40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
PASS

> memtest
Quick test: 4 addresses x 4 patterns...
  [0x00000000] OK
  [0x00004000] OK
  [0x00008000] OK
  [0x0000C000] OK
Quick test PASS

> eew 0x1000 0xAB
OK

> eer 0x1000
0x00001000 = 0x000000AB

> eefill 0x2000 32 0x55
OK

> eedump 0x0000 48
00000000: 40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F
00000010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00000020: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00

> eedump 0x2000 32
00002000: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55
00002010: 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55 55

> nvm save
Saving NVM pattern...
OK
Power off the board, then power on and run 'nvm load'.

> id
ID INFO
FW      = v1.0.0 AT24C512C
DATE    = 2026-06-18
ID      = 0x41543235
VERSION = 0x00010000
DATEHEX = 0x20260618
FW_BASE = 0xF80FF000
I2C_REG = 0xF8016000
I2CINIT = 0x00000001
EE TYPE = AT24C512C 64KB
```

## ファームウェア仮想レジスタ

- `0xF80FF000`: ID、`"AT25"` (`0x41543235`)
- `0xF80FF004`: バージョン、`0x00010000`
- `0xF80FF008`: 日付、`0x20260618`
- `0xF80FF00C`: 直前のエラー

## I2C 設定

- 周波数: 100kHz (Standard Mode)
- スレーブアドレス: 0xA0 (7-bit: 0x50, A2A1A0=000)
- アドレス幅: 16-bit
- ライターイクルタイム: 5ms

### 対応EEPROM

`eetype` コマンドで実行時に切り替え可能。デフォルトは AT24C512C。

| コマンド | EEPROM | 容量 | ページサイズ | 最大アドレス |
|----------|--------|------|:----------:|:----------:|
| `eetype 256` | AT24C256 | 32KB | 64B | 0x7FFF |
| `eetype 512` | AT24C512C | 64KB | 128B | 0xFFFF |

```
> eetype 256
EEPROM: AT24C256 32KB page=64

> eetype 512
EEPROM: AT24C512C 64KB page=128
```

`id` コマンドで現在のEEPROMタイプを確認可能:

```
> id
ID INFO
FW      = v1.0.0 AT24C512C
...
EE TYPE = AT24C512C 64KB
```

## テストバッチ (test.ps1)

`test.ps1` は全コマンドを自動テストするスクリプトです。ファームウェア書き込み後の動作確認に使用します。

### 使用法

```powershell
.\test.ps1 -Port COM11
```

### テスト内容 (35項目)

| グループ | テスト数 | 内容 |
|---|---|---|
| 情報表示 | 4 | `err?` `id` `dump` `help` |
| EEPROMタイプ | 1 | `eetype 256` |
| 読み書き | 4 | `eew` `eer` `eefill` `eedump` |
| テストパターン | 2 | `eetest` `eedump`(確認) |
| memtest | 3 | `memtest quick` `page` `range` |
| NVM保持 | 5 | `nvm save` `load` `inc` `load` `clear` |
| I2Cバス | 2 | `iinit` `scan` |
| LED/GPIO | 2 | LED目視確認 / `g` |
| ウォッチドッグ | 3 | `wdt on` `pat` `off` |
| MMIO | 2 | `m`(FW仮想レジスタ) |
| エラー処理 | 3 | `eetype`(無引数) `eetype 999` `unknowncmd` |
| 64KBモード | 2 | `eetype 512` `memtest quick` |
| 後片付け | 1 | `eetype 256` |

### インタラクティブテスト

以下のテストはユーザー操作が必要です:

- **SW4状態変化検出**: 「SW4 を押してください」→自動検出→「SW4 を離してください」→自動検出 (30秒以内)
- **LED目視確認**: LED1〜6を順に点灯→各LEDを目視確認 `[y/n]`→全点灯/全消灯確認

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
.\test.ps1       # 全コマンド動作テスト (オプション: -Port COMxx)
```

> **重要: SoC IP の再生成が必要**
>
> 内蔵RAMを8KB→16KBに変更しているため、初回ビルド前にEfinity IDEでSapphire SoC IPを再生成する必要があります:
> 1. Efinity IDEでプロジェクトを開く
> 2. IP Manager で `soc` IPを開く
> 3. `OCRSize` が `16384` になっていることを確認 (settings.jsonは更新済み)
> 4. 「Generate」ボタンでIPを再生成
> 5. `ip/soc/soc.v` と `embedded_sw/` が自動更新される
> 6. その後 `build_sw.ps1` → `build.ps1` → `program.ps1` の順に実行
