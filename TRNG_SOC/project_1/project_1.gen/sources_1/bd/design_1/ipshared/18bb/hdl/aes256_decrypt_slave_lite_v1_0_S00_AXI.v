`timescale 1 ns / 1 ps

module aes256_decrypt_slave_lite_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)
(
    // AES256 복호화 코어 인터페이스
    output wire         aes_start,
    input  wire         aes_done,
    input  wire         aes_busy,
    input  wire         aes_key_ready,
    output wire [127:0] aes_data_in,
    input  wire [127:0] aes_data_out,

    // AXI4-Lite 슬레이브 포트
    input  wire                          S_AXI_ACLK,
    input  wire                          S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]                    S_AXI_AWPROT,
    input  wire                          S_AXI_AWVALID,
    output wire                          S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                          S_AXI_WVALID,
    output wire                          S_AXI_WREADY,
    output wire [1:0]                    S_AXI_BRESP,
    output wire                          S_AXI_BVALID,
    input  wire                          S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]                    S_AXI_ARPROT,
    input  wire                          S_AXI_ARVALID,
    output wire                          S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]                    S_AXI_RRESP,
    output wire                          S_AXI_RVALID,
    input  wire                          S_AXI_RREADY
);

    // =========================================================================
    // AXI4-Lite 내부 신호
    // =========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg  axi_awready, axi_wready, axi_bvalid;
    reg [1:0] axi_bresp;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg  axi_arready, axi_rvalid;
    reg [1:0] axi_rresp;

    localparam integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 3;  // 2^4 = 16 주소 → 10개 레지스터 충분

    // =========================================================================
    // 슬레이브 레지스터 (10개)
    // reg0=CTRL, reg1=STATUS(RO), reg2~5=DIN, reg6~9=DOUT(RO)
    // =========================================================================
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;   // CTRL
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;   // DIN_0  암호문[31:0]
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;   // DIN_1  암호문[63:32]
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;   // DIN_2  암호문[95:64]
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg5;   // DIN_3  암호문[127:96]
    integer byte_index;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    reg [1:0] state_write, state_read;
    localparam Idle  = 2'b00;
    localparam Raddr = 2'b10;
    localparam Rdata = 2'b11;
    localparam Waddr = 2'b10;
    localparam Wdata = 2'b11;

    // =========================================================================
    // 쓰기 상태머신
    // =========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 0; axi_wready <= 0;
            axi_bvalid  <= 0; axi_bresp  <= 0;
            axi_awaddr  <= 0; state_write <= Idle;
        end else begin
            case (state_write)
                Idle: begin
                    if (S_AXI_ARESETN) begin
                        axi_awready <= 1'b1;
                        axi_wready  <= 1'b1;
                        state_write <= Waddr;
                    end
                end
                Waddr: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        axi_awaddr <= S_AXI_AWADDR;
                        if (S_AXI_WVALID) begin
                            axi_awready <= 1'b1;
                            state_write <= Waddr;
                            axi_bvalid  <= 1'b1;
                        end else begin
                            axi_awready <= 1'b0;
                            state_write <= Wdata;
                            if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                        end
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
                Wdata: begin
                    if (S_AXI_WVALID) begin
                        state_write <= Waddr;
                        axi_bvalid  <= 1'b1;
                        axi_awready <= 1'b1;
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 레지스터 쓰기 (CTRL, DIN만 쓰기 가능 / STATUS, DOUT는 읽기 전용)
    // =========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0 <= 0;
            slv_reg2 <= 0; slv_reg3 <= 0;
            slv_reg4 <= 0; slv_reg5 <= 0;
        end else begin
            if (S_AXI_WVALID) begin
                case ((S_AXI_AWVALID) ?
                      S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] :
                      axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    4'h0: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index])
                                  slv_reg0[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8]; // CTRL
                    4'h2: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index])
                                  slv_reg2[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8]; // DIN_0
                    4'h3: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index])
                                  slv_reg3[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8]; // DIN_1
                    4'h4: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index])
                                  slv_reg4[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8]; // DIN_2
                    4'h5: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index])
                                  slv_reg5[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8]; // DIN_3
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 읽기 상태머신
    // =========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0; axi_rvalid <= 1'b0;
            axi_rresp   <= 1'b0; state_read <= Idle;
        end else begin
            case (state_read)
                Idle: begin
                    if (S_AXI_ARESETN) begin
                        state_read  <= Raddr;
                        axi_arready <= 1'b1;
                    end
                end
                Raddr: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        state_read  <= Rdata;
                        axi_araddr  <= S_AXI_ARADDR;
                        axi_rvalid  <= 1'b1;
                        axi_arready <= 1'b0;
                    end else state_read <= state_read;
                end
                Rdata: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        axi_rvalid  <= 1'b0;
                        axi_arready <= 1'b1;
                        state_read  <= Raddr;
                    end else state_read <= state_read;
                end
            endcase
        end
    end

    // =========================================================================
    // 읽기 데이터 선택
    // STATUS, DOUT는 복호화 코어 출력을 직접 반환
    // =========================================================================
    wire [3:0] rd_sel = axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
    assign S_AXI_RDATA =
        (rd_sel == 4'h0) ? slv_reg0                                     : // CTRL
        (rd_sel == 4'h1) ? {29'b0, aes_key_ready, aes_busy, aes_done}  : // STATUS
        (rd_sel == 4'h2) ? slv_reg2                                     : // DIN_0  암호문
        (rd_sel == 4'h3) ? slv_reg3                                     : // DIN_1  암호문
        (rd_sel == 4'h4) ? slv_reg4                                     : // DIN_2  암호문
        (rd_sel == 4'h5) ? slv_reg5                                     : // DIN_3  암호문
        (rd_sel == 4'h6) ? aes_data_out[31:0]                          : // DOUT_0 평문
        (rd_sel == 4'h7) ? aes_data_out[63:32]                         : // DOUT_1 평문
        (rd_sel == 4'h8) ? aes_data_out[95:64]                         : // DOUT_2 평문
        (rd_sel == 4'h9) ? aes_data_out[127:96]                        : // DOUT_3 평문
        32'h0;

    // =========================================================================
    // AES 코어 신호 매핑
    // =========================================================================
    // start 펄스: CTRL[0] 라이징 엣지 → 1클록 펄스
    reg start_prev;
    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) start_prev <= 1'b0;
        else                start_prev <= slv_reg0[0];
    end

    assign aes_start   = slv_reg0[0] & ~start_prev;
    assign aes_data_in = {slv_reg5, slv_reg4, slv_reg3, slv_reg2};

endmodule
