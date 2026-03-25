// =============================================================================
// Module      : uart_baud_gen
// Description : Baud rate generator. Produces a single-cycle tick at 16× the
//               target baud rate. The 16× oversampling clock is consumed by
//               uart_tx and uart_rx for precise bit timing and mid-bit sampling.
// Formula     : baud_division = clk_freq / (baud_rate × 16)
// Example     : 50 MHz, 115200 baud → baud_division = 50_000_000 / (115200×16) ≈ 27
// Ports:
//   clk           - System clock
//   rst           - Synchronous active-high reset
//   baud_division - Clock divider value (set before asserting en)
//   en            - Enable the counter; rising edge resets the counter phase
//   baud_tick     - Single-cycle pulse at 16× baud rate
// =============================================================================
module uart_baud_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] baud_division,
    input  wire        en,
    output reg         baud_tick
);

    reg [31:0] baud_count;
    reg        en_d;

    // edge detect
    always @(posedge clk) begin
        if (rst)
            en_d <= 0;
        else
            en_d <= en;
    end

    wire en_q = en & ~en_d;

    // baud counter
    always @(posedge clk) begin
        if (rst) begin
            baud_count <= 0;
            baud_tick  <= 0;
        end
        else begin
            baud_tick <= 0;   // default

            if (!en || baud_division == 0) begin
                baud_count <= 0;
            end
            else if (en_q) begin
                baud_count <= 0;
            end
            else if (baud_count == baud_division - 1) begin
                baud_count <= 0;
                baud_tick  <= 1;
            end
            else begin
                baud_count <= baud_count + 1;
            end
        end
    end

endmodule
