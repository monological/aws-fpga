`default_nettype none

// -----------------------------------------------------------------------------
//  Pass-through stub for ed25519_sigverify_0
//  – Keeps the original module name and port list so other source files compile
//  – Simply forwards handshake (i_r/i_v -> o_v) and zero-pads meta struct
// -----------------------------------------------------------------------------

import wd_sigverify::*;

module ed25519_sigverify_0_passthrough #(
    parameter MUL_T  = 32'h007F_CCC2,
    parameter MUL_D  = 15,
    parameter N_SCH  = 2,
    parameter KEY_D  = 512,
    parameter KEY_D_L= $clog2(KEY_D)
)(
    output logic                                i_r,  // ready / back-pressure
    input  wire                                 i_w,  // wait      (unused)
    input  wire                                 i_v,  // valid in
    input  wire [$bits(sv_meta4_t)-1:0]         i_m,  // meta4 in

    output logic                                o_v,  // valid out
    output logic [$bits(sv_meta5_t)-1:0]        o_m,  // meta5 out

    input  wire                                 clk,
    input  wire                                 rst
);

    //--------------------------------------------------
    //  Handshake: pass i_v straight through; always ready
    //--------------------------------------------------
    assign i_r = 1'b1;  // always accept
    assign o_v = i_v;   // forward valid

    //--------------------------------------------------
    //  Widen meta struct (meta4 -> meta5) with zero padding
    //--------------------------------------------------
    sv_meta4_t m4;
    sv_meta5_t m5;

    assign m4 = sv_meta4_t'(i_m);
    assign m5 = '{default:0};           // zero all bits first
    assign m5.m = m4;                   // copy the sub-struct

    assign o_m = m5;

endmodule

`default_nettype wire
