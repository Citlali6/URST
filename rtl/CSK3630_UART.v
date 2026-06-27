module CSK3630_UART #(
    parameter integer CLOCK_FREQ = 50000000,
    parameter integer BAUD_RATE = 115200
) (
    input wire clk_50m,
    input wire rst_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire seg7_sclk,
    output wire seg7_dio,
    output wire seg7_rclk,
    output wire [3:0] led
);
    localparam integer SEG_DIV = (CLOCK_FREQ < 1000000) ? 1 : 25;
    localparam integer BLINK_RELOAD = (CLOCK_FREQ < 20) ? 1 : (CLOCK_FREQ / 20);

    wire tick_16x;
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_error;
    wire [7:0] tx_data;
    wire tx_start;
    wire tx_busy;
    wire [7:0] last_rx_byte;
    wire [7:0] last_tx_byte;
    wire [7:0] last_cmd;
    wire [7:0] last_addr;
    wire [3:0] display_status;
    wire error_seen;

    reg [31:0] rx_blink;
    reg [31:0] tx_blink;
    reg [23:0] heartbeat;

    CSK3630_baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(16)
    ) u_baud_gen (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick(tick_16x)
    );

    CSK3630_uart_rx u_uart_rx (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_16x(tick_16x),
        .rx(uart_rx),
        .data(rx_data),
        .data_valid(rx_valid),
        .frame_error(rx_frame_error)
    );

    CSK3630_uart_tx u_uart_tx (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_16x(tick_16x),
        .start(tx_start),
        .data(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    CSK3630_uart_protocol u_protocol (
        .clk(clk_50m),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .tx_busy(tx_busy),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .last_rx_byte(last_rx_byte),
        .last_tx_byte(last_tx_byte),
        .last_cmd(last_cmd),
        .last_addr(last_addr),
        .display_status(display_status),
        .error_seen(error_seen)
    );

    CSK3630_seg7_595 #(
        .SCLK_DIV(SEG_DIV)
    ) u_seg7 (
        .clk(clk_50m),
        .rst_n(rst_n),
        .hex_digits({
            last_tx_byte[7:4],
            last_tx_byte[3:0],
            last_rx_byte[7:4],
            last_rx_byte[3:0],
            last_cmd[3:0],
            last_addr[3:0],
            display_status,
            heartbeat[23:20]
        }),
        .seg7_sclk(seg7_sclk),
        .seg7_dio(seg7_dio),
        .seg7_rclk(seg7_rclk)
    );

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            rx_blink <= 32'd0;
            tx_blink <= 32'd0;
            heartbeat <= 24'd0;
        end else begin
            heartbeat <= heartbeat + 24'd1;

            if (rx_valid || rx_frame_error) begin
                rx_blink <= BLINK_RELOAD[31:0];
            end else if (rx_blink != 32'd0) begin
                rx_blink <= rx_blink - 32'd1;
            end

            if (tx_start) begin
                tx_blink <= BLINK_RELOAD[31:0];
            end else if (tx_blink != 32'd0) begin
                tx_blink <= tx_blink - 32'd1;
            end
        end
    end

    assign led[0] = (rx_blink != 32'd0) ? 1'b0 : 1'b1;
    assign led[1] = (tx_blink != 32'd0) ? 1'b0 : 1'b1;
    assign led[2] = error_seen ? 1'b0 : 1'b1;
    assign led[3] = heartbeat[23] ? 1'b0 : 1'b1;
endmodule
