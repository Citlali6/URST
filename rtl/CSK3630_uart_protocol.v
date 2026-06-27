module CSK3630_uart_protocol (
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
    localparam [2:0] P_WAIT_55 = 3'd0;
    localparam [2:0] P_WAIT_AA = 3'd1;
    localparam [2:0] P_CMD     = 3'd2;
    localparam [2:0] P_ADDR    = 3'd3;
    localparam [2:0] P_LEN     = 3'd4;
    localparam [2:0] P_DATA    = 3'd5;
    localparam [2:0] P_CRC     = 3'd6;

    localparam [7:0] CMD_WRITE     = 8'h01;
    localparam [7:0] CMD_READ      = 8'h02;
    localparam [7:0] CMD_ERASE_ALL = 8'h03;
    localparam [7:0] CMD_PING      = 8'h04;

    localparam [7:0] ST_ACK      = 8'h80;
    localparam [7:0] ST_DATA     = 8'h81;
    localparam [7:0] ST_BAD_CRC  = 8'hE0;
    localparam [7:0] ST_BAD_CMD  = 8'hE1;
    localparam [7:0] ST_BAD_ADDR = 8'hE2;
    localparam [7:0] ST_BAD_LEN  = 8'hE3;

    reg [2:0] parse_state;
    reg [7:0] req_cmd;
    reg [7:0] req_addr;
    reg [7:0] req_len;
    reg [7:0] req_crc;
    reg [4:0] data_index;

    reg [7:0] req_payload [0:15];
    reg [7:0] store_mem [0:15];
    reg [7:0] rsp_buf [0:21];
    reg [4:0] rsp_count;
    reg [4:0] rsp_index;
    reg sending;
    reg [1:0] tx_flow_state;

    integer i;

    function [3:0] status_digit;
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

    function address_range_ok;
        input [7:0] addr;
        input [7:0] len;
        reg [4:0] end_addr;
        begin
            end_addr = {1'b0, addr[3:0]} + len[4:0];
            address_range_ok = (len != 8'd0) && (len <= 8'd16) && (addr < 8'd16) && (end_addr <= 5'd16);
        end
    endfunction

    task mark_status;
        input [7:0] status;
        begin
            display_status <= status_digit(status);
            if (status[7:4] == 4'hE) begin
                error_seen <= 1'b1;
            end
        end
    endtask

    task start_response_no_data;
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

    task start_response_ping;
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

    task start_response_read;
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

    task handle_good_frame;
        integer h;
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
                        for (h = 0; h < 16; h = h + 1) begin
                            if (h < req_len) begin
                                store_mem[req_addr[3:0] + h] <= req_payload[h];
                            end
                        end
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
                        for (h = 0; h < 16; h = h + 1) begin
                            store_mem[h] <= 8'h00;
                        end
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state <= P_WAIT_55;
            req_cmd <= 8'h00;
            req_addr <= 8'h00;
            req_len <= 8'h00;
            req_crc <= 8'h00;
            data_index <= 5'd0;
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
            for (i = 0; i < 16; i = i + 1) begin
                req_payload[i] <= 8'h00;
                store_mem[i] <= 8'h00;
            end
            for (i = 0; i < 22; i = i + 1) begin
                rsp_buf[i] <= 8'h00;
            end
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

            if (rx_valid && !sending) begin
                last_rx_byte <= rx_data;
                case (parse_state)
                    P_WAIT_55: begin
                        if (rx_data == 8'h55) begin
                            parse_state <= P_WAIT_AA;
                        end
                    end

                    P_WAIT_AA: begin
                        if (rx_data == 8'hAA) begin
                            req_crc <= 8'h00;
                            parse_state <= P_CMD;
                        end else if (rx_data != 8'h55) begin
                            parse_state <= P_WAIT_55;
                        end
                    end

                    P_CMD: begin
                        req_cmd <= rx_data;
                        last_cmd <= rx_data;
                        req_crc <= rx_data;
                        parse_state <= P_ADDR;
                    end

                    P_ADDR: begin
                        req_addr <= rx_data;
                        last_addr <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        parse_state <= P_LEN;
                    end

                    P_LEN: begin
                        req_len <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        data_index <= 5'd0;
                        if (rx_data == 8'h00) begin
                            parse_state <= P_CRC;
                        end else if (rx_data <= 8'd16) begin
                            if (req_cmd == CMD_READ) begin
                                parse_state <= P_CRC;
                            end else begin
                                parse_state <= P_DATA;
                            end
                        end else begin
                            start_response_no_data(ST_BAD_LEN, req_addr);
                            parse_state <= P_WAIT_55;
                        end
                    end

                    P_DATA: begin
                        req_payload[data_index] <= rx_data;
                        req_crc <= req_crc ^ rx_data;
                        if (data_index == (req_len[4:0] - 5'd1)) begin
                            parse_state <= P_CRC;
                        end else begin
                            data_index <= data_index + 5'd1;
                        end
                    end

                    P_CRC: begin
                        if (rx_data == req_crc) begin
                            handle_good_frame();
                        end else begin
                            start_response_no_data(ST_BAD_CRC, req_addr);
                        end
                        parse_state <= P_WAIT_55;
                    end

                    default: begin
                        parse_state <= P_WAIT_55;
                    end
                endcase
            end
        end
    end
endmodule
