// =============================================================================
// Module      : uart_top
// Description : Top-level UART core integrating the baud generator, transmitter
//               and receiver. Exposes a simple 32-bit register bus interface.
//
// Register map (address width = 2 bits):
//   Addr 0 (BAUD_DATA) W: set baud_division  R: read back baud_division
//   Addr 1 (ENABLE)    W: bit[0]=enable      R: {rx_valid, tx_busy, enable}
//   Addr 2 (TX_DATA)   W: write byte → fires tx_start pulse automatically
//                      R: read back last written TX byte
//   Addr 3 (RX_DATA)   R: last received byte (latch rx_valid before reading)
//
// Ports:
//   clk        - System clock
//   rst        - Synchronous active-high reset
//   address    - 2-bit register select
//   write_data - 32-bit write data
//   we         - Write enable (synchronous)
//   re         - Read enable (synchronous; read_data valid one cycle later)
//   tx         - UART TX output pin
//   rx         - UART RX input pin
//   read_data  - 32-bit registered read data
//   tx_busy    - High while the transmitter is sending a frame
//   rx_valid   - Pulses high for 1 clock when a new RX byte is ready
// =============================================================================
module uart_top (
    input  wire        clk,
    input  wire        rst,

    // register interface
    input  wire [1:0]  address,
    input  wire [31:0] write_data,
    input  wire        we,
    input  wire        re,

    // uart pins
    output wire        tx,
    input  wire        rx,

    output reg  [31:0] read_data,  // widened to 32-bit to match write_data
    output wire        tx_busy,    // high while TX is transmitting
    output wire        rx_valid    // pulses high for 1 clock when RX byte is ready
);


    localparam BAUD_DATA = 2'd0;
    localparam ENABLE    = 2'd1;
    localparam TX_DATA   = 2'd2;
    localparam RX_DATA   = 2'd3;


    // Registers
    reg [31:0] baud_division;
    reg        enable;
    reg [7:0]  tx_data;

    wire [7:0] rx_data;
    wire       baud_tick;
    reg        tx_start;   // one-cycle pulse sent to uart_tx when TX_DATA is written


    // WRITE DATA
    // tx_start pulses for exactly 1 clock when the TX_DATA register is written.
    // This lets the TX FSM send exactly one byte per write.
    always @(posedge clk) begin
        if (rst) begin
            baud_division <= 32'd0;
            enable        <= 1'b0;
            tx_data       <= 8'd0;
            tx_start      <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;   // default: de-assert every cycle
            if (we) begin
                case (address)
                    BAUD_DATA: baud_division <= write_data;
                    ENABLE:    enable        <= write_data[0];
                    TX_DATA: begin
                        tx_data  <= write_data[7:0];
                        tx_start <= 1'b1;   // pulse to kick off one transmission
                    end
                    default: ;
                endcase
            end
        end
    end


    // READ DATA
    // Register map (read):
    //   0 (BAUD_DATA) : baud_division value
    //   1 (ENABLE)    : bit[0]=enable, bit[1]=tx_busy, bit[2]=rx_valid
    //   2 (TX_DATA)   : last written TX byte
    //   3 (RX_DATA)   : last received byte
    always @(posedge clk) begin
        if (rst)
            read_data <= 32'd0;
        else if (re) begin
            case (address)
                BAUD_DATA: read_data <= baud_division;
                ENABLE:    read_data <= {29'd0, rx_valid, tx_busy, enable};
                TX_DATA:   read_data <= {24'd0, tx_data};
                RX_DATA:   read_data <= {24'd0, rx_data};
                default:   read_data <= 32'd0;
            endcase
        end
    end


    // Baud generator
    uart_baud_gen baud_gen (
        .clk           (clk),
        .rst           (rst),
        .baud_division (baud_division),
        .en            (enable),
        .baud_tick     (baud_tick)
    );

    // Transmitter
    uart_tx tx_core (
        .clk         (clk),
        .rst         (rst),
        .baud_tick   (baud_tick),
        .ext_data_in (tx_data),
        .tx_start    (tx_start),
        .tx          (tx),
        .tx_busy     (tx_busy)
    );

    // Receiver
    uart_rx rx_core (
        .clk          (clk),
        .rst          (rst),
        .baud_tick    (baud_tick),
        .rx           (rx),
        .ext_data_out (rx_data),
        .rx_valid     (rx_valid)
    );

endmodule

