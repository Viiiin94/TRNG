`timescale 1ns/1ps

module tb_ro_bank;

    logic        clk, rst_n, enable;
    logic [31:0] data_out;
    logic        data_valid;
    logic        raw_bit;
    logic        raw_valid;

    // ── SIM_MODE=1 로 인스턴스 ──────────────────────────────────
    ro_bank #(
        .SIM_MODE(1)       // ← 핵심! LFSR 모드로 시뮬레이션
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .data_out   (data_out),
        .data_valid (data_valid),
        .raw_bit    (raw_bit),
        .raw_valid  (raw_valid)
    );

    // 100MHz 클럭
    initial clk = 0;
    always #5 clk = ~clk;

    int valid_count;

    initial begin
        rst_n       = 0;
        enable      = 0;
        valid_count = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        enable = 1;

        $display("=== ro_bank 시뮬레이션 시작 (SIM_MODE=1) ===");

        // ── 테스트 1: data_valid 발생 확인 ──
        $display("TEST1: data_valid 기다리는 중...");
        for (int i = 0; i < 2000; i++) begin
            @(posedge clk);
            if (data_valid) begin
                valid_count++;
                $display("[%0d ns] data_valid=1  data_out=0x%08X  (count=%0d)",
                          $time/1000, data_out, valid_count);
                if (valid_count >= 4) begin
                    $display("TEST1 PASS ✓");
                    break;
                end
            end
        end

        if (valid_count == 0)
            $display("TEST1 FAIL: data_valid 미발생");

        // ── 테스트 2: enable=0 정지 확인 ──
        $display("\nTEST2: enable=0 정지 확인");
        enable = 0;
        repeat(20) @(posedge clk);
        $display("TEST2 %s: data_valid=%b",
                  (data_valid==0) ? "PASS ✓" : "FAIL", data_valid);

        // ── 테스트 3: 재시작 확인 ──
        $display("\nTEST3: enable=1 재시작 확인");
        valid_count = 0;
        enable = 1;
        for (int i = 0; i < 2000; i++) begin
            @(posedge clk);
            if (data_valid) begin
                valid_count++;
                $display("[%0d ns] 재시작 후 data_out=0x%08X", $time/1000, data_out);
                if (valid_count >= 2) begin
                    $display("TEST3 PASS ✓");
                    break;
                end
            end
        end

        $display("\n=== 시뮬레이션 완료 ===");
        #50; $finish;
    end

    // 타임아웃
    initial begin
        #200000;
        $display("TIMEOUT 강제 종료");
        $finish;
    end

    initial begin
        $dumpfile("tb_ro_bank.vcd");
        $dumpvars(0, tb_ro_bank);
    end

endmodule