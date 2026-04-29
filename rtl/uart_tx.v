// =============================================================================
// Module      : uart_tx
// Description : UART transmitter. On a tx_start rising edge it latches the
//               input byte and serializes it LSB-first with a start bit and
//               one stop bit, clocked by the 16× oversampled baud tick from
//               uart_baud_gen. tx_busy stays high for the full frame duration.
//
// Frame format : [START(0)] [D0 D1 D2 D3 D4 D5 D6 D7] [STOP(1)]
// FSM states   : IDLE → START → DATA (×8) → STOP → IDLE
//
// Ports:
//   clk         - System clock
//   rst         - Synchronous active-high reset
//   baud_tick   - 16× baud rate tick from uart_baud_gen
//   ext_data_in - Byte to transmit (latched on rising edge of tx_start)
//   tx_start    - Pulse HIGH for ≥1 clock to begin transmission
//   tx          - Serial TX output (idle HIGH)
//   tx_busy     - High while a frame is being transmitted
// =============================================================================
module uart_tx (
    input  wire       clk,
    input  wire       rst,
    input  wire       baud_tick,
    input  wire [7:0] ext_data_in,
    input  wire       tx_start,
    output reg        tx,
    output wire       tx_busy
);

    // ---- Edge detector for tx_start ----
    reg tx_start_d;

    always @(posedge clk) begin
        if (rst)
            tx_start_d <= 1'b0;
        else
            tx_start_d <= tx_start;
    end

    wire tx_start_rise = tx_start & ~tx_start_d;  // rising-edge pulse


    // ---- FSM states ----
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state, next_state;

    assign tx_busy = (state != IDLE);


    // ---- Counters & shift register ----
    reg [3:0] bit_tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    wire bit_tick_done = (bit_tick_cnt == 4'd15);
    wire byte_done     = (bit_cnt == 3'd7);


    // ---- State register ----
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end


    // ---- Next-state logic ----
    always @(*) begin
        next_state = state;

        case (state)
            IDLE:    if (tx_start_rise)                       next_state = START;
            START:   if (baud_tick && bit_tick_done)           next_state = DATA;
            DATA:    if (baud_tick && bit_tick_done && byte_done) next_state = STOP;
            STOP:    if (baud_tick && bit_tick_done)           next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end


    // ---- Counters + shift register ----
    always @(posedge clk) begin
        if (rst) begin
            bit_tick_cnt <= 0;
            bit_cnt      <= 0;
            shift_reg    <= 0;
        end
        else if (baud_tick) begin
            if (state == IDLE && tx_start_rise) begin
                bit_tick_cnt <= 0;
                bit_cnt      <= 0;
                shift_reg    <= ext_data_in;   // latch data on start
            end
            else begin
                if (bit_tick_done) begin
                    bit_tick_cnt <= 0;

                    if (state == DATA) begin
                        bit_cnt   <= bit_cnt + 1;
                        shift_reg <= {1'b0, shift_reg[7:1]};  // LSB-first shift
                    end
                end
                else begin
                    bit_tick_cnt <= bit_tick_cnt + 1;
                end
            end
        end
    end


    // ---- TX output ----
    always @(posedge clk) begin
        if (rst)
            tx <= 1'b1;
        else begin
            case (state)
                IDLE:    tx <= 1'b1;       // idle line HIGH
                START:   tx <= 1'b0;       // start bit LOW
                DATA:    tx <= shift_reg[0]; // LSB-first
                STOP:    tx <= 1'b1;       // stop bit HIGH
                default: tx <= 1'b1;
            endcase
        end
    end

endmodule
