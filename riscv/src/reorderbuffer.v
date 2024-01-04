`include "const.v"

module ReorderBuffer #(
    parameter BITS = `RoB_BITS,
    parameter Size = `RoB_SIZE
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire issue_ready,
    input wire [31:0] inst,
    input wire [31:0] pc,
    input wire [31:0] pc_B_fail,  // what pc should be if branch fails
    input wire pred_res,  // prediction result

    input wire [6:0] opcode,
    input wire [4:0] rd,

    input wire RS_finish_rdy,
    input wire [BITS-1:0] RS_finish_id,
    input wire [31:0] RS_finish_value,

    input wire LSB_finish_rdy,
    input wire [BITS-1:0] LSB_finish_id,
    input wire [31:0] LSB_finish_value,

    output wire [BITS-1:0] RoB_id_1,  // boardcast after excute
    output wire [BITS-1:0] RoB_id_2,
    output wire RoB_rdy_1,
    output wire RoB_rdy_2,
    output wire [31:0] RoB_value_1,
    output wire [31:0] RoB_value_2,

    input wire [BITS-1:0] get_RoB_id_1,  // get value from RoB if q_i is not ready
    input wire [BITS-1:0] get_RoB_id_2,
    output wire RoB_busy_1,
    output wire RoB_busy_2,
    output wire [31:0] get_RoB_value_1,
    output wire [31:0] get_RoB_value_2,

    output wire [BITS-1:0] RoB_head,
    output wire [BITS-1:0] RoB_tail,
    output wire full,

    output wire [ 4:0] set_reg_id,
    output wire [31:0] set_reg_value,

    output wire [ 4:0] set_reg_q_1,  // q_i to be set from issue
    output wire [31:0] set_val_q_1,
    output wire [ 4:0] set_reg_q_2,  // q_i to be set from commit
    output wire [31:0] set_val_q_2,

    output wire RoB_clear,
    output wire [31:0] RoB_clear_pc_value,

    output reg stall
);
    reg [BITS-1:0] head;
    reg [BITS-1:0] tail;
    reg busy[Size-1:0];  // if the place is working
    reg free[Size-1:0];  // if the place is empty
    reg [31:0] value[Size-1:0];
    reg [31:0] dest[Size-1:0];
    reg [1:0] op[Size-1:0];  // 0: load, 1: store, 2: branch, 3: jalr
    reg [31:0] pc_jalr[Size-1:0];

    // reg [31:0] insts[Size-1:0];
    // reg [31:0] pcs[Size-1:0];

    wire is_J = opcode == 7'b1101111;
    wire is_B = opcode == 7'b1100011;
    wire is_S = opcode == 7'b0100011;
    wire is_jalr = opcode == 7'b1100111;

    assign RoB_head = head;
    assign RoB_tail = tail;
    assign full = head == tail && !free[head];

    assign RoB_id_1 = RS_finish_id;
    assign RoB_id_2 = LSB_finish_id;
    assign RoB_rdy_1 = RS_finish_rdy;
    assign RoB_rdy_2 = LSB_finish_rdy;
    assign RoB_value_1 = RS_finish_value;
    assign RoB_value_2 = LSB_finish_value;

    assign RoB_busy_1 = busy[get_RoB_id_1];
    assign RoB_busy_2 = busy[get_RoB_id_2];
    assign get_RoB_value_1 = value[get_RoB_id_1];
    assign get_RoB_value_2 = value[get_RoB_id_2];

    assign set_reg_id = (!free[head] && !busy[head] && (op[head] == 2'd0 || op[head] == 2'd3)) ? dest[head] : 0;
    assign set_reg_value = value[head];

    assign set_reg_q_1 = issue_ready ? ((is_B || is_S) ? 0 : rd) : 0;
    assign set_val_q_1 = tail;

    assign set_reg_q_2 = !free[head] && !busy[head] ? (op[head] ? 0 : dest[head]) : 0;
    assign set_val_q_2 = head;

    assign RoB_clear = !free[head] && !busy[head] && (op[head] == 2'd3 || (op[head] == 2'd2 && (value[head] & 32'd1)));
    assign RoB_clear_pc_value = op[head] == 2'd2? dest[head] : pc_jalr[head];    

    // reg[31:0] counter = 0;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            head  <= 0;
            tail  <= 0;
            stall <= 0;
            for (integer i = 0; i < Size; i = i + 1) begin
                busy[i]  <= 0;
                free[i]  <= 1;
                value[i] <= 0;
                dest[i]  <= 0;
                op[i]    <= 0;
                pc_jalr[i] <= 0;
            end
        end
        else if (rdy_in) begin
            if (issue_ready) begin

                // insts[tail] <= inst;
                // pcs[tail] <= pc;

                tail <= tail + 1;                
                if (is_J) begin
                    value[tail] <= pc + 4;
                end
                else if (is_jalr) begin
                    value[tail] <= pc + 4;                    
                    stall <= 1;
                end
                else if (is_B) begin
                    value[tail] <= pc | pred_res;
                end
                else begin
                    value[tail] <= 0;
                end

                if (is_B) begin
                    dest[tail] <= pc_B_fail;
                end
                else if (!is_S) begin
                    dest[tail] <= rd;
                end

                if (is_S) begin
                    op[tail] <= 2'd1;
                end
                else if (is_B) begin
                    op[tail] <= 2'd2;
                end
                else if (is_jalr) begin
                    op[tail] <= 2'd3;
                end
                else begin
                    op[tail] <= 2'd0;
                end

                busy[tail] <= 1;
                free[tail] <= 0;
            end
            if (LSB_finish_rdy) begin
                busy[LSB_finish_id]  <= 0;
                value[LSB_finish_id] <= LSB_finish_value;
            end
            if (RS_finish_rdy) begin
                busy[RS_finish_id] <= 0;
                if (op[RS_finish_id] != 2'd2) begin
                    if (!value[RS_finish_id]) begin                        
                        value[RS_finish_id] <= RS_finish_value;
                    end
                    else if (op[RS_finish_id] == 2'd3) begin
                        pc_jalr[RS_finish_id] <= RS_finish_value;
                    end
                end
                else begin
                    value[RS_finish_id] <= RS_finish_value ^ value[RS_finish_id];
                end
            end


            if (!busy[head] && !free[head]) begin
                // counter <= counter + 1;
                free[head] <= 1;
                head <= head + 1;
                // $display("inst: %h, %d %h", insts[head], pcs[head], pcs[head]);
                case (op[head])
                    2'd2: begin

                    end
                    2'd3: begin
                        stall <= 0;
                    end
                endcase
            end
        end
    end

endmodule
