`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 01:20:44 PM
// Design Name: 
// Module Name: tb_trng256_core
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


module tb_trng256_core;

    logic         clk, rst_n, enable;
    logic [255:0] rand_data;
    logic         rand_valid;
    logic         health_fail;
    logic         rct_fail, apt_fail;

    // SIM_MODE=1 로 인스턴스 (LFSR 기반 시뮬레이션)
    trng256_core #(
        .SIM_MODE(1)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .rand_data   (rand_data),
        .rand_valid  (rand_valid),
        .health_fail (health_fail),
        .rct_fail    (rct_fail),
        .apt_fail    (apt_fail)
    );

    // 100MHz 클럭
    initial clk = 0;
    always #5 clk = ~clk;

    int valid_count;
    logic [255:0] prev_data;

    initial begin
        rst_n       = 0;
        enable      = 0;
        valid_count = 0;
        prev_data   = 256'h0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        enable = 1;

        $display("=============================================");
        $display("  trng256_core 통합 검증  (SIM_MODE=1)");
        $display("=============================================\n");

        // ── TEST 1: rand_valid + 256bit 출력 확인 ──────────────────────
        $display("=== TEST 1: rand_valid 발생 + 256bit 출력 확인 ===");
        for (int i = 0; i < 100000; i++) begin
            @(posedge clk);
            if (rand_valid) begin
                valid_count++;
                $display("[count=%0d] rand_data = %h", valid_count, rand_data);

                // 이전 값과 다른지 확인 (충돌 검사)
                if (valid_count > 1 && rand_data === prev_data)
                    $display("  WARNING: 연속 동일값 감지!");

                prev_data = rand_data;

                if (valid_count >= 4) begin
                    $display("TEST1 PASS ✓  rand_valid 정상 발생\n");
                    break;
                end
            end
        end

        if (valid_count == 0)
            $display("TEST1 FAIL ✗  rand_valid 미발생\n");

        // ── TEST 2: health_fail = 0 확인 ───────────────────────────────
        $display("=== TEST 2: 정상 동작 중 health_fail=0 확인 ===");
        @(posedge clk);
        if (health_fail == 0)
            $display("TEST2 PASS ✓  health_fail=0 (정상)\n");
        else
            $display("TEST2 FAIL ✗  health_fail=1 (오탐!)\n");

        // ── TEST 3: enable=0 → 출력 정지 확인 ─────────────────────────
        $display("=== TEST 3: enable=0 출력 정지 확인 ===");
        enable = 0;
        repeat(20) @(posedge clk);
        if (rand_valid == 0)
            $display("TEST3 PASS ✓  enable=0 후 rand_valid=0\n");
        else
            $display("TEST3 FAIL ✗  enable=0 인데 rand_valid 발생\n");

        // ── TEST 4: 재시작 후 정상 동작 ────────────────────────────────
        $display("=== TEST 4: enable=1 재시작 확인 ===");
        valid_count = 0;
        enable = 1;
        for (int i = 0; i < 100000; i++) begin
            @(posedge clk);
            if (rand_valid) begin
                valid_count++;
                $display("[재시작 count=%0d] rand_data = %h", valid_count, rand_data);
                if (valid_count >= 2) begin
                    $display("TEST4 PASS ✓  재시작 후 정상 동작\n");
                    break;
                end
            end
        end

        $display("=============================================");
        $display("  시뮬레이션 완료");
        $display("=============================================");
        #100; $finish;
    end

    // 타임아웃
    initial begin
        #50000000;
        $display("TIMEOUT 강제 종료");
        $finish;
    end

    initial begin
        $dumpfile("tb_trng256_core.vcd");
        $dumpvars(0, tb_trng256_core);
    end

endmodule
