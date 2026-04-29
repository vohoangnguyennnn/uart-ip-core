

module uart_rx (
    input  wire       clk,
    input  wire       rst,
    input  wire       baud_tick,
    input  wire       rx,
    output reg  [7:0] ext_data_out,
    output reg        rx_valid,
    output reg        frame_error
);

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
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state, next_state;
    reg [3:0] bit_tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    wire bit_tick_done = (bit_tick_cnt == 4'd15);
    wire half_tick     = (bit_tick_cnt == 4'd7);
    wire byte_done     = (bit_cnt == 3'd7);
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end
    always @(*) begin
        next_state = state;

        case (state)
            IDLE:  if (!rx_d2) next_state = START;

            START: if (baud_tick && half_tick && !rx_d2)
                       next_state = DATA;

            DATA:  if (baud_tick && bit_tick_done && byte_done)
                       next_state = STOP;

            STOP:  if (baud_tick && bit_tick_done) begin

                       next_state  = IDLE;
                   end

            default: next_state = IDLE;
        endcase
    end
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

                    shift_reg <= {rx_d2, shift_reg[7:1]};
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            ext_data_out <= 8'd0;
            rx_valid     <= 1'b0;
            frame_error  <= 1'b0;
        end
        else begin
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            if (state == STOP && baud_tick && bit_tick_done) begin
                ext_data_out <= shift_reg;
                rx_valid     <= rx_d2;
                frame_error  <= ~rx_d2;
            end
        end
    end

endmodule
