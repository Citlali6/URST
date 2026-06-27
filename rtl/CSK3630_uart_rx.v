module CSK3630_uart_rx (
    input wire clk,
    input wire rst_n,
    input wire tick_16x,
    input wire rx,
    output reg [7:0] data,
    output reg data_valid,
    output reg frame_error
);
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [3:0] sample_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;
    reg rx_meta;
    reg rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            sample_count <= 4'd0;
            bit_index <= 3'd0;
            rx_shift <= 8'h00;
            data <= 8'h00;
            data_valid <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            frame_error <= 1'b0;

            if (tick_16x) begin
                case (state)
                    ST_IDLE: begin
                        sample_count <= 4'd0;
                        bit_index <= 3'd0;
                        if (rx_sync == 1'b0) begin
                            state <= ST_START;
                        end
                    end

                    ST_START: begin
                        if (sample_count == 4'd7) begin
                            if (rx_sync == 1'b0) begin
                                sample_count <= 4'd0;
                                bit_index <= 3'd0;
                                state <= ST_DATA;
                            end else begin
                                state <= ST_IDLE;
                            end
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end

                    ST_DATA: begin
                        if (sample_count == 4'd15) begin
                            rx_shift[bit_index] <= rx_sync;
                            sample_count <= 4'd0;
                            if (bit_index == 3'd7) begin
                                state <= ST_STOP;
                            end else begin
                                bit_index <= bit_index + 3'd1;
                            end
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end

                    ST_STOP: begin
                        if (sample_count == 4'd15) begin
                            data <= rx_shift;
                            data_valid <= rx_sync;
                            frame_error <= ~rx_sync;
                            state <= ST_IDLE;
                            sample_count <= 4'd0;
                        end else begin
                            sample_count <= sample_count + 4'd1;
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
