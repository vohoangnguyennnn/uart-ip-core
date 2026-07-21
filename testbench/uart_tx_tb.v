`timescale 1ns/1ps

module uart_tx_tb;

    localparam CLOCK_PERIOD = 20;
    localparam OVERSAMPLE   = 16;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        baud_tick = 1'b0;
    reg  [7:0] ext_data_in = 8'd0;
    reg        tx_start = 1'b0;
    wire       tx;
    wire       tx_busy;

    always #(CLOCK_PERIOD / 2) clk = ~clk;

    uart_tx dut (
        .clk         (clk),
        .rst         (rst),
        .baud_tick   (baud_tick),
        .ext_data_in (ext_data_in),
        .tx_start    (tx_start),
        .tx          (tx),
        .tx_busy     (tx_busy)
    );

    task pulse_baud_tick;
        begin
            @(negedge clk);
            baud_tick = 1'b1;
            @(negedge clk);
            baud_tick = 1'b0;
        end
    endtask

    task start_transmission;
        input [7:0] data;
        begin
            // No baud tick is present here. The byte must still be accepted.
            @(negedge clk);
            ext_data_in = data;
            tx_start = 1'b1;
            @(posedge clk);
            #1;

            if (!tx_busy || tx !== 1'b0)
                $fatal(1, "TX did not enter the START state for byte 0x%02h", data);

            @(negedge clk);
            tx_start = 1'b0;

            // Prove that the DUT uses its latched copy during the frame.
            ext_data_in = ~data;
        end
    endtask

    task check_uart_bit;
        input expected_value;
        input integer frame_index;
        integer i;
        begin
            // Inspect the line at the midpoint of the UART bit.
            for (i = 0; i < OVERSAMPLE / 2; i = i + 1)
                pulse_baud_tick();

            if (tx !== expected_value)
                $fatal(1,
                       "Frame bit %0d is %b, expected %b",
                       frame_index,
                       tx,
                       expected_value);

            if (!tx_busy)
                $fatal(1, "tx_busy deasserted during frame bit %0d", frame_index);

            for (i = OVERSAMPLE / 2; i < OVERSAMPLE; i = i + 1)
                pulse_baud_tick();
        end
    endtask

    task send_and_check;
        input [7:0] data;
        integer bit_index;
        begin
            start_transmission(data);

            check_uart_bit(1'b0, 0);  // START

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                check_uart_bit(data[bit_index], bit_index + 1);

            check_uart_bit(1'b1, 9);  // STOP

            #1;
            if (tx_busy)
                $fatal(1, "tx_busy remained asserted after byte 0x%02h", data);
            if (tx !== 1'b1)
                $fatal(1, "TX did not return to the idle-high level");

            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);

        $display("[PASS] uart_tx_tb: complete 8N1 frames, LSB-first");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "uart_tx_tb timeout");
    end

endmodule
