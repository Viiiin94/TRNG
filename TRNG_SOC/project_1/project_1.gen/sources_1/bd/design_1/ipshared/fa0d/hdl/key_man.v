`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: key_man
// Description: TRNG → BRAM Port B 키 저장 + AES 코어 BRAM 읽기 중재
//
// 동작 순서:
//   1. TRNG rand_valid=1 → 256bit 키를 BRAM Port B에 32bit×8 순차 쓰기
//      (바이트 주소: word 0→0x00, word 1→0x04, ..., word 7→0x1C)
//   2. 쓰기 완료 → key_ready=1, key_reload=1(1클록 펄스)
//   3. key_ready=1 이후 → AES 코어가 Port B로 읽기 접근
//   4. 새 rand_valid 수신 시 키 갱신 (key_ready=0 → WRITE_KEY → KEY_DONE)
//
// BRAM Port B (blk_mem_gen True Dual Port, Width=32, 바이트 주소)
//   addrb : 32bit 바이트 주소 (word N = N×4)
//   dinb  : 32bit 쓰기 데이터
//   doutb : 32bit 읽기 데이터
//   enb   : port enable
//   web   : byte write enable (4bit)
//   rstb  : synchronous reset (0 고정)
//////////////////////////////////////////////////////////////////////////////////

module key_man (
    input  wire         clk,
    input  wire         rst_n,

    // ── TRNG 인터페이스 ─────────────────────────────────
    input  wire [255:0] rand_data,     // TRNG 256bit 출력
    input  wire         rand_valid,    // TRNG 유효 펄스 (1클록)

    // ── BRAM Port B 인터페이스 ──────────────────────────
    output reg  [31:0]  bram_addrb,    // 32bit 바이트 주소
    output reg  [31:0]  bram_dinb,     // 쓰기 데이터
    output reg  [3:0]   bram_web,      // 쓰기 인에이블 (byte-wise)
    output reg          bram_enb,      // 포트 인에이블
    output wire         bram_rstb,     // 동기 리셋 (0 고정)
    input  wire [31:0]  bram_doutb,    // 읽기 데이터

    // ── AES 코어 인터페이스 ─────────────────────────────
    input  wire [3:0]   aes_bram_addr, // AES 읽기 워드 주소 (0~7)
    input  wire         aes_bram_en,   // AES 읽기 인에이블
    output wire [31:0]  aes_bram_dout, // AES로 전달되는 읽기 데이터

    // ── 상태 출력 ───────────────────────────────────────
    output reg          key_ready,     // 1=키 저장 완료, AES 사용 가능
    output reg          key_reload     // 1클록 펄스: AES 코어 키 재로드 요청
);

    // BRAM rstb는 BRAM 내용을 지우지 않도록 0 고정
    assign bram_rstb     = 1'b0;
    // AES 읽기 데이터는 BRAM doutb 직결
    assign aes_bram_dout = bram_doutb;

    // =========================================================================
    // FSM 상태
    // =========================================================================
    localparam WAIT_TRNG = 2'd0;   // TRNG rand_valid 대기
    localparam WRITE_KEY = 2'd1;   // BRAM에 32bit×8 쓰기
    localparam KEY_DONE  = 2'd2;   // 키 저장 완료, AES 접근 허용

    reg [1:0]   state;
    reg [2:0]   wr_idx;       // 쓰기 인덱스 0~7
    reg [255:0] key_buf;      // rand_data 래치

    // =========================================================================
    // 현재 쓰기 워드 선택
    // =========================================================================
    reg [31:0] key_word;
    always @(*) begin
        case (wr_idx)
            3'd0: key_word = key_buf[255:224];
            3'd1: key_word = key_buf[223:192];
            3'd2: key_word = key_buf[191:160];
            3'd3: key_word = key_buf[159:128];
            3'd4: key_word = key_buf[127:96];
            3'd5: key_word = key_buf[95:64];
            3'd6: key_word = key_buf[63:32];
            3'd7: key_word = key_buf[31:0];
            default: key_word = 32'h0;
        endcase
    end

    // =========================================================================
    // BRAM Port B 중재 (조합 회로)
    //   key_ready=0 : key_man 쓰기 모드
    //   key_ready=1 : AES 코어 읽기 모드
    // =========================================================================
    always @(*) begin
        if (!key_ready) begin
            // 쓰기 모드: 워드 주소 → 바이트 주소 변환 (×4)
            bram_addrb = {27'h0, wr_idx[2:0], 2'b00};
            bram_dinb  = key_word;
            bram_web   = 4'hF;
            bram_enb   = (state == WRITE_KEY);
        end else begin
            // 읽기 모드: AES 워드 주소 → 바이트 주소 변환 (×4)
            bram_addrb = {27'h0, aes_bram_addr[2:0], 2'b00};
            bram_dinb  = 32'h0;
            bram_web   = 4'h0;
            bram_enb   = aes_bram_en;
        end
    end

    // =========================================================================
    // 메인 FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= WAIT_TRNG;
            wr_idx     <= 3'd0;
            key_buf    <= 256'h0;
            key_ready  <= 1'b0;
            key_reload <= 1'b0;
        end else begin
            key_reload <= 1'b0;  // 기본값: 0 (1클록 펄스)

            case (state)

                // ── TRNG 데이터 대기 ──────────────────────────────────
                WAIT_TRNG: begin
                    if (rand_valid) begin
                        key_buf <= rand_data;
                        wr_idx  <= 3'd0;
                        state   <= WRITE_KEY;
                    end
                end

                // ── BRAM 쓰기 (32bit × 8회) ───────────────────────────
                WRITE_KEY: begin
                    if (wr_idx == 3'd7) begin
                        key_ready  <= 1'b1;
                        key_reload <= 1'b1;   // AES 코어에 키 재로드 신호
                        state      <= KEY_DONE;
                    end else begin
                        wr_idx <= wr_idx + 1'b1;
                    end
                end

                // ── 키 저장 완료 (AES 읽기 허용, 갱신 대기) ──────────
                KEY_DONE: begin
                    if (rand_valid) begin
                        key_buf   <= rand_data;
                        key_ready <= 1'b0;
                        wr_idx    <= 3'd0;
                        state     <= WRITE_KEY;
                    end
                end

                default: state <= WAIT_TRNG;
            endcase
        end
    end

endmodule
