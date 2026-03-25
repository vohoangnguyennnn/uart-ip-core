// =============================================================================
// Module      : uart_rx
// Description : UART receiver. Samples the RX line using a 16× oversampled
//               baud tick, detects the start bit, shifts in 8 data bits
//               LSB-first, validates the stop bit, then asserts rx_valid for
//               one clock cycle to indicate a new byte is available.
//               A 2-FF synchronizer prevents metastability on the async RX pin.
// Frame format : [START(0)] [D0 D1 D2 D3 D4 D5 D6 D7] [STOP(1)]
// FSM states  : IDLE → START → DATA (×8) → STOP → IDLE
// Ports:
//   clk          - System clock
//   rst          - Synchronous active-high reset
//   baud_tick    - 16× baud rate tick from uart_baud_gen
//   rx           - Serial RX input (async, will be synchronized internally)
//   ext_data_out - Received byte, valid when rx_valid is high
//   rx_valid     - Pulses high for 1 clock when ext_data_out holds a new byte
// =============================================================================
module uart_rx (
    input  wire       clk,
    input  wire       rst,
    input  wire       baud_tick,
    input  wire       rx,
    output reg  [7:0] ext_data_out,
    output reg        rx_valid      // pulses high for 1 clock when a new byte is ready
);

    // Synchronize RX (2-FF synchronizer)
    // Reset to 1 because UART idle line is logic HIGH
    reg rx_d1, rx_d2;

    always @(posedge clk) begin
        if (rst) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
        end
        else begin
            rx_d1 <= rx;
            rx_d2 <= rx_d1;
        end
    end



    // FSM states
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state, next_state;


    // counters
    reg [3:0] bit_tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    wire bit_tick_done = (bit_tick_cnt == 4'd15);
    wire half_tick     = (bit_tick_cnt == 4'd7);
    wire byte_done     = (bit_cnt == 3'd7);


    // state register
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end


    // next state logic
    always @(*) begin
        next_state = state;

        case (state)
            IDLE:  if (!rx_d2) next_state = START;

            START: if (baud_tick && half_tick && !rx_d2)
                       next_state = DATA;

            DATA:  if (baud_tick && bit_tick_done && byte_done)
                       next_state = STOP;

            STOP:  if (baud_tick && bit_tick_done)
                       next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end


    // counters + shift
    always @(posedge clk) begin
        if (rst) begin
            bit_tick_cnt <= 0;
            bit_cnt      <= 0;
            shift_reg    <= 0;
        end
        else if (baud_tick) begin
            if (state == IDLE) begin
                bit_tick_cnt <= 0;
                bit_cnt      <= 0;
            end
            else begin
                if (bit_tick_done)
                    bit_tick_cnt <= 0;
                else
                    bit_tick_cnt <= bit_tick_cnt + 1;

                if (state == DATA && bit_tick_done) begin
                    bit_cnt   <= bit_cnt + 1;
                    // LSB-first: first received bit enters at MSB then shifts right
                    // After 8 bits: shift_reg = {D7,D6,D5,D4,D3,D2,D1,D0} — correct byte
                    shift_reg <= {rx_d2, shift_reg[7:1]};
                end
            end
        end
    end


    // output register + rx_valid pulse
    always @(posedge clk) begin
        if (rst) begin
            ext_data_out <= 8'd0;
            rx_valid     <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;   // default: de-assert every cycle
            if (state == STOP && baud_tick && bit_tick_done) begin
                ext_data_out <= shift_reg;
                rx_valid     <= 1'b1;   // pulse for exactly 1 clock
            end
        end
    end

endmodule
