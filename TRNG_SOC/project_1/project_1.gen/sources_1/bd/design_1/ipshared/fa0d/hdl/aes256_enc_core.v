`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: aes256_enc_core
// Description: AES256 암호화 코어 FSM
//              시작 시 BRAM에서 256비트 키 읽기 → 키 확장 → 암호화 대기
//
// 암호화 흐름:
//   InitARK(1) → [SubBytes→ShiftRows→MixColumns→AddRoundKey] × 13 → FinalARK(1)
//
// 타이밍 (키 준비 후):
//   INIT_ARK(1) + ROUND×13(2클록×13=26) + FINAL_ARK(1) + OUTPUT(1) = 29클록
//
// BRAM 구성: Simple Dual Port, 32비트 폭, 주소 0x0~0x7 (256비트 키 저장)
//////////////////////////////////////////////////////////////////////////////////

module aes256_enc_core(
    input  wire         clk,
    input  wire         rst_n,

    // BRAM Port B - 256비트 키 읽기 (1클록 읽기 지연)
    output reg  [3:0]   bram_addr,
    output reg          bram_en,
    input  wire [31:0]  bram_dout,

    // AES 제어 인터페이스
    input  wire         key_reload,    // 새 키 로드 요청 (key_manager 펄스)
    input  wire         start,         // 1클록 펄스
    input  wire [127:0] data_in,       // 평문 128비트
    output reg  [127:0] data_out,      // 암호문 128비트
    output reg          done,          // 완료 1클록 펄스
    output reg          busy           // 처리 중
);

    // =========================================================================
    // FSM 상태 정의
    // =========================================================================
    localparam WAIT_KEY   = 4'd0;  // BRAM에서 키 읽기 (9클록)
    localparam KEY_EXPAND = 4'd1;  // 키 확장 대기 (54클록)
    localparam READY      = 4'd2;  // 암호화 대기
    localparam INIT_ARK   = 4'd3;  // 초기 AddRoundKey (라운드 키 0)
    localparam ROUND_MIX  = 4'd4;  // MixColumns 실행
    localparam ROUND_ARK  = 4'd5;  // AddRoundKey (라운드 1~13)
    localparam FINAL_ARK  = 4'd6;  // 최종 AddRoundKey (라운드 14, MixColumns 없음)
    localparam OUTPUT     = 4'd7;  // 결과 출력

    reg [3:0]   state;
    reg [127:0] aes_state;    // 현재 AES state
    reg [3:0]   round_cnt;    // 현재 라운드 (1~13)
    reg [3:0]   round_num;    // key_expasion에 요청할 라운드 키 번호
    reg [3:0]   bram_cnt;     // BRAM 읽기 카운터 (0~8)
    reg [255:0] aes_key;      // 조립된 256비트 키

    // =========================================================================
    // 내부 신호
    // =========================================================================
    reg          key_valid_r;
    wire [127:0] round_key;
    wire         key_done;

    wire [127:0] sub_out;
    wire [127:0] shift_out;

    reg          mix_valid_in;
    wire [127:0] mix_out;
    wire         mix_valid_out;

    wire [127:0] ark_out;

    // AddRoundKey 입력 선택 (조합회로)
    //   INIT_ARK  → data_in   (초기 평문)
    //   ROUND_ARK → mix_out   (MixColumns 결과)
    //   FINAL_ARK → shift_out (MixColumns 생략)
    reg [127:0] ark_in_sel;
    always @(*) begin
        case (state)
            INIT_ARK:  ark_in_sel = data_in;
            ROUND_ARK: ark_in_sel = mix_out;
            FINAL_ARK: ark_in_sel = shift_out;
            default:   ark_in_sel = 128'h0;
        endcase
    end

    // =========================================================================
    // 서브 모듈 인스턴스
    // =========================================================================
    key_expasion u_key_exp (
        .clk       (clk),
        .rst_n     (rst_n),
        .key       (aes_key),
        .key_valid (key_valid_r),
        .round_num (round_num),
        .round_key (round_key),
        .done      (key_done)
    );

    sub_bytes u_sub (
        .in  (aes_state),
        .out (sub_out)
    );

    shift_rows u_shift (
        .in  (sub_out),
        .out (shift_out)
    );

    mix_columns u_mix (
        .clk       (clk),
        .rst_n     (rst_n),
        .in        (shift_out),
        .valid_in  (mix_valid_in),
        .out       (mix_out),
        .valid_out (mix_valid_out)
    );

    add_round_key u_ark (
        .state     (ark_in_sel),
        .round_key (round_key),
        .out       (ark_out)
    );

    // =========================================================================
    // 메인 FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= WAIT_KEY;
            bram_addr    <= 4'd0;
            bram_en      <= 1'b1;
            bram_cnt     <= 4'd0;
            aes_key      <= 256'h0;
            aes_state    <= 128'h0;
            round_cnt    <= 4'd0;
            round_num    <= 4'd0;
            key_valid_r  <= 1'b0;
            mix_valid_in <= 1'b0;
            data_out     <= 128'h0;
            done         <= 1'b0;
            busy         <= 1'b0;
        end else begin
            // 기본값 (매 클록 리셋)
            done         <= 1'b0;
            key_valid_r  <= 1'b0;
            mix_valid_in <= 1'b0;

            case (state)

                // ── BRAM에서 256비트 키 읽기 (9클록) ─────────────────────
                // 1클록 읽기 지연: addr 설정 → 다음 클록에 데이터 유효
                WAIT_KEY: begin
                    bram_en   <= 1'b1;
                    bram_addr <= bram_cnt;

                    if (bram_cnt > 4'd0) begin
                        case (bram_cnt)
                            4'd1: aes_key[255:224] <= bram_dout;
                            4'd2: aes_key[223:192] <= bram_dout;
                            4'd3: aes_key[191:160] <= bram_dout;
                            4'd4: aes_key[159:128] <= bram_dout;
                            4'd5: aes_key[127:96]  <= bram_dout;
                            4'd6: aes_key[95:64]   <= bram_dout;
                            4'd7: aes_key[63:32]   <= bram_dout;
                            4'd8: begin
                                aes_key[31:0] <= bram_dout;
                                bram_en       <= 1'b0;
                                key_valid_r   <= 1'b1;  // 키 확장 트리거
                                state         <= KEY_EXPAND;
                            end
                            default: ;
                        endcase
                    end

                    if (bram_cnt < 4'd8)
                        bram_cnt <= bram_cnt + 1'b1;
                end

                // ── 키 확장 완료 대기 (54클록) ────────────────────────────
                KEY_EXPAND: begin
                    if (key_done)
                        state <= READY;
                end

                // ── 암호화 대기 ───────────────────────────────────────────
                READY: begin
                    busy <= 1'b0;
                    if (key_reload) begin
                        // 새 키가 BRAM에 기록됨 → 키 재로드
                        bram_addr <= 4'd0;
                        bram_en   <= 1'b1;
                        bram_cnt  <= 4'd0;
                        aes_key   <= 256'h0;
                        state     <= WAIT_KEY;
                    end else if (start) begin
                        round_num <= 4'd0;  // 라운드 키 0 선택
                        busy      <= 1'b1;
                        state     <= INIT_ARK;
                    end
                end

                // ── 초기 AddRoundKey: state = data_in ^ rk[0] ────────────
                INIT_ARK: begin
                    aes_state <= ark_out;   // data_in ^ round_key[0]
                    round_cnt <= 4'd1;
                    round_num <= 4'd1;
                    state     <= ROUND_MIX;
                end

                // ── 라운드 1~13: MixColumns 실행 (1클록) ──────────────────
                // shift_out(=ShiftRows(SubBytes(aes_state)))을 mix_columns에 전달
                ROUND_MIX: begin
                    mix_valid_in <= 1'b1;
                    state        <= ROUND_ARK;
                end

                // ── 라운드 1~13: AddRoundKey ──────────────────────────────
                // mix_valid_out=1, state = mix_out ^ rk[round_cnt]
                ROUND_ARK: begin
                    aes_state <= ark_out;              // mix_out ^ round_key[round_cnt]
                    round_cnt <= round_cnt + 1'b1;
                    round_num <= round_cnt + 1'b1;

                    if (round_cnt == 4'd13) begin
                        round_num <= 4'd14;            // 마지막 라운드 키 선택
                        state     <= FINAL_ARK;
                    end else begin
                        state <= ROUND_MIX;
                    end
                end

                // ── 라운드 14: MixColumns 없이 AddRoundKey ────────────────
                // state = ShiftRows(SubBytes(aes_state)) ^ rk[14]
                FINAL_ARK: begin
                    aes_state <= ark_out;   // shift_out ^ round_key[14]
                    state     <= OUTPUT;
                end

                // ── 결과 출력 ─────────────────────────────────────────────
                OUTPUT: begin
                    data_out <= aes_state;
                    done     <= 1'b1;
                    busy     <= 1'b0;
                    state    <= READY;
                end

                default: state <= WAIT_KEY;

            endcase
        end
    end

endmodule
