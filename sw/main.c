// =============================================================================
// main.c  Sapphire SoC ファームウェア v1.0.0
//
// AT24C512C (64KB I2C EEPROM) 制御ファームウェア
//
// 機能:
//   - UART (9600bps 8N1) でコマンドモニタを提供
//   - I2C で AT24C512C EEPROM の読み書き (16bitアドレス)
//   - GPIO でLED制御 (デバッグ用)
//   - I2C バススキャン
// =============================================================================

#include "type.h"
#include "soc.h"
#include "uart.h"
#include "gpio.h"
#include "i2c.h"
#include "watchdog.h"

#define UART_REG    SYSTEM_UART_0_IO_CTRL
#define GPIO_REG    SYSTEM_GPIO_0_IO_CTRL
#define I2C_REG     SYSTEM_I2C_0_IO_CTRL

#define EEPROM_SLAVE_ADDR  0xA0u
#define EEPROM_PAGE_SIZE   128u
#define EEPROM_WRITE_DELAY_MS  5u

// 不揮発性保持テスト用アドレス・マジック
#define NVM_TEST_ADDR      0xFFF0u
#define NVM_TEST_MAGIC     0xA5u
#define NVM_TEST_COUNT_OFF 1u   // 電源サイクルカウンタのオフセット
#define NVM_TEST_TS_OFF    2u   // タイムスタンプのオフセット (2バイト)

#define CPU_BLINK_PERIOD        1000000u
#define WDT_PAT_PERIOD          100000u
#define WDT_PRESCALER_PER_MS    (SYSTEM_CLINT_HZ / 1000u)
#define WDT_TIMEOUT_MS          3000u

#define FW_REG_BASE       0xF80FF000u
#define FW_REG_ID         (FW_REG_BASE + 0x00u)
#define FW_REG_VERSION    (FW_REG_BASE + 0x04u)
#define FW_REG_DATE       (FW_REG_BASE + 0x08u)
#define FW_REG_LAST_ERR   (FW_REG_BASE + 0x0cu)

#define FW_ID_VALUE       0x41543235u
#define FW_VERSION_VALUE  0x00010000u
#define FW_DATE_VALUE     0x20260618u

#define CMD_BUF_SIZE      80u
#define DUMP_MAX          64u
#define FILL_MAX          128u

enum {
    ERR_NONE         = 0,
    ERR_UNKNOWN_CMD  = 1,
    ERR_BAD_ARG      = 2,
    ERR_READONLY     = 3,
    ERR_LINE_TOO_LONG = 4,
    ERR_I2C_NACK     = 5,
    ERR_RANGE        = 6
};

static u8 led = 0x00u;
static u32 last_error = ERR_NONE;
static u8 wdt_enabled = 0u;
static u8 wdt_hang = 0u;
static u8 i2c_initialized = 0u;

// -----------------------------------------------------------------------------
// 遅延
// -----------------------------------------------------------------------------
static void delay_cycles(volatile u32 count)
{
    while (count--) {}
}

static void delay_ms(u32 ms)
{
    while (ms--)
        delay_cycles(100000u);
}

// -----------------------------------------------------------------------------
// UART
// -----------------------------------------------------------------------------
static void uart_putc(char c)
{
    u32 timeout = 1000000u;
    while (uart_writeAvailability(UART_REG) == 0u && timeout)
        timeout--;
    if (timeout)
        uart_write(UART_REG, c);
    else
        last_error = ERR_LINE_TOO_LONG;
}

static void uart_put_label_hex(const char *label, u32 value)
{
    uart_writeStr(UART_REG, label);
    uart_writeStr(UART_REG, "0x");
    uart_writeHex(UART_REG, (int)value);
    uart_writeStr(UART_REG, "\r\n");
}

static char uart_getc(void)
{
    return (char)(read_u32(UART_REG + UART_DATA) & 0xffu);
}

static void uart_init(void)
{
    Uart_Config cfg;
    cfg.dataLength   = BITS_8;
    cfg.parity       = NONE;
    cfg.stop         = ONE;
    cfg.clockDivider = 1301u;
    uart_applyConfig(UART_REG, &cfg);
}

// -----------------------------------------------------------------------------
// LED / GPIO
// -----------------------------------------------------------------------------
static void led_write(void)
{
    gpio_setOutput(GPIO_REG, (u32)led);
}

