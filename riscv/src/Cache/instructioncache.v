module InstructionCache #(
    parameter IndexBit = 2
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire wr,  // write/read signal (1 for write)
    input wire waiting,  // waiting for work
    input wire [31:0] addr,  // address
    input wire [31:0] value,  // value to write

    output wire hit,  // hit signal
    output wire [31:0] result  // result
);

    localparam Size = 1 << IndexBit;
    localparam TagBit = 32 - IndexBit - 2;

    wire [TagBit-1:0] tag = addr[31:2+IndexBit];
    wire [IndexBit-1:0] index = addr[1+IndexBit:2];

    reg valid[Size-1:0];
    reg [TagBit-1:0] tags[Size-1:0];
    reg [31:0] block[Size-1:0];

    assign hit = valid[index] && tags[index] == tag;
    assign result = block[index];
    
    integer i;
    
    always @(posedge clk_in) begin
        if (rst_in) begin
            for (i = 0; i < Size; i = i + 1) begin
                valid[i] <= 0;
                tags[i]  <= 0;
                block[i] <= 0;
            end
        end
        else if (wr) begin            
            valid[index] <= 1;
            tags[index]  <= tag;
            block[index] <= value;
        end
    end

endmodule
