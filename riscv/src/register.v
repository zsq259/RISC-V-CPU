module register(
    input  wire                 clk_in,			// system clock signal
    input  wire                 rst_in,			// reset signa
	input  wire					rdy_in,			// ready signal, pause cpu when low

    input wire[ 4:0]            set_reg,		// register to be set
    input wire[31:0]            set_val,		// value to be set
    input wire[ 4:0]            get_reg_1,		// register1 to be read
    input wire[ 4:0]            get_reg_2,		// register2 to be read
    output wire[31:0]           get_val_1,		// value read from register1
    output wire[31:0]           get_val_2,		// value read from register2
);

reg [31:0] regfile[31:0];

assign get_val_1 = regfile[get_reg_1];
assign get_val_2 = regfile[get_reg_2];

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
    end
end

`ifdef DEBUG 
    
`endif


endmodule