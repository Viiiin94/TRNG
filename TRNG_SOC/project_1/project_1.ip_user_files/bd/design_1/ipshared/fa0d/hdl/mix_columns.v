`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mix_columns
// Description: AES MixColumns - GF(2^8) 열 혼합 (FIPS 197 Section 5.1.3)
//              순차회로 (1클록 파이프라인) - WNS 안정화
//
// 각 열에 적용되는 행렬:
//   | 2 3 1 1 |   | s0 |
//   | 1 2 3 1 | × | s1 |
//   | 1 1 2 3 |   | s2 |
//   | 3 1 1 2 |   | s3 |
//
// xtime(a) = a << 1 (MSB=1이면 ^ 8'h1b)
// ×2 = xtime(a)
// ×3 = xtime(a) ^ a
//////////////////////////////////////////////////////////////////////////////////

module mix_columns(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] in,
    input  wire         valid_in,
    output reg  [127:0] out,
    output reg          valid_out
);

    // xtime 함수: GF(2^8) x2 연산
    function [7:0] xtime;
        input [7:0] a;
        xtime = a[7] ? (a << 1) ^ 8'h1b : (a << 1);
    endfunction

    // 한 열(4바이트)에 대한 MixColumns 연산
    function [31:0] mix_col;
        input [7:0] s0, s1, s2, s3;
        reg [7:0] r0, r1, r2, r3;
        begin
            r0 = xtime(s0) ^ xtime(s1)^s1 ^ s2        ^ s3;
            r1 = s0        ^ xtime(s1) ^ xtime(s2)^s2 ^ s3;
            r2 = s0        ^ s1        ^ xtime(s2) ^ xtime(s3)^s3;
            r3 = xtime(s0)^s0 ^ s1    ^ s2        ^ xtime(s3);
            mix_col = {r0, r1, r2, r3};
        end
    endfunction

    // 조합 논리 결과
    wire [127:0] mixed;
    assign mixed = {
        mix_col(in[127:120], in[119:112], in[111:104], in[103:96]),  // 열 0
        mix_col(in[95:88],   in[87:80],   in[79:72],   in[71:64]),   // 열 1
        mix_col(in[63:56],   in[55:48],   in[47:40],   in[39:32]),   // 열 2
        mix_col(in[31:24],   in[23:16],   in[15:8],    in[7:0])      // 열 3
    };

    // 1클록 파이프라인 레지스터
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out       <= 128'h0;
            valid_out <= 1'b0;
        end else begin
            out       <= mixed;
            valid_out <= valid_in;
        end
    end

endmodule
