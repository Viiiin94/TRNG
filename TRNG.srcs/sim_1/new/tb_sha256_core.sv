// =============================================================================
// 파일명  : tb_sha256.sv
// 설명    : sha256_core 검증 테스트벤치
//           NIST 테스트 벡터로 정확성 검증
// =============================================================================
`timescale 1ns/1ps

module tb_sha256;

    // ── 신호 선언 ──────────────────────────────────────────────────────────
    logic         clk;
    logic         rst_n;
    logic [255:0] entropy_in;
    logic         start;
    logic [255:0] hash_out;
    logic         hash_valid;

    // ── DUT ────────────────────────────────────────────────────────────────
    sha256_core dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .entropy_in (entropy_in),
        .start      (start),
        .hash_out   (hash_out),
        .hash_valid (hash_valid)
    );

    // ── 100MHz 클럭 ────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Python으로 계산한 테스트 벡터 ──────────────────────────────────────
    // TEST1: SHA-256(0x00 × 32bytes)
    localparam [255:0] EXP_T1 =
        256'h66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925;

    // TEST2: SHA-256(0xFF × 32bytes)
    localparam [255:0] EXP_T2 =
        256'haf9613760f72635fbdb44a5a0a63c39f12af30f950a6ee5c971be188e89c4051;

    // ── 태스크: SHA-256 실행 + 검증 ────────────────────────────────────────
    task run_sha256(
        input [255:0] input_data,
        input [255:0] expected,
        input string  test_name
    );
        integer cycle_cnt;
        begin
            cycle_cnt = 0;

            // start 펄스 1클럭
            @(posedge clk); #1;
            entropy_in = input_data;
            start      = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;

            // hash_valid 대기 (최대 200클럭)
            fork
                begin : wait_valid
                    while (!hash_valid) begin
                        @(posedge clk);
                        cycle_cnt++;
                    end
                end
                begin : timeout
                    repeat(200) @(posedge clk);
                    $display("[%s] TIMEOUT: hash_valid 미발생!", test_name);
                    disable wait_valid;
                end
            join_any
            disable fork;

            @(posedge clk); #1;

            // 결과 출력
            $display("[%s] 소요 클럭 : %0d", test_name, cycle_cnt);
            $display("[%s] hash_out  : %h", test_name, hash_out);
            $display("[%s] expected  : %h", test_name, expected);

            if (hash_out === expected)
                $display("[%s] >>> PASS ✓\n", test_name);
            else
                $display("[%s] >>> FAIL ✗  (불일치!)\n", test_name);
        end
    endtask

    // ── 메인 테스트 ────────────────────────────────────────────────────────
    initial begin
        // 초기화
        rst_n      = 0;
        start      = 0;
        entropy_in = 256'h0;

        // 리셋
        repeat(4) @(posedge clk); #1;
        rst_n = 1;
        repeat(2) @(posedge clk); #1;

        $display("=============================================");
        $display("  SHA-256 Core 검증  (NIST 테스트 벡터)");
        $display("=============================================\n");

        // ── TEST 1: 256bit 전부 0 ──
        $display("=== TEST 1: entropy = 256'h0 (all zeros) ===");
        run_sha256(256'h0, EXP_T1, "TEST1");

        // ── TEST 2: 256bit 전부 0xFF ──
        $display("=== TEST 2: entropy = 256'hFF...FF (all ones) ===");
        run_sha256(
            256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            EXP_T2, "TEST2"
        );

        // ── TEST 3: 연속 실행 (같은 입력 → 같은 출력) ──
        $display("=== TEST 3: 재현성 확인 (TEST1 재실행) ===");
        run_sha256(256'h0, EXP_T1, "TEST3");

        // ── TEST 4: 다른 입력 → 다른 출력 확인 ──
        $display("=== TEST 4: 다른 입력 → 다른 출력 확인 ===");
        begin
            logic [255:0] out1, out2;

            entropy_in = 256'h0;
            start = 1'b1; @(posedge clk); #1;
            start = 1'b0;
            wait(hash_valid); @(posedge clk); #1;
            out1 = hash_out;

            entropy_in = 256'h1;
            start = 1'b1; @(posedge clk); #1;
            start = 1'b0;
            wait(hash_valid); @(posedge clk); #1;
            out2 = hash_out;

            $display("[TEST4] input=0  out=%h", out1);
            $display("[TEST4] input=1  out=%h", out2);
            if (out1 !== out2)
                $display("[TEST4] >>> PASS ✓  (다른 입력 → 다른 출력)\n");
            else
                $display("[TEST4] >>> FAIL ✗  (충돌 발생!)\n");
        end

        $display("=============================================");
        $display("  시뮬레이션 완료");
        $display("=============================================");
        #50; $finish;
    end

    // ── 타임아웃 안전장치 ──────────────────────────────────────────────────
    initial begin
        #100000;
        $display("TIMEOUT: 강제 종료");
        $finish;
    end

    // ── 파형 덤프 ──────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_sha256.vcd");
        $dumpvars(0, tb_sha256);
    end

endmodule


















