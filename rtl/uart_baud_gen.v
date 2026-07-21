`timescale 1ns/1ps

// =============================================================================
// Module      : uart_baud_gen
// Description : Generates a one-clock oversampling tick for the UART TX/RX.
//               For 16x oversampling:
//               baud_division = clock_frequency / (baud_rate * 16)
//
// Notes:
//   - baud_division = 0 disables tick generation.
//   - Disabling the generator resets its phase.
// =============================================================================
module uart_baud_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] baud_division,
    input  wire        en,
    output reg         baud_tick
);

    reg [31:0] baud_count;

    always @(posedge clk) begin
        if (rst) begin
            baud_count <= 32'd0;
            baud_tick  <= 1'b0;
        end
        else begin
            baud_tick <= 1'b0;

            if (!en || baud_division == 0) begin
                baud_count <= 32'd0;
            end
            else if (baud_count >= baud_division - 1'b1) begin
                baud_count <= 32'd0;
                baud_tick <= 1'b1;
            end
            else begin
                baud_count <= baud_count + 1'b1;
            end
        end
    end

endmodule
