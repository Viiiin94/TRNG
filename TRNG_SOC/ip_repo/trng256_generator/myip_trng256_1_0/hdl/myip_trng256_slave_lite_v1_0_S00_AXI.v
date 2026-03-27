`timescale 1 ns / 1 ps

// =============================================================================
// myip_trng256_slave_lite_v1_0_S00_AXI
//
// AXI4-Lite Slave + TRNG256 Core 통합 구현
//
// Register Map (32-bit, byte addr):
//   0x00  CTRL    [RW]  [0]=enable, [1]=sw_reset
//   0x04  STATUS  [RO]  [0]=data_valid, [1]=fifo_empty, [2]=fifo_full,
//                        [3]=health_fail, [4]=rct_fail, [5]=apt_fail
//   0x08  DATA_0  [RO]  rand_data[31:0]    (읽으면 FIFO pop)
//   0x0C  DATA_1  [RO]  rand_data[63:32]
//   0x10  DATA_2  [RO]  rand_data[95:64]
//   0x14  DATA_3  [RO]  rand_data[127:96]
//   0x18  DATA_4  [RO]  rand_data[159:128]
//   0x1C  DATA_5  [RO]  rand_data[191:160]
//   0x20  DATA_6  [RO]  rand_data[223:192]
//   0x24  DATA_7  [RO]  rand_data[255:224]  (읽으면 read_buf_valid 클리어)
//   0x28  COUNT   [RO]  생성 카운터
// =============================================================================

module myip_trng256_slave_lite_v1_0_S00_AXI #
(
    // Users to add parameters here
    parameter integer SIM_MODE        = 0,   // 1=시뮬레이션(LFSR), 0=합성(RO)
    parameter integer FIFO_DEPTH      = 64,  // 256bit 워드 단위 FIFO 깊이

    // User parameters ends
    // Do not modify the parameters beyond this line

    // Width of S_AXI data bus
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    // Width of S_AXI address bus
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    // Users to add ports here

    // key_manager 연결용 전체 256bit 출력
    output wire [255:0] rand_data_out,
    output wire         rand_valid_key,

    // User ports ends
    // Do not modify the ports beyond this line

    // Global Clock Signal
    input wire  S_AXI_ACLK,
    // Global Reset Signal. This Signal is Active LOW
    input wire  S_AXI_ARESETN,
    // Write address (issued by master, accepted by Slave)
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output reg  S_AXI_AWREADY,
    // Write data
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output reg  S_AXI_WREADY,
    // Write response
    output reg [1 : 0] S_AXI_BRESP,
    output reg  S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    // Read address
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output reg  S_AXI_ARREADY,
    // Read data
    output reg [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output reg [1 : 0] S_AXI_RRESP,
    output reg  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // =========================================================================
    // 내부 클럭/리셋 alias
    // =========================================================================
    wire clk   = S_AXI_ACLK;
    wire rst_n = S_AXI_ARESETN;

    // =========================================================================
    // 제어 레지스터
    // =========================================================================
    reg ctrl_enable;
    reg ctrl_reset;   // 1클럭 sw_reset 펄스

    // =========================================================================
    // trng256_core 출력 신호
    // =========================================================================
    wire [255:0] rand_data;
    wire         rand_valid;
    wire         health_fail;
    wire         rct_fail;
    wire         apt_fail;

    // TRNG 내부 리셋: AXI 리셋 AND NOT sw_reset
    wire trng_rst_n = rst_n & ~ctrl_reset;

    // =========================================================================
    // trng256_core 인스턴스
    // =========================================================================
    trng256_core #(
        .SIM_MODE(SIM_MODE)
    ) u_core (
        .clk         (clk),
        .rst_n       (trng_rst_n),
        .enable      (ctrl_enable & ~ctrl_reset),
        .rand_data   (rand_data),
        .rand_valid  (rand_valid),
        .health_fail (health_fail),
        .rct_fail    (rct_fail),
        .apt_fail    (apt_fail)
    );

    // =========================================================================
    // FIFO (256bit × FIFO_DEPTH)
    // =========================================================================
    reg [255:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH)-1:0] fifo_wr_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0] fifo_rd_ptr;

    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_full  = ((fifo_wr_ptr + 1'b1) == fifo_rd_ptr);

    // FIFO 쓰기 (rand_valid → push)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 0;
        end else if (ctrl_reset) begin
            fifo_wr_ptr <= fifo_rd_ptr;  // sw_reset → FIFO 비우기
        end else if (rand_valid && !fifo_full) begin
            fifo_mem[fifo_wr_ptr] <= rand_data;
            fifo_wr_ptr           <= fifo_wr_ptr + 1'b1;
        end
    end

    // =========================================================================
    // 생성 카운터
    // =========================================================================
    reg [31:0] gen_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || ctrl_reset)
            gen_count <= 32'h0;
        else if (rand_valid && !fifo_full)
            gen_count <= gen_count + 1'b1;
    end

    // =========================================================================
    // 읽기용 256bit 버퍼 (FIFO pop 후 32bit씩 제공)
    // =========================================================================
    reg [255:0] read_buf;
    reg         read_buf_valid;

    // =========================================================================
    // AXI4-Lite Write 채널
    // =========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= 2'b00;
            ctrl_enable   <= 1'b0;
            ctrl_reset    <= 1'b0;
            aw_addr_latch <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            ctrl_reset <= 1'b0;  // sw_reset은 1클럭 펄스

            if (S_AXI_AWVALID && S_AXI_WVALID &&
                !S_AXI_AWREADY && !S_AXI_BVALID) begin
                S_AXI_AWREADY <= 1'b1;
                S_AXI_WREADY  <= 1'b1;
                aw_addr_latch <= S_AXI_AWADDR;

                // 0x00 CTRL 레지스터 쓰기
                if (S_AXI_AWADDR[5:2] == 4'h0) begin
                    ctrl_enable <= S_AXI_WDATA[0];
                    ctrl_reset  <= S_AXI_WDATA[1];
                end

                S_AXI_BRESP  <= 2'b00;  // OKAY
                S_AXI_BVALID <= 1'b1;
            end else begin
                S_AXI_AWREADY <= 1'b0;
                S_AXI_WREADY  <= 1'b0;
            end

            if (S_AXI_BVALID && S_AXI_BREADY)
                S_AXI_BVALID <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Read 채널
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY  <= 1'b0;
            S_AXI_RVALID   <= 1'b0;
            S_AXI_RDATA    <= 32'h0;
            S_AXI_RRESP    <= 2'b00;
            fifo_rd_ptr    <= 0;
            read_buf       <= 256'h0;
            read_buf_valid <= 1'b0;
        end else begin

            if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
                S_AXI_ARREADY <= 1'b1;
                S_AXI_RRESP   <= 2'b00;
                S_AXI_RVALID  <= 1'b1;

                case (S_AXI_ARADDR[5:2])
                    // 0x00 CTRL
                    4'h0: S_AXI_RDATA <= {31'h0, ctrl_enable};

                    // 0x04 STATUS
                    4'h1: S_AXI_RDATA <= {26'h0,
                                           apt_fail,
                                           rct_fail,
                                           health_fail,
                                           fifo_full,
                                           fifo_empty,
                                           ~fifo_empty};  // [0]=data_valid

                    // 0x08 DATA_0 : FIFO pop → read_buf 로드
                    4'h2: begin
                        if (!fifo_empty) begin
                            read_buf       <= fifo_mem[fifo_rd_ptr];
                            fifo_rd_ptr    <= fifo_rd_ptr + 1'b1;
                            read_buf_valid <= 1'b1;
                            S_AXI_RDATA   <= fifo_mem[fifo_rd_ptr][31:0];
                        end else
                            S_AXI_RDATA <= 32'hDEAD_BEEF;
                    end

                    // 0x0C ~ 0x20 DATA_1~6
                    4'h3: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[63:32]   : 32'hDEAD_BEEF;
                    4'h4: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[95:64]   : 32'hDEAD_BEEF;
                    4'h5: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[127:96]  : 32'hDEAD_BEEF;
                    4'h6: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[159:128] : 32'hDEAD_BEEF;
                    4'h7: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[191:160] : 32'hDEAD_BEEF;
                    4'h8: S_AXI_RDATA <= read_buf_valid ?
                                          read_buf[223:192] : 32'hDEAD_BEEF;

                    // 0x24 DATA_7 : 읽기 완료 → read_buf_valid 클리어
                    4'h9: begin
                        S_AXI_RDATA   <= read_buf_valid ?
                                          read_buf[255:224] : 32'hDEAD_BEEF;
                        read_buf_valid <= 1'b0;
                    end

                    // 0x28 COUNT
                    4'hA: S_AXI_RDATA <= gen_count;

                    default: S_AXI_RDATA <= 32'h0;
                endcase
            end else begin
                S_AXI_ARREADY <= 1'b0;
            end

            if (S_AXI_RVALID && S_AXI_RREADY)
                S_AXI_RVALID <= 1'b0;
        end
    end

    // =========================================================================
    // 외부 출력 연결
    // =========================================================================
    assign rand_data_out  = rand_data;
    assign rand_valid_key = rand_valid;

endmodule
