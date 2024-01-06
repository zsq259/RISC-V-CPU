// RISCV32I CPU top module
// port modification allowed for debugging purposes
`include "const.v"

module cpu (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire io_buffer_full,  // 1 if uart buffer is full

    output wire [31:0] dbgreg_dout  // cpu register output (debugging demo)
);

    // implementation goes here

    // Specifications:
    // - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
    // - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
    // - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
    // - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
    // - 0x30000 read: read a byte from input
    // - 0x30000 write: write a byte to output (write 0x00 is ignored)
    // - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
    // - 0x30004 write: indicates program stop (will output '\0' through uart tx)    

    wire reddy_in = rdy_in & !io_buffer_full;
    
    wire i_m_ready;

    wire fetch_ready;
    wire [31:0] inst;

    wire [31:0] i_result;
    wire [31:0] pc;

    wire d_wr;
    wire d_waiting;
    wire [31:0] d_addr;
    wire [31:0] d_value;
    wire [2:0] d_len;
    wire [31:0] d_result;
    wire d_m_ready;

    wire RoB_clear;
    wire [31:0] RoB_clear_pc_value;

    Cache cache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(reddy_in),

        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),

        .RoB_clear(RoB_clear),

        .i_waiting(1'b1),
        .i_addr(pc),

        .i_result (i_result),
        .i_m_ready(i_m_ready),

        .d_waiting(d_waiting),
        .d_addr(d_addr),
        .d_value(d_value),
        .d_len(d_len),
        .d_wr(d_wr),

        .d_result(d_result),
        .d_m_ready(d_m_ready)
    );

    wire fetch_stall;

    wire decoder_pc_change_flag;
    wire [31:0] decoder_pc_change;

    wire pc_change_flag = RoB_clear | decoder_pc_change_flag;
    wire [31:0] pc_change = RoB_clear ? RoB_clear_pc_value : decoder_pc_change;

    InstructionFetch ifetch (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(reddy_in),

        .pc_change_flag(pc_change_flag),
        .pc_change(pc_change),

        .stall(fetch_stall),
        .ready_in(i_m_ready),
        .inst_in(i_result),

        .RoB_clear(RoB_clear),
        .RoB_clear_pc_value(RoB_clear_pc_value),

        .ready_out(fetch_ready),
        .inst_out(inst),
        .pc_out(pc)
    );

    wire RS_full;
    wire LSB_full;
    wire RoB_full;
    wire RoB_stall;

    wire [6:0] opcode;
    wire [4:0] rd;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [2:0] funct3;
    wire funct7;
    wire [31:0] imm;
    wire need_LSB;

    wire issue_ready;
    wire issue_stall;

    wire [31:0] pc_B_fail;

    Decoder decoder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .RS_full  (RS_full),
        .LSB_full (LSB_full),
        .RoB_full (RoB_full),
        .RoB_stall(RoB_stall),

        .fetch_ready(fetch_ready),
        .inst(inst),
        .pc(pc),
        .pred_res(1'b0),
        .pc_B_fail(pc_B_fail),

        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm(imm),

        .need_LSB(need_LSB),

        .issue_ready(issue_ready),

        .pc_change_flag(decoder_pc_change_flag),
        .pc_change(decoder_pc_change),

        .stall(fetch_stall)
    );

    wire [31:0] reg_value_1;
    wire [31:0] reg_value_2;
    wire [`RoB_BITS-1:0] q_value_1;
    wire [`RoB_BITS-1:0] q_value_2;
    wire q_ready_1;
    wire q_ready_2;

    wire [4:0] set_reg;
    wire [31:0] set_val;

    wire [4:0] set_reg_q_1;
    wire [31:0] set_val_q_1;

    wire [4:0] set_reg_q_2;
    wire [31:0] set_val_q_2;

    Register regster (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .RoB_clear(RoB_clear),

        .set_reg(set_reg),
        .set_val(set_val),

        .set_reg_q_1(set_reg_q_1),
        .set_val_q_1(set_val_q_1),

        .set_reg_q_2(set_reg_q_2),
        .set_val_q_2(set_val_q_2),

        .get_reg_1(rs1),
        .get_reg_2(rs2),

        .get_val_1(reg_value_1),
        .get_val_2(reg_value_2),

        .get_q_value_1(q_value_1),
        .get_q_ready_1(q_ready_1),

        .get_q_value_2(q_value_2),
        .get_q_ready_2(q_ready_2)
    );

    // wire RS_finish_rdy;
    wire [`RoB_BITS-1:0] RS_finish_id;
    // wire [31:0] RS_finish_value;

    wire LSB_finish_rdy;
    wire [`RoB_BITS-1:0] LSB_finish_id;
    wire [31:0] LSB_finish_value;

    wire [3:0] RoB_head;
    wire [3:0] RoB_tail;

    wire [`RoB_BITS-1:0] RoB_id_1;
    wire [`RoB_BITS-1:0] RoB_id_2;
    wire RoB_rdy_1;
    wire RoB_rdy_2;
    wire [31:0] RoB_value_1;
    wire [31:0] RoB_value_2;

    wire [3:0] get_RoB_id_1;
    wire [3:0] get_RoB_id_2;
    wire RoB_busy_1;
    wire RoB_busy_2;
    wire [31:0] get_RoB_value_1;
    wire [31:0] get_RoB_value_2;

    wire ALU_finish_rdy;
    wire waiting_ALU;
    wire [31:0] vj_ALU;
    wire [31:0] vk_ALU;
    wire [31:0] imm_ALU;
    wire [5:0] op_ALU;
    wire [31:0] ALU_value;

    ReorderBuffer RoB (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .issue_ready(issue_ready),
        .inst(inst),
        .pc(pc),
        .pc_B_fail(pc_B_fail),
        .pred_res(1'b0),

        .opcode(opcode),
        .rd(rd),

        .RS_finish_rdy(ALU_finish_rdy),
        .RS_finish_id(RS_finish_id),
        .RS_finish_value(ALU_value),

        .LSB_finish_rdy(LSB_finish_rdy),
        .LSB_finish_id(LSB_finish_id),
        .LSB_finish_value(LSB_finish_value),

        .RoB_id_1(RoB_id_1),
        .RoB_id_2(RoB_id_2),
        .RoB_rdy_1(RoB_rdy_1),
        .RoB_rdy_2(RoB_rdy_2),
        .RoB_value_1(RoB_value_1),
        .RoB_value_2(RoB_value_2),

        .get_RoB_id_1(get_RoB_id_1),
        .get_RoB_id_2(get_RoB_id_2),
        .RoB_busy_1(RoB_busy_1),
        .RoB_busy_2(RoB_busy_2),
        .get_RoB_value_1(get_RoB_value_1),
        .get_RoB_value_2(get_RoB_value_2),

        .RoB_head(RoB_head),
        .RoB_tail(RoB_tail),
        .full(RoB_full),

        .set_reg_id(set_reg),
        .set_reg_value(set_val),

        .set_reg_q_1(set_reg_q_1),
        .set_val_q_1(set_val_q_1),
        .set_reg_q_2(set_reg_q_2),
        .set_val_q_2(set_val_q_2),

        .RoB_clear(RoB_clear),
        .RoB_clear_pc_value(RoB_clear_pc_value),

        .stall(RoB_stall)
    );

    ReserveStation RS (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .pc(pc),

        .issue_ready(issue_ready),
        .need_LSB(need_LSB),
        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm(imm),

        .q_rs1(q_value_1),
        .q_rs2(q_value_2),
        .q_ready_rs1(q_ready_1),
        .q_ready_rs2(q_ready_2),
        .value_rs1(reg_value_1),
        .value_rs2(reg_value_2),

        .RoB_tail(RoB_tail),

        .RoB_id_1(RoB_id_1),
        .RoB_rdy_1(RoB_rdy_1),
        .RoB_value_1(RoB_value_1),
        .RoB_id_2(RoB_id_2),
        .RoB_rdy_2(RoB_rdy_2),
        .RoB_value_2(RoB_value_2),

        .get_RoB_id_1(get_RoB_id_1),
        .get_RoB_id_2(get_RoB_id_2),
        .RoB_busy_1(RoB_busy_1),
        .RoB_busy_2(RoB_busy_2),
        .get_RoB_value_1(get_RoB_value_1),
        .get_RoB_value_2(get_RoB_value_2),

        .RoB_clear(RoB_clear),

        .ALU_finish_rdy(ALU_finish_rdy),
        .waiting_ALU(waiting_ALU),
        .vj_ALU(vj_ALU),
        .vk_ALU(vk_ALU),
        .imm_ALU(imm_ALU),
        .op_ALU(op_ALU),

        // .RS_finish_rdy(RS_finish_rdy),
        .RS_finish_id(RS_finish_id),
        // .RS_finish_value(RS_finish_value),

        .full(RS_full)
    );

    ALU alu (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .vj(vj_ALU),
        .vk(vk_ALU),
        .imm(imm_ALU),
        .op(op_ALU),
        .waiting(waiting_ALU),

        .RoB_clear(RoB_clear),

        .ALU_finish_rdy(ALU_finish_rdy),
        .ALU_value(ALU_value)
    );

    LoadStoreBuffer LSB (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(reddy_in),

        .pc(pc),

        .issue_ready(issue_ready),
        .need_LSB(need_LSB),
        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm(imm),

        .mem_result(d_result),
        .mem_rdy(d_m_ready),

        .q_rs1(q_value_1),
        .q_rs2(q_value_2),
        .q_ready_rs1(q_ready_1),
        .q_ready_rs2(q_ready_2),
        .value_rs1(reg_value_1),
        .value_rs2(reg_value_2),

        .RoB_head(RoB_head),
        .RoB_tail(RoB_tail),

        .RoB_id_1(RoB_id_1),
        .RoB_rdy_1(RoB_rdy_1),
        .RoB_value_1(RoB_value_1),
        .RoB_id_2(RoB_id_2),
        .RoB_rdy_2(RoB_rdy_2),
        .RoB_value_2(RoB_value_2),

        .get_RoB_id_1(get_RoB_id_1),
        .get_RoB_id_2(get_RoB_id_2),
        .RoB_busy_1(RoB_busy_1),
        .RoB_busy_2(RoB_busy_2),
        .get_RoB_value_1(get_RoB_value_1),
        .get_RoB_value_2(get_RoB_value_2),

        .RoB_clear(RoB_clear),

        .d_waiting(d_waiting),
        .d_wr(d_wr),
        .d_len(d_len),
        .d_addr(d_addr),
        .d_value(d_value),

        .LSB_finish_rdy(LSB_finish_rdy),
        .LSB_finish_id(LSB_finish_id),
        .LSB_finish_value(LSB_finish_value),

        .full(LSB_full)
    );
    
    always @(posedge clk_in) begin        

    end

endmodule
