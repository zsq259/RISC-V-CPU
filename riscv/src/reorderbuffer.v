module ReorderBuffer #(
    parameter BITS = 4,
    parameter Size = 16
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire issue_ready,
    input wire[31:0] pc,
    input wire[31:0] pc_B_fail, // what pc should be if branch fails
    input wire pred_res,  // prediction result

    input wire is_J,
    input wire is_B,
    input wire is_S,
    input wire is_jail,
    input wire[4:0] rd,

    input wire get_RoBid_1,
    input wire get_RoBid_2,
    output wire RoB_busy_1,
    output wire RoB_busy_2,
    output wire [31:0] RoB_value_1,
    output wire [31:0] RoB_value_2,

    output wire [BITS-1:0] RoB_tail,
    output wire full,

    output reg stall
);
    reg [BITS-1:0] head;
    reg [BITS-1:0] tail;
    reg busy[Size-1:0];
    reg free[Size-1:0];
    reg [31:0] value[Size-1:0];
    reg [31:0] dest[Size-1:0];

    assign RoB_tail = tail;
    assign full = head == tail && !free[head];

    assign RoB_busy_1 = busy[get_RoBid_1];
    assign RoB_busy_2 = busy[get_RoBid_2];
    assign RoB_value_1 = value[get_RoBid_1];
    assign RoB_value_2 = value[get_RoBid_2];

    always @(posedge clk_in) begin
        if (rst_in) begin
            head <= 0;
            tail <= 0;
            for (integer i = 0; i < Size; i = i + 1) begin
                busy[i]  <= 0;
                free[i]  <= 1;
                value[i] <= 0;
                dest[i]  <= 0;
            end
        end
        else begin
            if (issue_ready) begin
                if (is_J) begin
                    value[tail] <= pc + 4;
                end
                else if (is_jail) begin
                    value[tail] <= pc + 4;
                    stall <= 1;
                end
                else if (is_B) begin
                    value[tail] <= pc | pred_res;
                end
                
                if (is_B) begin
                    dest[tail] <= pc_B_fail;                
                end
                else if (!is_S) begin
                    dest[tail] <= rd;
                end
            end
        end
    end

endmodule
