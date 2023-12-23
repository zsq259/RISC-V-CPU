module register (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signa
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 4:0] set_reg,      // register to be set
    input  wire [31:0] set_val,      // value to be set
    input  wire [ 4:0] set_reg_q,    // q_i to be set
    input  wire [31:0] set_val_q,    // q_i value to be set
    input  wire        set_rdy_q,    // q_i ready to be set
    input  wire [ 4:0] get_reg_1,    // register1 to be read
    input  wire [ 4:0] get_reg_2,    // register2 to be read
    output wire [31:0] get_val_1,    // value read from register1
    output wire [31:0] get_val_2,    // value read from register2
    output wire [31:0] get_q,        // q_i 
    output wire        get_q_value,  // q_i value
    output wire        get_q_ready   // q_i ready
);

    reg [31:0] regfile[31:0];
    reg [31:0] q[31:0];
    reg ready[31:0];

    assign get_val_1   = regfile[get_reg_1];
    assign get_val_2   = regfile[get_reg_2];
    assign get_q_value = q[get_q];
    assign get_q_ready = ready[get_q];    

    always @(posedge clk_in) begin
        if (rst_in) begin
            for (integer i = 0; i < 32; i = i + 1) begin
                regfile[i] <= 0;
            end
        end
        else if (rdy_in) begin
            if (set_reg != 0) begin
                regfile[set_reg] <= set_val;
            end
            if (set_reg_q != 0) begin
                q[set_reg_q] <= set_val_q;
                ready[set_reg_q] <= set_rdy_q;
            end
        end
    end

`ifdef DEBUG

`endif


endmodule
