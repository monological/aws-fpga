// ============================================================================
// Amazon FPGA Hardware Development Kit
//
// Simple PCIS to PCIM loopback test for cl_wiredancer
// ============================================================================

`include "common_base_test.svh"

module pcis_loopback_test();
   import tb_type_defines_pkg::*;

   localparam logic [63:0] TEST_ADDR = 64'h0000_0000_1234_0000;
   logic [511:0] wr_data;
   logic [511:0] rd_data;

   // -------------------------------------------------------------------
   // Utility: generate 256b pattern duplicated to upper half
   // -------------------------------------------------------------------
   task automatic gen_wr_data(input int seed, output logic [511:0] data);
      for (int i = 0; i < 32; i++) begin
         byte val = (seed + i) & 8'hff;
         data[i*8 +: 8]       = val;
         data[(i+32)*8 +: 8]  = val;
      end
   endtask

   // -------------------------------------------------------------------
   // Write and verify a single beat
   // -------------------------------------------------------------------
   task automatic single_write_check(input logic [63:0] addr,
                                     input int seed,
                                     input logic [63:0] strb = 64'hFFFF_FFFF_FFFF_FFFF);
      gen_wr_data(seed, wr_data);
      tb.poke_pcis(.addr(addr), .data(wr_data), .strb(strb));
      #1us;
      for (int i = 0; i < 64; i++) begin
         rd_data[i*8 +: 8] = tb.hm_get_byte(addr + i);
      end
      compare_data(rd_data, wr_data, addr);
   endtask

   // -------------------------------------------------------------------
   // Burst write using write-combine helper
   // -------------------------------------------------------------------
   task automatic burst_write_check(input logic [63:0] addr,
                                    input int beats);
      logic [31:0] q[$];
      logic [511:0] exp;
      q.delete();
      for (int b = 0; b < beats; b++) begin
         gen_wr_data(b, exp);
         for (int i = 0; i < 16; i++) begin
            q.push_back(exp[i*32 +: 32]);
         end
      end

      tb.poke_pcis_wc(.addr(addr), .data(q));
      #1us;

      for (int b = 0; b < beats; b++) begin
         gen_wr_data(b, exp);
         for (int i = 0; i < 64; i++) begin
            rd_data[i*8 +: 8] = tb.hm_get_byte(addr + (b*64) + i);
         end
         compare_data(rd_data, exp, addr + (b*64));
      end
   endtask

   initial begin
      tb.power_up();

      // ----------------------------------------------------------------
      // Basic aligned single beat
      // ----------------------------------------------------------------
      single_write_check(TEST_ADDR, 0);

      // ----------------------------------------------------------------
      // Multi-beat burst (4 beats)
      // ----------------------------------------------------------------
      burst_write_check(TEST_ADDR + 64, 4);

      // ----------------------------------------------------------------
      // Misaligned address write
      // ----------------------------------------------------------------
      single_write_check(TEST_ADDR + 8, 10);

      // ----------------------------------------------------------------
      // Consecutive writes back-to-back without wait
      // ----------------------------------------------------------------
      for (int c = 0; c < 3; c++) begin
         gen_wr_data(20 + c, wr_data);
         tb.poke_pcis(.addr(TEST_ADDR + 512 + c*64), .data(wr_data), .strb({64{1'b1}}));
      end
      #2us;
      for (int c = 0; c < 3; c++) begin
         gen_wr_data(20 + c, wr_data);
         for (int i = 0; i < 64; i++) begin
            rd_data[i*8 +: 8] = tb.hm_get_byte(TEST_ADDR + 512 + c*64 + i);
         end
         compare_data(rd_data, wr_data, TEST_ADDR + 512 + c*64);
      end

      // ----------------------------------------------------------------
      // Burst crossing a 4KB boundary
      // ----------------------------------------------------------------
      burst_write_check(TEST_ADDR + 64'h0000_0000_0000_0FC0, 2);

      tb.power_down();
      report_pass_fail_status();
      $finish;
   end
endmodule

