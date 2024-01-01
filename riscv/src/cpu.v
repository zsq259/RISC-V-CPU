// RISCV32I CPU top module
// port modification allowed for debugging purposes

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

    reg waiting;
    wire i_ready;

    wire fetch_ready;
    wire [31:0] inst;

    wire [31:0] m_res;
    wire [31:0] pc;

    wire d_wr;
    wire d_wating;
    wire [31:0] d_addr;
    wire [31:0] d_value;

    Cache cache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),

        .i_waiting(1'b1),
        .i_addr(pc),

        .d_wating(1'b0),
        .d_addr(d_addr),
        .d_value(d_value),
        .d_wr(d_wr),

        .i_result (m_res),
        .i_m_ready(i_ready)
    );

    wire fetch_stall;

    InstructionFetch ifetch (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .pc_change_flag(1'b0),
        .pc_change(0),

        .stall(fetch_stall),
        .ready_in(i_ready),
        .inst_in(m_res),

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

        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm(imm),

        .need_LSB(need_LSB),

        .issue_ready(issue_ready),
        .stall(fetch_stall)
    );

    wire [31:0] reg_value_1;
    wire [31:0] reg_value_2;
    wire [3:0] q_value_1;
    wire [3:0] q_value_2;
    wire q_ready_1;
    wire q_ready_2;

    Register regster (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .set_reg(5'b0),
        .set_val(32'b0),

        .set_reg_q(5'b0),
        .set_val_q(32'b0),
        .set_rdy_q(1'b0),
        
        .get_reg_1(rs1),
        .get_reg_2(rs2),

        .get_val_1(reg_value_1),
        .get_val_2(reg_value_2),

        .get_q_value_1(q_value_1),
        .get_q_ready_1(q_ready_1),

        .get_q_value_2(q_value_2),
        .get_q_ready_2(q_ready_2)
    );

    wire [3:0] RoB_tail;
    wire [3:0] get_RoBid_1;
    wire [3:0] get_RoBid_2;
    wire RoB_busy_1;
    wire RoB_busy_2;
    wire [31:0] RoB_value_1;
    wire [31:0] RoB_value_2;

    ReorderBuffer RoB (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .issue_ready(issue_ready),
        .pc(pc),
        .pc_B_fail(32'b0),
        .pred_res(1'b0),

        .opcode(opcode),
        .rd(rd),

        .get_RoBid_1(get_RoBid_1),
        .get_RoBid_2(get_RoBid_2),
        .RoB_busy_1(RoB_busy_1),
        .RoB_busy_2(RoB_busy_2),
        .RoB_value_1(RoB_value_1),
        .RoB_value_2(RoB_value_2),

        .RoB_tail(RoB_tail),
        .full(RoB_full),

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

        .RoB_busy_1(RoB_busy_1),
        .RoB_value_1(RoB_value_1),

        .RoB_busy_2(RoB_busy_2),
        .RoB_value_2(RoB_value_2),

        .full(RS_full)
    );

    LoadStoreBuffer LSB (
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

        .RoB_busy_1(RoB_busy_1),
        .RoB_value_1(RoB_value_1),

        .RoB_busy_2(RoB_busy_2),
        .RoB_value_2(RoB_value_2),

        .d_wating(d_wating),
        .d_addr(d_addr),
        .d_value(d_value),
        .d_wr(d_wr),

        .full(LSB_full)
    );

    reg [31:0] counter;
    always @(posedge clk_in) begin
        if (rst_in) begin
            counter <= 0;
            waiting <= 0;

        end
        else if (!rdy_in) begin

        end
        else begin
            // $display("counter: %d", counter);
            // counter <= counter + 1;
            // if (ready) begin
            //     $display("inst: %h, pc: %d", inst, pc);

            // end

        end

    end

endmodule
