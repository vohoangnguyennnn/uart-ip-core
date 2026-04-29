

module uart_baud_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] baud_division,
    input  wire        en,
    output reg         baud_tick
);

    reg [31:0] baud_count;
    reg        en_d;
    always @(posedge clk) begin
        if (rst)
            en_d <= 0;
        else
            en_d <= en;
    end

    wire en_q = en & ~en_d;
    always @(posedge clk) begin
        if (rst) begin
            baud_count <= 0;
            baud_tick  <= 0;
        end
        else begin
            baud_tick <= 0;

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