// -----------------------------------------------------------------------------
// Watchdog
// -----------------------------------------------------------------------------
static void wdt_start(void)
{
    watchdog_disable(SYSTEM_WATCHDOG_LOGIC_CTRL, 0x03u);
    watchdog_setPrescaler(SYSTEM_WATCHDOG_LOGIC_CTRL, WDT_PRESCALER_PER_MS - 1u);
    watchdog_setCounterLimit(SYSTEM_WATCHDOG_LOGIC_CTRL, 1u, WDT_TIMEOUT_MS - 1u);
    watchdog_heartbeat(SYSTEM_WATCHDOG_LOGIC_CTRL);
    watchdog_enable(SYSTEM_WATCHDOG_LOGIC_CTRL, 0x02u);
    wdt_enabled = 1u;
    wdt_hang = 0u;
}

static void wdt_stop(void)
{
    watchdog_disable(SYSTEM_WATCHDOG_LOGIC_CTRL, 0x03u);
    wdt_enabled = 0u;
    wdt_hang = 0u;
}

static void wdt_service(void)
{
    if (wdt_enabled && !wdt_hang)
        watchdog_heartbeat(SYSTEM_WATCHDOG_LOGIC_CTRL);
}

// -----------------------------------------------------------------------------
// I2C 初期化 (100kHz)
// -----------------------------------------------------------------------------
static void i2c_init(void)
{
    I2c_Config cfg;
    cfg.samplingClockDivider = 9u;
    cfg.timeout              = 100000u;
    cfg.tsuDat               = 24u;
    cfg.tLow                 = 469u;
    cfg.tHigh                = 399u;
    cfg.tBuf                 = 469u;
    i2c_applyConfig(I2C_REG, &cfg);
    i2c_initialized = 1u;
}

// -----------------------------------------------------------------------------
// AT24C512C EEPROM アクセス
// -----------------------------------------------------------------------------

// 1バイト書き込み
static u8 eeprom_write_byte(u16 addr, u8 data)
{
    u8 buf[1];
    buf[0] = data;
    i2c_writeData_w(I2C_REG, EEPROM_SLAVE_ADDR, addr, buf, 1u);
    delay_ms(EEPROM_WRITE_DELAY_MS);
    return 0u;
}

// ページ書き込み (最大128バイト)
static u8 eeprom_write_page(u16 addr, u8 *data, u32 len)
{
    if (len > EEPROM_PAGE_SIZE) return ERR_RANGE;
    i2c_writeData_w(I2C_REG, EEPROM_SLAVE_ADDR, addr, data, len);
    delay_ms(EEPROM_WRITE_DELAY_MS);
    return 0u;
}

// 1バイト読み取り
static u8 eeprom_read_byte(u16 addr, u8 *data)
{
    i2c_readData_w(I2C_REG, EEPROM_SLAVE_ADDR, addr, data, 1u);
    return 0u;
}

// 複数バイト読み取り
static u8 eeprom_read_bytes(u16 addr, u8 *data, u32 len)
{
    i2c_readData_w(I2C_REG, EEPROM_SLAVE_ADDR, addr, data, len);
    return 0u;
}

// I2Cバススキャン
static void i2c_scan(void)
{
    uart_writeStr(UART_REG, "Scanning I2C bus 0x03..0x77...\r\n");
    for (u32 addr = 0x03u; addr <= 0x77u; addr++) {
        u8 slave = (u8)(addr << 1);
        i2c_masterStartBlocking(I2C_REG);
        i2c_txByte(I2C_REG, slave | I2C_WRITE);
        i2c_txNackBlocking(I2C_REG);
        if (i2c_rxAck(I2C_REG)) {
            uart_writeStr(UART_REG, "Found: 0x");
            uart_writeHex(UART_REG, (int)addr);
            uart_writeStr(UART_REG, " (w:0x");
            uart_writeHex(UART_REG, (int)slave);
            uart_writeStr(UART_REG, ")\r\n");
        }
        i2c_masterStopBlocking(I2C_REG);
    }
    uart_writeStr(UART_REG, "Scan done.\r\n");
}

