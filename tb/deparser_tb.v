module tb_rq_deparser;

reg clk=0, rst_n;
reg [63:0] s_tlp_addr; 
reg [9:0]  s_tlp_length;
reg [7:0]  s_tlp_tag; 
reg [3:0]  s_tlp_first_be, s_tlp_last_be;
reg s_meta_valid;

reg [511:0] s_axi_tdata; 
reg [15:0]  s_axi_tkeep;
reg s_axi_tvalid, s_axi_tlast, m_axis_tready=1;

wire s_meta_ready, s_axi_tready;
wire [511:0] m_axis_tdata; 
wire [15:0]  m_axis_tkeep;
wire m_axis_tvalid, m_axis_tlast;

rq_deparser #(.MY_REQUESTER_ID(16'h0100)) dut(.*);

always #2 clk=~clk;

task pay_beat; 
    input [511:0] d; 
    input [15:0] k; 
    input l;
    begin 
        s_axi_tdata=d; 
        s_axi_tkeep=k; 
        s_axi_tlast=l; 
        s_axi_tvalid=1;
        @(posedge clk); 
        while(!s_axi_tready) @(posedge clk); 
        s_axi_tvalid=0; 
    end
endtask

task meta; 
    input [63:0] a; 
    input [9:0] l; 
    input [7:0] t;
    begin 
        s_tlp_addr=a; 
        s_tlp_length=l; 
        s_tlp_tag=t; 
        s_tlp_first_be=4'hF; 
        s_tlp_last_be=4'hF; 
        s_meta_valid=1;
        @(posedge clk); 
        while(!s_meta_ready) @(posedge clk); 
        s_meta_valid=0; 
    end
endtask

always @(posedge clk)
    if(m_axis_tvalid && m_axis_tready)
        $display("[RQ] DW0=%08h DW1=%08h DW2=%08h DW3=%08h last=%b",
            m_axis_tdata[31:0],   m_axis_tdata[63:32],
            m_axis_tdata[95:64],  m_axis_tdata[127:96], m_axis_tlast);

initial begin
    $dumpfile("tb_rq.vcd"); 
    $dumpvars(0,tb_rq_deparser);
    rst_n=0; 
    s_meta_valid=0; 
    s_axi_tvalid=0;
    
    @(posedge clk); @(posedge clk); 
    rst_n=1; 
    @(posedge clk);

    $display("Test 1: 1-DWord fits in beat 0");
    fork
        meta(64'hDEAD_BEEF_CAFE_1000, 10'd1, 8'hAA);
        pay_beat({480'h0, 32'h12345678}, 16'hFFFF, 1);
    join
    #20;

    $display(" Test 2: 16-DWord 2 beats");
    fork
        meta(64'h0000000100000000, 10'd16, 8'hBB);
        begin
            pay_beat(512'hAAAA_BBBB_CCCC_DDDD, 16'hFFFF, 0);
            pay_beat(512'hEEEE_FFFF_0000_1111, 16'hFFFF, 1);
        end
    join
    #20;

    $display(" All done ");
    $finish;
end
endmodule