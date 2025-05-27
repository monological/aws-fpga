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

   initial begin
      // create a simple data pattern
      for (int i = 0; i < 64; i++) begin
         wr_data[i*8 +: 8] = i;
      end

      tb.power_up();

      // Issue a single 512b write on the PCIS interface
      tb.poke_pcis(.addr(TEST_ADDR), .data(wr_data), .strb({64{1'b1}}));

      // Wait for the loopback path to write into host memory
      #1us;

      // Read back the data from host memory using backdoor access
      for (int i = 0; i < 64; i++) begin
         rd_data[i*8 +: 8] = tb.hm_get_byte(TEST_ADDR + i);
      end

      compare_data(rd_data, wr_data, TEST_ADDR);

      tb.power_down();
      report_pass_fail_status();
      $finish;
   end
endmodule

