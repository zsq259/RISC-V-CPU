`include "const.v"

module ReserveStation #(
    parameter BITS = `RS_BITS,
    parameter SIZE = `RS_SIZE
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

    // for register
    input wire [`RoB_BITS-1:0] q_rs1,
    input wire [`RoB_BITS-1:0] q_rs2,
    input wire q_ready_rs1,  // 1 if rs1 is not dependent
    input wire q_ready_rs2,  // 1 if rs2 is not dependent
    input wire [31:0] value_rs1,
    input wire [31:0] value_rs2,

    // for RoB
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

    // for ALU
    input wire ALU_finish_rdy,
    output wire waiting_ALU,
    output wire [31:0] vj_ALU,
    output wire [31:0] vk_ALU,
    output wire [31:0] imm_ALU,
    output wire [5:0] op_ALU,

    output wire [`RoB_BITS-1:0] RS_finish_id,

    output wire full
);

    wire is_U = opcode == 7'b0110111 || opcode == 7'b0010111;
    wire is_J = opcode == 7'b1101111;
    wire is_I = opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111;
    wire is_S = opcode == 7'b0100011;
    wire is_B = opcode == 7'b1100011;
    wire is_R = opcode == 7'b0110011;
    wire is_load = opcode == 7'b0000011;
    wire is_jalr = opcode == 7'b1100111;

    wire need_RS = !need_LSB;
    reg busy[SIZE-1:0];  // if the place is not empty
    reg working[SIZE-1:0];  // if the place is or need working
    reg waiting[SIZE-1:0];  // if the place is waiting for result
    reg [5:0] op[SIZE-1:0];  // func7, func3, 0: U, 1: I, 2: B, 3: R, all 1: J
    reg [31:0] vj[SIZE-1:0];
    reg [31:0] vk[SIZE-1:0];
    reg [31:0] qj[SIZE-1:0];
    reg [31:0] qk[SIZE-1:0];
    reg rdj[SIZE-1:0];  // 1 if no dependency
    reg rdk[SIZE-1:0];  // 1 if no dependency
    reg [31:0] A[SIZE-1:0];
    reg [`RoB_BITS-1:0] dest[SIZE-1:0];  // id in RoB

    wire [BITS-1:0] free[SIZE-1:0];

    wire rdjk[SIZE-1:0];  // vj and vk are ready
    wire finish_work[SIZE-1:0];  // finished working
    wire [BITS-1:0] rdy_work[SIZE-1:0];  // ready to work id
    wire [BITS-1:0] finished[SIZE-1:0];  // finished working id

    assign waiting_ALU = rdjk[rdy_work_id] && busy[rdy_work_id] && working[rdy_work_id];
    assign vj_ALU = vj[rdy_work_id];
    assign vk_ALU = vk[rdy_work_id];
    assign imm_ALU = A[rdy_work_id];
    assign op_ALU = op[rdy_work_id];

    assign get_RoB_id_1 = q_rs1;
    assign get_RoB_id_2 = q_rs2;

    assign RS_finish_id = dest[rdy_work_id];

    generate
        genvar i;
        for (i = 0; i < (1 << BITS); i = i + 1) begin : gen0
            assign rdjk[i] = rdj[i] && rdk[i] && busy[i];
            assign finish_work[i] = !working[i] && !waiting[i] && busy[i];
        end
        for (i = 0; i < (1 << (BITS - 1)); i = i + 1) begin : gen1
            assign free[i] = !busy[free[i<<1]] ? free[i<<1] : free[(i<<1)|1];

            assign rdy_work[i] = rdjk[rdy_work[i<<1]] ? rdy_work[i<<1] : rdy_work[(i<<1)|1];

            assign finished[i] = finish_work[finished[i<<1]] ? finished[i<<1] : finished[(i<<1)|1];
        end
        for (i = (1 << (BITS - 1)); i < (1 << BITS); i = i + 1) begin : gen2
            assign free[i] = !busy[(i<<1)-SIZE] ? (i << 1) - SIZE : ((i << 1) | 1) - SIZE;

            assign rdy_work[i] = rdjk[(i<<1)-SIZE] ? (i << 1) - SIZE : ((i << 1) | 1) - SIZE;

            assign finished[i] = finish_work[(i<<1)-SIZE] ? (i << 1) - SIZE : ((i << 1) | 1) - SIZE;
        end

    endgenerate

    wire [31:0] dbg_vj0 = vj[0];
    wire [31:0] dbg_vj = vj[4'b0001];
    wire dbg_rdj = rdj[1];
    wire dbg_rdk = rdk[1];
    wire dbg_rdjk = rdjk[1];
    wire dbg_busy = busy[1];
    wire dbg_working = working[rdy_work_id];
    wire dbg_waiting = waiting[rdy_work_id];
    wire dbg_finished = finish_work[rdy_work_id];    

    wire [BITS-1:0] id = free[1];
    wire ready = need_RS && !busy[id];
    assign full = busy[id];

    wire [BITS-1:0] rdy_work_id = rdy_work[1];
    wire [BITS-1:0] finish_id = finished[1];

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            for (integer i = 0; i < SIZE; i = i + 1) begin
                busy[i]    <= 0;
                working[i] <= 0;
                waiting[i] <= 0;
                vj[i]      <= 0;
                vk[i]      <= 0;
                qj[i]      <= 0;
                qk[i]      <= 0;
                rdj[i]     <= 0;
                rdk[i]     <= 0;
                A[i]       <= 0;
                dest[i]    <= 0;
                op[i]      <= 0;
            end            
        end
        else if (rdy_in) begin
            if (issue_ready && ready) begin
                busy[id] <= 1;
                working[id] <= 1;
                dest[id] <= RoB_tail;
                A[id] <= opcode == 7'b0010111 ? pc + imm : imm;
                if (is_J) begin
                    op[id] <= 6'b111111;
                end
                else begin
                    if (is_U) op[id] <= {funct7, funct3, 2'd0};
                    else if (is_I) op[id] <= {funct7, funct3, 2'd1};
                    else if (is_B) op[id] <= {funct7, funct3, 2'd2};
                    else if (is_R) op[id] <= {funct7, funct3, 2'd3};
                end

                if (!(is_U || is_J)) begin
                    if (q_ready_rs1) begin                        
                        vj[id]  <= value_rs1;
                        qj[id]  <= 0;
                        rdj[id] <= 1;
                    end
                    else begin
                        if (RoB_rdy_1 && (q_rs1 == RoB_id_1)) begin
                            vj[id]  <= RoB_value_1;
                            qj[id]  <= 0;
                            rdj[id] <= 1;
                        end
                        else if (RoB_rdy_2 && (q_rs1 == RoB_id_2)) begin
                            vj[id]  <= RoB_value_2;
                            qj[id]  <= 0;
                            rdj[id] <= 1;
                        end
                        else if (!RoB_busy_1) begin
                            vj[id]  <= get_RoB_value_1;
                            qj[id]  <= 0;
                            rdj[id] <= 1;
                        end
                        else begin
                            vj[id]  <= 0;
                            qj[id]  <= q_rs1;
                            rdj[id] <= 0;
                        end
                    end
                end
                else begin
                    vj[id]  <= 0;
                    qj[id]  <= 0;
                    rdj[id] <= 1;
                end

                if (is_B || is_S || is_R) begin
                    if (q_ready_rs2) begin
                        vk[id]  <= value_rs2;
                        qk[id]  <= 0;
                        rdk[id] <= 1;
                    end
                    else begin
                        if (RoB_rdy_1 && (q_rs2 == RoB_id_1)) begin
                            vk[id]  <= RoB_value_1;
                            qk[id]  <= 0;
                            rdk[id] <= 1;
                        end
                        else if (RoB_rdy_2 && (q_rs2 == RoB_id_2)) begin
                            vk[id]  <= RoB_value_2;
                            qk[id]  <= 0;
                            rdk[id] <= 1;
                        end
                        else if (!RoB_busy_2) begin
                            vk[id]  <= get_RoB_value_2;
                            qk[id]  <= 0;
                            rdk[id] <= 1;
                        end
                        else begin
                            vk[id]  <= 0;
                            qk[id]  <= rs2;
                            rdk[id] <= 0;
                        end
                    end
                end
                else begin
                    vk[id]  <= 0;
                    qk[id]  <= 0;
                    rdk[id] <= 1;
                end
            end

            if (rdj[rdy_work_id] && rdk[rdy_work_id] && busy[rdy_work_id]) begin
                if (working[rdy_work_id]) begin
                    working[rdy_work_id] <= 0;
                    waiting[rdy_work_id] <= 1;
                end
                else if (waiting[rdy_work_id] && ALU_finish_rdy) begin
                    waiting[rdy_work_id] <= 0;
                    busy[rdy_work_id] <= 0;
                end
            end

            for (integer i = 0; i < SIZE; i = i + 1) begin
                if (busy[i] && working[i]) begin                                    
                    if (busy[i] && working[i] && !rdj[i] && qj[i] == RoB_id_1 && RoB_rdy_1) begin
                        vj[i]  <= RoB_value_1;
                        qj[i]  <= 0;
                        rdj[i] <= 1;
                    end
                    if (busy[i] && working[i] && !rdj[i] && qj[i] == RoB_id_2 && RoB_rdy_2) begin
                        vj[i]  <= RoB_value_2;
                        qj[i]  <= 0;
                        rdj[i] <= 1;
                    end
                    if (busy[i] && working[i] && !rdk[i] && qk[i] == RoB_id_1 && RoB_rdy_1) begin
                        vk[i]  <= RoB_value_1;
                        qk[i]  <= 0;
                        rdk[i] <= 1;
                    end
                    if (busy[i] && working[i] && !rdk[i] && qk[i] == RoB_id_2 && RoB_rdy_2) begin
                        vk[i]  <= RoB_value_2;
                        qk[i]  <= 0;
                        rdk[i] <= 1;
                    end
                end
            end
        end
    end

endmodule
