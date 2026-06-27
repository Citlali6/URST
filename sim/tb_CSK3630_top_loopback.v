`timescale 1ns/1ps

module tb_CSK3630_top_loopback;
    reg clk_50m;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    wire seg7_sclk;
    wire seg7_dio;
    wire seg7_rclk;
    wire [3:0] led;
    wire mon_tick_16x;
    wire [7:0] mon_rx_data;
    wire mon_rx_valid;
    wire mon_frame_error;

    reg [7:0] captured [0:7];
    integer captured_count;
    reg clear_capture;

    CSK3630_UART #(
        .CLOCK_FREQ(1600),
        .BAUD_RATE(100)
    ) dut (
        .clk_50m(clk_50m),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .seg7_sclk(seg7_sclk),
        .seg7_dio(seg7_dio),
        .seg7_rclk(seg7_rclk),
        .led(led)
    );

    CSK3630_baud_gen #(
        .CLOCK_FREQ(1600),
        .BAUD_RATE(100),
        .OVERSAMPLE(16)
    ) u_monitor_baud (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick(mon_tick_16x)
    );

    CSK3630_uart_rx u_monitor_rx (
        .clk(clk_50m),
        .rst_n(rst_n),
        .tick_16x(mon_tick_16x),
        .rx(uart_tx),
        .data(mon_rx_data),
        .data_valid(mon_rx_valid),
        .frame_error(mon_frame_error)
    );

    initial begin
        clk_50m = 1'b0;
        forever #5 clk_50m = ~clk_50m;
    end

    task wait_clocks;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk_50m);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] value;
        integer bit_index;
        begin
            uart_rx = 1'b0;
            wait_clocks(16);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                wait_clocks(16);
            end
            uart_rx = 1'b1;
            wait_clocks(16);
        end
    endtask

    always @(posedge clk_50m) begin
        if (!rst_n || clear_capture) begin
            captured_count <= 0;
        end else if (mon_rx_valid) begin
            captured[captured_count] <= mon_rx_data;
            captured_count <= captured_count + 1;
        end
    end

    task reset_capture;
        begin
            clear_capture = 1'b1;
            @(posedge clk_50m);
            clear_capture = 1'b0;
            wait_clocks(1);
        end
    endtask

    task wait_response_count;
        input integer expected_count;
        integer timeout;
        begin
            timeout = 0;
            while (captured_count < expected_count && timeout < 5000) begin
                wait_clocks(1);
                timeout = timeout + 1;
            end
            if (timeout >= 5000) begin
                $display("FAIL: timed out waiting for top UART response start bit");
                $display("      captured_count=%0d mon_valid=%0b mon_data=%02h mon_frame_error=%0b", captured_count, mon_rx_valid, mon_rx_data, mon_frame_error);
                $display("      rx_valid=%0b rx_data=%02h frame_error=%0b state=%0d last_rx=%02h last_tx=%02h req_cmd=%02h req_addr=%02h req_len=%02h req_crc=%02h sending=%0b tx_start=%0b tx_busy=%0b uart_tx=%0b",
                         dut.rx_valid, dut.rx_data, dut.rx_frame_error,
                         dut.u_protocol.parse_state, dut.u_protocol.last_rx_byte,
                         dut.u_protocol.last_tx_byte,
                         dut.u_protocol.req_cmd, dut.u_protocol.req_addr,
                         dut.u_protocol.req_len, dut.u_protocol.req_crc,
                         dut.u_protocol.sending, dut.tx_start, dut.tx_busy, uart_tx);
                $finish;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        uart_rx = 1'b1;
        clear_capture = 1'b0;
        wait_clocks(12);
        rst_n = 1'b1;
        wait_clocks(24);

        reset_capture();
        send_uart_byte(8'h5A);
        wait_response_count(1);
        if (captured[0] !== 8'h5A) begin
            $display("FAIL: top single-byte echo expected 5A got %02h", captured[0]);
            $finish;
        end

        reset_capture();
        send_uart_byte(8'h55);
        send_uart_byte(8'hA1);
        send_uart_byte(8'h03);
        send_uart_byte(8'h5A);
        send_uart_byte(8'hF9);
        wait_response_count(1);
        if (captured[0] !== 8'h06) begin
            $display("FAIL: top simple WRITE expected ACK 06 got %02h", captured[0]);
            $finish;
        end
        if (dut.u_seg7.hex_digits[31:16] !== 16'h5A06) begin
            $display("FAIL: display should show RX/TX as 5A06 after simple WRITE, got %04h",
                     dut.u_seg7.hex_digits[31:16]);
            $finish;
        end

        reset_capture();
        send_uart_byte(8'h55);
        send_uart_byte(8'hA2);
        send_uart_byte(8'h03);
        send_uart_byte(8'h00);
        send_uart_byte(8'hA1);
        wait_response_count(1);
        if (captured[0] !== 8'h5A) begin
            $display("FAIL: top simple READ expected 5A got %02h", captured[0]);
            $finish;
        end

        reset_capture();
        send_uart_byte(8'h55);
        send_uart_byte(8'hAA);
        send_uart_byte(8'h04);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);
        send_uart_byte(8'h04);

        wait_response_count(7);

        if (captured[0] !== 8'h55 || captured[1] !== 8'hAA ||
            captured[2] !== 8'h80 || captured[3] !== 8'h00 ||
            captured[4] !== 8'h01 || captured[5] !== 8'h5A ||
            captured[6] !== 8'hDB) begin
            $display("FAIL: top PING response got %02h %02h %02h %02h %02h %02h %02h",
                     captured[0], captured[1], captured[2], captured[3],
                     captured[4], captured[5], captured[6]);
            $finish;
        end

        if (led[2] !== 1'b1) begin
            $display("FAIL: error LED should be off after valid PING");
            $finish;
        end

        $display("PASS: top UART loopback");
        $finish;
    end
endmodule
