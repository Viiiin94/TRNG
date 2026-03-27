`timescale 1 ns / 1 ps

// =============================================================================
// myip_trng256 - TRNG256 AXI IP 최상위 래퍼
//
// AXI4-Lite Slave 인터페이스를 통해 TRNG256 코어를 제어/읽기.
// ILA 디버그용 포트 및 key_manager 연결용 256bit 출력 포함.
// =============================================================================

module myip_trng256 #
(
    // Users to add parameters here
    parameter integer SIM_MODE   = 0,   // 1=시뮬레이션(LFSR), 0=합성(RO)
    parameter integer FIFO_DEPTH = 64,  // FIFO 깊이 (256bit 워드 단위)

    // User parameters ends
    // Do not modify the parameters beyond this line

    // Parameters of Axi Slave Bus Interface S00_AXI
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 6
)
(
    // Users to add ports here

    // key_manager 연결용 전체 256bit 출력
    output wire [255:0] rand_data_out,
    output wire         rand_valid_key,

    // User ports ends
    // Do not modify the ports beyond this line

    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready
);

    // Instantiation of Axi Bus Interface S00_AXI
    myip_trng256_slave_lite_v1_0_S00_AXI #(
        .SIM_MODE             (SIM_MODE),
        .FIFO_DEPTH           (FIFO_DEPTH),
        .C_S_AXI_DATA_WIDTH   (C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH   (C_S00_AXI_ADDR_WIDTH)
    ) myip_trng256_slave_lite_v1_0_S00_AXI_inst (
        // User ports
        .rand_data_out    (rand_data_out),
        .rand_valid_key   (rand_valid_key),
        // AXI ports
        .S_AXI_ACLK       (s00_axi_aclk),
        .S_AXI_ARESETN    (s00_axi_aresetn),
        .S_AXI_AWADDR     (s00_axi_awaddr),
        .S_AXI_AWPROT     (s00_axi_awprot),
        .S_AXI_AWVALID    (s00_axi_awvalid),
        .S_AXI_AWREADY    (s00_axi_awready),
        .S_AXI_WDATA      (s00_axi_wdata),
        .S_AXI_WSTRB      (s00_axi_wstrb),
        .S_AXI_WVALID     (s00_axi_wvalid),
        .S_AXI_WREADY     (s00_axi_wready),
        .S_AXI_BRESP      (s00_axi_bresp),
        .S_AXI_BVALID     (s00_axi_bvalid),
        .S_AXI_BREADY     (s00_axi_bready),
        .S_AXI_ARADDR     (s00_axi_araddr),
        .S_AXI_ARPROT     (s00_axi_arprot),
        .S_AXI_ARVALID    (s00_axi_arvalid),
        .S_AXI_ARREADY    (s00_axi_arready),
        .S_AXI_RDATA      (s00_axi_rdata),
        .S_AXI_RRESP      (s00_axi_rresp),
        .S_AXI_RVALID     (s00_axi_rvalid),
        .S_AXI_RREADY     (s00_axi_rready)
    );

endmodule
