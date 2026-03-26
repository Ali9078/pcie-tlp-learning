module tb_cq_parser;

// -- DUT signals --------------------------------------------------
reg           clk, rst_n;
reg  [511:0]  s_axis_tdata;
reg  [63:0]   s_axis_tkeep; // Updated to 64-bit for 512-bit data
reg           s_axis_tvalid, s_axis_tlast;
wire          s_axis_tready;

// Metadata signals
wire [2:0]   m_tlp_type;
wire [9:0]   m_tlp_length;
wire [63:0]  m_tlp_addr;
wire [15:0]  m_tlp_id;
wire [7:0]   m_tlp_tag;
wire [3:0]   m_tlp_first_be, m_tlp_last_be;
wire         m_meta_valid, m_has_payload;

// Payload interface
wire [511:0] m_axi_tdata;
wire [63:0]  m_axi_tkeep; // Updated to 64-bit
wire         m_axi_tvalid, m_axi_tlast;
reg          m_axi_tready;

initial m_axi_tready = 1'b1;  // downstream always ready in TB

// -- Instantiate DUT -----------------------------------------------
cq_parser #(
    .AXI_DATA_WIDTH(512)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axi_tdata(m_axi_tdata),
    .m_axi_tkeep(m_axi_tkeep),
    .m_axi_tvalid(m_axi_tvalid),
    .m_axi_tready(m_axi_tready),
    .m_axi_tlast(m_axi_tlast),
    .m_tlp_type(m_tlp_type),
    .m_tlp_length(m_tlp_length),
    .m_tlp_addr(m_tlp_addr),
    .m_tlp_id(m_tlp_id),
    .m_tlp_tag(m_tlp_tag),
    .m_tlp_first_be(m_tlp_first_be),
    .m_tlp_last_be(m_tlp_last_be),
    .m_meta_valid(m_meta_valid),
    .m_has_payload(m_has_payload)
);

// -- Clock: 250 MHz ------------------------------------------------
initial clk = 0;
always #2 clk = ~clk;

// -- Task: send one AXI-S beat -------------------------------------
task send_beat;
    input [511:0] data;
    input [63:0]  keep;
    input         last;
    begin
        s_axis_tdata  = data;
        s_axis_tkeep  = keep;
        s_axis_tlast  = last;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk); 
        s_axis_tvalid = 1'b0;
    end
endtask

// -- Task: check output --------------------------------------------
task check;
    input [63:0] exp_addr;
    input [9:0]  exp_len;
    input         exp_payload;
    begin
        @(posedge clk);
        if (m_meta_valid) begin
            if (m_tlp_addr !== exp_addr)
                $display("FAIL: address %h expected %h", m_tlp_addr, exp_addr);
            else if (m_tlp_length !== exp_len)
                $display("FAIL: length %d expected %d", m_tlp_length, exp_len);
            else
                $display("PASS: addr=%h len=%0d pay=%b",
                          m_tlp_addr, m_tlp_length, m_has_payload);
        end
    end
endtask

// -- Test cases ----------------------------------------------------
initial begin
    $dumpfile("tb_cq_parser.vcd");
    $dumpvars(0, tb_cq_parser);

    rst_n = 0; s_axis_tvalid = 0;
    @(posedge clk); @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    $display("--- Test 1: 4DW MemWrite, 4-byte payload ---");
    send_beat(
        {384'hDEAD_1234_5678_9ABC, 
         32'hCAFEBABE,              
         32'hDEADBEEF,              
         32'h0100_AB_FF,            
         32'h6000_0001},            
        64'hFFFF_FFFF_FFFF_FFFF,    
        1'b1                        
    );
    #4;
    check(64'hDEADBEEFCAFEBABE, 10'd1, 1'b1);

    $display("--- Test 2: 3DW MemRead, no payload ---");
    send_beat(
        {416'h0,
         32'hDEAD_BEEF,   
         32'h0200_CD_0F,  
         32'h2000_0004},  
        64'h0000_0000_0000_0FFF,    
        1'b1
    );
    #4;
    check(64'h00000000DEADBEEF, 10'd4, 1'b0);

    $display("--- Test 3: Multi-beat MemWrite ---");
    send_beat(
        {384'hAAAA_BBBB_CCCC,  
         32'h0000_1000,       
         32'h0000_0000,       
         32'h0300_EE_FF,      
         32'h6000_0010},      
        64'hFFFF_FFFF_FFFF_FFFF, 1'b0 
    );
    send_beat(
        512'hDDDD_EEEE_FFFF_0000,
        64'hFFFF_FFFF_FFFF_FFFF, 1'b1
    );
    #4;
    check(64'h0000000000001000, 10'd16, 1'b1);

    $display("--- All tests done ---");
    #20 $finish;
end

endmodule