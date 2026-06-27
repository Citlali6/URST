`timescale 1ns/1ps

module tb_CSK3630_protocol;
    reg clk;
    reg rst_n;
    reg [7:0] rx_data;
    reg rx_valid;
    reg tx_busy;
    wire [7:0] tx_data;
    wire tx_start;
    wire [7:0] last_rx_byte;
    wire [7:0] last_tx_byte;
    wire [7:0] last_cmd;
    wire [7:0] last_addr;
    wire [3:0] display_status;
    wire error_seen;

    reg [7:0] captured [0:31];
    integer captured_count;
    reg clear_capture;

    CSK3630_uart_protocol u_protocol (
        .clk(clk),
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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n || clear_capture) begin
            captured_count <= 0;
            tx_busy <= 1'b0;
        end else begin
            tx_busy <= tx_start;
            if (tx_start) begin
                captured[captured_count] <= tx_data;
                captured_count <= captured_count + 1;
            end
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

    task reset_capture;
        begin
            clear_capture = 1'b1;
            @(posedge clk);
            clear_capture = 1'b0;
            wait_clocks(1);
        end
    endtask

    task wait_response_count;
        input integer expected_count;
        integer timeout;
        begin
            timeout = 0;
            while (captured_count < expected_count && timeout < 80) begin
                wait_clocks(1);
                timeout = timeout + 1;
            end
        end
    endtask

    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            rx_data = value;
            rx_valid = 1'b1;
            @(negedge clk);
            rx_valid = 1'b0;
            wait_clocks(1);
        end
    endtask

    task expect_response_7;
        input [7:0] b0;
        input [7:0] b1;
        input [7:0] b2;
        input [7:0] b3;
        input [7:0] b4;
        input [7:0] b5;
        input [7:0] b6;
        begin
            wait_response_count(7);
            if (captured_count !== 7 ||
                captured[0] !== b0 || captured[1] !== b1 || captured[2] !== b2 ||
                captured[3] !== b3 || captured[4] !== b4 || captured[5] !== b5 ||
                captured[6] !== b6) begin
                $display("FAIL: expected 7-byte response %02h %02h %02h %02h %02h %02h %02h", b0,b1,b2,b3,b4,b5,b6);
                $display("      got count=%0d %02h %02h %02h %02h %02h %02h %02h",
                         captured_count, captured[0], captured[1], captured[2],
                         captured[3], captured[4], captured[5], captured[6]);
                $display("      state=%0d sending=%0b req_cmd=%02h req_addr=%02h req_len=%02h req_crc=%02h last_rx=%02h",
                         u_protocol.parse_state, u_protocol.sending, u_protocol.req_cmd,
                         u_protocol.req_addr, u_protocol.req_len, u_protocol.req_crc, last_rx_byte);
                $finish;
            end
        end
    endtask

    task expect_response_6;
        input [7:0] b0;
        input [7:0] b1;
        input [7:0] b2;
        input [7:0] b3;
        input [7:0] b4;
        input [7:0] b5;
        begin
            wait_response_count(6);
            if (captured_count !== 6 ||
                captured[0] !== b0 || captured[1] !== b1 || captured[2] !== b2 ||
                captured[3] !== b3 || captured[4] !== b4 || captured[5] !== b5) begin
                $display("FAIL: expected 6-byte response %02h %02h %02h %02h %02h %02h", b0,b1,b2,b3,b4,b5);
                $display("      got count=%0d %02h %02h %02h %02h %02h %02h",
                         captured_count, captured[0], captured[1], captured[2],
                         captured[3], captured[4], captured[5]);
                $finish;
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        rx_data = 8'h00;
        rx_valid = 1'b0;
        tx_busy = 1'b0;
        clear_capture = 1'b0;
        wait_clocks(5);
        rst_n = 1'b1;
        wait_clocks(2);

        reset_capture();
        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h04);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h04);
        expect_response_7(8'h55, 8'hAA, 8'h80, 8'h00, 8'h01, 8'h5A, 8'hDB);

        reset_capture();
        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h01);
        send_byte(8'hA5);
        send_byte(8'hA7);
        expect_response_6(8'h55, 8'hAA, 8'h80, 8'h02, 8'h00, 8'h82);

        reset_capture();
        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h02);
        send_byte(8'h02);
        send_byte(8'h01);
        send_byte(8'h01);
        expect_response_7(8'h55, 8'hAA, 8'h81, 8'h02, 8'h01, 8'hA5, 8'h27);

        reset_capture();
        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h04);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h05);
        expect_response_6(8'h55, 8'hAA, 8'hE0, 8'h00, 8'h00, 8'hE0);
        if (display_status !== 4'hC || error_seen !== 1'b1) begin
            $display("FAIL: bad CRC should set display_status=C and error_seen=1");
            $finish;
        end

        $display("PASS: UART protocol");
        $finish;
    end
endmodule
