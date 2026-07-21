`timescale 1ns/1ps

module uart_rx_tb;

    localparam CLOCK_PERIOD = 20;
    localparam OVERSAMPLE   = 16;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        baud_tick = 1'b0;
    reg        rx = 1'b1;
    wire [7:0] ext_data_out;
    wire       rx_valid;
    wire       frame_error;

    integer valid_count = 0;
    integer error_count = 0;
    reg [7:0] captured_data = 8'd0;

    always #(CLOCK_PERIOD / 2) clk = ~clk;

    uart_rx dut (
        .clk          (clk),
        .rst          (rst),
        .baud_tick    (baud_tick),
        .rx           (rx),
        .ext_data_out (ext_data_out),
        .rx_valid     (rx_valid),
        .frame_error  (frame_error)
    );

    always @(posedge clk) begin
        if (rst) begin
            valid_count   <= 0;
            error_count   <= 0;
            captured_data <= 8'd0;
        end
        else begin
            if (rx_valid) begin
                valid_count   <= valid_count + 1;
                captured_data <= ext_data_out;
            end

            if (frame_error)
                error_count <= error_count + 1;
        end
    end

    task pulse_baud_tick;
        begin
            @(negedge clk);
            baud_tick = 1'b1;
            @(negedge clk);
            baud_tick = 1'b0;
        end
    endtask

    task drive_uart_bit;
        input bit_value;
        integer i;
        begin
            rx = bit_value;
            for (i = 0; i < OVERSAMPLE; i = i + 1)
                pulse_baud_tick();
        end
    endtask

    task drive_uart_frame;
        input [7:0] data;
        input       stop_value;
        integer bit_index;
        begin
            drive_uart_bit(1'b0);

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                drive_uart_bit(data[bit_index]);

            drive_uart_bit(stop_value);
            rx = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    task send_and_expect_byte;
        input [7:0] data;
        integer valid_before;
        integer errors_before;
        begin
            valid_before = valid_count;
            errors_before = error_count;

            drive_uart_frame(data, 1'b1);

            if (valid_count != valid_before + 1)
                $fatal(1, "Expected one rx_valid pulse for byte 0x%02h", data);
            if (captured_data !== data)
                $fatal(1,
                       "Received 0x%02h, expected 0x%02h",
                       captured_data,
                       data);
            if (error_count != errors_before)
                $fatal(1, "frame_error asserted for valid byte 0x%02h", data);
        end
    endtask

    task send_and_expect_frame_error;
        input [7:0] data;
        integer valid_before;
        integer errors_before;
        begin
            valid_before = valid_count;
            errors_before = error_count;

            drive_uart_frame(data, 1'b0);

            if (valid_count != valid_before)
                $fatal(1, "rx_valid asserted for a frame with a bad stop bit");
            if (error_count != errors_before + 1)
                $fatal(1, "Bad stop bit did not produce frame_error");
        end
    endtask

    task check_false_start_rejection;
        integer valid_before;
        integer errors_before;
        integer i;
        begin
            valid_before = valid_count;
            errors_before = error_count;

            // Drive LOW for less than half a bit, then return to idle.
            rx = 1'b0;
            for (i = 0; i < 4; i = i + 1)
                pulse_baud_tick();

            rx = 1'b1;
            for (i = 0; i < OVERSAMPLE; i = i + 1)
                pulse_baud_tick();

            repeat (4) @(posedge clk);

            if (valid_count != valid_before || error_count != errors_before)
                $fatal(1, "Short false start generated a receive event");
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        check_false_start_rejection();
        send_and_expect_byte(8'hA5);
        send_and_expect_byte(8'h00);
        send_and_expect_byte(8'hFF);
        send_and_expect_frame_error(8'h3C);

        $display("[PASS] uart_rx_tb: valid frames, false start and frame error");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "uart_rx_tb timeout");
    end

endmodule
