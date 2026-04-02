`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: aes256_dec_core
// Description: AES256 복호화 코어 FSM
//
// 키 로딩: encrypt IP의 key_man이 BRAM Port B에 쓴 키를
//          BRAM Port A (read-only)를 통해 읽어 키 확장 수행
//
// 복호화 흐름 (FIPS 197 표준 역암호):
//   InitARK(rk[14]) → [InvShiftRows→InvSubBytes→ARK→InvMixColumns] ×13 → FinalARK(rk[0])
//
// 타이밍 (키 준비 후):
//   WAIT_KEY(9) + KEY_EXPAND + INIT_ARK(1) + ROUND×13(26) + FINAL_ARK(1) + OUTPUT(1) = 29클록
//
// BRAM Port A (read-only):
//   bram_addr[3:0] : 워드 주소 (0~7)
//   bram_en        : 읽기 인에이블
//   bram_dout[31:0]: 읽기 데이터
//   상위모듈에서 바이트 주소 변환: {27'h0, bram_addr[2:0], 2'b00}
//////////////////////////////////////////////////////////////////////////////////

module aes256_dec_core(
    input  wire         clk,
    input  wire         rst_n,

    // BRAM Port A - 키 읽기 전용 (1클록 읽기 지연)
    output reg  [3:0]   bram_addr,
    output reg          bram_en,
    input  wire [31:0]  bram_dout,

    // encrypt IP의 key_man에서 수신
    input  wire         key_ready_in,  // 1: BRAM에 키 저장 완료 (level)
    input  wire         key_reload_in, // 1클록 펄스: 새 키 기록 완료

    // AES 제어 인터페이스
    input  wire         start,         // 1클록 펄스
    input  wire [127:0] data_in,       // 암호문 128비트
    output reg  [127:0] data_out,      // 평문 128비트
    output reg          done,          // 완료 1클록 펄스
    output reg          busy           // 처리 중
);

    // =========================================================================
    // FSM 상태 정의
    // =========================================================================
    localparam WAIT_READY = 4'd0;  // key_ready_in=1 대기
    localparam WAIT_KEY   = 4'd1;  // BRAM Port A에서 키 읽기 (9클록)
    localparam KEY_EXPAND = 4'd2;  // 키 확장 대기
    localparam READY      = 4'd3;  // 복호화 대기
    localparam INIT_ARK   = 4'd4;  // 초기 AddRoundKey (라운드 키 14)
    localparam ROUND_ARK  = 4'd5;  // InvShiftRows→InvSubBytes→AddRoundKey (라운드 13~1)
    localparam ROUND_IMIX = 4'd6;  // InvMixColumns 파이프라인 완료 대기
    localparam FINAL_ARK  = 4'd7;  // 최종 AddRoundKey (라운드 키 0, InvMixColumns 없음)
    localparam OUTPUT     = 4'd8;  // 결과 출력

    reg [3:0]   state;
    reg [127:0] aes_state;
    reg [3:0]   round_num;    // key_expasion 라운드 키 선택 (14→0)
    reg [3:0]   bram_cnt;     // BRAM 읽기 카운터 (0~8)
    reg [255:0] aes_key;      // 조립된 256비트 키

    // =========================================================================
    // 내부 신호
    // =========================================================================
    reg          key_valid_r;
    wire [127:0] round_key;
    wire         key_done;

    wire [127:0] isb_out;    // InvSubBytes 출력
    wire [127:0] isr_out;    // InvShiftRows(InvSubBytes) 출력

    reg          imix_valid_in;
    wire [127:0] imix_out;
    wire         imix_valid_out;

    wire [127:0] ark_out;

    // AddRoundKey 입력 선택
    reg [127:0] ark_in_sel;
    always @(*) begin
        case (state)
            INIT_ARK:  ark_in_sel = data_in;
            ROUND_ARK: ark_in_sel = isr_out;
            FINAL_ARK: ark_in_sel = isr_out;
            default:   ark_in_sel = 128'h0;
        endcase
    end

    // =========================================================================
    // 서브 모듈 인스턴스
    // =========================================================================
    key_expansion u_key_exp (
        .clk       (clk),
        .rst_n     (rst_n),
        .key       (aes_key),
        .key_valid (key_valid_r),
        .round_num (round_num),
        .round_key (round_key),
        .done      (key_done)
    );

    inv_sub_bytes u_isub (
        .in  (aes_state),
        .out (isb_out)
    );

    inv_shift_rows u_ishift (
        .in  (isb_out),
        .out (isr_out)
    );

    inv_mix_columns u_imix (
        .clk       (clk),
        .rst_n     (rst_n),
        .in        (ark_out),
        .valid_in  (imix_valid_in),
        .out       (imix_out),
        .valid_out (imix_valid_out)
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
            state         <= WAIT_READY;
            bram_addr     <= 4'd0;
            bram_en       <= 1'b0;
            bram_cnt      <= 4'd0;
            aes_key       <= 256'h0;
            aes_state     <= 128'h0;
            round_num     <= 4'd0;
            key_valid_r   <= 1'b0;
            imix_valid_in <= 1'b0;
            data_out      <= 128'h0;
            done          <= 1'b0;
            busy          <= 1'b0;
        end else begin
            done          <= 1'b0;
            key_valid_r   <= 1'b0;
            imix_valid_in <= 1'b0;

            case (state)

                // ── encrypt IP의 key_man이 BRAM 쓰기 완료할 때까지 대기 ──
                WAIT_READY: begin
                    bram_en  <= 1'b0;
                    bram_cnt <= 4'd0;
                    if (key_ready_in)
                        state <= WAIT_KEY;
                end

                // ── BRAM Port A에서 256비트 키 읽기 (9클록) ─────────────
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
                                key_valid_r   <= 1'b1;
                                state         <= KEY_EXPAND;
                            end
                            default: ;
                        endcase
                    end

                    if (bram_cnt < 4'd8)
                        bram_cnt <= bram_cnt + 1'b1;
                end

                // ── 키 확장 완료 대기 ─────────────────────────────────────
                KEY_EXPAND: begin
                    if (key_done)
                        state <= READY;
                end

                // ── 복호화 대기 ───────────────────────────────────────────
                READY: begin
                    busy <= 1'b0;
                    if (key_reload_in) begin
                        // 새 키가 BRAM에 기록됨 → 즉시 키 재로드
                        // key_ready_in=1이 보장되므로 WAIT_KEY로 바로 진입
                        bram_cnt <= 4'd0;
                        aes_key  <= 256'h0;
                        state    <= WAIT_KEY;
                    end else if (start) begin
                        round_num <= 4'd14;
                        busy      <= 1'b1;
                        state     <= INIT_ARK;
                    end
                end

                // ── 초기 AddRoundKey: state = data_in ^ rk[14] ───────────
                INIT_ARK: begin
                    aes_state <= ark_out;
                    round_num <= 4'd13;
                    state     <= ROUND_ARK;
                end

                // ── 라운드 13~1: InvShiftRows→InvSubBytes→ARK→InvMixColumns
                ROUND_ARK: begin
                    aes_state     <= ark_out;
                    imix_valid_in <= 1'b1;
                    state         <= ROUND_IMIX;
                end

                // ── InvMixColumns 완료 (1클록 대기) ──────────────────────
                ROUND_IMIX: begin
                    aes_state <= imix_out;

                    if (round_num == 4'd1) begin
                        round_num <= 4'd0;
                        state     <= FINAL_ARK;
                    end else begin
                        round_num <= round_num - 4'd1;
                        state     <= ROUND_ARK;
                    end
                end

                // ── 라운드 0 (최종): InvShiftRows→InvSubBytes→ARK
                FINAL_ARK: begin
                    aes_state <= ark_out;
                    state     <= OUTPUT;
                end

                // ── 결과 출력 ─────────────────────────────────────────────
                OUTPUT: begin
                    data_out <= aes_state;
                    done     <= 1'b1;
                    busy     <= 1'b0;
                    state    <= READY;
                end

                default: state <= WAIT_READY;

            endcase
        end
    end

endmodule
