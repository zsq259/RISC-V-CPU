module Cache (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    // instruction cache
    input wire i_waiting,  // waiting for work instruction
    input wire [31:0] i_addr,  // address

    // data cache
    input wire d_wating,  // waiting for work data

    output wire [31:0] i_result,  // result of instruction read operation
    output wire i_m_ready  // ready to return instruction result and accept new instruction
);

    wire i_hit;  // instruction hit signal
    wire [31:0] i_res;  //result from instruction cache
    wire i_wr;  // write/read signal (1 for write) for instruction cache    
    assign i_result = i_hit ? i_res : m_res;
    assign i_wr = state && m_ready;



    reg m_wr;  // write/read signal (1 for write)
    wire m_waiting;  // waiting for work
    reg [2:0] m_len;  // length of data to be read/written
    reg [31:0] m_addr;  // address bus (only 17:0 is used)
    reg [31:0] m_value;  // value to be written

    assign m_waiting = i_hit ? 0 : i_waiting | d_wating;
    assign i_m_ready = i_hit ? i_hit : (m_ready && !m_waiting);

    wire m_ready;  // ready to work
    wire [31:0] m_res;  // result of read operation    

    reg state;



    InstructionCache #(
        .IndexBit(2)
    ) icache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .wr(i_wr),
        .waiting(i_waiting),
        .addr(i_addr),
        .value(i_result),

        .hit(i_hit),
        .result(i_res)
    );

    MemoryController mc (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),

        .waiting(m_waiting),
        .wr(m_wr),
        .len(m_len),
        .addr(m_addr),
        .value(m_value),

        .ready (m_ready),
        .result(m_res)
    );

    always @(posedge clk_in) begin
        if (rst_in) begin
            m_wr <= 0;
            m_len <= 0;
            m_addr <= 0;
            m_value <= 0;
            state <= 0;
        end
        else if (rdy_in) begin
            case (state)
                1'b0: begin  // vacant                        
                    if (d_wating) begin
                    end
                    else if (i_waiting) begin
                        if (i_hit) begin                            
                        end
                        else begin
                            state <= 1;
                            m_wr <= 0;
                            m_len <= 2;
                            m_addr <= i_addr;
                            m_value <= 0;
                        end
                    end
                end
                1'b1: begin  // busy                    
                    if (m_ready) begin
                        state = 0;
                    end
                end
            endcase
        end
    end


endmodule
