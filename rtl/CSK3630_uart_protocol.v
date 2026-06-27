module CSK3630_uart_protocol #(
    parameter integer BYTE_TIMEOUT_CLKS = 5208
) (
    input wire clk,
    input wire rst_n,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire tx_busy,
    output reg [7:0] tx_data,
    output reg tx_start,
    output reg [7:0] last_rx_byte,
    output reg [7:0] last_tx_byte,
    output reg [7:0] last_cmd,
    output reg [7:0] last_addr,
    output reg [3:0] display_status,
    output reg error_seen
);
    localparam [3:0] P_WAIT_BYTE   = 4'd0;
    localparam [3:0] P_AFTER_55    = 4'd1;
    localparam [3:0] P_EXT_CMD     = 4'd2;
    localparam [3:0] P_EXT_ADDR    = 4'd3;
    localparam [3:0] P_EXT_LEN     = 4'd4;
    localparam [3:0] P_EXT_DATA    = 4'd5;
    localparam [3:0] P_EXT_CRC     = 4'd6;
    localparam [3:0] P_SIMPLE_ADDR = 4'd7;
    localparam [3:0] P_SIMPLE_DATA = 4'd8;
    localparam [3:0] P_SIMPLE_CRC  = 4'd9;

    localparam [7:0] CMD_WRITE     = 8'h01;
    localparam [7:0] CMD_READ      = 8'h02;
    localparam [7:0] CMD_ERASE_ALL = 8'h03;
    localparam [7:0] CMD_PING      = 8'h04;
    localparam [7:0] CMD_SIMPLE_WRITE = 8'hA1;
    localparam [7:0] CMD_SIMPLE_READ  = 8'hA2;
    localparam [7:0] CMD_SIMPLE_ERASE = 8'hA3;

    localparam [7:0] ST_ACK      = 8'h80;
    localparam [7:0] ST_DATA     = 8'h81;
    localparam [7:0] ST_BAD_CRC  = 8'hE0;
    localparam [7:0] ST_BAD_CMD  = 8'hE1;
    localparam [7:0] ST_BAD_ADDR = 8'hE2;
    localparam [7:0] ST_BAD_LEN  = 8'hE3;
    localparam [7:0] SIMPLE_ACK  = 8'h06;
    localparam [7:0] SIMPLE_NACK = 8'h15;

    reg [3:0] parse_state;
    reg [7:0] req_cmd;
    reg [7:0] req_addr;
    reg [7:0] req_len;
    reg [7:0] req_crc;
    reg [7:0] simple_data;
    reg [4:0] data_index;
    reg [31:0] pending_55_count;

    reg [7:0] req_payload [0:15];
    reg [7:0] store_mem [0:15];
    reg [7:0] rsp_buf [0:21];
    reg [4:0] rsp_count;
    reg [4:0] rsp_index;
    reg sending;
    reg [1:0] tx_flow_state;

    function automatic [3:0] status_digit;
        input [7:0] status;
        begin
            case (status)
                ST_ACK:      status_digit = 4'hA;
                ST_DATA:     status_digit = 4'hD;
                ST_BAD_CRC:  status_digit = 4'hC;
                ST_BAD_CMD:  status_digit = 4'h1;
                ST_BAD_ADDR: status_digit = 4'h2;
                ST_BAD_LEN:  status_digit = 4'h3;
                default:     status_digit = 4'hF;
            endcase
        end
    endfunction

    function automatic simple_checksum_ok;
        input [7:0] cmd;
        input [7:0] addr;
        input [7:0] data;
        input [7:0] check_byte;
        reg [7:0] expected;
        begin
            expected = cmd ^ addr ^ data;
            simple_checksum_ok = (check_byte == expected) ||
                ((cmd == CMD_SIMPLE_WRITE) && (check_byte == (expected + 8'h01)));
        end
    endfunction

    function automatic address_range_ok;
        input [7:0] addr;
        input [7:0] len;
        reg [4:0] end_addr;
        begin
            end_addr = {1'b0, addr[3:0]} + len[4:0];
            address_range_ok = (len != 8'd0) && (len <= 8'd16) && (addr < 8'd16) && (end_addr <= 5'd16);
        end
    endfunction

    task automatic mark_status;
        input [7:0] status;
        begin
            display_status <= status_digit(status);
            if (status[7:4] == 4'hE) begin
                error_seen <= 1'b1;
            end
        end
    endtask

    task automatic start_response_no_data;
        input [7:0] status;
        input [7:0] addr;
        reg [7:0] crc;
        begin
            crc = status ^ addr ^ 8'h00;
            rsp_buf[0] <= 8'h55;
            rsp_buf[1] <= 8'hAA;
            rsp_buf[2] <= status;
            rsp_buf[3] <= addr;
            rsp_buf[4] <= 8'h00;
            rsp_buf[5] <= crc;
            rsp_count <= 5'd6;
            rsp_index <= 5'd0;
            sending <= 1'b1;
            mark_status(status);
        end
    endtask

    task automatic start_response_byte;
        input [7:0] value;
        input [3:0] status_value;
        begin
            rsp_buf[0] <= value;
            rsp_count <= 5'd1;
            rsp_index <= 5'd0;
            sending <= 1'b1;
            display_status <= status_value;
            if (value == SIMPLE_NACK) begin
                error_seen <= 1'b1;
            end
        end
    endtask

    task automatic start_response_two_bytes;
        input [7:0] first_value;
        input [7:0] second_value;
        begin
            rsp_buf[0] <= first_value;
            rsp_buf[1] <= second_value;
            rsp_count <= 5'd2;
            rsp_index <= 5'd0;
            sending <= 1'b1;
            display_status <= 4'hE;
        end
    endtask

    task automatic start_response_ping;
        reg [7:0] crc;
        begin
            crc = ST_ACK ^ 8'h00 ^ 8'h01 ^ 8'h5A;
            rsp_buf[0] <= 8'h55;
            rsp_buf[1] <= 8'hAA;
            rsp_buf[2] <= ST_ACK;
            rsp_buf[3] <= 8'h00;
            rsp_buf[4] <= 8'h01;
            rsp_buf[5] <= 8'h5A;
            rsp_buf[6] <= crc;
            rsp_count <= 5'd7;
            rsp_index <= 5'd0;
            sending <= 1'b1;
            mark_status(ST_ACK);
        end
    endtask

    task automatic start_response_read;
        input [7:0] addr;
        input [4:0] len;
        reg [7:0] crc;
        integer r;
        begin
            crc = ST_DATA ^ addr ^ {3'b000, len};
            rsp_buf[0] <= 8'h55;
            rsp_buf[1] <= 8'hAA;
            rsp_buf[2] <= ST_DATA;
            rsp_buf[3] <= addr;
            rsp_buf[4] <= {3'b000, len};
            for (r = 0; r < 16; r = r + 1) begin
                if (r < len) begin
                    rsp_buf[5 + r] <= store_mem[addr[3:0] + r];
                    crc = crc ^ store_mem[addr[3:0] + r];
                end
            end
            rsp_buf[5 + len] <= crc;
            rsp_count <= len + 5'd6;
            rsp_index <= 5'd0;
            sending <= 1'b1;
            mark_status(ST_DATA);
        end
    endtask

    task automatic handle_good_frame;
        begin
            case (req_cmd)
                CMD_PING: begin
                    if (req_len == 8'd0) begin
                        start_response_ping();
                    end else begin
                        start_response_no_data(ST_BAD_LEN, req_addr);
                    end
                end

                CMD_WRITE: begin
                    if (address_range_ok(req_addr, req_len)) begin
                        if (req_len > 8'd0)  store_mem[{1'b0, req_addr[3:0]} + 5'd0]  <= req_payload[0];
                        if (req_len > 8'd1)  store_mem[{1'b0, req_addr[3:0]} + 5'd1]  <= req_payload[1];
                        if (req_len > 8'd2)  store_mem[{1'b0, req_addr[3:0]} + 5'd2]  <= req_payload[2];
                        if (req_len > 8'd3)  store_mem[{1'b0, req_addr[3:0]} + 5'd3]  <= req_payload[3];
                        if (req_len > 8'd4)  store_mem[{1'b0, req_addr[3:0]} + 5'd4]  <= req_payload[4];
                        if (req_len > 8'd5)  store_mem[{1'b0, req_addr[3:0]} + 5'd5]  <= req_payload[5];
                        if (req_len > 8'd6)  store_mem[{1'b0, req_addr[3:0]} + 5'd6]  <= req_payload[6];
                        if (req_len > 8'd7)  store_mem[{1'b0, req_addr[3:0]} + 5'd7]  <= req_payload[7];
                        if (req_len > 8'd8)  store_mem[{1'b0, req_addr[3:0]} + 5'd8]  <= req_payload[8];
                        if (req_len > 8'd9)  store_mem[{1'b0, req_addr[3:0]} + 5'd9]  <= req_payload[9];
                        if (req_len > 8'd10) store_mem[{1'b0, req_addr[3:0]} + 5'd10] <= req_payload[10];
                        if (req_len > 8'd11) store_mem[{1'b0, req_addr[3:0]} + 5'd11] <= req_payload[11];
                        if (req_len > 8'd12) store_mem[{1'b0, req_addr[3:0]} + 5'd12] <= req_payload[12];
                        if (req_len > 8'd13) store_mem[{1'b0, req_addr[3:0]} + 5'd13] <= req_payload[13];
                        if (req_len > 8'd14) store_mem[{1'b0, req_addr[3:0]} + 5'd14] <= req_payload[14];
                        if (req_len > 8'd15) store_mem[{1'b0, req_addr[3:0]} + 5'd15] <= req_payload[15];
                        start_response_no_data(ST_ACK, req_addr);
                    end else begin
                        start_response_no_data(ST_BAD_ADDR, req_addr);
                    end
                end

                CMD_READ: begin
                    if (address_range_ok(req_addr, req_len)) begin
                        start_response_read(req_addr, req_len[4:0]);
                    end else begin
                        start_response_no_data(ST_BAD_ADDR, req_addr);
                    end
                end

                CMD_ERASE_ALL: begin
                    if (req_len == 8'd0) begin
                        store_mem[0] <= 8'h00;
                        store_mem[1] <= 8'h00;
                        store_mem[2] <= 8'h00;
                        store_mem[3] <= 8'h00;
                        store_mem[4] <= 8'h00;
                        store_mem[5] <= 8'h00;
                        store_mem[6] <= 8'h00;
                        store_mem[7] <= 8'h00;
                        store_mem[8] <= 8'h00;
                        store_mem[9] <= 8'h00;
                        store_mem[10] <= 8'h00;
                        store_mem[11] <= 8'h00;
                        store_mem[12] <= 8'h00;
                        store_mem[13] <= 8'h00;
                        store_mem[14] <= 8'h00;
                        store_mem[15] <= 8'h00;
                        start_response_no_data(ST_ACK, 8'h00);
                    end else begin
                        start_response_no_data(ST_BAD_LEN, req_addr);
                    end
                end

                default: begin
                    start_response_no_data(ST_BAD_CMD, req_addr);
                end
            endcase
        end
    endtask

    task automatic handle_simple_frame;
        begin
            if (!simple_checksum_ok(req_cmd, req_addr, simple_data, rx_data) || req_addr >= 8'd16) begin
                start_response_byte(SIMPLE_NACK, 4'hC);
            end else begin
                case (req_cmd)
                    CMD_SIMPLE_WRITE: begin
                        store_mem[req_addr[3:0]] <= simple_data;
                        last_rx_byte <= simple_data;
                        start_response_byte(SIMPLE_ACK, 4'hA);
                    end

                    CMD_SIMPLE_READ: begin
                        last_rx_byte <= store_mem[req_addr[3:0]];
                        start_response_byte(store_mem[req_addr[3:0]], 4'hD);
                    end

                    CMD_SIMPLE_ERASE: begin
                        store_mem[req_addr[3:0]] <= 8'h00;
                        last_rx_byte <= simple_data;
                        start_response_byte(SIMPLE_ACK, 4'hA);
                    end

                    default: begin
                        start_response_byte(SIMPLE_NACK, 4'hC);
                    end
                endcase
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state <= P_WAIT_BYTE;
            req_cmd <= 8'h00;
            req_addr <= 8'h00;
            req_len <= 8'h00;
            req_crc <= 8'h00;
            simple_data <= 8'h00;
            data_index <= 5'd0;
            pending_55_count <= 32'd0;
            tx_data <= 8'hFF;
            tx_start <= 1'b0;
            last_rx_byte <= 8'h00;
            last_tx_byte <= 8'h00;
            last_cmd <= 8'h00;
            last_addr <= 8'h00;
            display_status <= 4'h0;
            error_seen <= 1'b0;
            rsp_count <= 5'd0;
            rsp_index <= 5'd0;
            sending <= 1'b0;
            tx_flow_state <= 2'd0;
            req_payload[0] <= 8'h00;
            req_payload[1] <= 8'h00;
            req_payload[2] <= 8'h00;
            req_payload[3] <= 8'h00;
            req_payload[4] <= 8'h00;
            req_payload[5] <= 8'h00;
            req_payload[6] <= 8'h00;
            req_payload[7] <= 8'h00;
            req_payload[8] <= 8'h00;
            req_payload[9] <= 8'h00;
            req_payload[10] <= 8'h00;
            req_payload[11] <= 8'h00;
            req_payload[12] <= 8'h00;
            req_payload[13] <= 8'h00;
            req_payload[14] <= 8'h00;
            req_payload[15] <= 8'h00;
            store_mem[0] <= 8'h00;
            store_mem[1] <= 8'h00;
            store_mem[2] <= 8'h00;
            store_mem[3] <= 8'h00;
            store_mem[4] <= 8'h00;
            store_mem[5] <= 8'h00;
            store_mem[6] <= 8'h00;
            store_mem[7] <= 8'h00;
            store_mem[8] <= 8'h00;
            store_mem[9] <= 8'h00;
            store_mem[10] <= 8'h00;
            store_mem[11] <= 8'h00;
            store_mem[12] <= 8'h00;
            store_mem[13] <= 8'h00;
            store_mem[14] <= 8'h00;
            store_mem[15] <= 8'h00;
            rsp_buf[0] <= 8'h00;
            rsp_buf[1] <= 8'h00;
            rsp_buf[2] <= 8'h00;
            rsp_buf[3] <= 8'h00;
            rsp_buf[4] <= 8'h00;
            rsp_buf[5] <= 8'h00;
            rsp_buf[6] <= 8'h00;
            rsp_buf[7] <= 8'h00;
            rsp_buf[8] <= 8'h00;
            rsp_buf[9] <= 8'h00;
            rsp_buf[10] <= 8'h00;
            rsp_buf[11] <= 8'h00;
            rsp_buf[12] <= 8'h00;
            rsp_buf[13] <= 8'h00;
            rsp_buf[14] <= 8'h00;
            rsp_buf[15] <= 8'h00;
            rsp_buf[16] <= 8'h00;
            rsp_buf[17] <= 8'h00;
            rsp_buf[18] <= 8'h00;
            rsp_buf[19] <= 8'h00;
            rsp_buf[20] <= 8'h00;
            rsp_buf[21] <= 8'h00;
        end else begin
            tx_start <= 1'b0;

            if (tx_flow_state == 2'd1 && tx_busy) begin
                tx_flow_state <= 2'd2;
            end else if (tx_flow_state == 2'd2 && !tx_busy) begin
                tx_flow_state <= 2'd0;
            end

            if (sending && (tx_flow_state == 2'd0) && !tx_busy) begin
                tx_data <= rsp_buf[rsp_index];
                last_tx_byte <= rsp_buf[rsp_index];
                tx_start <= 1'b1;
                tx_flow_state <= 2'd1;
                if (rsp_index == (rsp_count - 5'd1)) begin
                    sending <= 1'b0;
                    rsp_index <= 5'd0;
                end else begin
                    rsp_index <= rsp_index + 5'd1;
                end
            end

            if (!sending && parse_state == P_AFTER_55 && !rx_valid) begin
                if (pending_55_count >= (BYTE_TIMEOUT_CLKS - 1)) begin
                    start_response_byte(8'h55, 4'hE);
                    parse_state <= P_WAIT_BYTE;
                    pending_55_count <= 32'd0;
                end else begin
                    pending_55_count <= pending_55_count + 32'd1;
                end
            end

            if (rx_valid && !sending) begin
                last_rx_byte <= rx_data;
                case (parse_state)
                    P_WAIT_BYTE: begin
                        if (rx_data == 8'h55) begin
                            pending_55_count <= 32'd0;
                            parse_state <= P_AFTER_55;
                        end else begin
                            start_response_byte(rx_data, 4'hE);
                        end
                    end

                    P_AFTER_55: begin
                        if (rx_data == 8'hAA) begin
                            req_crc <= 8'h00;
                            pending_55_count <= 32'd0;
                            parse_state <= P_EXT_CMD;
                        end else if (rx_data == CMD_SIMPLE_WRITE || rx_data == CMD_SIMPLE_READ || rx_data == CMD_SIMPLE_ERASE) begin
                            req_cmd <= rx_data;
                            last_cmd <= rx_data;
                            pending_55_count <= 32'd0;
                            parse_state <= P_SIMPLE_ADDR;
                        end else if (rx_data == 8'h55) begin
                            start_response_byte(8'h55, 4'hE);
                            pending_55_count <= 32'd0;
                            parse_state <= P_AFTER_55;
                        end else begin
                            start_response_two_bytes(8'h55, rx_data);
                            pending_55_count <= 32'd0;
                            parse_state <= P_WAIT_BYTE;
                        end
                    end

                    P_EXT_CMD: begin
                        req_cmd <= rx_data;
                        last_cmd <= rx_data;
                        req_crc <= rx_data;
                        parse_state <= P_EXT_ADDR;
                    end

                    P_EXT_ADDR: begin
                        req_addr <= rx_data;
                        last_addr <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        parse_state <= P_EXT_LEN;
                    end

                    P_EXT_LEN: begin
                        req_len <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        data_index <= 5'd0;
                        if (rx_data == 8'h00) begin
                            parse_state <= P_EXT_CRC;
                        end else if (rx_data <= 8'd16) begin
                            if (req_cmd == CMD_READ) begin
                                parse_state <= P_EXT_CRC;
                            end else begin
                                parse_state <= P_EXT_DATA;
                            end
                        end else begin
                            start_response_no_data(ST_BAD_LEN, req_addr);
                            parse_state <= P_WAIT_BYTE;
                        end
                    end

                    P_EXT_DATA: begin
                        req_payload[data_index] <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        if (data_index == (req_len[4:0] - 5'd1)) begin
                            parse_state <= P_EXT_CRC;
                        end else begin
                            data_index <= data_index + 5'd1;
                        end
                    end

                    P_EXT_CRC: begin
                        if (rx_data == req_crc) begin
                            handle_good_frame();
                        end else begin
                            start_response_no_data(ST_BAD_CRC, req_addr);
                        end
                        parse_state <= P_WAIT_BYTE;
                    end

                    P_SIMPLE_ADDR: begin
                        req_addr <= rx_data;
                        last_addr <= rx_data;
                        parse_state <= P_SIMPLE_DATA;
                    end

                    P_SIMPLE_DATA: begin
                        simple_data <= rx_data;
                        parse_state <= P_SIMPLE_CRC;
                    end

                    P_SIMPLE_CRC: begin
                        handle_simple_frame();
                        parse_state <= P_WAIT_BYTE;
                    end

                    default: begin
                        parse_state <= P_WAIT_BYTE;
                    end
                endcase
            end
        end
    end
endmodule
