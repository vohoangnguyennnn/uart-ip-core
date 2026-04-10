// =============================================================================
// Module      : uart_tx
// Description : UART transmitter. On a one-cycle tx_start pulse it latches the
//               input byte and serializes it LSB-first with a start bit and one
//               stop bit, clocked by the 16× oversampled baud tick from
//               uart_baud_gen. tx_busy remains high for the full frame duration;
//               the host must wait for tx_busy to de-assert before issuing the
//               next tx_start pulse.
// Frame format : [START(0)] [D0 D1 D2 D3 D4 D5 D6 D7] [STOP(1)]
// FSM states  : IDLE → START → DATA (×8) → STOP → IDLE
// Ports:
//   clk         - System clock
//   rst         - Synchronous active-high reset
//   baud_tick   - 16× baud rate tick from uart_baud_gen
//   ext_data_in - Byte to transmit (sampled on the rising edge of tx_start)
//   tx_start    - Pulse high for 1 clock to begin transmitting ext_data_in
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

    reg [1:0] state, next_state;



    // FSM states
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    assign tx_busy = (state != IDLE);




    // counters
    reg [3:0] bit_tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;


    wire bit_tick_done = (bit_tick_cnt == 4'd15);
    wire byte_done     = (bit_cnt == 3'd7);


    // state register
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end


    // Combinational logic (state)
    always @(*) begin

        next_state = state;

        case (state)
            // Wait for a tx_start pulse before beginning a frame
            IDLE:  if (tx_start) next_state = START;

            START: if (baud_tick && bit_tick_done) next_state = DATA;

            DATA:  if (baud_tick && bit_tick_done && byte_done) next_state = STOP;

            STOP:  if (baud_tick && bit_tick_done) next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end


    // Sequential logic (counters + shift register)
    always @(posedge clk) begin
        if (rst) begin
            bit_tick_cnt <= 0;
            bit_cnt      <= 0;
            shift_reg    <= 0;
        end
        else if (baud_tick) begin

            if (state == IDLE && tx_start) begin
                bit_tick_cnt <= 0;
                bit_cnt      <= 0;
                shift_reg    <= ext_data_in;   // latch data on start
            end
            else begin
                if (bit_tick_done) begin
                    bit_tick_cnt <= 0;

                    if (state == DATA) begin
                        bit_cnt   <= bit_cnt + 1;
                        // LSB-first: shift right, padding MSB with 0
                        shift_reg <= {1'b0, shift_reg[7:1]};
                    end
                end
                else begin
                    bit_tick_cnt <= bit_tick_cnt + 1;
                end
            end
        end
    end


    // registered output
    always @(posedge clk) begin
        if (rst)
            tx <= 1'b1;
        else begin
            case (state)
                IDLE:  tx <= 1'b1;
                START: tx <= 1'b0;
                DATA:  tx <= shift_reg[0];   // LSB-first
                STOP:  tx <= 1'b1;
                default: tx <= 1'b1;
            endcase
        end
    end

endmodule
