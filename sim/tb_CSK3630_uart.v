`timescale 1ns/1ps

module tb_CSK3630_uart;
    reg clk;
    reg rst_n;
    reg rx_line;
    reg tx_start;
    reg [7:0] tx_data;
    wire tick_16x;
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_error;
    wire tx_line;
    wire tx_busy;
    reg saw_rx_valid;
    reg [7:0] saw_rx_data;
    reg saw_rx_frame_error;

    CSK3630_baud_gen #(
        .CLOCK_FREQ(1600),
        .BAUD_RATE(100),
        .OVERSAMPLE(16)
    ) u_baud (
        .clk(clk),
        .rst_n(rst_n),
        .tick(tick_16x)
    );

    CSK3630_uart_rx u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .tick_16x(tick_16x),
        .rx(rx_line),
        .data(rx_data),
        .data_valid(rx_valid),
        .frame_error(rx_frame_error)
    );

    CSK3630_uart_tx u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tick_16x(tick_16x),
        .start(tx_start),
        .data(tx_data),
        .tx(tx_line),
        .busy(tx_busy)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            saw_rx_valid <= 1'b0;
            saw_rx_data <= 8'h00;
            saw_rx_frame_error <= 1'b0;
        end else if (rx_valid || rx_frame_error) begin
            saw_rx_valid <= rx_valid;
            saw_rx_data <= rx_data;
            saw_rx_frame_error <= rx_frame_error;
        end
    end

    task wait_clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task drive_rx_byte;
        input [7:0] value;
        integer bit_index;
        begin
            rx_line = 1'b0;
            wait_clocks(16);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx_line = value[bit_index];
                wait_clocks(16);
            end
            rx_line = 1'b1;
            wait_clocks(16);
        end
    endtask

    task expect_tx_byte;
        input [7:0] value;
        integer bit_index;
        integer timeout;
        begin
            timeout = 0;
            while (tx_line != 1'b0 && timeout < 200) begin
                wait_clocks(1);
                timeout = timeout + 1;
            end
            if (timeout >= 200) begin
                $display("FAIL: timed out waiting for tx start bit, tx_busy=%0b tx_line=%0b", tx_busy, tx_line);
                $finish;
            end
            wait_clocks(8);
            if (tx_line !== 1'b0) begin
                $display("FAIL: tx start bit was not low");
                $finish;
            end
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                wait_clocks(16);
                if (tx_line !== value[bit_index]) begin
                    $display("FAIL: tx bit %0d expected %0b got %0b", bit_index, value[bit_index], tx_line);
                    $finish;
                end
            end
            wait_clocks(16);
            if (tx_line !== 1'b1) begin
                $display("FAIL: tx stop bit was not high");
                $finish;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        rx_line = 1'b1;
        tx_start = 1'b0;
        tx_data = 8'h00;
        wait_clocks(8);
        rst_n = 1'b1;
        wait_clocks(8);

        drive_rx_byte(8'h3C);
        wait_clocks(4);
        if (saw_rx_valid !== 1'b1 || saw_rx_data !== 8'h3C || saw_rx_frame_error !== 1'b0) begin
            $display("FAIL: rx expected valid 3C without frame error, valid=%0b data=%02h frame_error=%0b",
                     saw_rx_valid, saw_rx_data, saw_rx_frame_error);
            $finish;
        end

        tx_data = 8'hA5;
        @(negedge clk);
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        expect_tx_byte(8'hA5);
        wait (tx_busy == 1'b0);

        $display("PASS: UART RX/TX");
        $finish;
    end
endmodule
