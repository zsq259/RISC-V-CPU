module MemoryController (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire RoB_clear,

    input wire        waiting,  // waiting for work
    input wire        wr,       // write/read signal (1 for write)
    input wire [ 2:0] len,      // length of data to be read/written 
    // 0: 1 byte, 1: 2 bytes, 2: 4 bytes
    // len[2]: signed or unsigned
    input wire [31:0] addr,     // address bus (only 17:0 is used)
    input wire [31:0] value,    // value to be written

    output wire        ready,  // ready to work
    output wire [31:0] result  // result of read operation
);

    // work_*** is the work to be done
    reg         work_wr;
    reg  [ 2:0] work_len;
    reg  [31:0] work_addr;
    reg  [31:0] work_value;

    // working state
    wire        need_work;
    wire        first_cycle;
    reg         busy;
    reg  [ 2:0] state;
    reg  [31:0] res;

    // current working
    reg         current_wr;
    reg  [31:0] current_addr;
    reg  [ 7:0] current_value;

    assign ready = !busy && state == 0 && work_wr == wr && work_len == len && work_addr == addr && work_value == value;
    assign result = sign_extend(len, mem_din, res);

    assign need_work = waiting && !ready;
    assign first_cycle = state == 0 && need_work;

    assign mem_wr = first_cycle ? wr : current_wr;
    assign mem_a = first_cycle ? addr : current_addr;
    assign mem_dout = first_cycle ? value[7:0] : current_value;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            // $display("reset");
            work_wr <= 0;
            work_len <= 0;
            work_addr <= 0;
            work_value <= 0;
            busy <= 1;
            state <= 0;
            res <= 0;
            current_wr <= 0;
            current_addr <= 0;
            current_value <= 0;
        end
        else if (rdy_in) begin
            if (waiting) begin
                // $display("state: %d, res: %h, m_din: %h, work_addr: %d, cur_addr: %d, addr: %d", state, res, mem_din, work_addr, current_addr, addr);    
            end

            case (state)
                3'b000: begin
                    if (need_work) begin  // start working                        
                        work_wr <= wr;
                        work_len <= len;
                        work_addr <= addr;
                        work_value <= value;
                        if (len[1:0]) begin
                            state <= 3'b001;
                            busy <= 1;
                            current_wr <= wr;
                            current_addr <= addr + 1;
                            current_value <= value[15:8];
                        end
                        else begin
                            state <= 3'b000;
                            busy <= 0;
                            current_wr <= 0;
                            current_value <= 0;
                            // special case: addr[17:16] == 2'b11
                            // otherwise, keep addr
                            current_addr <= addr[17:16] == 2'b11 ? 0 : addr;
                        end
                    end
                end
                3'b001: begin
                    if (work_len[1:0] == 2'b00) begin
                        state <= 3'b000;
                        busy <= 0;
                        current_wr <= 0;
                        current_value <= 0;
                    end
                    else begin
                        state <= 3'b010;
                        res[7:0] <= mem_din;
                        current_addr <= work_addr + 2;
                        current_value <= work_value[23:16];
                    end
                end
                3'b010: begin
                    if (work_len[1:0] == 2'b01) begin
                        state <= 3'b000;
                        busy <= 0;
                        current_wr <= 0;
                        current_value <= 0;
                    end
                    else begin
                        state <= 3'b011;
                        res[15:8] <= mem_din;
                        current_addr <= work_addr + 3;
                        current_value <= work_value[31:24];
                    end
                end
                3'b011: begin
                    state <= 3'b000;
                    busy <= 0;
                    res[23:16] <= mem_din;
                    current_wr <= 0;
                    current_value <= 0;
                end
            endcase
        end
    end

    function [31:0] sign_extend;
        input [2:0] len;
        input [7:0] mem_din;
        input [31:0] value;
        case (len)
            3'b000:  sign_extend = {24'b0, mem_din};
            3'b100:  sign_extend = {{24{mem_din[7]}}, mem_din};
            3'b001:  sign_extend = {16'b0, mem_din[7:0], value[7:0]};
            3'b101:  sign_extend = {{16{mem_din[7]}}, mem_din[7:0], value[7:0]};
            3'b010:  sign_extend = {mem_din[7:0], value[23:0]};
            3'b110:  sign_extend = {mem_din[7:0], value[23:0]};
            default: sign_extend = 0;
        endcase
    endfunction
endmodule
