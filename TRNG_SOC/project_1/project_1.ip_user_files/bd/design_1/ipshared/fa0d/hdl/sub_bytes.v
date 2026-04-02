`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: sub_bytes
// Description: AES SubBytes - 16바이트 각각 S-Box 치환
//////////////////////////////////////////////////////////////////////////////////

module sub_bytes(
    input  wire [127:0] in,
    output wire [127:0] out
);

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_sbox
            s_box u_sbox (
                .in  (in [127 - i*8 -: 8]),
                .out (out[127 - i*8 -: 8])
            );
        end
    endgenerate

endmodule
