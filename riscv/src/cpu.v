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

    reg [2:0] counter;
    reg wating;
    reg wr;
    reg [2:0] len;
    reg [31:0] addr;
    reg [31:0] value;
    reg beg;

    wire ready;
    wire [31:0] result;
    MemoryController mc (
        clk_in,
        rst_in,
        rdy_in,
        mem_din,
        mem_dout,
        mem_a,
        mem_wr,
        wating,
        wr,
        len,
        addr,
        value,
        ready,
        result
    );

    always @(posedge clk_in) begin
        if (rst_in) begin            
            counter <= 0;
            beg <= 1;
            wating <= 1;
            wr <= 0;
            len <= 2;
            addr <= 0;
            value <= 0;
        end
        else if (!rdy_in) begin

        end
        else begin                    
            
            if (ready || beg) begin
                $display("result: %h", result);
                $display("ojbk");
                if (!beg) begin
                    addr <= addr + 4;
                end
                beg <= 0;                
            end
        end
    end

endmodule
