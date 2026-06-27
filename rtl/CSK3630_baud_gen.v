module CSK3630_baud_gen #(
    parameter integer CLOCK_FREQ = 50000000,
    parameter integer BAUD_RATE = 115200,
    parameter integer OVERSAMPLE = 16
) (
    input wire clk,
    input wire rst_n,
    output reg tick
);
    localparam integer TICK_RATE = BAUD_RATE * OVERSAMPLE;
    localparam integer RAW_DIVISOR = CLOCK_FREQ / TICK_RATE;
    localparam integer DIVISOR = (RAW_DIVISOR < 1) ? 1 : RAW_DIVISOR;

    reg [31:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'd0;
            tick <= 1'b0;
        end else begin
            if (counter == (DIVISOR - 1)) begin
                counter <= 32'd0;
                tick <= 1'b1;
            end else begin
                counter <= counter + 32'd1;
                tick <= 1'b0;
            end
        end
    end
endmodule
