`timescale 1ns/1ps

// =============================================================================
// Module      : uart_top
// Description : Small memory-mapped wrapper around the educational UART 8N1
//               transmitter, receiver, and 16x baud generator.
//
// Register map:
//   0 - BAUD_DATA : oversampling divider
//   1 - STATUS/ENABLE
//       write bit 0: enable
//       read  bit 0: enable
//             bit 1: TX busy (pending request or active frame)
//             bit 2: RX data ready (sticky)
//             bit 3: frame error (sticky, cleared by a status read)
//             bit 4: RX overrun (sticky, cleared by a status read)
//       error set wins over a simultaneous status-read clear.
//   2 - TX_DATA   : write byte to transmit; ignored while busy/disabled
//   3 - RX_DATA   : read buffered byte; clears ready unless a new byte arrives
//       RX buffer full: retain the old byte, discard the new byte, set overrun.
// =============================================================================
module uart_top (
    input wire clk,
    input wire rst,
    input wire [1:0] address,
    input wire [31:0] write_data,
    input wire we,
    input wire re,
    output wire tx,
    input wire rx,

    output reg [31:0] read_data,
    output wire tx_busy,
    output wire rx_valid
);

    localparam BAUD_DATA = 2'd0;
    localparam ENABLE = 2'd1;
    localparam TX_DATA = 2'd2;
    localparam RX_DATA = 2'd3;
    reg [31:0] baud_division;
    reg enable;
    reg [7:0] tx_data;

    wire [7:0] rx_data;
    wire baud_tick;
    wire frame_error;
    wire tx_busy_core;
    reg tx_start;
    reg rx_ready;
    reg frame_error_sticky;
    reg [7:0] rx_data_reg;
    reg overrun_sticky;

    wire rx_read = re && (address == RX_DATA);
    wire status_read = re && (address == ENABLE);
    wire overrun_event = rx_valid && rx_ready && !rx_read;

    // Disabling the UART aborts any partial frame and returns TX/RX to idle.
    wire core_rst = rst || !enable;
    assign tx_busy = tx_busy_core || tx_start;

    always @(posedge clk) begin
        if (rst) begin
            baud_division <= 32'd0;
            enable <= 1'b0;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;
            if (we) begin
                case (address)
                    BAUD_DATA: baud_division <= write_data;
                    ENABLE: enable <= write_data[0];
                    TX_DATA: begin
                        if (enable && !tx_busy) begin
                            tx_data  <= write_data[7:0];
                            tx_start <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // Hold unread data and retain RX error events for software.
    always @(posedge clk) begin
        if (rst || !enable) begin
            rx_data_reg <= 8'd0;
            rx_ready <= 1'b0;
            frame_error_sticky <= 1'b0;
            overrun_sticky <= 1'b0;
        end
        else begin
            if (rx_valid) begin
                if (!rx_ready || rx_read) begin
                    rx_data_reg <= rx_data;
                    rx_ready <= 1'b1;
                end
            end
            else if (rx_read) begin
                rx_ready <= 1'b0;
            end

            if (overrun_event)
                overrun_sticky <= 1'b1;
            else if (status_read)
                overrun_sticky <= 1'b0;

            if (frame_error)
                frame_error_sticky <= 1'b1;
            else if (status_read)
                frame_error_sticky <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst)
            read_data <= 32'd0;
        else if (re) begin
            case (address)
                BAUD_DATA: read_data <= baud_division;
                ENABLE: read_data <= {27'd0, overrun_sticky, frame_error_sticky, rx_ready, tx_busy, enable};
                TX_DATA: read_data <= {24'd0, tx_data};
                RX_DATA: read_data <= {24'd0, rx_data_reg};
                default: read_data <= 32'd0;
            endcase
        end
    end
    uart_baud_gen baud_gen (
        .clk(clk),
        .rst(rst),
        .baud_division(baud_division),
        .en(enable),
        .baud_tick(baud_tick)
    );
    uart_tx tx_core (
        .clk(clk),
        .rst(core_rst),
        .baud_tick(baud_tick),
        .ext_data_in(tx_data),
        .tx_start(tx_start),
        .tx(tx),
        .tx_busy(tx_busy_core)
    );
    uart_rx rx_core (
        .clk(clk),
        .rst(core_rst),
        .baud_tick(baud_tick),
        .rx(rx),
        .ext_data_out(rx_data),
        .rx_valid(rx_valid),
        .frame_error(frame_error)
    );

endmodule
