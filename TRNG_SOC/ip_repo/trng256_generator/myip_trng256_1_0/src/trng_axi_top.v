`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 02:17:44 PM
// Design Name: 
// Module Name: trng_axi_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module trng256_axi_top #(
    parameter SIM_MODE   = 0,   // 1=시뮬레이션
    parameter FIFO_DEPTH = 64   // FIFO 깊이 (256bit 워드 단위)
)(
    // ── AXI4-Lite Slave 인터페이스 ──────────────────────────────────────
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    // Write Address
    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    // Write Data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    // Write Response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // Read Address
    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    // Read Data
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    
    output wire        raw_bit_out,
    output wire        rand_valid_out,
    output wire [31:0] rand_data_low,
    output wire        health_fail_out,
    output wire        apt_fail_out,

    // key_manager 연결용 전체 256bit 출력
    output wire [255:0] rand_data_out,
    output wire         rand_valid_key
);

    // =========================================================================
    // 내부 신호
    // =========================================================================
    wire        clk   = s_axi_aclk;
    wire        rst_n = s_axi_aresetn;

    // ── 제어 레지스터 ──
    reg         ctrl_enable;
    reg         ctrl_reset;

    // ── trng256_core 출력 ──
    wire [255:0] rand_data;
    wire         rand_valid;
    wire         health_fail;
    wire         rct_fail;
    wire         apt_fail;

    // TRNG 내부 리셋 (aresetn AND NOT sw_reset)
    wire trng_rst_n = rst_n & ~ctrl_reset;

    // ── FIFO (256bit × FIFO_DEPTH) ──────────────────────────────────────
    reg [255:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH)-1:0] fifo_wr_ptr;
    reg [$clog2(FIFO_DEPTH)-1:0] fifo_rd_ptr;
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_full  = ((fifo_wr_ptr + 1'b1) == fifo_rd_ptr);

    // FIFO 쓰기 (rand_valid → FIFO push)
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

    // ── 생성 카운터 ──
    reg [31:0] gen_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || ctrl_reset)
            gen_count <= 32'h0;
        else if (rand_valid && !fifo_full)
            gen_count <= gen_count + 1'b1;
    end

    // ── 읽기용 256bit 버퍼 (FIFO pop 후 32bit씩 제공) ──
    reg [255:0] read_buf;
    reg         read_buf_valid;

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
    // AXI4-Lite Write 채널
    // =========================================================================
    reg [5:0] aw_addr_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            ctrl_enable   <= 1'b0;
            ctrl_reset    <= 1'b0;
            aw_addr_latch <= 6'h0;
        end else begin
            ctrl_reset <= 1'b0;  // sw_reset은 1클럭 펄스

            if (s_axi_awvalid && s_axi_wvalid &&
                !s_axi_awready && !s_axi_bvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                aw_addr_latch <= s_axi_awaddr;

                // 0x00 CTRL 레지스터 쓰기
                if (s_axi_awaddr[5:2] == 4'h0) begin
                    ctrl_enable <= s_axi_wdata[0];
                    ctrl_reset  <= s_axi_wdata[1];
                end

                s_axi_bresp  <= 2'b00;  // OKAY
                s_axi_bvalid <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Read 채널
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= 32'h0;
            s_axi_rresp    <= 2'b00;
            fifo_rd_ptr    <= 0;
            read_buf       <= 256'h0;
            read_buf_valid <= 1'b0;
        end else begin

            if (s_axi_arvalid && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1'b1;

                case (s_axi_araddr[5:2])
                    // 0x00 CTRL
                    4'h0: s_axi_rdata <= {31'h0, ctrl_enable};

                    // 0x04 STATUS
                    4'h1: s_axi_rdata <= {26'h0,
                                           apt_fail,
                                           rct_fail,
                                           health_fail,
                                           fifo_full,
                                           fifo_empty,
                                           ~fifo_empty};  // [0]=data_valid

                    // 0x08~0x24 DATA_0~DATA_7
                    // DATA_0 읽을 때 FIFO pop → read_buf 로드
                    4'h2: begin
                        if (!fifo_empty) begin
                            read_buf       <= fifo_mem[fifo_rd_ptr];
                            fifo_rd_ptr    <= fifo_rd_ptr + 1'b1;
                            read_buf_valid <= 1'b1;
                            s_axi_rdata    <= fifo_mem[fifo_rd_ptr][31:0];
                        end else
                            s_axi_rdata <= 32'hDEAD_BEEF;
                    end
                    4'h3: s_axi_rdata <= read_buf_valid ?
                                          read_buf[63:32]   : 32'hDEAD_BEEF;
                    4'h4: s_axi_rdata <= read_buf_valid ?
                                          read_buf[95:64]   : 32'hDEAD_BEEF;
                    4'h5: s_axi_rdata <= read_buf_valid ?
                                          read_buf[127:96]  : 32'hDEAD_BEEF;
                    4'h6: s_axi_rdata <= read_buf_valid ?
                                          read_buf[159:128] : 32'hDEAD_BEEF;
                    4'h7: s_axi_rdata <= read_buf_valid ?
                                          read_buf[191:160] : 32'hDEAD_BEEF;
                    4'h8: s_axi_rdata <= read_buf_valid ?
                                          read_buf[223:192] : 32'hDEAD_BEEF;
                    // DATA_7 읽기 완료 → read_buf_valid 클리어
                    4'h9: begin
                        s_axi_rdata    <= read_buf_valid ?
                                          read_buf[255:224] : 32'hDEAD_BEEF;
                        read_buf_valid <= 1'b0;
                    end

                    // 0x28 COUNT
                    4'hA: s_axi_rdata <= gen_count;

                    default: s_axi_rdata <= 32'h0;
                endcase
            end else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end
    
    assign raw_bit_out     = u_core.bank_raw[0];
    assign rand_valid_out  = rand_valid;
    assign rand_data_low   = rand_data[31:0];
    assign health_fail_out = health_fail;
    assign apt_fail_out    = apt_fail;

    // key_manager 연결용
    assign rand_data_out   = rand_data;
    assign rand_valid_key  = rand_valid;

endmodule