// テストパターン書き込み＆検証
static void eeprom_test(void)
{
    u8 wbuf[16];
    u8 rbuf[16];
    u16 addr = 0x0000u;

    uart_writeStr(UART_REG, "EEPROM test: write 16 bytes at 0x0000...\r\n");
    for (u32 i = 0u; i < 16u; i++)
        wbuf[i] = (u8)(0x40u + i);

    for (u32 i = 0u; i < 16u; i++) {
        eeprom_write_byte((u16)(addr + i), wbuf[i]);
        uart_putc('.');
    }
    uart_writeStr(UART_REG, "\r\nReading back...\r\n");

    eeprom_read_bytes(addr, rbuf, 16u);

    u8 ok = 1u;
    for (u32 i = 0u; i < 16u; i++) {
        uart_writeHex(UART_REG, (int)rbuf[i]);
        if (i < 15u) uart_putc(' ');
        if (rbuf[i] != wbuf[i]) ok = 0u;
    }
    uart_writeStr(UART_REG, "\r\n");
    if (ok) {
        uart_writeStr(UART_REG, "PASS\r\n");
        last_error = ERR_NONE;
    } else {
        uart_writeStr(UART_REG, "FAIL\r\n");
        last_error = ERR_I2C_NACK;
    }
}

// -----------------------------------------------------------------------------
// EEPROM メモリテスト
// -----------------------------------------------------------------------------
// テスト内容:
//   1. データバステスト: 固定アドレスで 0x00/0xFF/0x55/0xAA を書いて読む
//   2. アドレスユニークネス: 2の累乗アドレスにアドレス依存パターンを書く
//   3. March風テスト: 全範囲に 0x00 → 0xFF → 0x55 の順で書いて読む
// -----------------------------------------------------------------------------

#define MEMTEST_PATTERNS_COUNT 4
static const u8 memtest_patterns[MEMTEST_PATTERNS_COUNT] = {0x00u, 0xFFu, 0x55u, 0xAAu};

// 1アドレスでデータバステスト
static u8 memtest_data_bus(u16 addr)
{
    for (u32 i = 0u; i < MEMTEST_PATTERNS_COUNT; i++) {
        u8 w = memtest_patterns[i];
        u8 r = 0u;
        eeprom_write_byte(addr, w);
        eeprom_read_byte(addr, &r);
        if (r != w) {
            uart_writeStr(UART_REG, "  data bus FAIL @0x");
            uart_writeHex(UART_REG, (int)addr);
            uart_writeStr(UART_REG, " wrote 0x");
            uart_writeHex(UART_REG, (int)w);
            uart_writeStr(UART_REG, " read 0x");
            uart_writeHex(UART_REG, (int)r);
            uart_writeStr(UART_REG, "\r\n");
            return 0u;
        }
    }
    return 1u;
}

// クイックテスト: 4アドレス x 4パターン
static void eeprom_memtest_quick(void)
{
    static const u16 quick_addrs[4] = {0x0000u, 0x4000u, 0x8000u, 0xC000u};

    uart_writeStr(UART_REG, "Quick test: 4 addresses x 4 patterns...\r\n");
    u8 ok = 1u;
    for (u32 i = 0u; i < 4u; i++) {
        uart_writeStr(UART_REG, "  [0x");
        uart_writeHex(UART_REG, (int)quick_addrs[i]);
        uart_writeStr(UART_REG, "] ");
        if (memtest_data_bus(quick_addrs[i])) {
            uart_writeStr(UART_REG, "OK\r\n");
        } else {
            ok = 0u;
        }
    }
    if (ok) {
        uart_writeStr(UART_REG, "Quick test PASS\r\n");
        last_error = ERR_NONE;
    } else {
        uart_writeStr(UART_REG, "Quick test FAIL\r\n");
        last_error = ERR_I2C_NACK;
    }
}

// ページテスト: 128バイト範囲でパターン検証
static void eeprom_memtest_page(u16 addr)
{
    u8 wbuf[EEPROM_PAGE_SIZE];
    u8 rbuf[EEPROM_PAGE_SIZE];
    u16 page_base = (u16)(addr & 0xFF80u);

    uart_writeStr(UART_REG, "Page test: 128 bytes at 0x");
    uart_writeHex(UART_REG, (int)page_base);
    uart_writeStr(UART_REG, "...\r\n");

    u8 ok = 1u;
    for (u32 pat = 0u; pat < MEMTEST_PATTERNS_COUNT; pat++) {
        u8 w = memtest_patterns[pat];
        for (u32 i = 0u; i < EEPROM_PAGE_SIZE; i++)
            wbuf[i] = w;
        eeprom_write_page(page_base, wbuf, EEPROM_PAGE_SIZE);
        eeprom_read_bytes(page_base, rbuf, EEPROM_PAGE_SIZE);
        for (u32 i = 0u; i < EEPROM_PAGE_SIZE; i++) {
            if (rbuf[i] != w) {
                uart_writeStr(UART_REG, "  FAIL @0x");
                uart_writeHex(UART_REG, (int)(page_base + i));
                uart_writeStr(UART_REG, " exp 0x");
                uart_writeHex(UART_REG, (int)w);
                uart_writeStr(UART_REG, " got 0x");
                uart_writeHex(UART_REG, (int)rbuf[i]);
                uart_writeStr(UART_REG, "\r\n");
                ok = 0u;
            }
        }
        uart_putc('.');
    }
    uart_writeStr(UART_REG, "\r\n");
    if (ok) {
        uart_writeStr(UART_REG, "Page test PASS\r\n");
        last_error = ERR_NONE;
    } else {
        uart_writeStr(UART_REG, "Page test FAIL\r\n");
        last_error = ERR_I2C_NACK;
    }
}

