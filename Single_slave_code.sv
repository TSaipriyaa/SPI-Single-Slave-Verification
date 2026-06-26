//Single-slave: CPOL, CPHA, clk_div, Assertions and scoreboard. 


`timescale 1ns / 1ps
// =============================================================================
// Module      : spi_master_cfg
// Description : Configurable SPI Master supporting all 4 SPI modes.
//
// SPI Modes (CPOL / CPHA):
//   Mode 0 (0,0) - SCK idle LOW,  sample on rising  (1st edge), shift on falling
//   Mode 1 (0,1) - SCK idle LOW,  sample on falling (2nd edge), shift on rising
//   Mode 2 (1,0) - SCK idle HIGH, sample on falling (1st edge), shift on rising
//   Mode 3 (1,1) - SCK idle HIGH, sample on rising  (2nd edge), shift on falling
//
// Clock divider (clk_div[1:0]) - SCK half-period in system clocks:
//   2'b00  1 clk  →  SCK = sys_clk / 2
//   2'b01  2 clk  →  SCK = sys_clk / 4
//   2'b10  4 clk  →  SCK = sys_clk / 8
//   2'b11  8 clk  →  SCK = sys_clk / 16
//
// FSM: IDLE → LOAD → TRANSFER → DONE → IDLE
//
// Key implementation notes:
//   - SCK is fully registered (sck_reg). Never generated combinationally.
//   - phase tracks first (0) vs second (1) edge of each bit period.
//   - sample_en = sck_en & (phase == cpha)   - unified for all modes
//   - shift_en  = sck_en & (phase != cpha)   - unified for all modes
//   - rx_data is captured from rx_shift only - no extra miso appending.
//   - LOAD pre-drives MOSI (tx_shift[MSB]) so it is stable before first SCK edge.
// =============================================================================
 
module spi_master_cfg #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                  clk,
    input  logic                  rst,       // synchronous active-high
 
    // Control
    input  logic                  start,     // single-cycle pulse to begin
    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic                  cpol,
    input  logic                  cpha,
    input  logic [1:0]            clk_div,
 
    // SPI bus
    input  logic                  miso,
    output logic                  sck,
    output logic                  mosi,
    output logic                  ss_n,
 
    // Status
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  busy,
    output logic                  done
);
 
    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int CNT_W   = $clog2(DATA_WIDTH);
    localparam logic [CNT_W-1:0] LAST_BIT = DATA_WIDTH[CNT_W-1:0] - 1'b1;
 
    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        LOAD     = 2'b01,
        TRANSFER = 2'b10,
        DONE     = 2'b11
    } state_t;
 
    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    state_t state, next_state;
 
    // Clock divider
    logic [3:0] half_period;
    logic [3:0] presc;
    logic       sck_en;     // one-cycle strobe every SCK half-period
 
    // SCK
    logic sck_reg;
 
    // Phase tracker (0 = first edge of bit, 1 = second edge)
    logic phase;
 
    // Bit counter
    logic [CNT_W-1:0] bit_cnt;
 
    // Edge strobes - derived combinationally from sck_en and phase
    logic sample_en;   // when to capture miso → rx_shift
    logic shift_en;    // when to advance tx_shift
 
    // Shift registers
    logic [DATA_WIDTH-1:0] tx_shift;
    logic [DATA_WIDTH-1:0] rx_shift;
 
    // -------------------------------------------------------------------------
    // Clock divider decode
    // -------------------------------------------------------------------------
    always_comb begin
        unique case (clk_div)
            2'b00:   half_period = 4'd1;
            2'b01:   half_period = 4'd2;
            2'b10:   half_period = 4'd4;
            2'b11:   half_period = 4'd8;
        endcase
    end
 
    // Prescaler - runs only during TRANSFER
    always_ff @(posedge clk) begin
        if (rst)
            presc <= '0;
        else if (state == TRANSFER)
            presc <= (presc == half_period - 1'b1) ? '0 : presc + 1'b1;
        else
            presc <= '0;
    end
 
    assign sck_en = (state == TRANSFER) && (presc == half_period - 1'b1);
 
    // -------------------------------------------------------------------------
    // SCK register
    // Holds CPOL level when not transferring. Toggles on every sck_en.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            sck_reg <= 1'b0;
        else begin
            unique case (state)
                IDLE, LOAD: sck_reg <= cpol;
                TRANSFER:   sck_reg <= sck_en ? ~sck_reg : sck_reg;
                DONE:       sck_reg <= cpol;
            endcase
        end
    end
 
    // -------------------------------------------------------------------------
    // Phase tracker
    // Resets to 0 outside TRANSFER. Toggles on each sck_en during TRANSFER.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            phase <= 1'b0;
        else if (state == TRANSFER && sck_en)
            phase <= ~phase;
        else if (state != TRANSFER)
            phase <= 1'b0;
    end
 
    // -------------------------------------------------------------------------
    // Edge strobes - unified formula for all four SPI modes:
    //
    //   phase == cpha  →  this is the SAMPLE edge
    //   phase != cpha  →  this is the SHIFT  edge
    //
    //   Proof:
    //     CPHA=0: sample at phase=0 (first edge), shift at phase=1 (second edge)
    //     CPHA=1: sample at phase=1 (second edge), shift at phase=0 (first edge)
    //   The CPOL value determines whether phase=0 is rising or falling, but
    //   the sample/shift assignment to phase is the same for any CPOL.
    // -------------------------------------------------------------------------
    assign sample_en = sck_en & ~(phase ^ cpha);   // phase == cpha
    assign shift_en  = sck_en &  (phase ^ cpha);   // phase != cpha
 
    // -------------------------------------------------------------------------
    // Bit counter - increments at the second edge of each bit (phase==1)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            bit_cnt <= '0;
        else if (state == LOAD)
            bit_cnt <= '0;
        else if (state == TRANSFER && sck_en && phase == 1'b1)
            bit_cnt <= (bit_cnt == LAST_BIT) ? bit_cnt : bit_cnt + 1'b1;
    end
 
    // -------------------------------------------------------------------------
    // Transmit shift register
    // LOAD: captures tx_data so MOSI[MSB] is valid before first SCK edge.
    // TRANSFER: left-shifts on shift_en.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            tx_shift <= '0;
        else begin
            unique case (state)
                LOAD:     tx_shift <= tx_data;
                TRANSFER: if (shift_en)
                              tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                default:  ; // hold
            endcase
        end
    end
 
    // -------------------------------------------------------------------------
    // Receive shift register - captures miso on every sample_en
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            rx_shift <= '0;
        else if (state == LOAD)
            rx_shift <= '0;
        else if (state == TRANSFER && sample_en)
            rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};
    end
 
    // -------------------------------------------------------------------------
    // FSM - next-state logic (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        unique case (state)
            IDLE:     if (start) next_state = LOAD;
            LOAD:     next_state = TRANSFER;
            TRANSFER: if (sck_en && phase == 1'b1 && bit_cnt == LAST_BIT)
                          next_state = DONE;
            DONE:     next_state = IDLE;
        endcase
    end
 
    // FSM state register
    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end
 
    // -------------------------------------------------------------------------
    // rx_data - captured from rx_shift when entering DONE.
    //
    // At the cycle next_state==DONE: rx_shift has received all DATA_WIDTH bits.
    // For CPHA=0: last sample was at first_edge of last bit (1 cycle earlier than DONE).
    //             rx_shift is fully committed - use directly.
    // For CPHA=1: last sample is also at the second_edge = same cycle as DONE trigger.
    //             Due to NBA, rx_shift update is scheduled simultaneously.
    //             rx_shift[DW-2:0] holds bits 1..DW-1; miso holds last bit directly.
    //
    // Unified solution: capture (next_state == DONE) handles both cases because
    // for CPHA=0 the last sample fired at sample_en one cycle before DONE, so
    // rx_shift is committed. For CPHA=1 the last sample fires at the SAME posedge
    // as DONE trigger; since both rx_shift and rx_data use NBAs, rx_data receives
    // {rx_shift[DW-2:0], miso} to stitch in the concurrent last bit.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            rx_data <= '0;
        else if (next_state == DONE)
            rx_data <= cpha ? {rx_shift[DATA_WIDTH-2:0], miso} : rx_shift;
    end
 
    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign sck  = sck_reg;
    assign mosi = (state == LOAD || state == TRANSFER) ? tx_shift[DATA_WIDTH-1] : 1'b0;
    assign ss_n = (state == IDLE);
    assign busy = (state != IDLE);
    assign done = (state == DONE);
 
endmodule


