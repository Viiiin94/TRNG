`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/23/2026 03:32:01 PM
// Design Name: 
// Module Name: ro_cell
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

(* DONT_TOUCH = "TRUE" *)
module ro_cell #(
    parameter STAGES = 3
)
(
    input wire enable,
    output wire ro_out
);

    generate
        if(STAGES % 2 ==0) begin
            initial begin
                $error("ro_cell: STAGES must be ODD! Got %0d", STAGES);
                $finish;
            end
        end
    endgenerate
    
    // ── 인버터 체인 신호 ────────────────────────────────────────────────────
    // KEEP: 신호선(net) 제거 방지
    // DONT_TOUCH: 셀 자체 최적화/병합 방지
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
    wire [STAGES-1:0] chain;

    // ── enable 게이팅 ───────────────────────────────────────────────────────
    // enable=0 → feedback=0 → 체인 전체 0으로 수렴 → 발진 정지
    // enable=1 → 마지막 인버터 출력이 피드백 → 발진 지속
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
    wire feedback;
    assign feedback = enable & chain[STAGES-1];
    
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
    INV u_inv_0 (.I(feedback), .O(chain[0]));
    
        // ── 나머지 인버터 체인 생성 ─────────────────────────────────────────────
    genvar i;
    generate
        for (i = 1; i < STAGES; i = i + 1) begin : g_inv_chain
            (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *)
            INV u_inv (
                .I (chain[i-1]),
                .O (chain[i])
            );
        end
    endgenerate

    // ── 출력 ────────────────────────────────────────────────────────────────
    assign ro_out = chain[STAGES-1];

endmodule





