// 範囲テスト: 指定範囲でアドレス依存パターン検証
static void eeprom_memtest_range(u16 addr, u32 len)
{
    if (len > 1024u) len = 1024u;
    if ((u32)addr + len > 0x10000u) {
        print_err(ERR_RANGE);
        return;
    }

    uart_writeStr(UART_REG, "Range test: ");
    uart_writeHex(UART_REG, (int)len);
    uart_writeStr(UART_REG, " bytes at 0x");
    uart_writeHex(UART_REG, (int)addr);
    uart_writeStr(UART_REG, "...\r\n");

    // パス1: アドレス依存パターン (low byte of address)
    u8 ok = 1u;
    u8 rbuf[64];
    for (u32 off = 0u; off < len; off += 64u) {
        u32 chunk = len - off;
        if (chunk > 64u) chunk = 64u;
        for (u32 i = 0u; i < chunk; i++) {
            u16 a = (u16)(addr + off + i);
            eeprom_write_byte(a, (u8)(a & 0xFFu));
        }
    }
    for (u32 off = 0u; off < len; off += 64u) {
        u32 chunk = len - off;
        if (chunk > 64u) chunk = 64u;
        eeprom_read_bytes((u16)(addr + off), rbuf, chunk);
        for (u32 i = 0u; i < chunk; i++) {
            u16 a = (u16)(addr + off + i);
            if (rbuf[i] != (u8)(a & 0xFFu)) {
                uart_writeStr(UART_REG, "  FAIL @0x");
                uart_writeHex(UART_REG, (int)a);
                uart_writeStr(UART_REG, " exp 0x");
                uart_writeHex(UART_REG, (int)(a & 0xFFu));
                uart_writeStr(UART_REG, " got 0x");
                uart_writeHex(UART_REG, (int)rbuf[i]);
                uart_writeStr(UART_REG, "\r\n");
                ok = 0u;
            }
        }
        uart_putc('.');
    }
    uart_writeStr(UART_REG, "\r\n");
    if (ok) {
        uart_writeStr(UART_REG, "Range test PASS\r\n");
        last_error = ERR_NONE;
    } else {
        uart_writeStr(UART_REG, "Range test FAIL\r\n");
        last_error = ERR_I2C_NACK;
    }
}

