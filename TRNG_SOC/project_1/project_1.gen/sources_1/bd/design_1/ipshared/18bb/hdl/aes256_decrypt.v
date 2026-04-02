`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name: aes256_decrypt
// Description: AES256 복호화 IP 최상위 래퍼
//
// 키 공유 구조:
//   encrypt IP의 key_man이 TRNG 키를 BRAM Port B에 저장
//   decrypt IP는 BRAM Port A (read-only)로 동일한 키를 읽음
//   → blk_mem_gen True Dual Port 사용
//      Port A : aes256_decrypt (읽기 전용)
//      Port B : aes256_encrypt의 key_man (쓰기 + enc_core 읽기)
//
// 외부 신호:
//   key_ready_in  : encrypt IP key_man의 key_ready  (level)
//   key_reload_in : encrypt IP key_man의 key_reload (1클록 펄스)
//
// Register Map (AXI4-Lite, byte addr):
//   0x00 CTRL    [RW] [0]=start 펄스
//   0x04 STATUS  [RO] [0]=done, [1]=busy, [2]=key_ready (= key_ready_in)
//   0x08 DIN_0   [RW] 암호문[31:0]
//   0x0C DIN_1   [RW] 암호문[63:32]
//   0x10 DIN_2   [RW] 암호문[95:64]
//   0x14 DIN_3   [RW] 암호문[127:96]
//   0x18 DOUT_0  [RO] 평문[31:0]
//   0x1C DOUT_1  [RO] 평문[63:32]
//   0x20 DOUT_2  [RO] 평문[95:64]
//   0x24 DOUT_3  [RO] 평문[127:96]
//////////////////////////////////////////////////////////////////////////////////

module aes256_decrypt #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 7
)
(
    // ── BRAM Port A (키 읽기 전용, encrypt IP와 공유 blk_mem_gen) ────────
    output wire [31:0]  bram_addra,   // 32bit 바이트 주소
    output wire         bram_ena,     // 읽기 인에이블
    input  wire [31:0]  bram_douta,   // 읽기 데이터
    output wire         bram_clka,    // = s00_axi_aclk

    // ── encrypt IP key_man 상태 입력 ─────────────────────────────────────
    input  wire         key_ready_in,   // level: BRAM에 유효한 키 저장됨
    input  wire         key_reload_in,  // 1클록 펄스: 새 키 기록 완료

    // ── AXI4-Lite Slave 인터페이스 ────────────────────────────────────────
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire  [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr,
    input wire  [2:0]  s00_axi_awprot,
    input wire         s00_axi_awvalid,
    output wire        s00_axi_awready,
    input wire  [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,
    input wire  [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input wire         s00_axi_wvalid,
    output wire        s00_axi_wready,
    output wire [1:0]  s00_axi_bresp,
    output wire        s00_axi_bvalid,
    input wire         s00_axi_bready,
    input wire  [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr,
    input wire  [2:0]  s00_axi_arprot,
    input wire         s00_axi_arvalid,
    output wire        s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0]  s00_axi_rresp,
    output wire        s00_axi_rvalid,
    input wire         s00_axi_rready
);

    // =========================================================================
    // 내부 신호
    // =========================================================================
    wire        aes_start;
    wire        aes_done;
    wire        aes_busy;
    wire [127:0] aes_data_in;
    wire [127:0] aes_data_out;

    // dec_core ↔ BRAM Port A (워드 주소, 상위에서 바이트 변환)
    wire [3:0]  core_bram_addr;
    wire        core_bram_en;
    wire [31:0] core_bram_dout;

    // =========================================================================
    // BRAM Port A 연결
    // dec_core 워드 주소(0~7) → 32bit 바이트 주소 변환 (key_man 방식 동일)
    // =========================================================================
    assign bram_addra  = {27'h0, core_bram_addr[2:0], 2'b00};
    assign bram_ena    = core_bram_en;
    assign core_bram_dout = bram_douta;
    assign bram_clka   = s00_axi_aclk;

    // =========================================================================
    // AES256 복호화 코어 인스턴스
    // =========================================================================
    aes256_dec_core u_aes256_dec (
        .clk           (s00_axi_aclk),
        .rst_n         (s00_axi_aresetn),
        .bram_addr     (core_bram_addr),
        .bram_en       (core_bram_en),
        .bram_dout     (core_bram_dout),
        .key_ready_in  (key_ready_in),
        .key_reload_in (key_reload_in),
        .start         (aes_start),
        .data_in       (aes_data_in),
        .data_out      (aes_data_out),
        .done          (aes_done),
        .busy          (aes_busy)
    );

    // =========================================================================
    // AXI4-Lite 슬레이브 인스턴스
    // STATUS[2] = key_ready_in (PS가 키 준비 여부 확인 가능)
    // =========================================================================
    aes256_decrypt_slave_lite_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH)
    ) aes256_decrypt_slave_lite_v1_0_S00_AXI_inst (
        .aes_start       (aes_start),
        .aes_done        (aes_done),
        .aes_busy        (aes_busy),
        .aes_key_ready   (key_ready_in),
        .aes_data_in     (aes_data_in),
        .aes_data_out    (aes_data_out),
        .S_AXI_ACLK      (s00_axi_aclk),
        .S_AXI_ARESETN   (s00_axi_aresetn),
        .S_AXI_AWADDR    (s00_axi_awaddr),
        .S_AXI_AWPROT    (s00_axi_awprot),
        .S_AXI_AWVALID   (s00_axi_awvalid),
        .S_AXI_AWREADY   (s00_axi_awready),
        .S_AXI_WDATA     (s00_axi_wdata),
        .S_AXI_WSTRB     (s00_axi_wstrb),
        .S_AXI_WVALID    (s00_axi_wvalid),
        .S_AXI_WREADY    (s00_axi_wready),
        .S_AXI_BRESP     (s00_axi_bresp),
        .S_AXI_BVALID    (s00_axi_bvalid),
        .S_AXI_BREADY    (s00_axi_bready),
        .S_AXI_ARADDR    (s00_axi_araddr),
        .S_AXI_ARPROT    (s00_axi_arprot),
        .S_AXI_ARVALID   (s00_axi_arvalid),
        .S_AXI_ARREADY   (s00_axi_arready),
        .S_AXI_RDATA     (s00_axi_rdata),
        .S_AXI_RRESP     (s00_axi_rresp),
        .S_AXI_RVALID    (s00_axi_rvalid),
        .S_AXI_RREADY    (s00_axi_rready)
    );

endmodule
