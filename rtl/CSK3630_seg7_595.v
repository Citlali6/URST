module CSK3630_seg7_595 #(
    parameter integer SCLK_DIV = 25
) (
    input wire clk,
    input wire rst_n,
    input wire [31:0] hex_digits,
    output reg seg7_sclk,
    output reg seg7_dio,
    output reg seg7_rclk
);
    localparam [1:0] ST_LOAD  = 2'd0;
    localparam [1:0] ST_HIGH  = 2'd1;
    localparam [1:0] ST_LOW   = 2'd2;
    localparam [1:0] ST_LATCH = 2'd3;

    reg [1:0] state;
    reg [15:0] shift_reg;
    reg [4:0] bit_count;
    reg [2:0] digit_index;
    reg [7:0] active_digit;
    reg [15:0] div_count;
    wire [7:0] current_segments;

    function [7:0] seg_decode;
        input [3:0] value;
        begin
            case (value)
                4'h0: seg_decode = 8'b1100_0000;
                4'h1: seg_decode = 8'b1111_1001;
                4'h2: seg_decode = 8'b1010_0100;
                4'h3: seg_decode = 8'b1011_0000;
                4'h4: seg_decode = 8'b1001_1001;
                4'h5: seg_decode = 8'b1001_0010;
                4'h6: seg_decode = 8'b1000_0010;
                4'h7: seg_decode = 8'b1111_1000;
                4'h8: seg_decode = 8'b1000_0000;
                4'h9: seg_decode = 8'b1001_0000;
                4'hA: seg_decode = 8'b1000_1000;
                4'hB: seg_decode = 8'b1000_0011;
                4'hC: seg_decode = 8'b1100_0110;
                4'hD: seg_decode = 8'b1010_0001;
                4'hE: seg_decode = 8'b1000_0110;
                4'hF: seg_decode = 8'b1000_1110;
                default: seg_decode = 8'b1111_1111;
            endcase
        end
    endfunction

    function [3:0] digit_value;
        input [2:0] index;
        begin
            case (index)
                3'd0: digit_value = hex_digits[3:0];
                3'd1: digit_value = hex_digits[7:4];
                3'd2: digit_value = hex_digits[11:8];
                3'd3: digit_value = hex_digits[15:12];
                3'd4: digit_value = hex_digits[19:16];
                3'd5: digit_value = hex_digits[23:20];
                3'd6: digit_value = hex_digits[27:24];
                3'd7: digit_value = hex_digits[31:28];
                default: digit_value = 4'h0;
            endcase
        end
    endfunction

    assign current_segments = seg_decode(digit_value(digit_index));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_LOAD;
            shift_reg <= 16'hFFFF;
            bit_count <= 5'd0;
            digit_index <= 3'd0;
            active_digit <= 8'b0000_0001;
            div_count <= 16'd0;
            seg7_sclk <= 1'b0;
            seg7_dio <= 1'b0;
            seg7_rclk <= 1'b0;
        end else begin
            if (div_count < (SCLK_DIV - 1)) begin
                div_count <= div_count + 16'd1;
            end else begin
                div_count <= 16'd0;
                case (state)
                    ST_LOAD: begin
                        shift_reg <= {current_segments, active_digit};
                        seg7_dio <= current_segments[7];
                        seg7_sclk <= 1'b0;
                        seg7_rclk <= 1'b0;
                        bit_count <= 5'd0;
                        state <= ST_HIGH;
                    end

                    ST_HIGH: begin
                        seg7_sclk <= 1'b1;
                        state <= ST_LOW;
                    end

                    ST_LOW: begin
                        seg7_sclk <= 1'b0;
                        if (bit_count == 5'd15) begin
                            state <= ST_LATCH;
                        end else begin
                            bit_count <= bit_count + 5'd1;
                            shift_reg <= {shift_reg[14:0], 1'b0};
                            seg7_dio <= shift_reg[14];
                            state <= ST_HIGH;
                        end
                    end

                    ST_LATCH: begin
                        seg7_rclk <= 1'b1;
                        active_digit <= {active_digit[6:0], active_digit[7]};
                        digit_index <= digit_index + 3'd1;
                        state <= ST_LOAD;
                    end

                    default: begin
                        state <= ST_LOAD;
                    end
                endcase
            end
        end
    end
endmodule