// フルテスト: 全64KB を3パターンでページ書き込み検証
static void eeprom_memtest_full(void)
{
    u8 wbuf[EEPROM_PAGE_SIZE];
    u8 rbuf[EEPROM_PAGE_SIZE];
    const u32 total_pages = 0x10000u / EEPROM_PAGE_SIZE;

    uart_writeStr(UART_REG, "Full test: 64KB x 3 patterns (page write)...\r\n");
    uart_writeStr(UART_REG, "WARNING: ~3000 write cycles. Do not run frequently.\r\n");

    u8 ok = 1u;
    for (u32 pat = 0u; pat < MEMTEST_PATTERNS_COUNT - 1u; pat++) {
        u8 w = memtest_patterns[pat];
        uart_writeStr(UART_REG, "\r\nPattern 0x");
        uart_writeHex(UART_REG, (int)w);
        uart_writeStr(UART_REG, ": writing...\r\n");

        for (u32 pg = 0u; pg < total_pages; pg++) {
            u16 base = (u16)(pg * EEPROM_PAGE_SIZE);
            for (u32 i = 0u; i < EEPROM_PAGE_SIZE; i++)
                wbuf[i] = w;
            eeprom_write_page(base, wbuf, EEPROM_PAGE_SIZE);
            if ((pg & 0x3Fu) == 0u) uart_putc('.');
        }
        uart_writeStr(UART_REG, "\r\nVerifying...\r\n");

        for (u32 pg = 0u; pg < total_pages; pg++) {
            u16 base = (u16)(pg * EEPROM_PAGE_SIZE);
            eeprom_read_bytes(base, rbuf, EEPROM_PAGE_SIZE);
            for (u32 i = 0u; i < EEPROM_PAGE_SIZE; i++) {
                if (rbuf[i] != w) {
                    uart_writeStr(UART_REG, "  FAIL @0x");
                    uart_writeHex(UART_REG, (int)(base + i));
                    uart_writeStr(UART_REG, " exp 0x");
                    uart_writeHex(UART_REG, (int)w);
                    uart_writeStr(UART_REG, " got 0x");
                    uart_writeHex(UART_REG, (int)rbuf[i]);
                    uart_writeStr(UART_REG, "\r\n");
                    ok = 0u;
                }
            }
            if ((pg & 0x3Fu) == 0u) uart_putc('.');
        }
        uart_writeStr(UART_REG, "\r\n");
    }
    if (ok) {
        uart_writeStr(UART_REG, "Full test PASS\r\n");
        last_error = ERR_NONE;
    } else {
        uart_writeStr(UART_REG, "Full test FAIL\r\n");
        last_error = ERR_I2C_NACK;
    }
}

// -----------------------------------------------------------------------------
// コマンドライン入力ユーティリティ
// -----------------------------------------------------------------------------
static void uart_drain_line_end(void)
{
    while (uart_readOccupancy(UART_REG)) {
        char c = uart_getc();
        if (!(c == '\r' || c == '\n' || c == 0))
            break;
    }
}

static void command_preamble(void)
{
    delay_cycles(100000u);
    uart_drain_line_end();
    uart_writeStr(UART_REG, "\r\n");
}

static u8 sw4_read(void)
{
    return (u8)(gpio_getInput(GPIO_REG) & 0x01u);
}

static char to_lower(char c)
{
    return (c >= 'A' && c <= 'Z') ? (char)(c + ('a' - 'A')) : c;
}

static char *skip_spaces(char *p)
{
    while (*p == ' ' || *p == '\t') p++;
    return p;
}

static u8 token_eq(const char *p, const char *word)
{
    while (*word) {
        if (to_lower(*p++) != *word++) return 0u;
    }
    return (*p == 0 || *p == ' ' || *p == '\t' || *p == '?') ? 1u : 0u;
}

static u8 hex_digit(char c, u32 *value)
{
    if (c >= '0' && c <= '9') {
        *value = (u32)(c - '0');
        return 1u;
    }
    c = to_lower(c);
    if (c >= 'a' && c <= 'f') {
        *value = (u32)(c - 'a' + 10);
        return 1u;
    }
    return 0u;
}

static u8 parse_hex32(char **pp, u32 *value)
{
    char *p = skip_spaces(*pp);
    u32 parsed = 0u;
    u32 digit = 0u;
    u8 count = 0u;

    if (p[0] == '0' && to_lower(p[1]) == 'x') p += 2;

    while (hex_digit(*p, &digit)) {
        if (count >= 8u) return 0u;
        parsed = (parsed << 4) | digit;
        p++;
        count++;
    }
    if (count == 0u) return 0u;

    *value = parsed;
    *pp = p;
    return 1u;
}

static u8 parse_hex16(char **pp, u16 *value)
{
    u32 v = 0u;
    if (!parse_hex32(pp, &v)) return 0u;
    if (v > 0xFFFFu) return 0u;
    *value = (u16)v;
    return 1u;
}

static u8 parse_hex8(char **pp, u8 *value)
{
    u32 v = 0u;
    if (!parse_hex32(pp, &v)) return 0u;
    if (v > 0xFFu) return 0u;
    *value = (u8)v;
    return 1u;
}

// -----------------------------------------------------------------------------
// ファームウェア仮想レジスタ
// -----------------------------------------------------------------------------
static u8 read_fw_reg(u32 addr, u32 *value)
{
    if (addr == FW_REG_ID)       { *value = FW_ID_VALUE;      return 1u; }
    if (addr == FW_REG_VERSION)  { *value = FW_VERSION_VALUE; return 1u; }
    if (addr == FW_REG_DATE)     { *value = FW_DATE_VALUE;    return 1u; }
    if (addr == FW_REG_LAST_ERR) { *value = last_error;       return 1u; }
    return 0u;
}

