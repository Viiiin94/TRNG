`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: key_expasion
// Description: AES256 키 확장 (FIPS 197 Section 5.2)
//              256비트 키 → W[0..59] (15개 라운드 키) 순차 생성
//
// 알고리즘:
//   W[0..7]  : 원본 키에서 직접 로드
//   W[i] (i>=8):
//     if (i mod 8 == 0) : W[i-8] ^ SubWord(RotWord(W[i-1])) ^ Rcon[i/8]
//     if (i mod 8 == 4) : W[i-8] ^ SubWord(W[i-1])
//     else              : W[i-8] ^ W[i-1]
//
// 타이밍: key_valid → 52클록 → done=1
//////////////////////////////////////////////////////////////////////////////////

module key_expasion(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] key,
    input  wire         key_valid,
    input  wire [3:0]   round_num,    // 0~14, 요청할 라운드 키
    output reg  [127:0] round_key,    // 선택된 라운드 키
    output reg          done
);

    // =========================================================================
    // 상태머신
    // =========================================================================
    localparam IDLE   = 2'd0;
    localparam EXPAND = 2'd1;
    localparam DONE   = 2'd2;
    reg [1:0] state;

    // =========================================================================
    // 내부 워드 저장소 W[0..59]
    // =========================================================================
    reg [31:0] W [0:59];
    reg [5:0]  idx;   // 현재 생성 중인 워드 인덱스 (8~59)

    // =========================================================================
    // Rcon 테이블 (AES256: Rcon[1]~Rcon[7])
    // =========================================================================
    reg [31:0] Rcon [1:7];
    initial begin
        Rcon[1] = 32'h01000000;
        Rcon[2] = 32'h02000000;
        Rcon[3] = 32'h04000000;
        Rcon[4] = 32'h08000000;
        Rcon[5] = 32'h10000000;
        Rcon[6] = 32'h20000000;
        Rcon[7] = 32'h40000000;
    end

    // =========================================================================
    // SubWord: s_box 4개 인스턴스
    // =========================================================================
    wire [31:0] sub_word_in;
    wire [31:0] sub_word_out;

    // RotWord: 바이트 왼쪽 순환 (W[i-1])
    wire [31:0] rot_w = {W[idx-1][23:0], W[idx-1][31:24]};

    // i mod 8 == 0 → RotWord 후 SubWord, i mod 8 == 4 → 그냥 SubWord
    assign sub_word_in = (idx[2:0] == 3'd0) ? rot_w : W[idx-1];

    s_box u_sb0 (.in(sub_word_in[31:24]), .out(sub_word_out[31:24]));
    s_box u_sb1 (.in(sub_word_in[23:16]), .out(sub_word_out[23:16]));
    s_box u_sb2 (.in(sub_word_in[15:8]),  .out(sub_word_out[15:8]));
    s_box u_sb3 (.in(sub_word_in[7:0]),   .out(sub_word_out[7:0]));

    // Rcon 인덱스: idx / 8 (idx[5:3])
    wire [2:0] rcon_idx = idx[5:3];

    // =========================================================================
    // 라운드 키 출력: round_num으로 W[n*4 ~ n*4+3] 선택
    // =========================================================================
    always @(*) begin
        case (round_num)
            4'd0:  round_key = {W[0],  W[1],  W[2],  W[3]};
            4'd1:  round_key = {W[4],  W[5],  W[6],  W[7]};
            4'd2:  round_key = {W[8],  W[9],  W[10], W[11]};
            4'd3:  round_key = {W[12], W[13], W[14], W[15]};
            4'd4:  round_key = {W[16], W[17], W[18], W[19]};
            4'd5:  round_key = {W[20], W[21], W[22], W[23]};
            4'd6:  round_key = {W[24], W[25], W[26], W[27]};
            4'd7:  round_key = {W[28], W[29], W[30], W[31]};
            4'd8:  round_key = {W[32], W[33], W[34], W[35]};
            4'd9:  round_key = {W[36], W[37], W[38], W[39]};
            4'd10: round_key = {W[40], W[41], W[42], W[43]};
            4'd11: round_key = {W[44], W[45], W[46], W[47]};
            4'd12: round_key = {W[48], W[49], W[50], W[51]};
            4'd13: round_key = {W[52], W[53], W[54], W[55]};
            4'd14: round_key = {W[56], W[57], W[58], W[59]};
            default: round_key = 128'h0;
        endcase
    end

    // =========================================================================
    // 메인 FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            idx   <= 6'd8;
            done  <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 1'b0;
                    if (key_valid) begin
                        // W[0..7]: 256비트 키를 32비트씩 로드
                        W[0] <= key[255:224]; W[1] <= key[223:192];
                        W[2] <= key[191:160]; W[3] <= key[159:128];
                        W[4] <= key[127:96];  W[5] <= key[95:64];
                        W[6] <= key[63:32];   W[7] <= key[31:0];
                        idx   <= 6'd8;
                        state <= EXPAND;
                    end
                end

                EXPAND: begin
                    // i mod 8 기준으로 연산 분기
                    if (idx[2:0] == 3'd0)
                        W[idx] <= W[idx-8] ^ sub_word_out ^ Rcon[rcon_idx];
                    else if (idx[2:0] == 3'd4)
                        W[idx] <= W[idx-8] ^ sub_word_out;
                    else
                        W[idx] <= W[idx-8] ^ W[idx-1];

                    if (idx == 6'd59) begin
                        state <= DONE;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                DONE: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
