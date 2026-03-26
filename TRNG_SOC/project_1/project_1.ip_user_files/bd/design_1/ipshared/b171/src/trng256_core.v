`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 01:19:36 PM
// Design Name: 
// Module Name: trng256_core
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


module trng256_core #(
    parameter SIM_MODE = 0
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         enable,

    output reg  [255:0] rand_data,    // 256bit 랜덤 출력
    output reg          rand_valid,   // 유효 펄스 (1클럭)
    output wire         health_fail,  // 고장 감지
    output wire         rct_fail,     // RCT 실패 (디버그)
    output wire         apt_fail      // APT 실패 (디버그)
);

    // =========================================================================
    // ① ro_bank × 8 인스턴스
    //    뱅크마다 독립 32bit 엔트로피
    // =========================================================================
    wire [31:0] bank_data  [0:7];
    wire        bank_valid [0:7];
    wire        bank_raw   [0:7];   // health_test 입력용
    wire        bank_raw_v [0:7];

    genvar b;
    generate
        for (b = 0; b < 8; b = b + 1) begin : g_bank
            ro_bank #(
                .SIM_MODE(SIM_MODE)
            ) u_bank (
                .clk        (clk),
                .rst_n      (rst_n),
                .enable     (enable),
                .data_out   (bank_data[b]),
                .data_valid (bank_valid[b]),
                .raw_bit    (bank_raw[b]),
                .raw_valid  (bank_raw_v[b])
            );
        end
    endgenerate

    // =========================================================================
    // ② 256bit 엔트로피 풀 래치
    //    8개 뱅크 data_valid가 모두 1이 된 순간 entropy_pool 확정
    //
    //    valid_mask: 뱅크별 수신 완료 비트맵 (0000_0000 → 1111_1111)
    //    all_valid : valid_mask == 8'hFF → 256bit 전부 수집 완료
    // =========================================================================
    reg [255:0] entropy_pool;
    reg [7:0]   valid_mask;       // 뱅크별 수신 완료 비트맵
    wire        all_valid;
    reg         all_valid_d;      // 1클럭 지연 (sha256 start 타이밍)

    assign all_valid = (valid_mask == 8'hFF);

    // 뱅크 데이터 래치 + valid_mask 업데이트
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            entropy_pool <= 256'h0;
            valid_mask   <= 8'h00;
            all_valid_d  <= 1'b0;
        end else if (!enable) begin
            valid_mask   <= 8'h00;
            all_valid_d  <= 1'b0;
        end else begin
            all_valid_d <= all_valid;

            // 각 뱅크 data_valid가 뜰 때 해당 슬롯에 래치
            for (i = 0; i < 8; i = i + 1) begin
                if (bank_valid[i] && !valid_mask[i]) begin
                    // 해당 뱅크 32bit 슬롯에 저장
                    entropy_pool[i*32 +: 32] <= bank_data[i];
                    valid_mask[i]            <= 1'b1;
                end
            end

            // all_valid 후 다음 수집 사이클 준비
            if (all_valid && !all_valid_d) begin
                valid_mask <= 8'h00;  // 마스크 리셋 → 다음 256bit 수집 시작
            end
        end
    end

    // =========================================================================
    // ③ health_test 인스턴스
    //    bank0의 raw_bit을 대표로 사용
    //    (모든 뱅크를 개별 감시하려면 8개 인스턴스 필요하지만
    //     2주 프로젝트에서는 bank0 대표 감시로 충분)
    // =========================================================================
    health_test u_health (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .raw_bit     (bank_raw[0]),
        .raw_valid   (bank_raw_v[0]),
        .health_fail (health_fail),
        .rct_fail    (rct_fail),
        .apt_fail    (apt_fail)
    );

    // =========================================================================
    // ④ sha256_core 인스턴스
    //    all_valid 감지 후 1클럭 뒤 start 펄스
    //    → entropy_pool 레지스터 안정화 후 압축 시작
    // =========================================================================
    wire        sha_start;
    wire [255:0] sha_hash;
    wire         sha_valid;

    // all_valid 상승 엣지 감지 → 1클럭 start 펄스
    assign sha_start = all_valid && !all_valid_d;

    sha256_core u_sha256 (
        .clk        (clk),
        .rst_n      (rst_n),
        .entropy_in (entropy_pool),
        .start      (sha_start),
        .hash_out   (sha_hash),
        .hash_valid (sha_valid)
    );

    // =========================================================================
    // ⑤ 출력 게이트
    //    health_fail=1 이면 rand_valid 차단
    //    → 고장 난 상태에서 랜덤 데이터 절대 출력 안됨
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rand_data  <= 256'h0;
            rand_valid <= 1'b0;
        end else begin
            rand_valid <= 1'b0;  // 기본값

            if (sha_valid && !health_fail) begin
                rand_data  <= sha_hash;
                rand_valid <= 1'b1;
            end
        end
    end

endmodule
