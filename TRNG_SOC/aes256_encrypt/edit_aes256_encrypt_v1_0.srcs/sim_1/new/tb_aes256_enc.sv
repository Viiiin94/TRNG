`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_aes256_enc
// Description: AES256 암호화 코어 테스트벤치
//
// NIST FIPS 197 AES-256 테스트 벡터:
//   Key:    000102030405060708090a0b0c0d0e0f
//           101112131415161718191a1b1c1d1e1f
//   Plain:  00112233445566778899aabbccddeeff
//   Cipher: 8ea2b7ca516745bfeafc49904b496089
//////////////////////////////////////////////////////////////////////////////////

module tb_aes256_enc();

    // =========================================================================
    // 클록 / 리셋
    // =========================================================================
    reg clk, rst_n;

    initial clk = 0;
    always #5 clk = ~clk;   // 100MHz

    // =========================================================================
    // DUT 포트
    // =========================================================================
    wire [3:0]   bram_addr;
    wire         bram_en;
    reg  [31:0]  bram_dout;

    reg          start;
    reg  [127:0] data_in;
    wire [127:0] data_out;
    wire         done;
    wire         busy;

    // =========================================================================
    // BRAM 모델 (Simple Dual Port Port-B, 1클록 읽기 지연)
    // Key: 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
    // =========================================================================
    reg [31:0] bram_mem [0:7];

    initial begin
        bram_mem[0] = 32'h00010203;  // key[255:224]
        bram_mem[1] = 32'h04050607;  // key[223:192]
        bram_mem[2] = 32'h08090a0b;  // key[191:160]
        bram_mem[3] = 32'h0c0d0e0f;  // key[159:128]
        bram_mem[4] = 32'h10111213;  // key[127:96]
        bram_mem[5] = 32'h14151617;  // key[95:64]
        bram_mem[6] = 32'h18191a1b;  // key[63:32]
        bram_mem[7] = 32'h1c1d1e1f;  // key[31:0]
    end

    always @(posedge clk) begin
        if (bram_en)
            bram_dout <= bram_mem[bram_addr];
    end

    // =========================================================================
    // DUT 인스턴스
    // =========================================================================
    aes256_enc_core u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .bram_addr (bram_addr),
        .bram_en   (bram_en),
        .bram_dout (bram_dout),
        .start     (start),
        .data_in   (data_in),
        .data_out  (data_out),
        .done      (done),
        .busy      (busy)
    );

    // =========================================================================
    // 타임아웃 (무한 루프 방지)
    // =========================================================================
    initial begin
        #50000;
        $display("[TIMEOUT] 시뮬레이션 타임아웃");
        $finish;
    end

    // =========================================================================
    // 테스트 시퀀스
    // =========================================================================
    integer fail_cnt;

    initial begin
        fail_cnt = 0;
        start    = 0;
        data_in  = 128'h0;
        rst_n    = 0;

        $display("===================================================");
        $display("  AES256 암호화 코어 테스트 시작");
        $display("===================================================");

        // 리셋 인가
        repeat(5) @(posedge clk);
        rst_n = 1;
        $display("[%0t] 리셋 해제", $time);

        // ── BRAM 읽기 + 키 확장 완료 대기 ────────────────────────────────
        // WAIT_KEY(9클록) + KEY_EXPAND(54클록) = 63클록
        $display("[%0t] BRAM 키 읽기 + 키 확장 중...", $time);
        wait (u_dut.state == 4'd2);   // READY 상태 대기
        @(posedge clk);
        $display("[%0t] 키 확장 완료 → READY", $time);

        // ── 테스트 1: NIST AES-256 테스트 벡터 ───────────────────────────
        $display("---------------------------------------------------");
        $display("[테스트 1] NIST AES-256 테스트 벡터");
        $display("  Key:    000102...1e1f");
        $display("  Plain:  00112233445566778899aabbccddeeff");
        $display("  Expect: 8ea2b7ca516745bfeafc49904b496089");

        data_in = 128'h00112233445566778899aabbccddeeff;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // done 대기
        wait (done == 1);
        @(posedge clk);

        $display("  Result: %h", data_out);
        if (data_out === 128'h8ea2b7ca516745bfeafc49904b496089) begin
            $display("  [PASS]");
        end else begin
            $display("  [FAIL] 기대값과 다름");
            fail_cnt = fail_cnt + 1;
        end

        // ── 테스트 2: 전체 0 평문 ─────────────────────────────────────────
        $display("---------------------------------------------------");
        $display("[테스트 2] 전체 0 평문");
        $display("  Plain:  00000000000000000000000000000000");
        $display("  Expect: dc95c078a2408989ad48a21492842087");

        wait (u_dut.state == 4'd2);  // READY 대기
        @(posedge clk);

        data_in = 128'h0;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait (done == 1);
        @(posedge clk);

        $display("  Result: %h", data_out);
        if (data_out === 128'hdc95c078a2408989ad48a21492842087) begin
            $display("  [PASS]");
        end else begin
            $display("  [FAIL] 기대값과 다름");
            fail_cnt = fail_cnt + 1;
        end

        // ── 최종 결과 ─────────────────────────────────────────────────────
        $display("===================================================");
        if (fail_cnt == 0)
            $display("  최종 결과: 전체 PASS");
        else
            $display("  최종 결과: %0d개 FAIL", fail_cnt);
        $display("===================================================");

        #100;
        $finish;
    end

    // =========================================================================
    // 파형 덤프
    // =========================================================================
    initial begin
        $dumpfile("tb_aes256_enc.vcd");
        $dumpvars(0, tb_aes256_enc);
    end

endmodule