static u32 mmio_read(u32 addr)
{
    u32 value = 0u;
    if (read_fw_reg(addr, &value)) return value;
    return read_u32(addr);
}

static u8 mmio_write(u32 addr, u32 value)
{
    u32 unused = 0u;
    if (read_fw_reg(addr, &unused)) {
        last_error = ERR_READONLY;
        return 0u;
    }
    write_u32(value, addr);
    return 1u;
}

// -----------------------------------------------------------------------------
// 情報ダンプ
// -----------------------------------------------------------------------------
static void gpio_dump(void)
{
    uart_put_label_hex("GPIO_IN = ", gpio_getInput(GPIO_REG));
    uart_put_label_hex("GPIO_OUT= ", gpio_getOutput(GPIO_REG));
    uart_put_label_hex("GPIO_OE = ", gpio_getOutputEnable(GPIO_REG));
}

static void id_dump(void)
{
    uart_writeStr(UART_REG, "ID INFO\r\n");
    uart_writeStr(UART_REG, "FW      = v1.0.0 AT24C512C\r\n");
    uart_writeStr(UART_REG, "DATE    = 2026-06-18\r\n");
    uart_put_label_hex("ID      = ", FW_ID_VALUE);
    uart_put_label_hex("VERSION = ", FW_VERSION_VALUE);
    uart_put_label_hex("DATEHEX = ", FW_DATE_VALUE);
    uart_put_label_hex("FW_BASE = ", FW_REG_BASE);
    uart_put_label_hex("I2C_REG = ", I2C_REG);
    uart_put_label_hex("I2CINIT = ", i2c_initialized);
}

static void boot_banner(void)
{
    uart_writeStr(UART_REG, "\r\nAT24C512C I2C EEPROM v1.0.0 2026-06-18\r\n");
}

static void status_dump(void)
{
    id_dump();
    gpio_dump();
    uart_put_label_hex("UART_ST = ", read_u32(UART_REG + UART_STATUS));
    uart_put_label_hex("WDT_EN  = ", wdt_enabled);
    uart_put_label_hex("WDT_HANG= ", wdt_hang);
    uart_put_label_hex("LASTERR = ", last_error);
}

static void help(void)
{
    uart_writeStr(UART_REG, "=== EEPROM ===\r\n");
    uart_writeStr(UART_REG, "eew <addr16> <data>  write byte\r\n");
    uart_writeStr(UART_REG, "eer <addr16>          read byte\r\n");
    uart_writeStr(UART_REG, "eedump <addr16> <len> dump (max 64)\r\n");
    uart_writeStr(UART_REG, "eefill <addr16> <len> <data> fill (max 128)\r\n");
    uart_writeStr(UART_REG, "eetest                test pattern\r\n");
    uart_writeStr(UART_REG, "memtest [quick|page <a>|range <a> <l>|full]\r\n");
    uart_writeStr(UART_REG, "scan                  I2C bus scan\r\n");
    uart_writeStr(UART_REG, "iinit                 reinit I2C\r\n");
    uart_writeStr(UART_REG, "=== LED/GPIO ===\r\n");
    uart_writeStr(UART_REG, "1-6 a c s g           LED/SW4 control\r\n");
    uart_writeStr(UART_REG, "=== Misc ===\r\n");
    uart_writeStr(UART_REG, "id dump err? help     info/status\r\n");
    uart_writeStr(UART_REG, "wdt on/off/pat/hang   watchdog\r\n");
    uart_writeStr(UART_REG, "m <addr>              read32\r\n");
    uart_writeStr(UART_REG, "w <addr> <data>       write32\r\n");
}

static void print_ok(void)
{
    uart_writeStr(UART_REG, "OK\r\n");
    last_error = ERR_NONE;
}

static void print_err(u32 err)
{
    last_error = err;
    uart_writeStr(UART_REG, "ERR ");
    uart_writeHex(UART_REG, (int)err);
    uart_writeStr(UART_REG, "\r\n");
}

