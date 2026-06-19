// =============================================================================
// at24c512c_t20.v
// Trion T20 向け Sapphire SoC + I2C AT24C512C EEPROM トップモジュール
//
// 構成:
//   - EfxSapphireSoc (RISC-V RV32 コア) を内包
//   - CPU が UART コマンドモニタとして動作し I2C で AT24C512C を制御
//   - I2C SCL/SDA はオープンドレン双方向ピン (プルアップ抵抗必須)
//   - LED[7] はFPGA Fabric で独立したハードウェア点滅 (CPU 動作確認用)
//   - SW4 入力は3段同期化 + 20bitデバウンスフィルタを通してGPIOに接続
// =============================================================================

module at24c512c_t20 (
    input  wire       clk_100m,    // システムクロック 100MHz (PLL出力)
    input  wire       uart_rx_i,   // UART受信 (ピン C3)
    output wire       uart_tx_o,   // UART送信 (ピン D3)
    input  wire       sw4_i,       // ユーザースイッチ SW4 (アクティブLow)
    output wire [7:0] led_o,       // ユーザーLED (アクティブLow)
    input  wire       i2c_scl_i,   // I2C SCL 入力 (ピン B1, GPIOL_44)
    output wire       i2c_scl_o,   // I2C SCL 出力
    output wire       i2c_scl_oe,  // I2C SCL 出力イネーブル
    input  wire       i2c_sda_i,   // I2C SDA 入力 (ピン B2, GPIOL_45)
    output wire       i2c_sda_o,   // I2C SDA 出力
    output wire       i2c_sda_oe   // I2C SDA 出力イネーブル
);

    // -------------------------------------------------------------------------
    // パワーオンリセット (POR)
    // reset_cnt[7] が立つまで (128クロック) por_reset を High に保つ
    // -------------------------------------------------------------------------
    reg [7:0] reset_cnt = 8'h00;
    wire por_reset = ~reset_cnt[7];
    always @(posedge clk_100m) begin
        if (!reset_cnt[7])
            reset_cnt <= reset_cnt + 8'h01;
    end

    // -------------------------------------------------------------------------
    // ハードウェア点滅カウンタ (LED[7])
    // 100MHz / 2^26 ≒ 1.5Hz で点滅し、Fabric 単体の動作確認に使う
    // CPU のクラッシュ時も点滅が続くため、ハング判別に有効
    // -------------------------------------------------------------------------
    reg [26:0] blink_cnt = 27'd0;
    always @(posedge clk_100m)
        blink_cnt <= blink_cnt + 27'd1;

    // -------------------------------------------------------------------------
    // SW4 デバウンスフィルタ
    // 3段フリップフロップで同期化し、20bitカウンタで約10ms のチャタリング除去
    // -------------------------------------------------------------------------
    reg [2:0] sw4_sync = 3'b111;
    reg       sw4_stable = 1'b1;
    reg [19:0] sw4_debounce_cnt = 20'd0;

    always @(posedge clk_100m) begin
        sw4_sync <= {sw4_sync[1:0], sw4_i};
        if (sw4_sync[2] == sw4_stable) begin
            sw4_debounce_cnt <= 20'd0;
        end else begin
            sw4_debounce_cnt <= sw4_debounce_cnt + 20'd1;
            if (&sw4_debounce_cnt) begin
                sw4_stable <= sw4_sync[2];
                sw4_debounce_cnt <= 20'd0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // GPIO 接続
    // gpio_read  : bit0 = SW4 押下状態 (1=押下)
    // gpio_write : bit6:0 = CPU が書くLED値 (アクティブLow に反転して出力)
    // led_o[7]   : FPGA ハードウェア点滅 (アクティブLow)
    // led_o[6:0] : CPU GPIO 出力 (アクティブLow)
    // -------------------------------------------------------------------------
    wire [7:0] gpio_read;
    wire [7:0] gpio_write;
    wire [7:0] gpio_write_enable;
    wire       system_reset_unused;
    wire       jtag_tdo_unused;
    wire       watchdog_hard_panic;
    wire       soc_async_reset;

    // -------------------------------------------------------------------------
    // I2C オープンドレン双方向ピン (Trion向け分離信号)
    // Sapphire SoC の I2C インタフェースは write/read の分離信号。
    // write=1 → バス解放 (OE=0, 外部プルアップでHigh)
    // write=0 → Low駆動 (OE=1, 出力=0)
    // -------------------------------------------------------------------------
    wire       i2c_scl_write;
    wire       i2c_scl_read;
    wire       i2c_sda_write;
    wire       i2c_sda_read;

    assign i2c_scl_o  = 1'b0;
    assign i2c_scl_oe = ~i2c_scl_write;
    assign i2c_scl_read = i2c_scl_i;

    assign i2c_sda_o  = 1'b0;
    assign i2c_sda_oe = ~i2c_sda_write;
    assign i2c_sda_read = i2c_sda_i;

    wire        axiA_awready;
    wire [7:0]  axiA_awlen;
    wire [2:0]  axiA_awsize;
    wire [1:0]  axiA_arburst;
    wire        axiA_awlock;
    wire [3:0]  axiA_arcache;
    wire [3:0]  axiA_awqos;
    wire [2:0]  axiA_awprot;
    wire [2:0]  axiA_arsize;
    wire [3:0]  axiA_arregion;
    wire        axiA_arready;
    wire [3:0]  axiA_arqos;
    wire [2:0]  axiA_arprot;
    wire        axiA_arlock;
    wire [7:0]  axiA_arlen;
    wire [7:0]  axiA_arid;
    wire [3:0]  axiA_awcache;
    wire [1:0]  axiA_awburst;
    wire [31:0] axiA_awaddr;
    wire [31:0] axiA_araddr;
    wire        axiA_wvalid;
    wire        axiA_wready;
    wire [31:0] axiA_wdata;
    wire [3:0]  axiA_wstrb;
    wire        axiA_wlast;
    wire        axiA_bvalid;
    wire        axiA_bready;
    wire [7:0]  axiA_bid;
    wire [1:0]  axiA_bresp;
    wire        axiA_rvalid;
    wire        axiA_rready;
    wire [31:0] axiA_rdata;
    wire [7:0]  axiA_rid;
    wire [1:0]  axiA_rresp;
    wire        axiA_rlast;
    wire        axiA_arvalid;
    wire [7:0]  axiA_awid;
    wire [3:0]  axiA_awregion;
    wire        axiA_awvalid;
    wire        spi0_data_0_write_unused;
    wire        spi0_data_0_write_enable_unused;
    wire        spi0_data_1_write_unused;
    wire        spi0_data_1_write_enable_unused;
    wire        spi0_data_2_write_unused;
    wire        spi0_data_2_write_enable_unused;
    wire        spi0_data_3_write_unused;
    wire        spi0_data_3_write_enable_unused;
    wire        spi0_sclk_write_unused;
    wire [0:0]  spi0_ss_unused;
    wire [15:0] apb0_paddr_unused;
    wire        apb0_penable_unused;
    wire        apb0_psel_unused;
    wire [31:0] apb0_pwdata_unused;
    wire        apb0_pwrite_unused;

    reg         axi_dummy_bvalid = 1'b0;
    reg  [7:0]  axi_dummy_bid = 8'd0;
    reg         axi_dummy_rvalid = 1'b0;
    reg  [7:0]  axi_dummy_rid = 8'd0;

    assign axiA_awready = 1'b1;
    assign axiA_arready = 1'b1;
    assign axiA_wready  = 1'b1;
    assign axiA_bvalid  = axi_dummy_bvalid;
    assign axiA_bid     = axi_dummy_bid;
    assign axiA_bresp   = 2'b00;
    assign axiA_rvalid  = axi_dummy_rvalid;
    assign axiA_rdata   = 32'd0;
    assign axiA_rid     = axi_dummy_rid;
    assign axiA_rresp   = 2'b00;
    assign axiA_rlast   = 1'b1;

    always @(posedge clk_100m) begin
        if (por_reset) begin
            axi_dummy_bvalid <= 1'b0;
            axi_dummy_bid    <= 8'd0;
            axi_dummy_rvalid <= 1'b0;
            axi_dummy_rid    <= 8'd0;
        end else begin
            if (axi_dummy_bvalid && axiA_bready)
                axi_dummy_bvalid <= 1'b0;
            if (!axi_dummy_bvalid && axiA_awvalid && axiA_wvalid) begin
                axi_dummy_bvalid <= 1'b1;
                axi_dummy_bid    <= axiA_awid;
            end

            if (axi_dummy_rvalid && axiA_rready)
                axi_dummy_rvalid <= 1'b0;
            if (!axi_dummy_rvalid && axiA_arvalid) begin
                axi_dummy_rvalid <= 1'b1;
                axi_dummy_rid    <= axiA_arid;
            end
        end
    end

    assign gpio_read = {7'b0, ~sw4_stable};
    assign led_o     = {~blink_cnt[25], ~gpio_write[6:0]};
    assign soc_async_reset = por_reset | watchdog_hard_panic;

    // -------------------------------------------------------------------------
    // Sapphire SoC インスタンス
    // JTAG は未使用のためすべて固定値。io_systemReset は内部でのみ使用。
    // I2C_0 は AT24C512C EEPROM に接続。
    // -------------------------------------------------------------------------
    soc u_soc (
        .io_systemClk           (clk_100m),
        .axiA_awready           (axiA_awready),
        .axiA_awlen             (axiA_awlen),
        .axiA_awsize            (axiA_awsize),
        .axiA_arburst           (axiA_arburst),
        .axiA_awlock            (axiA_awlock),
        .axiA_arcache           (axiA_arcache),
        .axiA_awqos             (axiA_awqos),
        .axiA_awprot            (axiA_awprot),
        .axiA_arsize            (axiA_arsize),
        .axiA_arregion          (axiA_arregion),
        .axiA_arready           (axiA_arready),
        .axiA_arqos             (axiA_arqos),
        .axiA_arprot            (axiA_arprot),
        .axiA_arlock            (axiA_arlock),
        .axiA_arlen             (axiA_arlen),
        .axiA_arid              (axiA_arid),
        .axiA_awcache           (axiA_awcache),
        .axiA_awburst           (axiA_awburst),
        .axiA_awaddr            (axiA_awaddr),
        .axiAInterrupt          (1'b0),
        .axiA_rlast             (axiA_rlast),
        .jtagCtrl_enable        (1'b0),
        .jtagCtrl_tdi           (1'b0),
        .jtagCtrl_capture       (1'b0),
        .jtagCtrl_shift         (1'b0),
        .jtagCtrl_update        (1'b0),
        .jtagCtrl_reset         (1'b1),
        .jtagCtrl_tdo           (jtag_tdo_unused),
        .jtagCtrl_tck           (1'b0),
        .axiA_araddr            (axiA_araddr),
        .axiA_wvalid            (axiA_wvalid),
        .axiA_wready            (axiA_wready),
        .axiA_wdata             (axiA_wdata),
        .axiA_wstrb             (axiA_wstrb),
        .axiA_wlast             (axiA_wlast),
        .axiA_bvalid            (axiA_bvalid),
        .axiA_bready            (axiA_bready),
        .axiA_bid               (axiA_bid),
        .axiA_bresp             (axiA_bresp),
        .axiA_rvalid            (axiA_rvalid),
        .axiA_rready            (axiA_rready),
        .axiA_rdata             (axiA_rdata),
        .axiA_rid               (axiA_rid),
        .axiA_rresp             (axiA_rresp),
        .axiA_arvalid           (axiA_arvalid),
        .axiA_awid              (axiA_awid),
        .axiA_awregion          (axiA_awregion),
        .axiA_awvalid           (axiA_awvalid),
        .system_spi_0_io_data_0_read(1'b1),
        .system_spi_0_io_data_0_write(spi0_data_0_write_unused),
        .system_spi_0_io_data_0_writeEnable(spi0_data_0_write_enable_unused),
        .system_spi_0_io_data_1_read(1'b1),
        .system_spi_0_io_data_1_write(spi0_data_1_write_unused),
        .system_spi_0_io_data_1_writeEnable(spi0_data_1_write_enable_unused),
        .system_spi_0_io_data_2_read(1'b1),
        .system_spi_0_io_data_2_write(spi0_data_2_write_unused),
        .system_spi_0_io_data_2_writeEnable(spi0_data_2_write_enable_unused),
        .system_spi_0_io_data_3_read(1'b1),
        .system_spi_0_io_data_3_write(spi0_data_3_write_unused),
        .system_spi_0_io_data_3_writeEnable(spi0_data_3_write_enable_unused),
        .system_spi_0_io_sclk_write(spi0_sclk_write_unused),
        .userInterruptA         (1'b0),
        .io_apbSlave_0_PADDR    (apb0_paddr_unused),
        .io_apbSlave_0_PENABLE  (apb0_penable_unused),
        .io_apbSlave_0_PRDATA   (32'd0),
        .io_apbSlave_0_PREADY   (1'b1),
        .io_apbSlave_0_PSEL     (apb0_psel_unused),
        .io_apbSlave_0_PSLVERROR(1'b0),
        .io_apbSlave_0_PWDATA   (apb0_pwdata_unused),
        .io_apbSlave_0_PWRITE   (apb0_pwrite_unused),
        .io_asyncReset          (soc_async_reset),
        .io_systemReset         (system_reset_unused),
        .system_uart_0_io_txd   (uart_tx_o),
        .system_uart_0_io_rxd   (uart_rx_i),
        .system_i2c_0_io_scl_read (i2c_scl_read),
        .system_i2c_0_io_scl_write(i2c_scl_write),
        .system_i2c_0_io_sda_read (i2c_sda_read),
        .system_i2c_0_io_sda_write(i2c_sda_write),
        .system_gpio_0_io_writeEnable(gpio_write_enable),
        .system_gpio_0_io_write (gpio_write),
        .system_gpio_0_io_read  (gpio_read),
        .system_spi_0_io_ss     (spi0_ss_unused),
        .system_watchdog_hardPanic(watchdog_hard_panic)
    );

endmodule
