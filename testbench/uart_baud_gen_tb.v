`timescale 1ns/1ps

module uart_baud_gen_tb;

    localparam CLOCK_PERIOD = 20;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] baud_division = 32'd0;
    reg         en = 1'b0;
    wire        baud_tick;

    integer tick_count = 0;

    always #(CLOCK_PERIOD / 2) clk = ~clk;

    uart_baud_gen dut (
        .clk           (clk),
        .rst           (rst),
        .baud_division (baud_division),
        .en            (en),
        .baud_tick     (baud_tick)
    );

    always @(posedge baud_tick)
        tick_count = tick_count + 1;

    task expect_no_ticks;
        input integer clock_cycles;
        integer ticks_before;
        integer i;
        begin
            ticks_before = tick_count;

            for (i = 0; i < clock_cycles; i = i + 1) begin
                @(posedge clk);
                #1;
                if (baud_tick !== 1'b0)
                    $fatal(1, "baud_tick asserted while generator should be idle");
            end

            if (tick_count != ticks_before)
                $fatal(1, "Unexpected baud tick while generator should be idle");
        end
    endtask

    task check_tick_interval;
        input [31:0] division;
        input integer intervals;
        integer i;
        time previous_tick;
        time current_tick;
        time expected_interval;
        begin
            @(negedge clk);
            baud_division = division;
            en = 1'b1;
            expected_interval = division * CLOCK_PERIOD;

            @(posedge baud_tick);
            previous_tick = $time;

            for (i = 0; i < intervals; i = i + 1) begin
                @(posedge baud_tick);
                current_tick = $time;

                if ((current_tick - previous_tick) != expected_interval)
                    $fatal(1,
                           "Divider %0d produced %0t ns interval, expected %0t ns",
                           division,
                           current_tick - previous_tick,
                           expected_interval);

                previous_tick = current_tick;
            end

            @(negedge clk);
            en = 1'b0;
            expect_no_ticks(division + 2);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Disabled generator must remain quiet.
        baud_division = 32'd4;
        en = 1'b0;
        expect_no_ticks(10);

        // A zero divider is explicitly treated as disabled.
        @(negedge clk);
        baud_division = 32'd0;
        en = 1'b1;
        expect_no_ticks(10);

        // Check more than one divider and verify restart after disable.
        check_tick_interval(32'd4, 4);
        check_tick_interval(32'd7, 3);

        $display("[PASS] uart_baud_gen_tb: divider timing and disable behavior");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "uart_baud_gen_tb timeout");
    end

endmodule