// -----------------------------------------------------------------------------
// EEPROM ダンプ表示
// -----------------------------------------------------------------------------
static void eeprom_dump(u16 addr, u32 len)
{
    u8 buf[DUMP_MAX];
    if (len > DUMP_MAX) len = DUMP_MAX;
    if ((u32)addr + len > 0x10000u) {
        print_err(ERR_RANGE);
        return;
    }

    eeprom_read_bytes(addr, buf, len);

    for (u32 i = 0u; i < len; i += 16u) {
        u32 line_end = i + 16u;
        if (line_end > len) line_end = len;
        uart_writeHex(UART_REG, (int)(addr + i));
        uart_writeStr(UART_REG, ": ");
        for (u32 j = i; j < line_end; j++) {
            uart_writeHex(UART_REG, (int)buf[j]);
            uart_putc(' ');
        }
        uart_writeStr(UART_REG, "\r\n");
    }
    last_error = ERR_NONE;
}

// -----------------------------------------------------------------------------
// EEPROM フィル
// -----------------------------------------------------------------------------
static void eeprom_fill(u16 addr, u32 len, u8 data)
{
    u8 buf[FILL_MAX];
    if (len > FILL_MAX) len = FILL_MAX;
    if ((u32)addr + len > 0x10000u) {
        print_err(ERR_RANGE);
        return;
    }

    for (u32 i = 0u; i < len; i++)
        buf[i] = data;

    eeprom_write_page(addr, buf, len);
    print_ok();
}

