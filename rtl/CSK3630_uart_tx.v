module CSK3630_uart_tx (
    input wire clk,
    input wire rst_n,
    input wire tick_16x,
    input wire start,
    input wire [7:0] data,
    output reg tx,
    output reg busy
);
    reg [9:0] shift_reg;
    reg [3:0] tick_count;
    reg [3:0] bit_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 10'b11_1111_1111;
            tick_count <= 4'd0;
            bit_index <= 4'd0;
            tx <= 1'b1;
            busy <= 1'b0;
        end else begin
            if (!busy) begin
                tx <= 1'b1;
                tick_count <= 4'd0;
                bit_index <= 4'd0;
                if (start) begin
                    shift_reg <= {1'b1, data, 1'b0};
                    tx <= 1'b0;
                    busy <= 1'b1;
                end
            end else if (tick_16x) begin
                if (tick_count == 4'd15) begin
                    tick_count <= 4'd0;
                    if (bit_index == 4'd9) begin
                        tx <= 1'b1;
                        busy <= 1'b0;
                        bit_index <= 4'd0;
                    end else begin
                        bit_index <= bit_index + 4'd1;
                        tx <= shift_reg[bit_index + 1'b1];
                    end
                end else begin
                    tick_count <= tick_count + 4'd1;
                end
            end
        end
    end
endmodule
