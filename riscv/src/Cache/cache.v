module Cache (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input wire RoB_clear,

    // instruction cache
    input wire i_waiting,  // waiting for work instruction
    input wire [31:0] i_addr,  // address

    output wire [31:0] i_result,  // result of instruction read operation
    output wire i_m_ready,  // ready to return instruction result and accept new instruction
    
    // data cache
    input wire d_waiting,  // waiting for work data
    input wire [31:0] d_addr,  // address
    input wire [31:0] d_value,  // value to be written
    input wire [2:0] d_len,  // length of data to be read/written
    input wire d_wr,  // write/read signal (1 for write)

    output wire [31:0] d_result,  // result of data read operation
    output wire d_m_ready
);
    
    reg state;
    reg [31:0] current_addr;
    
    wire i_hit;  // instruction hit signal
    wire [31:0] i_res;  //result from instruction cache
    wire i_wr;  // write/read signal (1 for write) for instruction cache    
    assign i_result = i_hit ? i_res : m_res;

    assign i_wr = state && m_ready && (i_addr == current_addr) && !d_waiting;

    
    assign i_m_ready = (i_addr == current_addr) && (i_hit ? i_hit : (m_ready && !m_waiting)) && !d_waiting;

    assign d_result = m_res;
    assign d_m_ready = (d_addr == current_addr) && m_ready && d_waiting;

    reg m_wr;  // write/read signal (1 for write)
    wire m_waiting;  // waiting for work
    reg [2:0] m_len;  // length of data to be read/written
    reg [31:0] m_addr;  // address bus (only 17:0 is used)
    reg [31:0] m_value;  // value to be written

    assign m_waiting = (i_hit ? 0 : i_waiting) || d_waiting;
  
    wire m_ready;  // ready to work
    wire [31:0] m_res;  // result of read operation    

    



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

        .RoB_clear(RoB_clear),

        .waiting(m_waiting),
        .wr(m_wr),
        .len(m_len),
        .addr(m_addr),
        .value(m_value),

        .ready (m_ready),
        .result(m_res)
    );

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            m_wr <= 0;
            m_len <= 0;
            m_addr <= 0;
            m_value <= 0;
            state <= 0;
            current_addr <= 0;
        end
        else if (rdy_in) begin
            case (state)
                1'b0: begin  // vacant                        
                    if (d_waiting) begin
                        state <= 1;
                        m_wr <= d_wr;
                        m_len <= d_len;
                        m_addr <= d_addr;
                        m_value <= d_value;
                        current_addr <= d_addr;
                    end
                    else if (i_waiting) begin
                        if (i_hit) begin
                            current_addr <= i_addr;
                        end
                        else begin
                            state <= 1;
                            m_wr <= 0;
                            m_len <= 2;
                            m_addr <= i_addr;
                            m_value <= 0;
                            current_addr <= i_addr;
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
