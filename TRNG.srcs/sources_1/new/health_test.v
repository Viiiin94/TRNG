`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 12:19:05 PM
// Design Name: 
// Module Name: health_test
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


module health_test(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,

    input  wire raw_bit,     // VN 이전 raw 비트
    input  wire raw_valid,   // raw_bit 유효

    output reg  health_fail, // 1 = 고장 감지
    output reg  rct_fail,    // RCT 실패 (디버그)
    output reg  apt_fail     // APT 실패 (디버그)
    );
    
    // =========================================================================
    // 파라미터
    // =========================================================================
    // RCT: C = ceil(1 + 20/H) = 41  (H=0.5)
    localparam RCT_C = 6'd41;

    // APT: W=512 윈도우, C=325 컷오프
    localparam APT_W = 10'd512;
    localparam APT_C = 10'd325;
    
    // =========================================================================
    // RCT - Repetition Count Test
    // 연속으로 같은 값이 RCT_C번 나오면 fail
    // =========================================================================
    reg [5:0]  rct_count;   // 연속 카운터 (최대 41)
    reg        rct_prev;    // 이전 비트

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rct_count <= 6'd1;   // SP 800-90B: 초기값 1 (첫 비트 자체가 1회)
            rct_prev  <= 1'b0;
            rct_fail  <= 1'b0;
        end else if (!enable) begin
            rct_count <= 6'd1;
            rct_fail  <= 1'b0;
        end else if (raw_valid) begin
            if (raw_bit == rct_prev) begin
                // 같은 값 연속
                if (rct_count >= RCT_C - 1) begin
                    rct_fail  <= 1'b1;   // C번 연속 → 실패
                    rct_count <= rct_count; // 카운터 고정 (리셋 전까지 유지)
                end else begin
                    rct_count <= rct_count + 1'b1;
                end
            end else begin
                // 다른 값 → 카운터 리셋
                rct_count <= 6'd1;
                rct_prev  <= raw_bit;
                // rct_fail은 sw_reset 전까지 유지
            end
        end
    end
    
    // =========================================================================
    // APT - Adaptive Proportion Test
    // W=512 샘플 윈도우에서 첫 번째 비트 기준값(apt_B)이
    // C=325번 이상 나오면 편향 감지 → fail
    // =========================================================================
    reg [9:0]  apt_cnt;     // 윈도우 내 샘플 카운터 (0~511)
    reg [9:0]  apt_match;   // 기준값과 같은 비트 카운터
    reg        apt_B;       // 윈도우 첫 번째 비트 (기준값)
    reg        apt_window;  // 0: 기준값 대기, 1: 윈도우 진행 중

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            apt_cnt    <= 10'd0;
            apt_match  <= 10'd0;
            apt_B      <= 1'b0;
            apt_window <= 1'b0;
            apt_fail   <= 1'b0;
        end else if (!enable) begin
            apt_cnt    <= 10'd0;
            apt_match  <= 10'd0;
            apt_window <= 1'b0;
            apt_fail   <= 1'b0;
        end else if (raw_valid) begin

            if (!apt_window) begin
                // ── 윈도우 시작: 첫 번째 비트를 기준값으로 설정 ──
                apt_B      <= raw_bit;
                apt_cnt    <= 10'd1;
                apt_match  <= 10'd1;   // 첫 비트 자체가 1번 카운트
                apt_window <= 1'b1;

            end else begin
                // ── 윈도우 진행 중: 기준값과 비교 ──
                apt_cnt <= apt_cnt + 1'b1;

                if (raw_bit == apt_B)
                    apt_match <= apt_match + 1'b1;

                // 컷오프 초과 체크
                if ((raw_bit == apt_B) &&
                    (apt_match + 1'b1 >= APT_C)) begin
                    apt_fail <= 1'b1;
                end

                // 윈도우 완료 (512번 수집)
                if (apt_cnt >= APT_W - 1) begin
                    // 다음 윈도우 시작
                    apt_window <= 1'b0;
                    apt_cnt    <= 10'd0;
                    apt_match  <= 10'd0;
                    // apt_fail은 sw_reset 전까지 유지
                end
            end
        end
    end

    // =========================================================================
    // health_fail - RCT 또는 APT 중 하나라도 실패하면 1
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            health_fail <= 1'b0;
        else
            health_fail <= rct_fail | apt_fail;
    end
    
endmodule























