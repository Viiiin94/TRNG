`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: aes256_encrypt
// Description: AES256 암호화 IP 최상위 래퍼
//
// 동작 흐름:
//   TRNG rand_valid → key_manager → BRAM Port B 쓰기 (256bit 키)
//   key_reload 펄스 → aes256_enc_core 키 재로드
//   PS AXI Write DIN → aes256_enc_core 암호화 → DOUT 읽기
//
// Register Map (AXI4-Lite, byte addr):
//   0x00 CTRL    [RW] [0]=start 펄스
//   0x04 STATUS  [RO] [0]=done, [1]=busy, [2]=key_ready
//   0x08 DIN_0   [RW] 평문[31:0]
//   0x0C DIN_1   [RW] 평문[63:32]
//   0x10 DIN_2   [RW] 평문[95:64]
//   0x14 DIN_3   [RW] 평문[127:96]
//   0x18 DOUT_0  [RO] 암호문[31:0]
//   0x1C DOUT_1  [RO] 암호문[63:32]
//   0x20 DOUT_2  [RO] 암호문[95:64]
//   0x24 DOUT_3  [RO] 암호문[127:96]
//////////////////////////////////////////////////////////////////////////////////

module aes256_encrypt #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 7
)
(
    // ── TRNG 키 입력 ───────────────────────────────────────────────────────
    input  wire [255:0] rand_data,    // TRNG 256bit 랜덤 키
    input  wire         rand_valid,   // TRNG 유효 펄스 (1클록)

    // ── key_manager 상태 출력 (→ aes256_decrypt) ─────────────────────────
    output wire         key_ready_out,  // level: BRAM에 유효한 키 저장됨
    output wire         key_reload_out, // 1클록 펄스: 새 키 기록 완료

    // ── BRAM Port B (key_manager → blk_mem_gen Port B) ────────────────────
    output wire [31:0]  bram_addrb,   // 32bit 바이트 주소
    output wire [31:0]  bram_dinb,    // 쓰기 데이터
    output wire [3:0]   bram_web,     // 바이트 쓰기 인에이블
    output wire         bram_enb,     // 포트 인에이블
    output wire         bram_rstb,    // 동기 리셋 (0 고정)
    input  wire [31:0]  bram_doutb,   // 읽기 데이터
    output wire         bram_clkb,    // 포트 B 클럭 (aclk 연결)

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

    wire        key_ready;
    wire        key_reload;

    assign key_ready_out  = key_ready;
    assign key_reload_out = key_reload;

    // AES 코어 ↔ key_manager BRAM 중재 신호
    wire [3:0]  core_bram_addr;
    wire        core_bram_en;
    wire [31:0] core_bram_dout;

    // BRAM Port B 클럭 = AXI 클럭
    assign bram_clkb = s00_axi_aclk;

    // =========================================================================
    // key_manager 인스턴스
    // TRNG → BRAM Port B 키 쓰기 / AES 읽기 중재
    // =========================================================================
    key_man u_key_mgr (
        .clk           (s00_axi_aclk),
        .rst_n         (s00_axi_aresetn),
        // TRNG
        .rand_data     (rand_data),
        .rand_valid    (rand_valid),
        // BRAM Port B
        .bram_addrb    (bram_addrb),
        .bram_dinb     (bram_dinb),
        .bram_web      (bram_web),
        .bram_enb      (bram_enb),
        .bram_rstb     (bram_rstb),
        .bram_doutb    (bram_doutb),
        // AES 코어 읽기 중재
        .aes_bram_addr (core_bram_addr),
        .aes_bram_en   (core_bram_en),
        .aes_bram_dout (core_bram_dout),
        // 상태
        .key_ready     (key_ready),
        .key_reload    (key_reload)
    );

    // =========================================================================
    // AES256 암호화 코어 인스턴스
    // =========================================================================
    aes256_enc_core u_aes256_enc (
        .clk        (s00_axi_aclk),
        .rst_n      (s00_axi_aresetn),
        // BRAM 키 읽기 (key_manager 경유)
        .bram_addr  (core_bram_addr),
        .bram_en    (core_bram_en),
        .bram_dout  (core_bram_dout),
        // 키 재로드
        .key_reload (key_reload),
        // AES 제어
        .start      (aes_start),
        .data_in    (aes_data_in),
        .data_out   (aes_data_out),
        .done       (aes_done),
        .busy       (aes_busy)
    );

    // =========================================================================
    // AXI4-Lite 슬레이브 인스턴스
    // =========================================================================
    aes256_encrypt_slave_lite_v1_0_S00_AXI #(
        .C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH)
    ) aes256_encrypt_slave_lite_v1_0_S00_AXI_inst (
        .aes_start       (aes_start),
        .aes_done        (aes_done),
        .aes_busy        (aes_busy),
        .aes_key_ready   (key_ready),
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
