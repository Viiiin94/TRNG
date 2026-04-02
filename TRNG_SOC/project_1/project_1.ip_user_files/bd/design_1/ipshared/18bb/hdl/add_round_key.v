`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: add_round_key
// Description: AES AddRoundKey - state XOR 라운드 키 (FIPS 197 Section 5.1.4)
//              조합회로
//////////////////////////////////////////////////////////////////////////////////

module add_round_key(
    input  wire [127:0] state,
    input  wire [127:0] round_key,
    output wire [127:0] out
);

    assign out = state ^ round_key;

endmodule
