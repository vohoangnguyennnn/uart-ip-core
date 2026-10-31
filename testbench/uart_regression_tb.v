`timescale 1ns/1ps

// Directed regressions for pending TX writes, RX overrun and bad stop bits.
// RX has an independent serial driver; it is never connected to TX.
module uart_regression_tb;
    localparam CLOCK_PERIOD = 20;
    localparam DIVIDER = 4;
    localparam BIT_CYCLES = DIVIDER * 16;
    localparam BIT_PERIOD = CLOCK_PERIOD * BIT_CYCLES;
    localparam BAUD_DATA = 2'd0;
    localparam STATUS = 2'd1;
    localparam TX_DATA = 2'd2;
    localparam RX_DATA = 2'd3;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [1:0] address = BAUD_DATA;
    reg [31:0] write_data = 32'd0;
    reg we = 1'b0;
    reg re = 1'b0;
    reg rx = 1'b1;
    wire tx;
    wire [31:0] read_data;
    wire tx_busy;
    wire rx_valid;

    integer failures = 0;
    integer before_test;
    integer valid_count = 0;
    integer tx_count = 0;
    integer tx_bit;
    reg monitor_tx = 1'b0;
    reg [7:0] serial_byte;
    reg [7:0] first_tx_byte;
    reg serial_error = 1'b0;
    reg [31:0] status_value;
    reg [31:0] data_value;
    reg busy_gap;

    always #(CLOCK_PERIOD / 2) clk = ~clk;

    uart_top dut (
        .clk(clk), .rst(rst), .address(address), .write_data(write_data),
        .we(we), .re(re), .tx(tx), .rx(rx), .read_data(read_data),
        .tx_busy(tx_busy), .rx_valid(rx_valid)
    );

    always @(posedge clk) begin
        if (rst)
            valid_count <= 0;
        else if (rx_valid)
            valid_count <= valid_count + 1;
    end

    // Sample near bit centers, allowing the documented sub-tick START skew.
    always @(negedge tx) begin
        if (monitor_tx && !rst) begin
            #(BIT_PERIOD / 2);
            if (tx !== 1'b0)
                serial_error = 1'b1;
            for (tx_bit = 0; tx_bit < 8; tx_bit = tx_bit + 1) begin
                #(BIT_PERIOD);
                serial_byte[tx_bit] = tx;
            end
            #(BIT_PERIOD);
            if (tx !== 1'b1)
                serial_error = 1'b1;
            if (tx_count == 0)
                first_tx_byte = serial_byte;
            tx_count = tx_count + 1;
        end
    end

    task check;
        input condition;
        input [639:0] message;
        begin
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("[FAIL] %0s", message);
            end
        end
    endtask

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

    task reset_and_enable;
        begin
            @(negedge clk);
            rst = 1'b1;
            we = 1'b0;
            re = 1'b0;
            rx = 1'b1;
            monitor_tx = 1'b0;
            repeat (4) @(negedge clk);
            rst = 1'b0;
            write_register(BAUD_DATA, DIVIDER);
            write_register(STATUS, 32'd1);
            repeat (4) @(negedge clk);
        end
    endtask

    task drive_rx_bit;
        input value;
        begin
            rx = value;
            repeat (BIT_CYCLES) @(negedge clk);
        end
    endtask

    task drive_rx_frame;
        input [7:0] data;
        input stop_value;
        integer bit_index;
        begin
            @(negedge clk);
            drive_rx_bit(1'b0);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                drive_rx_bit(data[bit_index]);
            drive_rx_bit(stop_value);
            drive_rx_bit(1'b1);
        end
    endtask

    initial begin
        // T1: keep WE high across two consecutive write sampling edges.
        reset_and_enable();
        before_test = failures;
        monitor_tx = 1'b1;
        @(negedge clk);
        address = TX_DATA;
        write_data = 32'hA1;
        we = 1'b1;
        @(posedge clk);
        #1 busy_gap = (tx_busy !== 1'b1);
        @(negedge clk);
        write_data = 32'hB2;
        @(posedge clk);
        #1 busy_gap = busy_gap || (tx_busy !== 1'b1);
        @(negedge clk);
        we = 1'b0;
        read_register(STATUS, status_value);
        read_register(TX_DATA, data_value);
        $display("[INFO] T1 immediate_busy_gap=%0b STATUS=%08h TX_DATA=%08h",
                 busy_gap, status_value, data_value);
        check(!busy_gap, "T1 B1: busy must assert immediately after the first write");
        check(status_value[1] === 1'b1, "T1 B1: STATUS must report TX busy");
        check(data_value === 32'hA1, "T1 B1: rejected second write must preserve TX_DATA=A1");
        // More than two frames: detect a delayed or duplicate second frame too.
        repeat (24 * BIT_CYCLES) @(negedge clk);
        monitor_tx = 1'b0;
        $display("[INFO] T1 serial_frames=%0d first_byte=%02h serial_error=%0b",
                 tx_count, first_tx_byte, serial_error);
        check(tx_count == 1 && first_tx_byte === 8'hA1 && !serial_error,
              "T1 B1: exactly one valid A1 frame must be transmitted");
        check(tx_busy === 1'b0, "T1 B1: TX must return to idle");
        if (failures == before_test) $display("[PASS] T1 B1 back-to-back TX writes");
        else $display("[FAIL] T1 B1 back-to-back TX writes");

        // T2: retain the first unread byte and expose a clear-on-read overrun.
        reset_and_enable();
        before_test = failures;
        drive_rx_frame(8'h11, 1'b1);
        drive_rx_frame(8'h22, 1'b1);
        read_register(STATUS, status_value);
        check(status_value[4:2] === 3'b101, "T2 B3: ready=1, frame_error=0, overrun=1");
        read_register(STATUS, status_value);
        check(status_value[4:2] === 3'b001, "T2 B3: STATUS read clears overrun but retains ready");
        read_register(RX_DATA, data_value);
        $display("[INFO] T2 valid_events=%0d STATUS=%08h RX_DATA=%08h",
                 valid_count, status_value, data_value);
        check(valid_count == 2, "T2 B3: independent RX driver must deliver two valid frames");
        check(data_value === 32'h11, "T2 B3: overrun must retain unread byte 11");
        read_register(STATUS, status_value);
        check(status_value[4:2] === 3'b000, "T2 B3: reads must clear overrun and RX ready");
        if (failures == before_test) $display("[PASS] T2 B3 RX overrun");
        else $display("[FAIL] T2 B3 RX overrun");

        // T3: a malformed frame must not change a previous unread good byte.
        reset_and_enable();
        before_test = failures;
        drive_rx_frame(8'h5A, 1'b1);
        read_register(STATUS, status_value);
        check(status_value[4:2] === 3'b001, "T3 B2: good frame must set ready without errors");
        drive_rx_frame(8'hC3, 1'b0);
        read_register(STATUS, status_value);
        read_register(RX_DATA, data_value);
        $display("[INFO] T3 valid_events=%0d STATUS=%08h RX_DATA=%08h core_data=%02h",
                 valid_count, status_value, data_value, dut.rx_core.ext_data_out);
        check(valid_count == 1, "T3 B2: malformed frame must not assert rx_valid");
        check(data_value === 32'h5A, "T3 B2: bad stop bit must preserve unread RX_DATA=5A");
        // Check the core contract too, so a top-level buffer cannot mask B2.
        check(dut.rx_core.ext_data_out === 8'h5A, "T3 B2: RX core must preserve its last good byte");
        check(status_value[4:2] === 3'b011, "T3 B2: ready=1, frame_error=1, overrun=0");
        read_register(STATUS, status_value);
        check(status_value[3] === 1'b0, "T3 B2: STATUS read must clear frame_error");
        if (failures == before_test) $display("[PASS] T3 B2 invalid stop bit");
        else $display("[FAIL] T3 B2 invalid stop bit");

        // T4: consume the old byte on the exact edge accepting a new byte.
        reset_and_enable();
        before_test = failures;
        drive_rx_frame(8'h11, 1'b1);
        fork
            drive_rx_frame(8'h22, 1'b1);
            begin
                @(posedge rx_valid);
                @(negedge clk);
                address = RX_DATA;
                re = 1'b1;
                @(posedge clk);
                #1;
                check(read_data === 32'h11, "T4: simultaneous read must return the old byte");
                @(negedge clk);
                re = 1'b0;
            end
        join
        read_register(STATUS, status_value);
        check(status_value[4:2] === 3'b001, "T4: replacement byte stays ready without overrun");
        read_register(RX_DATA, data_value);
        check(data_value === 32'h22, "T4: replacement byte must remain available");
        if (failures == before_test) $display("[PASS] T4 B3 simultaneous RX read and arrival");
        else $display("[FAIL] T4 B3 simultaneous RX read and arrival");

        // T5: a fresh overrun must survive a simultaneous STATUS clear.
        reset_and_enable();
        before_test = failures;
        drive_rx_frame(8'h33, 1'b1);
        fork
            drive_rx_frame(8'h44, 1'b1);
            begin
                @(posedge rx_valid);
                read_register(STATUS, status_value);
                check(status_value[4] === 1'b0, "T5: simultaneous STATUS read sees the old flag");
            end
        join
        read_register(STATUS, status_value);
        check(status_value[4] === 1'b1, "T5: overrun set must win over simultaneous clear");
        read_register(STATUS, status_value);
        check(status_value[4] === 1'b0, "T5: a later STATUS read must clear overrun");
        read_register(RX_DATA, data_value);
        check(data_value === 32'h33, "T5: simultaneous STATUS read must preserve unread data");
        if (failures == before_test) $display("[PASS] T5 B3 overrun set wins over clear");
        else $display("[FAIL] T5 B3 overrun set wins over clear");

        // T6: framing-error events use the same set-over-clear policy.
        reset_and_enable();
        before_test = failures;
        fork
            drive_rx_frame(8'h55, 1'b0);
            begin
                @(posedge dut.frame_error);
                read_register(STATUS, status_value);
            end
        join
        read_register(STATUS, status_value);
        check(status_value[3] === 1'b1, "T6: frame-error set must win over simultaneous clear");
        read_register(STATUS, status_value);
        check(status_value[3] === 1'b0, "T6: a later STATUS read must clear frame error");
        if (failures == before_test) $display("[PASS] T6 frame-error set wins over clear");
        else $display("[FAIL] T6 frame-error set wins over clear");

        // T7: disabling aborts active TX/RX and clears pending RX status.
        reset_and_enable();
        before_test = failures;
        drive_rx_frame(8'h66, 1'b1);
        drive_rx_frame(8'h77, 1'b1);
        drive_rx_frame(8'h88, 1'b0);
        write_register(TX_DATA, 32'hA5);
        fork
            drive_rx_frame(8'h99, 1'b1);
            begin
                repeat (2 * BIT_CYCLES) @(negedge clk);
                check(tx_busy === 1'b1, "T7: TX must be active before disabling");
                write_register(STATUS, 32'd0);
                repeat (4) @(negedge clk);
                check(tx === 1'b1 && tx_busy === 1'b0, "T7: disable must abort TX to idle");
            end
        join
        read_register(STATUS, status_value);
        check(status_value === 32'd0, "T7: disable must clear RX ready and sticky errors");
        write_register(STATUS, 32'd1);
        drive_rx_frame(8'hAB, 1'b1);
        read_register(STATUS, status_value);
        check(status_value === 32'd5, "T7: RX must recover after re-enabling");
        read_register(RX_DATA, data_value);
        check(data_value === 32'hAB, "T7: re-enabled RX must deliver the new byte");
        if (failures == before_test) $display("[PASS] T7 disable abort and RX recovery");
        else $display("[FAIL] T7 disable abort and RX recovery");

        if (failures != 0)
            $fatal(1, "[FAIL] uart_regression_tb: %0d failed checks", failures);
        $display("[PASS] uart_regression_tb");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "[FAIL] uart_regression_tb: watchdog timeout");
    end
endmodule