// -----------------------------------------------------------------------------
// コマンド解釈・実行
// -----------------------------------------------------------------------------
static void execute_line(char *line)
{
    char *p = skip_spaces(line);
    u32 addr32 = 0u;
    u32 value32 = 0u;
    u16 addr16 = 0u;
    u8 data8 = 0u;
    u32 len = 0u;

    if (*p == 0) return;

    // 1文字コマンド (LED/SW4)
    if (p[1] == 0) {
        char c = to_lower(p[0]);

        if (c >= '1' && c <= '6') {
            led ^= (u8)(1u << (u8)(c - '0'));
            led_write();
            print_ok();
            return;
        }
        if (c == 'a') {
            led |= 0x7eu;
            led_write();
            print_ok();
            return;
        }
        if (c == 'c') {
            led &= 0x01u;
            led_write();
            print_ok();
            return;
        }
        if (c == 's') {
            uart_putc(sw4_read() ? '1' : '0');
            uart_writeStr(UART_REG, "\r\n");
            last_error = ERR_NONE;
            return;
        }
        if (c == 'g') {
            gpio_dump();
            last_error = ERR_NONE;
            return;
        }
    }

    if (token_eq(p, "id")) {
        id_dump();
        last_error = ERR_NONE;
        return;
    }
    if (token_eq(p, "dump")) {
        status_dump();
        last_error = ERR_NONE;
        return;
    }
    if (token_eq(p, "help") || p[0] == '?') {
        help();
        last_error = ERR_NONE;
        return;
    }
    if (token_eq(p, "err") && p[3] == '?') {
        uart_put_label_hex("LASTERR = ", last_error);
        return;
    }
    if (token_eq(p, "iinit")) {
        i2c_init();
        print_ok();
        return;
    }
    if (token_eq(p, "scan")) {
        i2c_scan();
        last_error = ERR_NONE;
        return;
    }
    if (token_eq(p, "eetest")) {
        eeprom_test();
        return;
    }
    if (token_eq(p, "memtest")) {
        p = skip_spaces(p + 7);
        if (*p == 0) {
            eeprom_memtest_quick();
            return;
        }
        if (token_eq(p, "quick")) {
            eeprom_memtest_quick();
            return;
        }
        if (token_eq(p, "page")) {
            p = skip_spaces(p + 4);
            if (!parse_hex16(&p, &addr16)) {
                print_err(ERR_BAD_ARG);
                return;
            }
            eeprom_memtest_page(addr16);
            return;
        }
        if (token_eq(p, "range")) {
            p = skip_spaces(p + 5);
            if (!parse_hex16(&p, &addr16) || !parse_hex32(&p, &len)) {
                print_err(ERR_BAD_ARG);
                return;
            }
            if (len == 0u) len = 256u;
            eeprom_memtest_range(addr16, len);
            return;
        }
        if (token_eq(p, "full")) {
            eeprom_memtest_full();
            return;
        }
        print_err(ERR_BAD_ARG);
        return;
    }
    if (token_eq(p, "eew")) {
        p = skip_spaces(p + 3);
        if (!parse_hex16(&p, &addr16) || !parse_hex8(&p, &data8)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        eeprom_write_byte(addr16, data8);
        print_ok();
        return;
    }
    if (token_eq(p, "eer")) {
        p = skip_spaces(p + 3);
        if (!parse_hex16(&p, &addr16)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        u8 rd = 0u;
        eeprom_read_byte(addr16, &rd);
        uart_writeStr(UART_REG, "0x");
        uart_writeHex(UART_REG, (int)addr16);
        uart_writeStr(UART_REG, " = 0x");
        uart_writeHex(UART_REG, (int)rd);
        uart_writeStr(UART_REG, "\r\n");
        last_error = ERR_NONE;
        return;
    }
    if (token_eq(p, "eedump")) {
        p = skip_spaces(p + 6);
        if (!parse_hex16(&p, &addr16) || !parse_hex32(&p, &len)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        if (len == 0u) len = 16u;
        eeprom_dump(addr16, len);
        return;
    }
    if (token_eq(p, "eefill")) {
        p = skip_spaces(p + 6);
        if (!parse_hex16(&p, &addr16) || !parse_hex32(&p, &len) || !parse_hex8(&p, &data8)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        if (len == 0u) len = 1u;
        eeprom_fill(addr16, len, data8);
        return;
    }
    if (token_eq(p, "wdt")) {
        p = skip_spaces(p + 3);
        if (token_eq(p, "on")) {
            wdt_start();
            print_ok();
            return;
        }
        if (token_eq(p, "off")) {
            wdt_stop();
            print_ok();
            return;
        }
        if (token_eq(p, "pat")) {
            watchdog_heartbeat(SYSTEM_WATCHDOG_LOGIC_CTRL);
            wdt_hang = 0u;
            print_ok();
            return;
        }
        if (token_eq(p, "hang")) {
            if (!wdt_enabled) {
                print_err(ERR_BAD_ARG);
                return;
            }
            wdt_hang = 1u;
            uart_writeStr(UART_REG, "WDT heartbeat stopped; reset expected in ~3s\r\n");
            last_error = ERR_NONE;
            return;
        }
        print_err(ERR_BAD_ARG);
        return;
    }
    if (to_lower(p[0]) == 'm' && (p[1] == 0 || p[1] == ' ' || p[1] == '\t')) {
        p++;
        if (!parse_hex32(&p, &addr32)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        value32 = mmio_read(addr32);
        uart_writeHex(UART_REG, (int)addr32);
        uart_writeStr(UART_REG, " = ");
        uart_writeHex(UART_REG, (int)value32);
        uart_writeStr(UART_REG, "\r\n");
        last_error = ERR_NONE;
        return;
    }
    if (to_lower(p[0]) == 'w' && (p[1] == ' ' || p[1] == '\t')) {
        p++;
        if (!parse_hex32(&p, &addr32) || !parse_hex32(&p, &value32)) {
            print_err(ERR_BAD_ARG);
            return;
        }
        if (mmio_write(addr32, value32)) {
            print_ok();
        } else {
            print_err(last_error);
        }
        return;
    }

    print_err(ERR_UNKNOWN_CMD);
}

// -----------------------------------------------------------------------------
// メインループ
// -----------------------------------------------------------------------------
int main(void)
{
    char cmd_buf[CMD_BUF_SIZE];
    u8 cmd_len = 0u;
    u32 cpu_blink_cnt = 0u;
    u32 wdt_pat_cnt = 0u;

    wdt_enabled = 0u;
    wdt_hang = 0u;

    uart_init();
    gpio_setOutputEnable(GPIO_REG, 0x7fu);
    led = 0x00u;
    led_write();
    i2c_init();

    boot_banner();

    for (;;) {
        cpu_blink_cnt++;
        if (cpu_blink_cnt >= CPU_BLINK_PERIOD) {
            cpu_blink_cnt = 0u;
            led ^= 0x01u;
            led_write();
        }

        wdt_pat_cnt++;
        if (wdt_pat_cnt >= WDT_PAT_PERIOD) {
            wdt_pat_cnt = 0u;
            wdt_service();
        }

        if (uart_readOccupancy(UART_REG)) {
            char c = uart_getc();

            if (c == '\r' || c == '\n' || c == 0) {
                cmd_buf[cmd_len] = 0;
                command_preamble();
                execute_line(cmd_buf);
                cmd_len = 0u;
            } else if (c == '\b' || c == 0x7f) {
                if (cmd_len > 0u) cmd_len--;
            } else if (cmd_len < (CMD_BUF_SIZE - 1u)) {
                cmd_buf[cmd_len++] = c;
            } else {
                cmd_len = 0u;
                print_err(ERR_LINE_TOO_LONG);
            }
        }
    }
}
