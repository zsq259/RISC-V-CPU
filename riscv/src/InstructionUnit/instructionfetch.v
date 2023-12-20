module InstructionFetch (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire stall,  // stall signal
    input wire ready_in,
    input wire [31:0] inst_in,  // instruction input

    output wire ready_out,  // ready signal;
    output wire [31:0] inst_out,  // instruction output
    output reg [31:0] pc,  // program counter
    output reg [31:0] addr  // address
);
    assign ready_out = rdy_in && ready_in && !stall;
    assign inst_out = inst_in;

    always @(posedge clk_in) begin
        if (rst_in) begin            
            pc <= 0;
            addr <= 0;
        end
        else if (rdy_in && !stall && ready_in) begin            
            pc <= pc + 4;            
            addr <= pc;
        end        
    end

endmodule
