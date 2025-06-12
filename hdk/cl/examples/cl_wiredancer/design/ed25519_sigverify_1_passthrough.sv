`default_nettype none

// -----------------------------------------------------------------------------
//  Pass-through stub for ed25519_sigverify_1
//  – Keeps identical port list so the rest of the design compiles
//  – Always ready (i_r = 1), forwards i_v → o_v
//  – Converts sv_meta5_t ➜ sv_meta6_t by zero-padding new fields
// -----------------------------------------------------------------------------

import wd_sigverify::*;

module ed25519_sigverify_1_passthrough #(
    parameter logic [32-1:0] MUL_T  = 32'h007F_CCC2,
    parameter integer        MUL_D  = 15,
    parameter integer        DSDP_WS= 2,
    parameter integer        KEY_D  = 512,
    parameter integer        KEY_D_L= $clog2(KEY_D)
)(
    output logic                        i_r,  // ready / back-pressure to previous stage
    input  wire                         i_w,  // wait      (unused in stub)
    input  wire                         i_v,  // valid in
    input  wire [$bits(sv_meta5_t)-1:0] i_m,  // meta5 in

    output logic                        o_v,  // valid out
    output logic [$bits(sv_meta6_t)-1:0] o_m, // meta6 out

    input  wire                         clk,
    input  wire                         rst
);

    //--------------------------------------------------
    // Handshake and readiness
    //--------------------------------------------------
    assign i_r = 1'b1; // always accept data
    assign o_v = i_v;  // propagate valid

    //--------------------------------------------------
    // Meta widening: sv_meta5_t → sv_meta6_t
    //--------------------------------------------------
    sv_meta5_t m5;
    sv_meta6_t m6;

    assign m5 = sv_meta5_t'(i_m);
    assign m6 = '{default:0};   // zero all fields initially
    assign m6.m = m5;           // copy existing sub-structure

    assign o_m = m6;

endmodule

`default_nettype wire

