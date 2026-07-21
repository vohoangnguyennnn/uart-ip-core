`timescale 1ns/1ps

module uart_top_tb;

    localparam CLOCK_PERIOD = 20;

    localparam BAUD_DATA = 2'd0;
    localparam STATUS    = 2'd1;
    localparam TX_DATA   = 2'd2;
    localparam RX_DATA   = 2'd3;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [1:0]  address = 2'd0;
    reg  [31:0] write_data = 32'd0;
    reg         we = 1'b0;
    reg         re = 1'b0;
    wire        tx;
    wire        rx;
    wire [31:0] read_data;
    wire        tx_busy;
    wire        rx_valid;

    integer rx_event_count = 0;

    // Physical loopback: everything transmitted is fed back to the receiver.
    assign rx = tx;

    always #(CLOCK_PERIOD / 2) clk = ~clk;

    uart_top dut (
        .clk        (clk),
        .rst        (rst),
        .address    (address),
        .write_data (write_data),
        .we         (we),
        .re         (re),
        .tx         (tx),
        .rx         (rx),
        .read_data  (read_data),
        .tx_busy    (tx_busy),
        .rx_valid   (rx_valid)
    );

    always @(posedge clk) begin
        if (rst)
            rx_event_count <= 0;
        else if (rx_valid)
            rx_event_count <= rx_event_count + 1;
    end

    task write_register;
        input [1:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            address = addr;
            write_data = data;
            we = 1'b1;

            @(negedge clk);
            we = 1'b0;
        end
    endtask

    task read_register;
        input [1:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            address = addr;
            re = 1'b1;

            @(posedge clk);
            #1 data = read_data;

            @(negedge clk);
            re = 1'b0;
        end
    endtask

    task wait_for_tx_busy;
        input expected_value;
        integer cycles;
        begin
            cycles = 0;

            while (tx_busy !== expected_value && cycles < 10000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (tx_busy !== expected_value)
                $fatal(1, "Timeout waiting for tx_busy=%b", expected_value);
        end
    endtask

    task send_and_expect_loopback;
        input [7:0] data;
        input       attempt_busy_write;
        input [7:0] rejected_data;
        integer events_before;
        integer cycles;
        reg [31:0] value;
        begin
            events_before = rx_event_count;
            write_register(TX_DATA, {24'd0, data});
            wait_for_tx_busy(1'b1);

            // An optional second write verifies that the active frame cannot
            // be replaced while the transmitter is busy.
            if (attempt_busy_write)
                write_register(TX_DATA, {24'd0, rejected_data});

            cycles = 0;
            while (rx_event_count == events_before && cycles < 10000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (rx_event_count != events_before + 1)
                $fatal(1, "Loopback did not receive byte 0x%02h", data);

            read_register(STATUS, value);
            if (!value[2])
                $fatal(1, "RX-ready status was not retained");
            if (value[3])
                $fatal(1, "Unexpected frame error during loopback");

            read_register(RX_DATA, value);
            if (value[7:0] !== data)
                $fatal(1,
                       "Loopback received 0x%02h, expected 0x%02h",
                       value[7:0],
                       data);

            read_register(STATUS, value);
            if (value[2])
                $fatal(1, "RX-ready status did not clear after RX_DATA read");

            wait_for_tx_busy(1'b0);
        end
    endtask

    reg [31:0] value;

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        if (tx !== 1'b1 || tx_busy !== 1'b0)
            $fatal(1, "UART did not reset to the idle state");

        // TX writes are ignored until the UART is enabled.
        write_register(TX_DATA, 32'h00000055);
        repeat (4) @(posedge clk);
        if (tx_busy)
            $fatal(1, "Disabled UART accepted a TX write");

        write_register(BAUD_DATA, 32'd4);
        read_register(BAUD_DATA, value);
        if (value !== 32'd4)
            $fatal(1, "BAUD_DATA readback failed");

        write_register(STATUS, 32'd1);
        read_register(STATUS, value);
        if (value[3:0] !== 4'b0001)
            $fatal(1, "Unexpected status after enable: %04b", value[3:0]);

        // Clean loopback frames used for protocol and waveform inspection.
        send_and_expect_loopback(8'hA5, 1'b0, 8'h00);
        send_and_expect_loopback(8'h5A, 1'b0, 8'h00);
        send_and_expect_loopback(8'h00, 1'b0, 8'h00);
        send_and_expect_loopback(8'hFF, 1'b0, 8'h00);

        // Separate busy-write test: C3 must be rejected while 3C is active.
        send_and_expect_loopback(8'h3C, 1'b1, 8'hC3);

        read_register(STATUS, value);
        if (value[3:0] !== 4'b0001)
            $fatal(1, "Unexpected final UART status: %04b", value[3:0]);

        $display("[PASS] uart_top_tb: register loopback and busy-write protection");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "uart_top_tb timeout");
    end

endmodule
