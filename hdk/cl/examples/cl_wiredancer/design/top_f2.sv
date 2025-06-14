`default_nettype none

import wd_sigverify::*;

module top_f2 #(
    // fast sim
    // MUL_T                                               = 32'h0000_0802, // 8-cycle mock mul_wide
    // MUL_D                                               = 15,
    // N_SCH                                               = 2,
    // DSDP_WS                                             = 256,
    // TH_PRE                                              = {12'h0, 12'd2, 12'd2},
    // TH_SHA                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV0                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV1                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV2                                              = {12'h0, 12'd2, 12'd2},

    // small
    // KEY_D                                               = 32,
    // MUL_T                                               = 32'h007F_CCC2,
    // MUL_D                                               = 15,
    // N_SCH                                               = 2,
    // DSDP_WS                                             = 256,
    // TH_PRE                                              = {12'h0, 12'd2, 12'd2},
    // TH_SHA                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV0                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV1                                              = {12'h0, 12'd2, 12'd2},
    // TH_SV2                                              = {12'h0, 12'd2, 12'd2},

    // full
    KEY_D                                               = 512,
    MUL_T                                               = 32'h07F_CCC2,
    MUL_D                                               = 15,
    N_SCH                                               = 5,
    DSDP_WS                                             = 256,
    TH_PRE                                              = {12'h0, 12'd10, 12'd10},
    TH_SHA                                              = {12'h0, 12'd200, 12'd200},
    TH_SV0                                              = {12'h0, 12'd200, 12'd200},
    TH_SV1                                              = {12'h0, 12'd200, 12'd200},
    TH_SV2                                              = {12'h0, 12'd200, 12'd200},

    DBG_WIDTH = 1024,
    DMA_N = 2,
    PCIE_N = 2
) (

    input wire [1-1:0]                                  avmm_read,
    input wire [1-1:0]                                  avmm_write,
    input wire [32-1:0]                                 avmm_address,
    input wire [32-1:0]                                 avmm_writedata,
    output logic [32-1:0]                               avmm_readdata,
    output logic [1-1:0]                                avmm_readdatavalid,
    output logic [1-1:0]                                avmm_waitrequest,

    input wire [16-1:0][8-1:0]                          priv_bytes,

    input wire [2-1:0]                                  pcie_v,
    input wire [64-1:0]                                 pcie_a,
    input wire [2-1:0][256-1:0]                         pcie_d,

    input wire [1-1:0]                                  dma_push_ready,
    output logic [1-1:0]                                dma_push_valid,
    output logic [64-1:0]                               dma_push_addr,
    output logic [64-1:0]                               dma_push_wstrb,
    input wire [1-1:0]                                  dma_fifo_full,
    output logic [256-1:0]                              dma_push_data,

    output logic [DBG_WIDTH-1:0]                        dbg_wire,

    input wire clk_f,
    input wire rst_f,

    input wire clk,
    input wire rst
);

logic [64-1:0]                          timestamp = 0;

logic [32-1:0]                          tr_pending;

(* dont_touch = "yes" *) logic [10-1:0] rst_r;
(* dont_touch = "yes" *) logic [10-1:0] rst_f_r;

logic [1-1:0]                           send_fails = 0;

logic [4-1:0]                           ths_msb;
logic [4-1:0][36-1:0]                   ths = {
    TH_SV1,
    TH_SV0,
    TH_SHA,
    TH_PRE
};

localparam int PCIE_L_WIDTH = $clog2(1024) + 1;

logic [1-1:0]                           pcie_input_valid     [PCIE_N-1:0];
logic [1-1:0]                           pcie_input_full     [PCIE_N-1:0];
logic [PCIE_L_WIDTH-1:0]                pcie_input_fill [PCIE_N-1:0];
logic [512-1:0]                         pcie_input_data     [PCIE_N-1:0];

logic [PCIE_N-1:0][1-1:0]               ext_ready;
logic [PCIE_N-1:0][1-1:0]               ext_valid;
logic [PCIE_N-1:0][1-1:0]               ext_eop;
sv_meta2_t [PCIE_N-1:0]                 ext_meta0;
pcie_meta_t [PCIE_N-1:0]                ext_meta1;

logic [1-1:0]                           pad_input_ready;
logic [1-1:0]                           pad_input_wait;
logic [1-1:0]                           pad_input_valid;
logic [1-1:0]                           pad_input_eop;
sv_meta2_t                              pad_input_meta;

logic [1-1:0]                           pad_output_valid;
logic [1-1:0]                           pad_output_eop;
sv_meta3_t                              pad_output_meta;
logic [10-1:0]                          pad_output_fill;

logic [1-1:0]                           sha_fifo_valid;
logic [1-1:0]                           sha_fifo_eop;
sv_meta3_t                              sha_fifo_meta;
logic [10-1:0]                          sha_fifo_fill;

logic [1-1:0]                           sha_input_ready;
logic [1-1:0]                           sha_input_wait;
logic [1-1:0]                           sha_input_valid;
logic [1-1:0]                           sha_input_eop;
sv_meta3_t                              sha_input_meta;

logic [1-1:0]                           sha_output_valid;
sv_meta4_t                              sha_output_meta;
logic [10-1:0]                          sha_output_fill;

logic [1-1:0]                           sv0_fifo_valid;
sv_meta4_t                              sv0_fifo_meta;
logic [10-1:0]                          sv0_fifo_fill;

logic [1-1:0]                           sv0_input_ready;
logic [1-1:0]                           sv0_input_wait;
logic [1-1:0]                           sv0_input_valid;
sv_meta4_t                              sv0_input_meta;

logic [1-1:0]                           sv0_output_valid;
sv_meta5_t                              sv0_output_meta;
logic [10-1:0]                          sv0_output_fill;

logic [1-1:0]                           sv1_fifo_valid;
sv_meta5_t                              sv1_fifo_meta;
logic [10-1:0]                          sv1_fifo_fill;

logic [1-1:0]                           sv1_input_ready;
logic [1-1:0]                           sv1_input_wait;
logic [1-1:0]                           sv1_input_valid;
sv_meta5_t                              sv1_input_meta;

logic [1-1:0]                           sv1_output_valid;
sv_meta6_t                              sv1_output_meta;
logic [10-1:0]                          sv1_output_fill;

logic [1-1:0]                           sv2_fifo_valid;
sv_meta6_t                              sv2_fifo_meta;
logic [10-1:0]                          sv2_fifo_fill;

logic [1-1:0]                           sv2_input_ready;
logic [1-1:0]                           sv2_input_valid;
sv_meta6_t                              sv2_input_meta;

logic [1-1:0]                           sv2_output_valid;
sv_meta7_t                              sv2_output_meta;

logic [1-1:0]                           ecc_output_valid;
sv_meta7_t                              ecc_output_meta;

logic [PCIE_N-1:0][1-1:0]               result_valid;
logic [PCIE_N-1:0][64-1:0]              result_tid;
logic [PCIE_N-1:0][1-1:0]               result_data;
logic [PCIE_N-1:0][16-1:0]              result_count;
logic [PCIE_N-1:0][1-1:0]               result_full;
logic [PCIE_N-1:0][1-1:0]               result_push;

logic [PCIE_N-1:0][1-1:0]               dma_port_ready;
logic [PCIE_N-1:0][1-1:0]               dma_port_valid;
logic [PCIE_N-1:0][1-1:0]               dma_port_vv;
logic [PCIE_N-1:0][1-1:0]               dma_port_full;
logic [PCIE_N-1:0][16-1:0]              dma_port_count;
mcache_pcim_t [PCIE_N-1:0]              dma_port_desc;







//                AAA               VVVVVVVV           VVVVVVVVMMMMMMMM               MMMMMMMMMMMMMMMM               MMMMMMMM
//               A:::A              V::::::V           V::::::VM:::::::M             M:::::::MM:::::::M             M:::::::M
//              A:::::A             V::::::V           V::::::VM::::::::M           M::::::::MM::::::::M           M::::::::M
//             A:::::::A            V::::::V           V::::::VM:::::::::M         M:::::::::MM:::::::::M         M:::::::::M
//            A:::::::::A            V:::::V           V:::::V M::::::::::M       M::::::::::MM::::::::::M       M::::::::::M
//           A:::::A:::::A            V:::::V         V:::::V  M:::::::::::M     M:::::::::::MM:::::::::::M     M:::::::::::M
//          A:::::A A:::::A            V:::::V       V:::::V   M:::::::M::::M   M::::M:::::::MM:::::::M::::M   M::::M:::::::M
//         A:::::A   A:::::A            V:::::V     V:::::V    M::::::M M::::M M::::M M::::::MM::::::M M::::M M::::M M::::::M
//        A:::::A     A:::::A            V:::::V   V:::::V     M::::::M  M::::M::::M  M::::::MM::::::M  M::::M::::M  M::::::M
//       A:::::AAAAAAAAA:::::A            V:::::V V:::::V      M::::::M   M:::::::M   M::::::MM::::::M   M:::::::M   M::::::M
//      A:::::::::::::::::::::A            V:::::V:::::V       M::::::M    M:::::M    M::::::MM::::::M    M:::::M    M::::::M
//     A:::::AAAAAAAAAAAAA:::::A            V:::::::::V        M::::::M     MMMMM     M::::::MM::::::M     MMMMM     M::::::M
//    A:::::A             A:::::A            V:::::::V         M::::::M               M::::::MM::::::M               M::::::M
//   A:::::A               A:::::A            V:::::V          M::::::M               M::::::MM::::::M               M::::::M
//  A:::::A                 A:::::A            V:::V           M::::::M               M::::::MM::::::M               M::::::M
// AAAAAAA                   AAAAAAA            VVV            MMMMMMMM               MMMMMMMMMMMMMMMM               MMMMMMMM

logic [8-1:0] reg_index;
logic [1-1:0] counter_reset;
logic [1-1:0] counter_snapshot;
logic [32-1:0][32-1:0] counter_value = 0;
logic [32-1:0][32-1:0] counter_snapshot_values;

assign avmm_waitrequest = '0;

always_ff@(posedge clk) begin

    timestamp                           <= timestamp + 1;

    avmm_readdatavalid                  <= avmm_read;

    case (avmm_address[2+:8])
        8'h00: avmm_readdata            <= 32'h5000_0000;
        8'h01: avmm_readdata            <= 32'h0002_0006;

        8'h10: avmm_readdata            <= reg_index;
        8'h11: avmm_readdata            <= timestamp[0 +:32];
        8'h12: avmm_readdata            <= timestamp[32+:32];

        8'h20: avmm_readdata            <= counter_snapshot_values[reg_index];
        8'h21: avmm_readdata            <= {tr_pending[0+:10], result_count[0][0+:10], pcie_input_fill[0]};
        8'h22: avmm_readdata            <= {tr_pending[0+:10], result_count[1][0+:10], pcie_input_fill[1]};
    endcase

    if (avmm_write) begin
    case (avmm_address[2+:8])

        8'h10: reg_index                      <= avmm_writedata;
        8'h11: send_fails               <= avmm_writedata;
        8'h13: ths_msb                  <= avmm_writedata;
        8'h14: ths[reg_index]                 <= {ths_msb, avmm_writedata};

        8'h20: begin
            counter_snapshot                     <= avmm_writedata[1];
            counter_reset                     <= avmm_writedata[0];
        end

    endcase
    end else begin
        counter_reset                         <= 0;
        counter_snapshot                         <= 0;
    end
end

`define CNT(ci, expr)       piped_counter #(.D(2),.W(32)) cntr_``ci`` (.clk(clk), .rst(rst), .c(counter_snapshot_values[ci]), .p(expr), .r(counter_reset), .s(counter_snapshot));
`define CNM(ci, expr, c)    always_ff@(posedge clk) begin if (counter_snapshot) counter_snapshot_values[ci] <= counter_value[ci]; counter_value[ci] <= (counter_reset) ? '0 : counter_value[ci] + ((expr) ? c : 0); end
`define MON(ci, expr)       always_ff@(posedge clk) begin if (counter_snapshot) counter_snapshot_values[ci] <= counter_value[ci]; counter_value[ci] <= (expr); end

