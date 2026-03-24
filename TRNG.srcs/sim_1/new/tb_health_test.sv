`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 12:27:53 PM
// Design Name: 
// Module Name: tb_health_test
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


module tb_health_test;

    logic clk, rst_n, enable;
    logic raw_bit, raw_valid;
    logic health_fail, rct_fail, apt_fail;

    // ── DUT ──────────────────────────────────────────────────────────────────
    health_test dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .raw_bit     (raw_bit),
        .raw_valid   (raw_valid),
        .health_fail (health_fail),
        .rct_fail    (rct_fail),
        .apt_fail    (apt_fail)
    );

    // 100MHz 클럭
    initial clk = 0;
    always #5 clk = ~clk;

    // ── 태스크: 비트 1개 전송 ─────────────────────────────────────────────
    task send_bit(input logic bit_val);
        @(posedge clk); #1;
        raw_bit   = bit_val;
        raw_valid = 1'b1;
        @(posedge clk); #1;
        raw_valid = 1'b0;
    endtask

    // ── 태스크: N비트 패턴 전송 ───────────────────────────────────────────
    task send_pattern(input int n, input logic pattern);
        for (int i = 0; i < n; i++) begin
            send_bit(pattern);
        end
    endtask

    // ── 태스크: LFSR 랜덤 N비트 전송 ─────────────────────────────────────
    logic [7:0] lfsr_state;
    task send_random(input int n);
        for (int i = 0; i < n; i++) begin
            // 8bit LFSR
            lfsr_state = {lfsr_state[6:0],
                          lfsr_state[7] ^ lfsr_state[5] ^
                          lfsr_state[4] ^ lfsr_state[3]};
            send_bit(lfsr_state[0]);
        end
    endtask

    // ── 리셋 태스크 ───────────────────────────────────────────────────────
    task do_reset();
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
    endtask

    // ── 메인 테스트 ───────────────────────────────────────────────────────
    initial begin
        // 초기화
        rst_n     = 0;
        enable    = 0;
        raw_bit   = 0;
        raw_valid = 0;
        lfsr_state = 8'hA5;

        do_reset();
        enable = 1;

        $display("=============================================");
        $display("  Health Test 검증");
        $display("=============================================\n");

        // ── TEST 1: 정상 동작 확인 ──────────────────────────────────────
        $display("=== TEST 1: 정상 랜덤 비트 600개 ===");
        send_random(600);
        @(posedge clk); #1;

        if (health_fail == 0)
            $display("TEST1 PASS ✓  health_fail=0 (정상)\n");
        else
            $display("TEST1 FAIL ✗  health_fail=1 (오탐!)\n");

        // ── TEST 2: RCT 고장 유발 ───────────────────────────────────────
        $display("=== TEST 2: RCT 고장 - 0을 41번 연속 ===");
        do_reset();
        enable = 1;

        // 정상 몇 개 보내고
        send_random(10);
        // 0을 41번 연속 전송 → RCT 트리거
        $display("  0을 41번 연속 전송 중...");
        send_pattern(41, 1'b0);
        @(posedge clk); #1;

        if (rct_fail == 1)
            $display("TEST2 PASS ✓  rct_fail=1 (고장 감지)\n");
        else
            $display("TEST2 FAIL ✗  rct_fail=0 (감지 못함!)\n");

        // ── TEST 3: APT 편향 유발 ───────────────────────────────────────
        $display("=== TEST 3: APT 편향 - 윈도우 내 0이 330개 ===");
        do_reset();
        enable = 1;

        // APT 윈도우 시작 (첫 비트 = 0 → 기준값 0)
        send_bit(1'b0);  // 기준값 설정
        // 0을 329번 더 전송 (총 330번 → 컷오프 325 초과)
        $display("  0을 330번 전송 중 (기준값=0, 컷오프=325)...");
        send_pattern(329, 1'b0);
        @(posedge clk); #1;

        if (apt_fail == 1)
            $display("TEST3 PASS ✓  apt_fail=1 (편향 감지)\n");
        else
            $display("TEST3 FAIL ✗  apt_fail=0 (감지 못함!)\n");

        // ── TEST 4: APT 정상 - 컷오프 미만 ─────────────────────────────
        $display("=== TEST 4: APT 정상 - 윈도우 내 0이 300개 ===");
        do_reset();
        enable = 1;

        // 0을 300개 + 1을 212개 = 512개 (0의 비율이 컷오프 325 미만)
        send_bit(1'b0);       // 기준값 = 0
        send_pattern(299, 1'b0);   // 0 추가 299개 (총 300개)
        send_pattern(212, 1'b1);   // 1을 212개
        @(posedge clk); #1;

        if (apt_fail == 0)
            $display("TEST4 PASS ✓  apt_fail=0 (정상 범위)\n");
        else
            $display("TEST4 FAIL ✗  apt_fail=1 (오탐!)\n");

        // ── TEST 5: enable=0 → 리셋 확인 ────────────────────────────────
        $display("=== TEST 5: enable=0 → 상태 리셋 확인 ===");
        // 고장 상태 만들기
        do_reset(); enable = 1;
        send_pattern(41, 1'b1);  // RCT 고장
        @(posedge clk);
        $display("  고장 전: rct_fail=%b", rct_fail);

        // enable=0 → 리셋
        enable = 0;
        repeat(5) @(posedge clk); #1;
        $display("  enable=0 후: rct_fail=%b health_fail=%b", rct_fail, health_fail);

        // enable=1 → 재시작
        enable = 1;
        send_random(10);
        @(posedge clk); #1;

        if (health_fail == 0)
            $display("TEST5 PASS ✓  재시작 후 정상\n");
        else
            $display("TEST5 FAIL ✗  재시작 후에도 fail\n");

        $display("=============================================");
        $display("  시뮬레이션 완료");
        $display("=============================================");
        #100; $finish;
    end

    // 타임아웃
    initial begin
        #500000;
        $display("TIMEOUT 강제 종료");
        $finish;
    end

    initial begin
        $dumpfile("tb_health_test.vcd");
        $dumpvars(0, tb_health_test);
    end

endmodule
