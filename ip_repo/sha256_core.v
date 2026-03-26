`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 03:32:27 PM
// Design Name: 
// Module Name: sha256_core
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


module sha256_core(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] entropy_in,   // 256bit 엔트로피 풀
    input  wire         start,         // 1클럭 펄스
    output reg  [255:0] hash_out,      // 256bit 해시 결과
    output reg          hash_valid     // 결과 유효 (1클럭 펄스)
    );
    
    // =========================================================================
    // 상수 K[0..63] - 처음 64개 소수의 세제곱근 소수점 이하 32bit
    // NIST FIPS 180-4 고정값
    // =========================================================================
    reg [31:0] K [0:63];
    initial begin
        K[0]=32'h428a2f98; K[1]=32'h71374491;
        K[2]=32'hb5c0fbcf; K[3]=32'he9b5dba5;
        K[4]=32'h3956c25b; K[5]=32'h59f111f1;
        K[6]=32'h923f82a4; K[7]=32'hab1c5ed5;
        K[8]=32'hd807aa98; K[9]=32'h12835b01;
        K[10]=32'h243185be; K[11]=32'h550c7dc3;
        K[12]=32'h72be5d74; K[13]=32'h80deb1fe;
        K[14]=32'h9bdc06a7; K[15]=32'hc19bf174;
        K[16]=32'he49b69c1; K[17]=32'hefbe4786;
        K[18]=32'h0fc19dc6; K[19]=32'h240ca1cc;
        K[20]=32'h2de92c6f; K[21]=32'h4a7484aa;
        K[22]=32'h5cb0a9dc; K[23]=32'h76f988da;
        K[24]=32'h983e5152; K[25]=32'ha831c66d;
        K[26]=32'hb00327c8; K[27]=32'hbf597fc7;
        K[28]=32'hc6e00bf3; K[29]=32'hd5a79147;
        K[30]=32'h06ca6351; K[31]=32'h14292967;
        K[32]=32'h27b70a85; K[33]=32'h2e1b2138;
        K[34]=32'h4d2c6dfc; K[35]=32'h53380d13;
        K[36]=32'h650a7354; K[37]=32'h766a0abb;
        K[38]=32'h81c2c92e; K[39]=32'h92722c85;
        K[40]=32'ha2bfe8a1; K[41]=32'ha81a664b;
        K[42]=32'hc24b8b70; K[43]=32'hc76c51a3;
        K[44]=32'hd192e819; K[45]=32'hd6990624;
        K[46]=32'hf40e3585; K[47]=32'h106aa070;
        K[48]=32'h19a4c116; K[49]=32'h1e376c08;
        K[50]=32'h2748774c; K[51]=32'h34b0bcb5;
        K[52]=32'h391c0cb3; K[53]=32'h4ed8aa4a;
        K[54]=32'h5b9cca4f; K[55]=32'h682e6ff3;
        K[56]=32'h748f82ee; K[57]=32'h78a5636f;
        K[58]=32'h84c87814; K[59]=32'h8cc70208;
        K[60]=32'h90befffa; K[61]=32'ha4506ceb;
        K[62]=32'hbef9a3f7; K[63]=32'hc67178f2;
    end
    
    // =========================================================================
    // 초기 해시값 H0..H7 - 소수의 제곱근 소수점 이하 32bit (FIPS 180-4)
    // =========================================================================
    localparam [31:0] H0_INIT = 32'h6a09e667;
    localparam [31:0] H1_INIT = 32'hbb67ae85;
    localparam [31:0] H2_INIT = 32'h3c6ef372;
    localparam [31:0] H3_INIT = 32'ha54ff53a;
    localparam [31:0] H4_INIT = 32'h510e527f;
    localparam [31:0] H5_INIT = 32'h9b05688c;
    localparam [31:0] H6_INIT = 32'h1f83d9ab;
    localparam [31:0] H7_INIT = 32'h5be0cd19;
    
    // =========================================================================
    // 내부 레지스터
    // =========================================================================
    reg [31:0] W [0:63];           // 메시지 스케줄
    reg [31:0] a, b, c, d,
               e, f, g, h_reg;    // 작업 변수 (h는 예약어라 h_reg 사용)
    reg [31:0] H0,H1,H2,H3,
               H4,H5,H6,H7;       // 해시 누적값
    reg [6:0]  round;              // 라운드 카운터 (0~63)
    reg [31:0] T1, T2;             // 임시 계산값

    // 상태머신
    localparam [1:0] IDLE     = 2'd0;
    localparam [1:0] SCHED    = 2'd1;   // W[16..63] 확장 (48클럭)
    localparam [1:0] COMPRESS = 2'd2;   // 64라운드 압축
    localparam [1:0] FINAL    = 2'd3;   // 합산 + 출력
    reg [1:0] state;
    
    // =========================================================================
    // 패딩 블록 구성
    // 256bit 입력 → 512bit (1블록)
    //   [511:256] entropy_in
    //   [255]     1'b1           (패딩 시작)
    //   [254:64]  191'b0         (0 패딩)
    //   [63:0]    64'd256        (원본 길이 256bit)
    //
    // → W[8] = 32'h80000000, W[9..14]=0, W[15]=32'h00000100
    // =========================================================================
    wire [511:0] M;
    assign M = {entropy_in, 1'b1, 191'b0, 64'd256};

    // =========================================================================
    // 논리 함수 정의
    // =========================================================================
    function [31:0] ROTR;
        input [31:0] x;
        input [4:0]  n;
        ROTR = (x >> n) | (x << (32 - n));
    endfunction

    // 메시지 스케줄 확장 함수 (소문자 σ)
    function [31:0] sigma0;
        input [31:0] x;
        sigma0 = ROTR(x,7) ^ ROTR(x,18) ^ (x >> 3);
    endfunction

    function [31:0] sigma1;
        input [31:0] x;
        sigma1 = ROTR(x,17) ^ ROTR(x,19) ^ (x >> 10);
    endfunction

    // 압축 라운드 함수 (대문자 Σ)
    function [31:0] Sigma0;
        input [31:0] x;
        Sigma0 = ROTR(x,2) ^ ROTR(x,13) ^ ROTR(x,22);
    endfunction

    function [31:0] Sigma1;
        input [31:0] x;
        Sigma1 = ROTR(x,6) ^ ROTR(x,11) ^ ROTR(x,25);
    endfunction

    function [31:0] Ch;
        input [31:0] x, y, z;
        Ch = (x & y) ^ (~x & z);
    endfunction

    function [31:0] Maj;
        input [31:0] x, y, z;
        Maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    // =========================================================================
    // 메인 상태머신
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            round      <= 7'd0;
            hash_valid <= 1'b0;
            hash_out   <= 256'h0;
        end else begin
            hash_valid <= 1'b0;  // 기본값

            case (state)

                // ── 대기 ─────────────────────────────────────────────────────
                IDLE: begin
                    if (start) begin
                        // W[0..15]: 512bit 패딩 블록을 32bit씩 분할
                        W[0]  <= M[511:480]; W[1]  <= M[479:448];
                        W[2]  <= M[447:416]; W[3]  <= M[415:384];
                        W[4]  <= M[383:352]; W[5]  <= M[351:320];
                        W[6]  <= M[319:288]; W[7]  <= M[287:256];
                        W[8]  <= M[255:224]; W[9]  <= M[223:192];
                        W[10] <= M[191:160]; W[11] <= M[159:128];
                        W[12] <= M[127:96];  W[13] <= M[95:64];
                        W[14] <= M[63:32];   W[15] <= M[31:0];
                        // 초기 해시값 로드
                        H0 <= H0_INIT; H1 <= H1_INIT;
                        H2 <= H2_INIT; H3 <= H3_INIT;
                        H4 <= H4_INIT; H5 <= H5_INIT;
                        H6 <= H6_INIT; H7 <= H7_INIT;
                        // 작업 변수 초기화
                        a <= H0_INIT; b <= H1_INIT;
                        c <= H2_INIT; d <= H3_INIT;
                        e <= H4_INIT; f <= H5_INIT;
                        g <= H6_INIT; h_reg <= H7_INIT;
                        // W[16]부터 스케줄 확장 시작
                        round <= 7'd16;
                        state <= SCHED;
                    end
                end

                // ── 메시지 스케줄 확장 W[16..63] (48클럭) ──────────────────
                SCHED: begin
                    // W[t] = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]
                    W[round] <= sigma1(W[round-2])  + W[round-7]
                              + sigma0(W[round-15]) + W[round-16];
                    round <= round + 1'b1;

                    if (round == 7'd63) begin
                        round <= 7'd0;
                        state <= COMPRESS;
                    end
                end

                // ── 64라운드 압축 ────────────────────────────────────────────
                COMPRESS: begin
                    // 블로킹으로 T1, T2 먼저 계산 후 작업 변수 업데이트
                    T1 = h_reg + Sigma1(e) + Ch(e,f,g) + K[round] + W[round];
                    T2 = Sigma0(a) + Maj(a,b,c);

                    h_reg <= g;
                    g     <= f;
                    f     <= e;
                    e     <= d + T1;
                    d     <= c;
                    c     <= b;
                    b     <= a;
                    a     <= T1 + T2;

                    // ── 디버그: 처음 3라운드 + 마지막 라운드 출력 ──
                    if (round <= 7'd2 || round == 7'd63) begin
                        $display("[COMPRESS round=%0d] W=%h K=%h",
                                  round, W[round], K[round]);
                        $display("  T1=%h T2=%h", T1, T2);
                        $display("  a=%h b=%h c=%h d=%h",  a, b, c, d);
                        $display("  e=%h f=%h g=%h h=%h",  e, f, g, h_reg);
                    end
                
                    round <= round + 1'b1;
                    if (round == 7'd63) begin
                        $display("[FINAL 직전] a=%h b=%h c=%h d=%h e=%h f=%h g=%h h=%h",
                                  a, b, c, d, e, f, g, h_reg);
                        state <= FINAL;
                    end
                end

                // ── 최종 합산 + 출력 ─────────────────────────────────────────
                FINAL: begin
                    hash_out <= {H0+a,     H1+b,     H2+c,     H3+d,
                                 H4+e,     H5+f,     H6+g,     H7+h_reg};
                    hash_valid <= 1'b1;
                    state      <= IDLE;
                end

            endcase
        end
    end
endmodule



