`CNT( 0, pad_input_valid & pad_input_ready & pad_input_eop)
`CNT( 1, pad_output_valid & pad_output_eop)
`CNT( 2, sha_output_valid)
`CNT( 3, sv0_output_valid)
`CNT( 4, sv2_fifo_valid) // sv1_output_valid is in clk_f domain
`CNT( 5, sv2_output_valid)
`CNT( 6, ecc_output_valid)

`MON( 7, tr_pending)

`CNT(10, pcie_input_valid[0])                    // input count
`MON(11, pcie_input_fill[0])                    // input fill
`CNT(12, pcie_input_valid[0] & pcie_input_full[0])       // input drops
`CNT(13, result_valid[0])                    // result count
`MON(14, result_count[0])                    // result fill
`CNT(15, result_valid[0] & result_full[0])       // result drops
`CNT(16, result_push[0])                    // result dma count

`CNT(20, pcie_input_valid[1])                    // input count
`MON(21, pcie_input_fill[1])                    // input fill
`CNT(22, pcie_input_valid[1] & pcie_input_full[1])       // input drops
`CNT(23, result_valid[1])                    // result count
`MON(24, result_count[1])                    // result fill
`CNT(25, result_valid[1] & result_full[1])       // result drops
`CNT(26, result_push[1])                    // result dma count

