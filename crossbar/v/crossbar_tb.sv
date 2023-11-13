module gcd_tb;
  localparam addr_width_lp = 2;
  localparam data_width_lp = 32;

  /* Dump Test Waveform To VPD File */
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars();
  end

  /* Non-synth clock generator */
  logic clk;
  bsg_nonsynth_clock_gen #(5000) clk_gen_1 (clk);

  /* Non-synth reset generator */
  logic reset;
  bsg_nonsynth_reset_gen #(.num_clocks_p(1),.reset_cycles_lo_p(5),. reset_cycles_hi_p(5))
    reset_gen
      (.clk_i        ( clk )
      ,.async_reset_o( reset )
      );

  logic dut_v_lo, dut_v_r;
  logic [data_width_lp-1:0] dut_data_lo;
  logic [63:0] dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [63:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [67:0] rom_data_lo;

  logic tr_yumi_li, dut_yumi_li;

  bsg_fsb_node_trace_replay #(.ring_width_p(64)
                             ,.rom_addr_width_p(32) )
    trace_replay
      ( .clk_i ( ~clk ) // Trace Replay should run no negative clock edge!
      , .reset_i( reset )
      , .en_i( 1'b1 )

      , .v_i    ( dut_v_r )
      , .data_i ( dut_data_r )
      , .ready_o( tr_ready_lo )

      , .v_o   ( tr_v_lo )
      , .data_o( tr_data_lo )
      , .yumi_i( tr_yumi_li )

      , .rom_addr_o( rom_addr_li )
      , .rom_data_i( rom_data_lo )

      , .done_o()
      , .error_o()
      );

  always_ff @(negedge clk) begin
    dut_ready_r <= dut_ready_lo;
    tr_yumi_li  <= dut_ready_r & tr_v_lo;
    dut_v_r     <= dut_v_lo;
   dut_data_r  <= dut_data_lo;
  end

  trace_rom #(.width_p(68),.addr_width_p(32))
    ROM
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo )
      );

  // gcd DUT
  //   (.clk_i     ( clk )
  //   ,.reset_i   ( reset )

  //   ,.A_i       ( tr_data_lo[63:32] )
  //   ,.B_i       ( tr_data_lo[31:0] )
  //   ,.data_v_i  ( tr_v_lo )
  //   ,.ready_o   ( dut_ready_lo )

  //   ,.result_o  ( dut_data_lo )
  //   ,.data_v_o  ( dut_v_lo )
  //   ,.yumi_i    ( dut_yumi_li )
  //   );

  //trace replay acts as requester
  logic [addr_width_lp-1:0] mem_addr_li;
  logic [data_width_lp-1:0] mem_data_li, mem_data_lo;
  logic mem_w_li, mem_v_li, mem_ready_li, mem_yumi_lo, mem_v_lo, mem_dest_id_lo;

  bsg_noc_crossbar_network_unmanaged_hop #
      (.req_ports_p(1)
      ,.resp_ports_p(2)
      ,.addr_width_p(addr_width_lp)
      ,.data_width_p(data_width_lp))
    DUT
      (.clk_i       (clk)
      ,.reset_i     (reset)

      ,.req_addr_i      ( tr_data_lo[63:33] )
      ,.req_data_i      ( tr_data_lo[32:1] )
      ,.req_w_i         ( tr_data_lo[0] )
      ,.req_v_i         ( tr_v_lo )
      ,.req_ready_o     ( dut_ready_lo )

      ,.req_data_o      ( dut_data_lo )
      ,.req_v_o         ( dut_v_lo )
      ,.req_yumi_i      ( dut_yumi_li )
      ,.req_fence_o     ( dut_fence_o )

      ,.resp_addr_o     ( mem_addr_li )
      ,.resp_data_o     ( mem_data_li )
      ,.resp_w_o        ( mem_w_li )
      ,.resp_v_o        ( mem_v_li )
      ,.resp_yumi_i     ( mem_yumi_lo )
      
      ,.resp_dest_id_i  ( mem_dest_id_lo )
      ,.resp_data_i     ( mem_data_lo)
      ,.resp_v_i        ( mem_v_lo )
      ,.resp_ready_o    ( mem_ready_li )
      );

  bsg_mem_1rw_sync #(.width_p(data_width_lp), .els_p(2**addr_width_lp))
    memory
        (.clk_i   (clk)
        ,.reset_i (reset)

        ,.addr_i  (mem_addr_li)
        ,.data_i  (mem_data_li)
        ,.w_i     (mem_w_li)
        ,.v_i     (mem_v_li)

        ,.data_o  (mem_data_lo)
        );
  
  assign mem_ready_li = 1'b1; //unused
  assign mem_yumi_lo = 1'b1;
  assign mem_v_lo = 1'b1;
  assign mem_dest_id_lo = 1'b0; //for one requester

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end

endmodule
