`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: inv_mix_columns
// Description: AES InvMixColumns - GF(2^8) 역 열 혼합 (FIPS 197 Section 5.3.3)
//              순차회로 (1클록 파이프라인) - mix_columns.v와 동일한 인터페이스
//
// 각 열에 적용되는 역행렬:
//   | 14  11  13   9 |   | s0 |
//   |  9  14  11  13 | × | s1 |
//   | 13   9  14  11 |   | s2 |
//   | 11  13   9  14 |   | s3 |
//
// xtime(a) = a << 1 (MSB=1이면 ^ 8'h1b)
// ×9  = ×8 ^ ×1 = xtime3(a) ^ a
// ×11 = ×8 ^ ×2 ^ ×1 = xtime3(a) ^ xtime(a) ^ a
// ×13 = ×8 ^ ×4 ^ ×1 = xtime3(a) ^ xtime2(a) ^ a
// ×14 = ×8 ^ ×4 ^ ×2 = xtime3(a) ^ xtime2(a) ^ xtime(a)
//////////////////////////////////////////////////////////////////////////////////

module inv_mix_columns(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] in,
    input  wire         valid_in,
    output reg  [127:0] out,
    output reg          valid_out
);

    // GF(2^8) xtime: ×2 연산
    function [7:0] xtime;
        input [7:0] a;
        xtime = a[7] ? (a << 1) ^ 8'h1b : (a << 1);
    endfunction

    // ×9  = xtime(xtime(xtime(a))) ^ a
    function [7:0] mul9;
        input [7:0] a;
        mul9 = xtime(xtime(xtime(a))) ^ a;
    endfunction

    // ×11 = xtime(xtime(xtime(a))) ^ xtime(a) ^ a
    function [7:0] mul11;
        input [7:0] a;
        mul11 = xtime(xtime(xtime(a))) ^ xtime(a) ^ a;
    endfunction

    // ×13 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ a
    function [7:0] mul13;
        input [7:0] a;
        mul13 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ a;
    endfunction

    // ×14 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ xtime(a)
    function [7:0] mul14;
        input [7:0] a;
        mul14 = xtime(xtime(xtime(a))) ^ xtime(xtime(a)) ^ xtime(a);
    endfunction

    // 한 열(4바이트)에 대한 InvMixColumns 연산
    function [31:0] inv_mix_col;
        input [7:0] s0, s1, s2, s3;
        reg [7:0] r0, r1, r2, r3;
        begin
            r0 = mul14(s0) ^ mul11(s1) ^ mul13(s2) ^ mul9(s3);
            r1 = mul9(s0)  ^ mul14(s1) ^ mul11(s2) ^ mul13(s3);
            r2 = mul13(s0) ^ mul9(s1)  ^ mul14(s2) ^ mul11(s3);
            r3 = mul11(s0) ^ mul13(s1) ^ mul9(s2)  ^ mul14(s3);
            inv_mix_col = {r0, r1, r2, r3};
        end
    endfunction

    // 조합 논리 결과
    wire [127:0] inv_mixed;
    assign inv_mixed = {
        inv_mix_col(in[127:120], in[119:112], in[111:104], in[103:96]),  // 열 0
        inv_mix_col(in[95:88],   in[87:80],   in[79:72],   in[71:64]),   // 열 1
        inv_mix_col(in[63:56],   in[55:48],   in[47:40],   in[39:32]),   // 열 2
        inv_mix_col(in[31:24],   in[23:16],   in[15:8],    in[7:0])      // 열 3
    };

    // 1클록 파이프라인 레지스터
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out       <= 128'h0;
            valid_out <= 1'b0;
        end else begin
            out       <= inv_mixed;
            valid_out <= valid_in;
        end
    end

endmodule
