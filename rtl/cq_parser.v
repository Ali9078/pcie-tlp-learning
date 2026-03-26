module cq_parser #(
    parameter AXI_DATA_WIDTH = 512
)(
    input wire clk,
    input wire rst_n,

    // AXI Stream input from PCIe IP
    input wire[AXI_DATA_WIDTH-1:0] s_axis_tdata,
    input wire[(AXI_DATA_WIDTH/8)-1:0] s_axis_tkeep,
    input wire s_axis_tvalid,   
    output reg s_axis_tready,
    input wire s_axis_tlast,

    // AXI Stream interface to CQ (payload data only)
    output reg[AXI_DATA_WIDTH-1:0] m_axi_tdata,
    output reg[(AXI_DATA_WIDTH/8)-1:0] m_axi_tkeep,
    output reg m_axi_tvalid,
    input wire m_axi_tready,
    output reg m_axi_tlast,

    // AXI Stream interface to CQ (parsed metadata)
    output reg[2:0] m_tlp_type,
    output reg[9:0] m_tlp_length,
    output reg[63:0] m_tlp_addr,
    output reg[15:0] m_tlp_id,
    output reg[7:0] m_tlp_tag,
    output reg[3:0] m_tlp_first_be,
    output reg[3:0] m_tlp_last_be,
    output reg m_meta_valid,
    output reg m_has_payload
);

localparam[1:0] IDLE = 2'b00,
                PARSE_HEADER = 2'b01,
                TRANSFER_PAYLOAD = 2'b10;

reg[1:0] state, next_state;

// Dword extraction
wire [31:0] dw0 = s_axis_tdata[31:0];
wire [31:0] dw1 = s_axis_tdata[63:32];
wire [31:0] dw2 = s_axis_tdata[95:64];
wire [31:0] dw3 = s_axis_tdata[127:96];

// TLP header fields
wire [2:0]  fmt      = dw0[31:29];
wire [9:0]  length_w = dw0[9:0];
wire        is_4dw   = fmt[0];
wire        has_data = fmt[1];

wire [15:0] req_id_w  = dw1[31:16];
wire [7:0]  tag_w     = dw1[15:8];
wire [3:0]  last_be_w = dw1[7:4];
wire [3:0]  frst_be_w = dw1[3:0];

wire [63:0] addr_w = is_4dw ? {dw2, dw3} : {32'h0, dw2};

wire[2:0] tlp_type_enc = {1'b0, is_4dw, has_data ? 1'b0 : 1'b1}; 

// Beat-0 payload extraction
wire [AXI_DATA_WIDTH-1:0] b0_pay_data = is_4dw
    ? {128'h0, s_axis_tdata[AXI_DATA_WIDTH-1:128]}
    : {96'h0,  s_axis_tdata[AXI_DATA_WIDTH-1:96]};

wire [(AXI_DATA_WIDTH/8)-1:0] b0_pay_keep = is_4dw
    ? {s_axis_tkeep[(AXI_DATA_WIDTH/8)-1:4], 4'h0}
    : {s_axis_tkeep[(AXI_DATA_WIDTH/8)-1:3], 3'h0};

wire xfer = s_axis_tvalid && s_axis_tready;

// tready logic
always @(*) begin
    case (state)
        IDLE:             s_axis_tready = 1'b1;
        PARSE_HEADER:     s_axis_tready = 1'b1;
        TRANSFER_PAYLOAD: s_axis_tready = m_axi_tready;
        default:          s_axis_tready = 1'b1;
    endcase
end

// Synchronous Logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= IDLE;
        m_meta_valid <= 1'b0;
        m_axi_tvalid <= 1'b0;
        m_axi_tlast  <= 1'b0;
    end else begin
        // Pulse clearing
        m_meta_valid <= 1'b0;
        m_axi_tvalid <= 1'b0;
        m_axi_tlast  <= 1'b0;

        case (state)
            IDLE: begin
                if (xfer) begin
                    m_tlp_type     <= tlp_type_enc;
                    m_tlp_addr     <= addr_w;
                    m_tlp_length   <= length_w;
                    m_tlp_id       <= req_id_w;
                    m_tlp_tag      <= tag_w;
                    m_tlp_first_be <= frst_be_w;
                    m_tlp_last_be  <= last_be_w;
                    m_has_payload  <= has_data;
                    m_meta_valid   <= 1'b1;

                    if (has_data && !s_axis_tlast) begin
                        m_axi_tdata  <= b0_pay_data;
                        m_axi_tkeep  <= b0_pay_keep;
                        m_axi_tvalid <= 1'b1;
                        m_axi_tlast  <= 1'b0;
                        state        <= TRANSFER_PAYLOAD;
                    end else if (has_data && s_axis_tlast) begin
                        m_axi_tdata  <= b0_pay_data;
                        m_axi_tkeep  <= b0_pay_keep;
                        m_axi_tvalid <= 1'b1;
                        m_axi_tlast  <= 1'b1;
                        state        <= IDLE;
                    end else begin
                        state        <= IDLE;
                    end
                end
            end

            TRANSFER_PAYLOAD: begin
                if (xfer) begin
                    m_axi_tdata  <= s_axis_tdata;
                    m_axi_tkeep  <= s_axis_tkeep;
                    m_axi_tvalid <= 1'b1;
                    m_axi_tlast  <= s_axis_tlast;
                    if (s_axis_tlast)
                        state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule