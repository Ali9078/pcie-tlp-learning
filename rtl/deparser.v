module rq_deparser #(
    parameter [15:0] MY_REQUESTER_ID = 16'h0100
) (
    input  wire          clk, rst_n,
    
    // Metadata Input
    input  wire [63:0]   s_tlp_addr,
    input  wire [9:0]    s_tlp_length,
    input  wire [7:0]    s_tlp_tag,
    input  wire [3:0]    s_tlp_first_be, s_tlp_last_be,
    input  wire          s_meta_valid,
    output reg           s_meta_ready,
    
    // AXI Stream Input (from Data Source)
    input  wire [511:0]  s_axi_tdata,
    input  wire [15:0]   s_axi_tkeep,
    input  wire          s_axi_tvalid, s_axi_tlast,
    output reg           s_axi_tready,
    
    // AXI Stream Output (to PCIe RQ Interface)
    output reg  [511:0]  m_axis_tdata,
    output reg  [15:0]   m_axis_tkeep,
    output reg           m_axis_tvalid, m_axis_tlast,
    input  wire          m_axis_tready
);

localparam [1:0] ST_IDLE = 2'd0, 
                 ST_BUILD_HDR = 2'd1, 
                 ST_SEND_PAY = 2'd2;

reg [1:0] state;

// Latched metadata
reg [63:0] tlp_addr_r;
reg [9:0]  tlp_length_r;
reg [7:0]  tlp_tag_r;
reg [3:0]  tlp_first_be_r, tlp_last_be_r;

// Header DWords
wire [31:0] hdr_dw0 = {3'b011, 5'b00000, 14'b0, tlp_length_r};
wire [31:0] hdr_dw1 = {MY_REQUESTER_ID, tlp_tag_r, tlp_last_be_r, tlp_first_be_r};
wire [31:0] hdr_dw2 = tlp_addr_r[63:32];
wire [31:0] hdr_dw3 = {tlp_addr_r[31:2], 2'b00};

// Beat 0 construction
wire [511:0] beat0_tdata = {s_axi_tdata[511:128], hdr_dw3, hdr_dw2, hdr_dw1, hdr_dw0};
wire [15:0]  beat0_tkeep = {s_axi_tkeep[15:4], 4'hF};
wire         fits_in_b0  = s_axi_tlast && (tlp_length_r <= 10'd12);

// Handshakes
wire meta_xfer = s_meta_valid && s_meta_ready;
wire rq_xfer   = m_axis_tvalid && m_axis_tready;

// Metadata latch
always @(posedge clk) begin
    if (meta_xfer) begin
        tlp_addr_r     <= s_tlp_addr; 
        tlp_length_r   <= s_tlp_length;
        tlp_tag_r      <= s_tlp_tag; 
        tlp_first_be_r <= s_tlp_first_be; 
        tlp_last_be_r  <= s_tlp_last_be;
    end
end

// Output logic (combinational)
always @(*) begin
    s_meta_ready  = 0; 
    s_axi_tready  = 0;
    m_axis_tvalid = 0; 
    m_axis_tlast  = 0;
    m_axis_tdata  = 0; 
    m_axis_tkeep  = 0;
    
    case (state)
        ST_IDLE: s_meta_ready = 1;
        ST_BUILD_HDR: if (s_axi_tvalid) begin
            m_axis_tdata  = beat0_tdata; 
            m_axis_tkeep  = beat0_tkeep;
            m_axis_tvalid = 1; 
            m_axis_tlast  = fits_in_b0;
            s_axi_tready  = m_axis_tready;
        end
        ST_SEND_PAY: begin
            m_axis_tdata  = s_axi_tdata; 
            m_axis_tkeep  = s_axi_tkeep;
            m_axis_tvalid = s_axi_tvalid; 
            m_axis_tlast  = s_axi_tlast;
            s_axi_tready  = m_axis_tready;
        end
    endcase
end

// State transitions
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= ST_IDLE;
    else case (state)
        ST_IDLE:      if (meta_xfer) state <= ST_BUILD_HDR;
        ST_BUILD_HDR: if (rq_xfer) state <= fits_in_b0 ? ST_IDLE : ST_SEND_PAY;
        ST_SEND_PAY:  if (rq_xfer && m_axis_tlast) state <= ST_IDLE;
    endcase
end

endmodule