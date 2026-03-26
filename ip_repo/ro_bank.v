`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 04:07:24 PM
// Design Name: 
// Module Name: ro_bank
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


module ro_bank #(
    parameter SIM_MODE = 0    // 1=시뮬레이션 (LFSR로 RO 대체)
                               // 0=실제 합성 (ro_cell 사용)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output reg  [31:0] data_out,
    output reg         data_valid,
    output wire        raw_bit,
    output reg         raw_valid
);

    // =========================================================================
    // ① RO 출력 - SIM_MODE에 따라 분기
    // =========================================================================
    wire [15:0] ro_out;

    generate
    if (SIM_MODE == 1) begin : g_sim

        reg [15:0] lfsr_a;  // LFSR A
        reg [15:0] lfsr_b;  // LFSR B - 다른 시드, 다른 탭

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                lfsr_a <= 16'hACE1;
                lfsr_b <= 16'h3D4F;   // 다른 시드
            end else if (enable) begin
                // LFSR A 탭: [15,14,12,3]
                lfsr_a <= {lfsr_a[14:0],
                           lfsr_a[15]^lfsr_a[14]^lfsr_a[12]^lfsr_a[3]};
                // LFSR B 탭: [15,13,11,2] - 다른 탭
                lfsr_b <= {lfsr_b[14:0],
                           lfsr_b[15]^lfsr_b[13]^lfsr_b[11]^lfsr_b[2]};
            end
        end

        // ✅ XOR 상쇄 없이 각 비트 독립 배정
        // lfsr_a[7:0] + lfsr_b[7:0] → 16개 독립 비트
        assign ro_out[0]  = lfsr_a[0];
        assign ro_out[1]  = lfsr_a[1];
        assign ro_out[2]  = lfsr_a[2];
        assign ro_out[3]  = lfsr_a[3];
        assign ro_out[4]  = lfsr_a[4];
        assign ro_out[5]  = lfsr_a[5];
        assign ro_out[6]  = lfsr_a[6];
        assign ro_out[7]  = lfsr_a[7];
        assign ro_out[8]  = lfsr_b[0];
        assign ro_out[9]  = lfsr_b[1];
        assign ro_out[10] = lfsr_b[2];
        assign ro_out[11] = lfsr_b[3];
        assign ro_out[12] = lfsr_b[4];
        assign ro_out[13] = lfsr_b[5];
        assign ro_out[14] = lfsr_b[6];
        assign ro_out[15] = lfsr_b[7];

        end
        else begin : g_synth
            genvar k;
            for (k = 0; k < 16; k = k + 1) begin : g_ro
                ro_cell #(.STAGES(3 + k*2)) u_ro (
                    .enable(enable),
                    .ro_out(ro_out[k])
                );
            end
        end
    endgenerate

    // =========================================================================
    // ② XOR 결합
    // =========================================================================
    wire raw_xor;
    assign raw_xor = ^ro_out;

    // =========================================================================
    // ③ D-FF 샘플링
    // =========================================================================
    reg raw_bit_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) raw_bit_d <= 1'b0;
        else        raw_bit_d <= raw_xor;
    end

    assign raw_bit = raw_bit_d;

    // =========================================================================
    // ④ Von Neumann 편향 제거
    // =========================================================================
    reg vn_prev;
    reg vn_phase;
    reg vn_bit;
    reg vn_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vn_prev   <= 1'b0;
            vn_phase  <= 1'b0;
            vn_bit    <= 1'b0;
            vn_valid  <= 1'b0;
            raw_valid <= 1'b0;
        end else if (enable) begin
            vn_valid  <= 1'b0;
            raw_valid <= 1'b1;

            if (vn_phase == 1'b0) begin
                vn_prev  <= raw_bit_d;
                vn_phase <= 1'b1;
            end else begin
                vn_phase <= 1'b0;
                if (vn_prev != raw_bit_d) begin
                    vn_bit   <= vn_prev;
                    vn_valid <= 1'b1;
                end
            end
        end else begin
            vn_phase  <= 1'b0;
            vn_valid  <= 1'b0;
            raw_valid <= 1'b0;
        end
    end

    // =========================================================================
    // ⑤ 32bit 시프트 누적
    // =========================================================================
    reg [31:0] shift_reg;
    reg [5:0]  bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 32'h0;
            bit_cnt    <= 6'd0;
            data_out   <= 32'h0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (vn_valid) begin
                shift_reg <= {shift_reg[30:0], vn_bit};
                bit_cnt   <= bit_cnt + 1'b1;

                if (bit_cnt == 6'd31) begin
                    data_out   <= {shift_reg[30:0], vn_bit};
                    data_valid <= 1'b1;
                    bit_cnt    <= 6'd0;
                end
            end
        end
    end

endmodule





















