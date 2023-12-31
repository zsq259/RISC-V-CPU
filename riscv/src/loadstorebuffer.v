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

    input wire [`RoB_BITS-1:0] q_rs1,
    input wire [`RoB_BITS-1:0] q_rs2,
    input wire q_ready_rs1,  // 1 if rs1 is not dependent
    input wire q_ready_rs2,  // 1 if rs2 is not dependent
    input wire [31:0] value_rs1,
    input wire [31:0] value_rs2,

    // for RoB
    input wire [`RoB_BITS-1:0] RoB_tail,

    input wire RoB_busy_1,
    input wire [31:0] RoB_value_1,
    output wire [`RoB_BITS-1:0] RoB_id_1,

    input wire RoB_busy_2,
    input wire [31:0] RoB_value_2,
    output wire [`RoB_BITS-1:0] RoB_id_2,

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
    reg rdj[SIZE-1:0];  // 1 if no dependency
    reg rdk[SIZE-1:0];  // 1 if no dependency
    reg [31:0] A[SIZE-1:0];
    reg [31:0] dest[SIZE-1:0];  // id in RoB

    wire ready = need_LSB && !busy[tail];
    assign full = head == tail && busy[head];
    assign need_q_1 = rs1;
    assign need_q_2 = rs2;

    always @(posedge clk_in) begin
        if (rst_in) begin
            head <= 0;
            tail <= 0;
            for (integer i = 0; i < SIZE; i = i + 1) begin
                busy[i] <= 0;
                vj[i] <= 0;
                vk[i] <= 0;
                qj[i] <= 0;
                qk[i] <= 0;
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
                if (!(is_U || is_J)) begin
                    if (q_ready_rs1) begin
                        vj[tail]  <= value_rs1;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else begin
                        if (!RoB_busy_1) begin
                            vj[tail]  <= RoB_value_1;
                            qj[tail]  <= 0;
                            rdj[tail] <= 1;
                        end
                        else begin
                            qj[tail]  <= rs1;
                            rdj[tail] <= 0;
                        end

                    end
                end
                else begin
                    vj[tail]  <= 0;
                    qj[tail]  <= 0;
                    rdj[tail] <= 1;
                end
                if (is_B || is_S || is_R) begin
                    if (q_ready_rs2) begin
                        vk[tail]  <= value_rs2;
                        qk[tail]  <= 0;
                        rdk[tail] <= 1;
                    end
                    else begin
                        if (!RoB_busy_2) begin
                            vk[tail]  <= RoB_value_2;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else begin
                            qk[tail]  <= rs2;
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
        end
    end
endmodule
