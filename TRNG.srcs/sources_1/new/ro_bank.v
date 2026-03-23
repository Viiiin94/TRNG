`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 04:07:24 PM
// Design Name: 
// Module Name: ro_bank
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


module ro_bank (
    input  wire        clk,         // 시스템 클럭
    input  wire        rst_n,       // 비동기 리셋
    input  wire        enable,      // 1 동작 / 0 정지

    output reg  [31:0] data_out,    // 32bit 랜덤 출력
    output reg         data_valid,  // data_out 유효 (1클럭 펄스)
    output wire        raw_bit,     // Health Test용 (VN 이전)
    output reg         raw_valid    // raw_bit 유효
);
    
    // =========================================================================
    // ① RO × 16 인스턴스 (스테이지 수 각각 다름 → 주파수 다름)
    // =========================================================================
    // 스테이지: 3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33
    // 전부 홀수, RO마다 다른 주파수 → 상관관계 최소화
    wire [15:0] ro_out;
    
    genvar k;
    generate
        for(k = 0; k < 16; k= k+1) begin
            ro_cell #(
                .STAGES(3 + k * 2)   // 3,5,7,...,33
            ) u_ro (
                .enable (enable),
                .ro_out (ro_out[k])
            );
        end
    endgenerate
    
    // =========================================================================
    // ② XOR 결합 - 16개 RO 출력을 1bit로 압축
    //    assign 한 줄로 표현 (Verilog reduction XOR)
    // =========================================================================
    wire raw_xor;
    assign raw_xor = ^ro_out;
    
    
    // =========================================================================
    // ③ D-FF 샘플링 - 비동기 RO 출력을 sys_clk 도메인으로 전환
    //    주의: 메타스테이빌리티 가능성 있음
    //    → 이게 바로 랜덤의 원천! (의도된 것)
    // =========================================================================
    reg raw_bit_d;
    
    always @(posedge clk, negedge rst_n) begin
        if(!rst_n) raw_bit_d <= 1;
        else raw_bit_d <= raw_xor;
    end
    
    // raw_bit: Health Test 모듈에서 VN 이전 비트 관찰용
    assign raw_bit = raw_bit_d;
    
    // =========================================================================
    // ④ Von Neumann 편향 제거
    //    동작 원리:
    //      phase=0: 첫 번째 비트 저장 (prev)
    //      phase=1: 두 번째 비트와 비교
    //      prev≠curr → vn_bit=prev, vn_valid=1  (01→0, 10→1)
    //      prev=curr  → 버림, vn_valid=0        (00,11 제거)
    // =========================================================================
    reg vn_prev;     // 이전 비트 저장
    reg vn_phase;    // 0: 첫 번째 대기, 1: 두 번째 처리
    reg vn_bit;      // 편향 제거된 출력 비트
    reg vn_valid;    // vn_bit 유효 신호
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vn_prev <= 0; 
            vn_phase <= 0;
            vn_bit <= 0;  
            vn_valid <= 0;
            raw_valid <= 0;
        end
        else if(enable) begin
            vn_valid <= 0;
            raw_valid <= 1;
            
            if(vn_phase == 0) begin
                vn_prev <= raw_bit_d;
                vn_phase <= 1;
            end
            else begin
                vn_phase <= 0;
                
                if(vn_prev != raw_bit_d) begin
                    // 01 또는 10 → 유효 출력
                    // 01: prev=0, curr=1 → vn_bit=0 (prev 사용)
                    // 10: prev=1, curr=0 → vn_bit=1 (prev 사용)
                    vn_bit   <= vn_prev;
                    vn_valid <= 1'b1;
                end
            end
        end
        else begin
            // enable=0: 전부 리셋
            vn_phase  <= 1'b0;
            vn_valid  <= 1'b0;
            raw_valid <= 1'b0;
        end
    end
    
    // =========================================================================
    // ⑤ 32bit 시프트 누적
    //    vn_valid=1 일 때마다 vn_bit를 MSB 방향으로 시프트
    //    32번 채워지면 data_valid=1 펄스 + data_out 출력
    // =========================================================================
    reg [31:0] shift_reg;
    reg [5:0]  bit_cnt;     // 0~31 카운트 (6bit)
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 32'h0;
            bit_cnt    <= 6'd0;
            data_out   <= 32'h0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // 기본값: 무효

            if (vn_valid) begin
                // 새 비트를 LSB로 시프트 입력
                shift_reg <= {shift_reg[30:0], vn_bit};
                bit_cnt   <= bit_cnt + 1'b1;

                if (bit_cnt == 6'd31) begin
                    // 32비트 완성
                    data_out   <= {shift_reg[30:0], vn_bit};
                    data_valid <= 1'b1;
                    bit_cnt    <= 6'd0;
                end
            end
        end
    end

endmodule





















