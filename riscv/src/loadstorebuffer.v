`include "const.v"

module LoadStoreBuffer #(
    parameter BTIS = `LSB_BITS,
    parameter SIZE = `LSB_SIZE
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire [31:0] pc,

    input wire issue_ready,
    input wire need_LSB,
    input wire [6:0] opcode,
    input wire [4:0] rd,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [2:0] funct3,
    input wire funct7,
    input wire [31:0] imm,

    // for memory
    input wire [31:0] mem_result,
    input wire mem_rdy,

    // for register
    input wire [`RoB_BITS-1:0] q_rs1,
    input wire [`RoB_BITS-1:0] q_rs2,
    input wire q_ready_rs1,  // 1 if rs1 is not dependent
    input wire q_ready_rs2,  // 1 if rs2 is not dependent
    input wire [31:0] value_rs1,
    input wire [31:0] value_rs2,

    // for RoB
    input wire [`RoB_BITS-1:0] RoB_head,
    input wire [`RoB_BITS-1:0] RoB_tail,

    input wire [`RoB_BITS-1:0] RoB_id_1,  // latest executed id in RoB
    input wire RoB_rdy_1,
    input wire [31:0] RoB_value_1,
    input wire [`RoB_BITS-1:0] RoB_id_2,
    input wire RoB_rdy_2,
    input wire [31:0] RoB_value_2,

    output wire [`RoB_BITS-1:0] get_RoB_id_1,  // get value from RoB if q_i is not ready
    output wire [`RoB_BITS-1:0] get_RoB_id_2,
    input wire RoB_busy_1,
    input wire RoB_busy_2,
    input wire [31:0] get_RoB_value_1,
    input wire [31:0] get_RoB_value_2,

    input wire RoB_clear,

    output wire d_waiting,
    output wire d_wr,
    output wire [2:0] d_len,
    output wire [31:0] d_addr,
    output wire [31:0] d_value,

    output wire LSB_finish_rdy,
    output wire [`RoB_BITS-1:0] LSB_finish_id,
    output wire [31:0] LSB_finish_value,

    output wire full
);

    wire is_U = opcode == 7'b0110111 || opcode == 7'b0010111;
    wire is_J = opcode == 7'b1101111;
    wire is_I = opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111;
    wire is_S = opcode == 7'b0100011;
    wire is_B = opcode == 7'b1100011;
    wire is_R = opcode == 7'b0110011;
    wire is_load = opcode == 7'b0000011;
    wire is_jail = opcode == 7'b1100111;

    reg [BTIS-1:0] head;
    reg [BTIS-1:0] tail;

    reg busy[SIZE-1:0];
    reg [31:0] vj[SIZE-1:0];
    reg [31:0] vk[SIZE-1:0];
    reg [31:0] qj[SIZE-1:0];
    reg [31:0] qk[SIZE-1:0];
    reg [2:0] op[SIZE-1:0];
    reg rdj[SIZE-1:0];  // 1 if no dependency
    reg rdk[SIZE-1:0];  // 1 if no dependency
    reg [31:0] A[SIZE-1:0];
    reg [`RoB_BITS-1:0] dest[SIZE-1:0];  // id in RoB

    wire ready = need_LSB && !busy[tail];
    assign full = head == tail && busy[head];
    assign need_q_1 = rs1;
    assign need_q_2 = rs2;    

    assign d_waiting = busy[head] && rdj[head] && rdk[head] && (op[head] <= 3'd4 ? 1 : dest[head] == RoB_head);
    assign d_addr = vj[head] + A[head];
    assign d_wr = op[head] > 3'b100;
    assign d_value = vk[head];
    assign d_len = op[head] == 3'b000 ? 3'b100 :  //
        op[head] == 3'b001 ? 3'b101 :  //
        op[head] == 3'b010 ? 3'b110 :  //
        op[head] == 3'b011 ? 3'b000 :  //
        op[head] == 3'b100 ? 3'b001 :  //
        op[head] == 3'b101 ? 3'b100 :  //
        op[head] == 3'b110 ? 3'b101 : 3'b110;

    assign LSB_finish_rdy = busy[head] && mem_rdy;
    assign LSB_finish_id = dest[head];
    assign LSB_finish_value = mem_result;

    assign get_RoB_id_1 = q_rs1;
    assign get_RoB_id_2 = q_rs2;

    wire[`RoB_BITS-1:0] dbg_id = dest[head];
    wire[31:0] dbg_vj = vj[head];

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            head <= 0;
            tail <= 0;
            for (integer i = 0; i < SIZE; i = i + 1) begin
                busy[i] <= 0;
                vj[i] <= 0;
                vk[i] <= 0;
                qj[i] <= 0;
                qk[i] <= 0;
                op[i] <= 0;
                rdj[i] <= 0;
                rdk[i] <= 0;
                A[i] <= 0;
                dest[i] <= 0;
            end
        end
        else if (rdy_in) begin
            if (issue_ready && ready) begin
                tail <= tail + 1;
                busy[tail] <= 1;
                dest[tail] <= RoB_tail;
                A[tail] <= opcode == 7'b0010111 ? pc + imm : imm;
                if (!is_S) begin
                    case (funct3)
                        3'b000: op[tail] <= 3'b000;
                        3'b001: op[tail] <= 3'b001;
                        3'b010: op[tail] <= 3'b010;
                        3'b100: op[tail] <= 3'b011;
                        3'b101: op[tail] <= 3'b100;
                    endcase
                end
                else begin
                    case (funct3)
                        3'b000: op[tail] <= 3'b101;
                        3'b001: op[tail] <= 3'b110;
                        3'b010: op[tail] <= 3'b111;
                    endcase
                end

                if (q_ready_rs1) begin
                    vj[tail]  <= value_rs1;
                    qj[tail]  <= 0;
                    rdj[tail] <= 1;
                end
                else begin
                    if (q_rs1 == RoB_id_1 && RoB_rdy_1) begin
                        vj[tail]  <= RoB_value_1;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else if (q_rs1 == RoB_id_2 && RoB_rdy_2) begin
                        vj[tail]  <= RoB_value_2;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else if (!RoB_busy_1) begin
                        vj[tail]  <= get_RoB_value_1;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else begin
                        qj[tail]  <= q_rs1;
                        rdj[tail] <= 0;
                    end
                end
                if (is_S) begin
                    if (q_ready_rs2) begin
                        vk[tail]  <= value_rs2;
                        qk[tail]  <= 0;
                        rdk[tail] <= 1;
                    end
                    else begin
                        if (q_rs2 == RoB_id_1 && RoB_rdy_1) begin
                            vk[tail]  <= RoB_value_1;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else if (q_rs2 == RoB_id_2 && RoB_rdy_2) begin
                            vk[tail]  <= RoB_value_2;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else if (!RoB_busy_2) begin
                            vk[tail]  <= get_RoB_value_2;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else begin
                            qk[tail]  <= q_rs2;
                            rdk[tail] <= 0;
                        end
                    end
                end
                else begin
                    vk[tail]  <= 0;
                    qk[tail]  <= 0;
                    rdk[tail] <= 1;
                end
            end
            if (mem_rdy) begin
                busy[head] <= 0;
                head <= head + 1;
            end

            for (integer i = 0; i < SIZE; i = i + 1) begin
                if (!rdj[i] && qj[i] == RoB_id_1 && RoB_rdy_1) begin
                    vj[i]  <= RoB_value_1;
                    qj[i]  <= 0;
                    rdj[i] <= 1;
                end
                if (!rdj[i] && qj[i] == RoB_id_2 && RoB_rdy_2) begin
                    vj[i]  <= RoB_value_2;
                    qj[i]  <= 0;
                    rdj[i] <= 1;
                end
                if (!rdk[i] && qk[i] == RoB_id_1 && RoB_rdy_1) begin
                    vk[i]  <= RoB_value_1;
                    qk[i]  <= 0;
                    rdk[i] <= 1;
                end
                if (!rdk[i] && qk[i] == RoB_id_2 && RoB_rdy_2) begin
                    vk[i]  <= RoB_value_2;
                    qk[i]  <= 0;
                    rdk[i] <= 1;
                end
            end
        end
    end
endmodule
