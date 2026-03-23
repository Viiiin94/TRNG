`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 04:33:55 PM
// Design Name: 
// Module Name: tb_ro_bank
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


module tb_ro_bank;

    logic        clk, rst_n, enable;
    logic [31:0] data_out;
    logic        data_valid;
    logic        raw_bit;
    logic        raw_valid;

    // DUT
    ro_bank u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .data_out   (data_out),
        .data_valid (data_valid),
        .raw_bit    (raw_bit),
        .raw_valid  (raw_valid)
    );

    // 클럭
    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz

    // ── 시뮬레이션에서 RO 강제 주입 ──
    // ro_out이 시뮬레이션에서 X이므로
    // 강제로 패턴을 주입해서 VN + 누적 로직만 검증
    // (실제 랜덤성은 FPGA 합성 후 ILA로 확인)
    initial begin
        // ro_out 강제 구동 (시뮬레이션 전용)
        // 실제 합성에서는 이 라인 무시됨
        force u_dut.ro_out = 16'hA5A5;  // 0101 패턴으로 강제
    end

    integer valid_count;
    integer i;

    initial begin
        rst_n       = 0;
        enable      = 0;
        valid_count = 0;

        // 리셋
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // 동작 시작
        enable = 1;
        $display("=== ro_bank 시뮬레이션 시작 ===");

        // ── 테스트 1: data_valid 신호 발생 확인 ──
        $display("TEST1: data_valid 신호 기다리는 중...");
        for (i = 0; i < 500; i++) begin
            @(posedge clk);
            if (data_valid) begin
                valid_count++;
                $display("[%0t] data_valid=1, data_out=0x%08X  (count=%0d)",
                          $time, data_out, valid_count);
                if (valid_count >= 4) begin
                    $display("TEST1 PASS: data_valid 정상 발생");
                    break;  // for 루프 탈출
                end
            end
        end

        if (valid_count == 0)
            $display("TEST1 FAIL: data_valid 미발생 (VN 로직 확인 필요)");

        // ── 테스트 2: enable=0 → 정지 확인 ──
        $display("\nTEST2: enable=0 동작 정지 확인");
        enable = 0;
        repeat(10) @(posedge clk);
        $display("enable=0 후 data_valid=%b (0이어야 정상)", data_valid);

        // ── 테스트 3: 재시작 확인 ──
        $display("\nTEST3: enable=1 재시작");
        enable = 1;
        @(posedge clk);
        wait(data_valid);
        $display("재시작 후 data_out=0x%08X", data_out);
        $display("TEST3 PASS");

        $display("\n=== 시뮬레이션 완료 ===");
        $finish;
    end

    // 파형 덤프
    initial begin
        $dumpfile("tb_ro_bank.vcd");
        $dumpvars(0, tb_ro_bank);
    end

endmodule
