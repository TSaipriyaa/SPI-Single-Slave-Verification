//single slave tb

`timescale 1ns / 1ps
// =============================================================================
// Module      : spi_master_cfg_tb
// Description : Self-checking testbench for spi_master_cfg.
//               Includes a behavioral SPI slave model.
//
// Test cases cover all 4 SPI modes, multiple clock dividers, data patterns.
//
// ── SPI Slave Design ──────────────────────────────────────────────────────────
//
// The behavioral slave uses posedge/negedge SCK directly (not a clk-domain
// bridge).  This is correct for a testbench model because:
//   1. No pipeline delay - slave reacts at the exact SCK edge.
//   2. SV NBA semantics guarantee that at the posedge clk where the master's
//      shift_en fires, "mosi" reads the PRE-shift (old) value, giving the
//      slave the correct current bit.
//
// Slave sample / shift edge assignment:
//   slave_sample_on_posedge = (cpol == 0)
//
//   │ Mode │ CPOL │ CPHA │ Slave sample  │ Slave shift   │
//   │   0  │  0   │  0   │ posedge SCK   │ negedge SCK   │
//   │   1  │  0   │  1   │ posedge SCK   │ negedge SCK   │
//   │   2  │  1   │  0   │ negedge SCK   │ posedge SCK   │
//   │   3  │  1   │  1   │ negedge SCK   │ posedge SCK   │
//
// Why cpol==0 → posedge, regardless of cpha:
//   CPHA=0: master shifts on negedge (second edge for CPOL=0).
//     At negedge, NBA commits new tx_shift → mosi already advanced.
//     Slave samples at posedge (before any shift) → gets correct bit. ✓
//   CPHA=1: master shifts on posedge (first edge for CPOL=0).
//     At posedge, NBA is scheduled but not committed → mosi still old value.
//     Slave samples at same posedge → gets correct bit. ✓
//   Both CPHA values → slave samples at posedge SCK for CPOL=0.
//   By symmetry, CPOL=1 → slave samples at negedge SCK.
//
// MISO path:
//   shift_out is preloaded = slave_tx while ss_n is high.
//   On slave's shift edge: shift_out shifts left, advancing MISO to next bit.
//   The shift edge is OPPOSITE to the sample edge, so MISO is always stable
//   when the master samples it.
// =============================================================================
 
module spi_master_cfg_tb;
 
    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int DATA_WIDTH  = 8;
    localparam int CLK_PERIOD  = 10;        // 10 ns → 100 MHz
    localparam int TIMEOUT_CYC = 10_000;
 
    // =========================================================================
    // DUT signals
    // =========================================================================
    logic                  clk, rst, start;
    logic [DATA_WIDTH-1:0] tx_data;
    logic                  cpol, cpha;
    logic [1:0]            clk_div;
    logic                  miso, sck, mosi, ss_n;
    logic [DATA_WIDTH-1:0] rx_data;
    logic                  busy, done;
 
    // =========================================================================
    // DUT instantiation
    // =========================================================================
    spi_master_cfg #(.DATA_WIDTH(DATA_WIDTH)) dut (
        .clk(clk), .rst(rst), .start(start),
        .tx_data(tx_data), .cpol(cpol), .cpha(cpha), .clk_div(clk_div),
        .miso(miso), .sck(sck), .mosi(mosi), .ss_n(ss_n),
        .rx_data(rx_data), .busy(busy), .done(done)
    );
 
    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 1'b0;
    always  #(CLK_PERIOD/2) clk = ~clk;
 
    // =========================================================================
    // ── Behavioral SPI Slave ─────────────────────────────────────────────────
    //
    // Registers
    // =========================================================================
    logic [DATA_WIDTH-1:0] slave_tx;        // data slave sends to master
    logic [DATA_WIDTH-1:0] slave_shift_out; // drives MISO
    logic [DATA_WIDTH-1:0] slave_shift_in;  // captures MOSI
    logic [DATA_WIDTH-1:0] slave_rx;        // final received byte
 
    // slave_sample_on_posedge = (cpol == 0)
    // Use it to select which always block is active.
 
    // -------------------------------------------------------------------------
    // Preload shift_out when slave is idle (ss_n == 1)
    // This runs in the clk domain. When ss_n is high, shift_out is refreshed
    // with the latest slave_tx every cycle, so it is always committed and ready
    // the instant ss_n goes low - no pipeline penalty.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            slave_shift_out <= '0;
            slave_shift_in  <= '0;
            slave_rx        <= '0;
        end
        else if (ss_n) begin
            slave_shift_out <= slave_tx;   // continuously preload while idle
            slave_shift_in  <= '0;
        end
    end
 
    // -------------------------------------------------------------------------
    // CPOL=0 slave: sample on posedge SCK, shift on negedge SCK
    // Activated for Modes 0 and 1 (cpol == 0).
    // -------------------------------------------------------------------------
    logic [3:0] slave_bit_cnt_r;   // bit counter for posedge-sample slave
    logic [3:0] slave_bit_cnt_f;   // bit counter for negedge-sample slave
 
    // posedge SCK - sample MOSI (CPOL=0 modes)
    always @(posedge sck) begin
        if (!ss_n && cpol == 1'b0) begin
            slave_shift_in  <= {slave_shift_in[DATA_WIDTH-2:0], mosi};
            slave_bit_cnt_r <= slave_bit_cnt_r + 1'b1;
            if (slave_bit_cnt_r == DATA_WIDTH[3:0] - 1'b1) begin
                slave_rx        <= {slave_shift_in[DATA_WIDTH-2:0], mosi};
                slave_bit_cnt_r <= '0;
            end
        end
    end
 
    // negedge SCK - shift MISO (CPOL=0 modes)
    always @(negedge sck) begin
        if (!ss_n && cpol == 1'b0)
            slave_shift_out <= {slave_shift_out[DATA_WIDTH-2:0], 1'b0};
    end
 
    // -------------------------------------------------------------------------
    // CPOL=1 slave: sample on negedge SCK, shift on posedge SCK
    // Activated for Modes 2 and 3 (cpol == 1).
    // -------------------------------------------------------------------------
 
    // negedge SCK - sample MOSI (CPOL=1 modes)
    always @(negedge sck) begin
        if (!ss_n && cpol == 1'b1) begin
            slave_shift_in  <= {slave_shift_in[DATA_WIDTH-2:0], mosi};
            slave_bit_cnt_f <= slave_bit_cnt_f + 1'b1;
            if (slave_bit_cnt_f == DATA_WIDTH[3:0] - 1'b1) begin
                slave_rx        <= {slave_shift_in[DATA_WIDTH-2:0], mosi};
                slave_bit_cnt_f <= '0;
            end
        end
    end
 
    // posedge SCK - shift MISO (CPOL=1 modes)
    always @(posedge sck) begin
        if (!ss_n && cpol == 1'b1)
            slave_shift_out <= {slave_shift_out[DATA_WIDTH-2:0], 1'b0};
    end
 
    // Reset bit counters and state on rst or ss_n deassertion
    always_ff @(posedge clk) begin
        if (rst || ss_n) begin
            slave_bit_cnt_r <= '0;
            slave_bit_cnt_f <= '0;
        end
    end
 
    // MISO is the MSB of slave_shift_out when selected
    assign miso = ss_n ? 1'b0 : slave_shift_out[DATA_WIDTH-1];
 
    // =========================================================================
    // ── Testbench tasks ───────────────────────────────────────────────────────
    // =========================================================================
    int pass_count, fail_count;
 
    // Apply reset
    task automatic apply_reset();
        rst = 1'b1; start = 1'b0; tx_data = '0;
        cpol = 1'b0; cpha = 1'b0; clk_div = 2'b00;
        slave_tx = '0;
        repeat(4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    endtask
 
    // Run one SPI transfer and check results
    task automatic run_test(
        input int                    test_num,
        input logic                  t_cpol, t_cpha,
        input logic [1:0]            t_clk_div,
        input logic [DATA_WIDTH-1:0] t_tx,
        input logic [DATA_WIDTH-1:0] t_slave_tx
    );
        automatic int timeout = 0;
        automatic string mode_str;
 
        unique case ({t_cpol, t_cpha})
            2'b00: mode_str = "Mode0(0,0)";
            2'b01: mode_str = "Mode1(0,1)";
            2'b10: mode_str = "Mode2(1,0)";
            2'b11: mode_str = "Mode3(1,1)";
        endcase
 
        $display("─────────────────────────────────────────────────────");
        $display("[TC%0d] %s  clk_div=%02b  tx=0x%02h  slave_tx=0x%02h",
                 test_num, mode_str, t_clk_div, t_tx, t_slave_tx);
 
        // Configure slave
        slave_tx = t_slave_tx;
 
        // Configure DUT - wait 2 cycles to settle
        @(posedge clk); #1;
        cpol    <= t_cpol;
        cpha    <= t_cpha;
        clk_div <= t_clk_div;
        tx_data <= t_tx;
        repeat(2) @(posedge clk);
 
        // Assert start for exactly 1 cycle
        @(posedge clk); #1;
        start <= 1'b1;
        @(posedge clk); #1;
        start <= 1'b0;
 
        // Wait for done with timeout
        while (!done && timeout < TIMEOUT_CYC) begin
            @(posedge clk);
            timeout++;
        end
 
        if (timeout >= TIMEOUT_CYC) begin
            $display("[TC%0d] TIMEOUT - no done pulse within %0d cycles", test_num, TIMEOUT_CYC);
            fail_count++;
        end else begin
            // Wait one more cycle for slave_rx to settle
            @(posedge clk);
            $display("[TC%0d] rx_data  = 0x%02h  (expected 0x%02h)  %s",
                     test_num, rx_data, t_slave_tx,
                     (rx_data == t_slave_tx) ? "PASS" : "FAIL");
            $display("[TC%0d] slave_rx = 0x%02h  (expected 0x%02h)  %s",
                     test_num, slave_rx, t_tx,
                     (slave_rx == t_tx) ? "PASS" : "FAIL");
 
            if (rx_data == t_slave_tx && slave_rx == t_tx) begin
                pass_count++;
                $display("[TC%0d] ✓ PASS", test_num);
            end else begin
                fail_count++;
                $display("[TC%0d] ✗ FAIL", test_num);
            end
        end
 
        // Inter-test settling
        repeat(10) @(posedge clk);
 
    endtask
 
    // =========================================================================
    // ── SVA Properties ───────────────────────────────────────────────────────
    // =========================================================================
 
    // done must be a single-cycle pulse
    property p_done_pulse;
        @(posedge clk) disable iff (rst)
        done |=> !done;
    endproperty
    assert property (p_done_pulse)
        else $error("[ASSERT] done held > 1 cycle at %0t", $time);
 
    // ss_n must stay low while busy (and not done)
    property p_ss_n_low_when_busy;
        @(posedge clk) disable iff (rst)
        (busy && !done) |-> !ss_n;
    endproperty
    assert property (p_ss_n_low_when_busy)
        else $error("[ASSERT] ss_n high while busy at %0t", $time);
 
    // SCK must be at CPOL level when not busy
    property p_sck_idle;
        @(posedge clk) disable iff (rst)
        !busy |-> (sck == cpol);
    endproperty
    assert property (p_sck_idle)
        else $error("[ASSERT] sck != cpol when idle at %0t", $time);
 
    // =========================================================================
    // ── Main stimulus ─────────────────────────────────────────────────────────
    // =========================================================================
    initial begin
        $dumpfile("spi_master_cfg.vcd");
        $dumpvars(0, spi_master_cfg_tb);
 
        pass_count = 0;
        fail_count = 0;
 
        apply_reset();
 
        $display("=====================================================");
        $display("  SPI Master Verification  - %0t ns", $time);
        $display("  DATA_WIDTH = %0d", DATA_WIDTH);
        $display("=====================================================");
 
        // ── Mode 0 tests ──────────────────────────────────────────
        run_test(1,  1'b0, 1'b0, 2'b00, 8'hA5, 8'h5A);  // /2  clock
        run_test(2,  1'b0, 1'b0, 2'b01, 8'hFF, 8'h3C);  // /4  clock
        run_test(3,  1'b0, 1'b0, 2'b10, 8'h00, 8'hAA);  // /8  clock
        run_test(4,  1'b0, 1'b0, 2'b11, 8'hB7, 8'hC3);  // /16 clock
 
        // ── Mode 1 tests ──────────────────────────────────────────
        run_test(5,  1'b0, 1'b1, 2'b00, 8'hA5, 8'h5A);
        run_test(6,  1'b0, 1'b1, 2'b01, 8'hFF, 8'h3C);
        run_test(7,  1'b0, 1'b1, 2'b10, 8'h00, 8'hAA);
        run_test(8,  1'b0, 1'b1, 2'b11, 8'hB7, 8'hC3);
 
        // ── Mode 2 tests ──────────────────────────────────────────
        run_test(9,  1'b1, 1'b0, 2'b00, 8'hA5, 8'h5A);
        run_test(10, 1'b1, 1'b0, 2'b01, 8'hFF, 8'h3C);
        run_test(11, 1'b1, 1'b0, 2'b10, 8'h00, 8'hAA);
        run_test(12, 1'b1, 1'b0, 2'b11, 8'hB7, 8'hC3);
 
        // ── Mode 3 tests ──────────────────────────────────────────
        run_test(13, 1'b1, 1'b1, 2'b00, 8'hA5, 8'h5A);
        run_test(14, 1'b1, 1'b1, 2'b01, 8'hFF, 8'h3C);
        run_test(15, 1'b1, 1'b1, 2'b10, 8'h00, 8'hAA);
        run_test(16, 1'b1, 1'b1, 2'b11, 8'hB7, 8'hC3);
 
        // ─────────────────────────────────────────────────────────
        $display("=====================================================");
        $display("  SUMMARY: %0d / %0d tests PASSED", pass_count, pass_count+fail_count);
        $display("  STATUS:  %s", (fail_count == 0) ? "ALL PASS ✓" : "FAILURES DETECTED ✗");
        $display("=====================================================");
        #5000;
        $finish;
    end
 
endmodule 