`undef CNT
`undef CNM
`undef MON

piped_pending #(
    .W(32),
    .D(2)
) tr_pending_pending (
    .u(pad_input_valid & pad_input_ready & pad_input_eop),
    .d(ecc_output_valid),
    .p(tr_pending),
    .clk(clk),
    .rst(rst)
);


(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                              ($bits({rst_r})),
    .DEPTH                                              (2)
) rst_pipe_inst (
    .in                                                 ({10{rst}}),
    .out                                                (rst_r),

    .clk                                                (clk),
    .reset                                              (rst)
);

(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                              ($bits({rst_f_r})),
    .DEPTH                                              (2)
) rst_f_pipe_inst (
    .in                                                 ({10{rst_f}}),
    .out                                                (rst_f_r),

    .clk                                                (clk_f),
    .reset                                              (rst_f)
);

// PPPPPPPPPPPPPPPPP           CCCCCCCCCCCCCIIIIIIIIIIEEEEEEEEEEEEEEEEEEEEEE
// P::::::::::::::::P       CCC::::::::::::CI::::::::IE::::::::::::::::::::E
// P::::::PPPPPP:::::P    CC:::::::::::::::CI::::::::IE::::::::::::::::::::E
// PP:::::P     P:::::P  C:::::CCCCCCCC::::CII::::::IIEE::::::EEEEEEEEE::::E
//   P::::P     P:::::P C:::::C       CCCCCC  I::::I    E:::::E       EEEEEE
//   P::::P     P:::::PC:::::C                I::::I    E:::::E             
//   P::::PPPPPP:::::P C:::::C                I::::I    E::::::EEEEEEEEEE   
//   P:::::::::::::PP  C:::::C                I::::I    E:::::::::::::::E   
//   P::::PPPPPPPPP    C:::::C                I::::I    E:::::::::::::::E   
//   P::::P            C:::::C                I::::I    E::::::EEEEEEEEEE   
//   P::::P            C:::::C                I::::I    E:::::E             
//   P::::P             C:::::C       CCCCCC  I::::I    E:::::E       EEEEEE
// PP::::::PP            C:::::CCCCCCCC::::CII::::::IIEE::::::EEEEEEEE:::::E
// P::::::::P             CC:::::::::::::::CI::::::::IE::::::::::::::::::::E
// P::::::::P               CCC::::::::::::CI::::::::IE::::::::::::::::::::E
// PPPPPPPPPP                  CCCCCCCCCCCCCIIIIIIIIIIEEEEEEEEEEEEEEEEEEEEEE

generate

    for (genvar g_i = 0; g_i < PCIE_N; g_i ++) begin: P_IN

        localparam logic [64-1:0] PCIE_OFF = {32'h0000_0001 + g_i, 32'h0000_0000};

        pcie_inorder #(
            .W                          (512),
            .D                          (512),
            .REG_O                      (1), // assumes no backpressure
            .ADDR_MASK                  (64'hFFFF_FFFF_0000_0000),
            .ADDR_VAL                   (PCIE_OFF)
        ) pcie_inorder_inst (
            .pcie_v                     (pcie_v),
            .pcie_a                     (pcie_a),
            .pcie_d                     (pcie_d),

            .out_v                      (pcie_input_valid[g_i]),
            .out_p                      ('1),
            .out_a                      (),
            .out_d                      (pcie_input_data[g_i]),
            .out_s                      (),

            .clk                        (clk),
            .rst                        (rst_r[0])
        );

        pcie_tr_ext #(
            .BUFF_SZ                    (EXT_BUFFER_SZ)
        ) tr_ext_inst (
            .pcie_v                     (pcie_input_valid        [g_i]),
            .pcie_d                     (pcie_input_data        [g_i]),
            .pcie_f                     (pcie_input_full        [g_i]), // full
            .pcie_l                     (pcie_input_fill        [g_i]), // fill

            .o_v                        (ext_valid          [g_i]),
            .o_r                        (ext_ready          [g_i]),
            .o_e                        (ext_eop          [g_i]),
            .o_m0                       (ext_meta0         [g_i]),
            .o_m1                       (ext_meta1         [g_i]),

            .clk                        (clk),
            .rst                        (rst_r[1])
        );

        (* dont_touch = "yes" *) piped_wire #(
            .WIDTH                                      ($bits({ext_valid[g_i], ext_meta0[g_i].m.m.tid})),
            .DEPTH                                      (20)
        ) sha_i_pipe_inst (
            .in                                         ({ext_valid[g_i], ext_meta0[g_i].m.m.tid}),
            .out                                        ({result_valid[g_i], result_tid[g_i]}),

            .clk                                        (clk),
            .reset                                      (rst)
        );

        always_ff@(posedge clk) begin
//            result_valid             [g_i]   <= ecc_output_valid & (ecc_output_meta.m.src[0+:4] == g_i);
//            result_tid             [g_i]   <= ecc_output_meta.m.tid;
//            result_data             [g_i]   <= ecc_output_meta.res;
//        end
            result_data             [g_i]   <= 0;
        end

    end
endgenerate

// DDDDDDDDDDDDD        MMMMMMMM               MMMMMMMM               AAA               
// D::::::::::::DDD     M:::::::M             M:::::::M              A:::A              
// D:::::::::::::::DD   M::::::::M           M::::::::M             A:::::A             
// DDD:::::DDDDD:::::D  M:::::::::M         M:::::::::M            A:::::::A            
//   D:::::D    D:::::D M::::::::::M       M::::::::::M           A:::::::::A           
//   D:::::D     D:::::DM:::::::::::M     M:::::::::::M          A:::::A:::::A          
//   D:::::D     D:::::DM:::::::M::::M   M::::M:::::::M         A:::::A A:::::A         
//   D:::::D     D:::::DM::::::M M::::M M::::M M::::::M        A:::::A   A:::::A        
//   D:::::D     D:::::DM::::::M  M::::M::::M  M::::::M       A:::::A     A:::::A       
//   D:::::D     D:::::DM::::::M   M:::::::M   M::::::M      A:::::AAAAAAAAA:::::A      
//   D:::::D     D:::::DM::::::M    M:::::M    M::::::M     A:::::::::::::::::::::A     
//   D:::::D    D:::::D M::::::M     MMMMM     M::::::M    A:::::AAAAAAAAAAAAA:::::A    
// DDD:::::DDDDD:::::D  M::::::M               M::::::M   A:::::A             A:::::A   
// D:::::::::::::::DD   M::::::M               M::::::M  A:::::A               A:::::A  
// D::::::::::::DDD     M::::::M               M::::::M A:::::A                 A:::::A 
// DDDDDDDDDDDDD        MMMMMMMM               MMMMMMMMAAAAAAA                   AAAAAAA

dma_result #(
    .PCIE_N                     (PCIE_N)
) dma_result_inst (

    .dma_push_ready             (dma_push_ready),
    .dma_push_valid             (dma_push_valid),
    .dma_push_addr              (dma_push_addr),
    .dma_push_wstrb             (dma_push_wstrb),
    .dma_fifo_full              (dma_fifo_full),
    .dma_push_data              (dma_push_data),

    .ext_v                      (ext_valid),
    .ext_r                      (ext_ready),
    .ext_e                      (ext_eop),
    .ext_m                      (ext_meta1),

    .res_v                      (result_valid),
    .res_t                      (result_tid),
    .res_d                      (result_data),
    .res_c                      (result_count),
    .res_f                      (result_full),
    .res_p                      (result_push),

    .send_fails                 (send_fails),

    .priv_base                  (priv_bytes[0+:8]),
    .priv_mask                  (priv_bytes[8+:8]),

    .clk                        (clk),
    .rst                        (rst_r[2])
);

// PPPPPPPPPPPPPPPPP                  AAA               DDDDDDDDDDDDD        
// P::::::::::::::::P                A:::A              D::::::::::::DDD     
// P::::::PPPPPP:::::P              A:::::A             D:::::::::::::::DD   
// PP:::::P     P:::::P            A:::::::A            DDD:::::DDDDD:::::D  
//   P::::P     P:::::P           A:::::::::A             D:::::D    D:::::D 
//   P::::P     P:::::P          A:::::A:::::A            D:::::D     D:::::D
//   P::::PPPPPP:::::P          A:::::A A:::::A           D:::::D     D:::::D
//   P:::::::::::::PP          A:::::A   A:::::A          D:::::D     D:::::D
//   P::::PPPPPPPPP           A:::::A     A:::::A         D:::::D     D:::::D
//   P::::P                  A:::::AAAAAAAAA:::::A        D:::::D     D:::::D
//   P::::P                 A:::::::::::::::::::::A       D:::::D     D:::::D
//   P::::P                A:::::AAAAAAAAAAAAA:::::A      D:::::D    D:::::D 
// PP::::::PP             A:::::A             A:::::A   DDD:::::DDDDD:::::D  
// P::::::::P            A:::::A               A:::::A  D:::::::::::::::DD   
// P::::::::P           A:::::A                 A:::::A D::::::::::::DDD     
// PPPPPPPPPP          AAAAAAA                   AAAAAAADDDDDDDDDDDDD        

/*
rrb_merge #(
    .W                                          ($bits(ext_meta0[0])),
    .N                                          (PCIE_N)
) ext_merge_inst (
    .i_r                                        (ext_ready),
    .i_v                                        (ext_valid),
    .i_e                                        (ext_eop),
    .i_m                                        (ext_meta0),

    .o_r                                        (pad_input_ready),
    .o_v                                        (pad_input_valid),
    .o_e                                        (pad_input_eop),
    .o_m                                        (pad_input_meta),

    .clk                                        (clk),
    .rst                                        (rst)
);

sha512_pre #(
) sha512_pre_inst (

    .i_r                                        (pad_input_ready),
    .i_w                                        (pad_input_wait),
    .i_v                                        (pad_input_valid),
    .i_e                                        (pad_input_eop),
    .i_m                                        (pad_input_meta),

    .o_v                                        (pad_output_valid),
    .o_e                                        (pad_output_eop),
    .o_m                                        (pad_output_meta),

    .clk                                        (clk),
    .rst                                        (rst_r[4])
);

(* keep_hierarchy = "yes" *) throttle pad_th_inst (
    .i                                          (pad_input_ready & pad_input_valid & pad_input_eop),
    .o                                          (pad_output_valid & pad_output_eop),
    .f                                          (pad_output_fill),
    .w                                          (pad_input_wait),
    .ths                                        ({ths[0]}),
    .clk                                        (clk),
    .rst                                        (rst)
);
*/

//    SSSSSSSSSSSSSSS HHHHHHHHH     HHHHHHHHH               AAA               
//  SS:::::::::::::::SH:::::::H     H:::::::H              A:::A              
// S:::::SSSSSS::::::SH:::::::H     H:::::::H             A:::::A             
// S:::::S     SSSSSSSHH::::::H     H::::::HH            A:::::::A            
// S:::::S              H:::::H     H:::::H             A:::::::::A           
// S:::::S              H:::::H     H:::::H            A:::::A:::::A          
//  S::::SSSS           H::::::HHHHH::::::H           A:::::A A:::::A         
//   SS::::::SSSSS      H:::::::::::::::::H          A:::::A   A:::::A        
//     SSS::::::::SS    H:::::::::::::::::H         A:::::A     A:::::A       
//        SSSSSS::::S   H::::::HHHHH::::::H        A:::::AAAAAAAAA:::::A      
//             S:::::S  H:::::H     H:::::H       A:::::::::::::::::::::A     
//             S:::::S  H:::::H     H:::::H      A:::::AAAAAAAAAAAAA:::::A    
// SSSSSSS     S:::::SHH::::::H     H::::::HH   A:::::A             A:::::A   
// S::::::SSSSSS:::::SH:::::::H     H:::::::H  A:::::A               A:::::A  
// S:::::::::::::::SS H:::::::H     H:::::::H A:::::A                 A:::::A 
//  SSSSSSSSSSSSSSS   HHHHHHHHH     HHHHHHHHHAAAAAAA                   AAAAAAA

/*
(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                      ($bits({sha_fifo_fill, pad_output_meta, pad_output_eop, pad_output_valid})),
    .DEPTH                                      (2)
) sha_i_pipe_inst (
    .in                                         ({sha_fifo_fill, pad_output_meta, pad_output_eop, pad_output_valid}),
    .out                                        ({pad_output_fill, sha_fifo_meta, sha_fifo_eop, sha_fifo_valid}),

    .clk                                        (clk),
    .reset                                      (rst)
);

(* keep_hierarchy = "yes" *) showahead_pkt_fifo #(
    .WIDTH                                      ($bits({sha_fifo_meta})),
    .DEPTH                                      (512)
) sha_f_inst (
    .aclr                                       (rst),

    .wr_clk                                     (clk),
    .wr_req                                     (sha_fifo_valid),
    .wr_full                                    (),
    .wr_full_b                                  (),
    .wr_data                                    (sha_fifo_meta),
    .wr_eop                                     (sha_fifo_eop),
    .wr_count                                   (),
    .wr_count_pkt                               (sha_fifo_fill),

    .rd_clk                                     (clk),
    .rd_req                                     (sha_input_valid & sha_input_ready),
    .rd_empty                                   (),
    .rd_not_empty                               (sha_input_valid),
    .rd_count                                   (),
    .rd_data                                    (sha_input_meta),
    .rd_eop                                     (sha_input_eop)
);

(* keep_hierarchy = "yes" *) sha512_modq_meta #(
    .KEY_D                                      (KEY_D)
) sha512_modq_meta_inst (
    .i_r                                        (sha_input_ready),
    .i_w                                        (sha_input_wait),
    .i_v                                        (sha_input_valid),
    .i_e                                        (sha_input_eop),
    .i_m                                        (sha_input_meta),

    .o_v                                        (sha_output_valid),
    .o_e                                        (),
    .o_m                                        (sha_output_meta),

    .clk                                        (clk),
    .rst                                        (rst_r[5])
);

(* keep_hierarchy = "yes" *) throttle #(
) sha_th_inst (
    .i                                          (sha_input_ready & sha_input_valid & sha_input_eop),
    .o                                          (sha_output_valid),
    .f                                          (sha_output_fill),
    .w                                          (sha_input_wait),
    .ths                                        ({ths[1]}),
    .clk                                        (clk),
    .rst                                        (rst)
);
*/

//    SSSSSSSSSSSSSSS VVVVVVVV           VVVVVVVV     000000000     
//  SS:::::::::::::::SV::::::V           V::::::V   00:::::::::00   
// S:::::SSSSSS::::::SV::::::V           V::::::V 00:::::::::::::00 
// S:::::S     SSSSSSSV::::::V           V::::::V0:::::::000:::::::0
// S:::::S             V:::::V           V:::::V 0::::::0   0::::::0
// S:::::S              V:::::V         V:::::V  0:::::0     0:::::0
//  S::::SSSS            V:::::V       V:::::V   0:::::0     0:::::0
//   SS::::::SSSSS        V:::::V     V:::::V    0:::::0 000 0:::::0
//     SSS::::::::SS       V:::::V   V:::::V     0:::::0 000 0:::::0
//        SSSSSS::::S       V:::::V V:::::V      0:::::0     0:::::0
//             S:::::S       V:::::V:::::V       0:::::0     0:::::0
//             S:::::S        V:::::::::V        0::::::0   0::::::0
// SSSSSSS     S:::::S         V:::::::V         0:::::::000:::::::0
// S::::::SSSSSS:::::S          V:::::V           00:::::::::::::00 
// S:::::::::::::::SS            V:::V              00:::::::::00   
//  SSSSSSSSSSSSSSS               VVV                 000000000     

/*
(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                      ($bits({sv0_fifo_fill, sha_output_meta, sha_output_valid})),
    .DEPTH                                      (2)
) sv_0_i_pipe_inst (
    .in                                         ({sv0_fifo_fill, sha_output_meta, sha_output_valid}),
    .out                                        ({sha_output_fill, sv0_fifo_meta, sv0_fifo_valid}),

    .clk                                        (clk),
    .reset                                      (rst)
);

(* keep_hierarchy = "yes" *) showahead_fifo #(
    .WIDTH                                      ($bits({sv0_fifo_meta})),
    .DEPTH                                      (512)
) sv0_f_inst (
    .aclr                                       (rst),

    .wr_clk                                     (clk),
    .wr_req                                     (sv0_fifo_valid),
    .wr_full                                    (),
    .wr_data                                    (sv0_fifo_meta),
    .wr_count                                   (sv0_fifo_fill),

    .rd_clk                                     (clk),
    .rd_req                                     (sv0_input_valid & sv0_input_ready),
    .rd_empty                                   (),
    .rd_not_empty                               (sv0_input_valid),
    .rd_count                                   (),
    .rd_data                                    (sv0_input_meta)
);

(* keep_hierarchy = "yes" *) ed25519_sigverify_0 #(
    .MUL_T                                      (MUL_T),
    .MUL_D                                      (MUL_D),
    .N_SCH                                      (N_SCH),
    .KEY_D                                      (KEY_D)
) ed25519_sigverify_0_inst (
    .i_r                                        (sv0_input_ready),
    .i_w                                        (sv0_input_wait),
    .i_v                                        (sv0_input_valid),
    .i_m                                        (sv0_input_meta),

    .o_v                                        (sv0_output_valid),
    .o_m                                        (sv0_output_meta),

    .clk                                        (clk),
    .rst                                        (rst_r[6])
);

(* keep_hierarchy = "yes" *) throttle #(
) sv0_th_inst (
    .i                                          (sv0_input_ready & sv0_input_valid),
    .o                                          (sv0_output_valid),
    .f                                          (sv0_output_fill),
    .w                                          (sv0_input_wait),
    .ths                                        ({ths[2]}),
    .clk                                        (clk),
    .rst                                        (rst)
);
*/

//    SSSSSSSSSSSSSSS VVVVVVVV           VVVVVVVV  1111111   
//  SS:::::::::::::::SV::::::V           V::::::V 1::::::1   
// S:::::SSSSSS::::::SV::::::V           V::::::V1:::::::1   
// S:::::S     SSSSSSSV::::::V           V::::::V111:::::1   
// S:::::S             V:::::V           V:::::V    1::::1   
// S:::::S              V:::::V         V:::::V     1::::1   
//  S::::SSSS            V:::::V       V:::::V      1::::1   
//   SS::::::SSSSS        V:::::V     V:::::V       1::::l   
//     SSS::::::::SS       V:::::V   V:::::V        1::::l   
//        SSSSSS::::S       V:::::V V:::::V         1::::l   
//             S:::::S       V:::::V:::::V          1::::l   
//             S:::::S        V:::::::::V           1::::l   
// SSSSSSS     S:::::S         V:::::::V         111::::::111
// S::::::SSSSSS:::::S          V:::::V          1::::::::::1
// S:::::::::::::::SS            V:::V           1::::::::::1
//  SSSSSSSSSSSSSSS               VVV            111111111111

/*
(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                      ($bits({sv1_fifo_fill, sv0_output_meta, sv0_output_valid})),
    .DEPTH                                      (2)
) sv1_i_pipe_inst (
    .in                                         ({sv1_fifo_fill, sv0_output_meta, sv0_output_valid}),
    .out                                        ({sv0_output_fill, sv1_fifo_meta, sv1_fifo_valid}),

    .clk                                        (clk),
    .reset                                      (rst)
);

(* keep_hierarchy = "yes" *) dual_clock_showahead_fifo #(
    .WIDTH                                      ($bits({sv1_fifo_meta})),
    .DEPTH                                      (512)
) sv1_f_inst (
    .aclr                                       (rst),

    .wr_clk                                     (clk),
    .wr_req                                     (sv1_fifo_valid),
    .wr_full                                    (),
    .wr_data                                    (sv1_fifo_meta),
    .wr_count                                   (sv1_fifo_fill),

    .rd_clk                                     (clk_f),
    .rd_req                                     (sv1_input_valid & sv1_input_ready),
    .rd_empty                                   (),
    .rd_not_empty                               (sv1_input_valid),
    .rd_count                                   (),
    .rd_data                                    (sv1_input_meta)
);

(* keep_hierarchy = "yes" *) ed25519_sigverify_1 #(
    .DSDP_WS                                    (DSDP_WS),
    .MUL_T                                      (MUL_T),
    .MUL_D                                      (MUL_D),
    .KEY_D                                      (KEY_D)
) ed25519_sigverify_1_inst (
    .i_r                                        (sv1_input_ready),
    .i_w                                        (sv1_input_wait),
    .i_v                                        (sv1_input_valid),
    .i_m                                        (sv1_input_meta),

    .o_v                                        (sv1_output_valid),
    .o_m                                        (sv1_output_meta),

    .clk                                        (clk_f),
    .rst                                        (rst_f_r[0])
);

(* keep_hierarchy = "yes" *) throttle #(
) sv1_th_inst (
    .i                                          (sv1_input_ready & sv1_input_valid),
    .o                                          (sv1_output_valid),
    .f                                          (sv1_output_fill),
    .w                                          (sv1_input_wait),
    .ths                                        ({ths[3]}),
    .clk                                        (clk_f),
    .rst                                        (rst_f_r[1])
);
*/

//    SSSSSSSSSSSSSSS VVVVVVVV           VVVVVVVV 222222222222222    
//  SS:::::::::::::::SV::::::V           V::::::V2:::::::::::::::22  
// S:::::SSSSSS::::::SV::::::V           V::::::V2::::::222222:::::2 
// S:::::S     SSSSSSSV::::::V           V::::::V2222222     2:::::2 
// S:::::S             V:::::V           V:::::V             2:::::2 
// S:::::S              V:::::V         V:::::V              2:::::2 
//  S::::SSSS            V:::::V       V:::::V            2222::::2  
//   SS::::::SSSSS        V:::::V     V:::::V        22222::::::22   
//     SSS::::::::SS       V:::::V   V:::::V       22::::::::222     
//        SSSSSS::::S       V:::::V V:::::V       2:::::22222        
//             S:::::S       V:::::V:::::V       2:::::2             
//             S:::::S        V:::::::::V        2:::::2             
// SSSSSSS     S:::::S         V:::::::V         2:::::2       222222
// S::::::SSSSSS:::::S          V:::::V          2::::::2222222:::::2
// S:::::::::::::::SS            V:::V           2::::::::::::::::::2
//  SSSSSSSSSSSSSSS               VVV            22222222222222222222

/*
(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                      ($bits({sv2_fifo_fill, sv1_output_meta, sv1_output_valid})),
    .DEPTH                                      (2)
) sv2_i_pipe_inst (
    .in                                         ({sv2_fifo_fill, sv1_output_meta, sv1_output_valid}),
    .out                                        ({sv1_output_fill, sv2_fifo_meta, sv2_fifo_valid}),

    .clk                                        (clk_f),
    .reset                                      (rst_f_r[2])
);

(* keep_hierarchy = "yes" *) dual_clock_showahead_fifo #(
    .WIDTH                                      ($bits({sv2_fifo_meta})),
    .DEPTH                                      (512)
) sv2_f_inst (
    .aclr                                       (rst_f_r[3]),

    .wr_clk                                     (clk_f),
    .wr_req                                     (sv2_fifo_valid),
    .wr_full                                    (),
    .wr_data                                    (sv2_fifo_meta),
    .wr_count                                   (sv2_fifo_fill),

    .rd_clk                                     (clk),
    .rd_req                                     (sv2_input_valid & sv2_input_ready),
    .rd_empty                                   (),
    .rd_not_empty                               (sv2_input_valid),
    .rd_count                                   (),
    .rd_data                                    (sv2_input_meta)
);

(* keep_hierarchy = "yes" *) ed25519_sigverify_2 #(
    .MUL_T                                      (MUL_T)
) ed25519_sigverify_2_inst (
    .i_r                                        (sv2_input_ready),
    .i_w                                        ('0),
    .i_v                                        (sv2_input_valid),
    .i_m                                        (sv2_input_meta),

    .o_v                                        (sv2_output_valid),
    .o_m                                        (sv2_output_meta),

    .clk                                        (clk),
    .rst                                        (rst_r[8])
);

(* dont_touch = "yes" *) piped_wire #(
    .WIDTH                                      ($bits({sv2_output_meta, sv2_output_valid})),
    .DEPTH                                      (4)
) ecc_o_pipe_inst (
    .in                                         ({sv2_output_meta, sv2_output_valid}),
    .out                                        ({ecc_output_meta, ecc_output_valid}),

    .clk                                        (clk),
    .reset                                      (rst)
);
*/
































































































always_ff@(posedge clk) dbg_wire[DBG_WIDTH-1:2] <= {

    ecc_output_meta.m.tid,
    ecc_output_valid,

    sv2_output_meta.m.tid,
    sv2_output_valid,

    sv2_input_meta.m.tid,
    sv2_input_valid,

    sv0_output_meta.m.m.m.tid,
    sv0_output_valid,

    sha_output_meta.m.m.tid,
    sha_output_valid,

    pad_output_meta.m.m.tid,
    pad_output_valid,

    |{
        ecc_output_valid,
        sv2_output_valid,
        sv2_input_valid,
        sv0_output_valid,
        sha_output_valid,
        pad_output_valid
    }
};

assign dbg_wire[0+:2] = {
    rst,
    clk
};

always_ff@(posedge clk)   if (pad_input_valid & pad_input_ready & pad_input_eop)    $display("%t: pad_i  :", $time);
always_ff@(posedge clk)   if (sha_input_valid & sha_input_ready & sha_input_eop)    $display("%t: sha_i  : %x", $time, sha_input_meta.m.m.tid);
always_ff@(posedge clk)   if (sv0_input_valid & sv0_input_ready)              $display("%t: sv0_i  :", $time);
always_ff@(posedge clk_f) if (sv1_input_valid & sv1_input_ready)              $display("%t: sv1_i  :", $time);
always_ff@(posedge clk)   if (sv2_input_valid & sv2_input_ready)              $display("%t: sv2_i  :", $time);

// always_ff@(posedge clk)   if (pad_input_wait)            $display("%t: pad_input_wait: %0d %0d %0d - %0d - %0d", $time, ths[0][0+:12], ths[0][12+:12], ths[0][24+:12], pad_output_fill, pad_th_inst.counter_value);
// always_ff@(posedge clk)   if (sha_input_wait)            $display("%t: sha_input_wait: %0d %0d %0d - %0d - %0d", $time, ths[1][0+:12], ths[1][12+:12], ths[1][24+:12], sha_output_fill, sha_th_inst.counter_value);
// always_ff@(posedge clk)   if (sv0_input_wait)            $display("%t: sv0_input_wait: %0d %0d %0d - %0d - %0d", $time, ths[2][0+:12], ths[2][12+:12], ths[2][24+:12], sv0_output_fill, sv0_th_inst.counter_value);
// always_ff@(posedge clk_f) if (sv1_input_wait)            $display("%t: sv1_input_wait: %0d %0d %0d - %0d - %0d", $time, ths[3][0+:12], ths[3][12+:12], ths[3][24+:12], sv1_output_fill, sv1_th_inst.counter_value);

always_ff@(posedge clk)   if (pad_output_valid & pad_output_eop)  $display("%t: o_pad_o: %x", $time, pad_output_meta.m.m.tid);
always_ff@(posedge clk)   if (sha_output_valid)            $display("%t: o_sha_o: %x", $time, sha_output_meta.m.m.tid);
always_ff@(posedge clk)   if (sv0_output_valid)            $display("%t: o_sv0_o: %x", $time, sv0_output_meta.m.m.m.tid);
always_ff@(posedge clk_f) if (sv1_output_valid)            $display("%t: o_sv1_o: %x", $time, sv1_output_meta.m.tid);
always_ff@(posedge clk)   if (sv2_output_valid)            $display("%t: o_sv2_o: %x", $time, sv2_output_meta.m.tid);
always_ff@(posedge clk)   if (ecc_output_valid)            $display("%t: o_ecc_o: %x", $time, ecc_output_meta.m.tid);
always_ff@(posedge clk)   if (result_valid[0])         $display("%t: o_re[0]: %x", $time, result_data[0]);

always_ff@(negedge clk) $display("%t: -----------",$time);


endmodule


`default_nettype wire
