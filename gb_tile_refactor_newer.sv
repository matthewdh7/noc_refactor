// BSD 3-Clause License
//
// Copyright (c) 2023, Bespoke Silicon Group
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

`include "bsg_defines.v"
`include "bsg_global_buffer_pkg.vh"

module bsg_global_buffer_tile
    import bsg_global_buffer_pkg::*;
        #( parameter data_width_p           = -1
         , parameter rw_addr_width_p        = -1
         , parameter ro_wo_addr_width_p     = -1
         , parameter bank_els_p             = -1
         , parameter num_tiles_x_p          = -1
         , parameter num_tiles_y_p          = -1
         , parameter num_rw_ch_p            = -1
         , parameter max_outstanding_p      = -1

         , parameter fwd_rx_fifo_els_p      =  2

         , localparam id_width_lp           = `BSG_SAFE_CLOG2(max_outstanding_p)
         , localparam x_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_x_p)
         , localparam y_cord_width_lp       = `BSG_SAFE_CLOG2(num_tiles_y_p + 1)
         , localparam bank_addr_width_lp    = `BSG_SAFE_CLOG2(bank_els_p)

         , localparam link_sif_width_lp     = `bsg_global_buffer_link_sif_width
         , localparam fwd_packet_width_lp   = `bsg_global_buffer_fwd_packet_width
         , localparam rev_packet_width_lp   = `bsg_global_buffer_rev_packet_width

         , localparam S                     = 32'(bsg_noc_pkg::S)
         , localparam N                     = 32'(bsg_noc_pkg::N)
         , localparam E                     = 32'(bsg_noc_pkg::E)
         , localparam W                     = 32'(bsg_noc_pkg::W)
         , localparam P                     = 32'(bsg_noc_pkg::P)
         )

( input  logic                                  clk_i
, input  logic                                  reset_i

, input  logic [x_cord_width_lp-1:0]            my_x_i
, input  logic [y_cord_width_lp-1:0]            my_y_i

// , input  logic [S:W][link_sif_width_lp-1:0]     links_sif_i
// , output logic [S:W][link_sif_width_lp-1:0]     links_sif_o

// , input  logic [bank_addr_width_lp-1:0]         ro_addr_i
// , input  logic [x_cord_width_lp-1:0]            ro_dest_x_i
// , input  logic                                  ro_addr_v_i

// , output logic [bank_addr_width_lp-1:0]         ro_addr_o
// , output logic [x_cord_width_lp-1:0]            ro_dest_x_o
// , output logic                                  ro_addr_v_o

// , input  logic [data_width_p-1:0]               ro_data_i
// , input  logic                                  ro_data_v_i
// , output logic [data_width_p-1:0]               ro_data_o
// , output logic                                  ro_data_v_o

// , input  logic [bank_addr_width_lp-1:0]         wo_addr_i
// , input  logic [x_cord_width_lp-1:0]            wo_dest_x_i
// , input  logic [data_width_p-1:0]               wo_data_i
// , input  logic                                  wo_v_i
// , output logic                                  wo_ready_o

// , output logic [bank_addr_width_lp-1:0]         wo_addr_o
// , output logic [x_cord_width_lp-1:0]            wo_dest_x_o
// , output logic [data_width_p-1:0]               wo_data_o
// , output logic                                  wo_v_o
// , input  logic                                  wo_ready_i

, input  logic [bank_addr_width_lp-1:0]         ro_mem_addr_i
, output logic [data_width_p-1:0]               ro_mem_data_o
, input  logic                                  ro_mem_v_i

, input  logic [bank_addr_width_lp-1:0]         wo_mem_addr_i
, input  logic [data_width_p-1:0]               wo_mem_data_i
, input  logic                                  wo_mem_v_i

, input  logic [bank_addr_width_lp-1:0]         rw_mem_addr_i
, input  logic [data_width_p-1:0]               rw_mem_data_i
, input  logic                                  rw_mem_w_i
, input  logic                                  rw_mem_v_i
, output logic [data_width_p-1:0]               rw_mem_data_o
, output logic                                  rw_mem_yumi_o //not used for SRAM I think
);

    logic rw_mem_yumi; //comes from arb

    logic wo_mem_yumi;

    logic ro_grant_lo;
    logic [data_width_p-1:0] mem_data_lo;

    logic z0, z1, z4;
    logic [data_width_p-1:0] z2;


    bsg_arb_fixed #(.inputs_p(3), .lo_to_hi_p(0))
        fixed_arb
            (.ready_i(1'b1)
            ,.reqs_i({ro_mem_v_i, wo_mem_v_i, rw_mem_v_i})
            ,.grants_o({ro_grant_lo, wo_mem_yumi, rw_mem_yumi})
            );

    wire [bank_addr_width_lp-1:0] mem_addr_li = rw_mem_yumi ? rw_mem_addr_i
                                              : wo_mem_yumi ? wo_mem_addr_i
                                              :               ro_mem_addr_i;

    wire [data_width_p-1:0] mem_data_li = rw_mem_yumi ? rw_mem_data_i
                                        :               wo_mem_data_i;

    wire mem_w_li = rw_mem_yumi ? rw_mem_w_i
                  : wo_mem_yumi ? 1'b1
                  :               1'b0;

    wire mem_v_li = rw_mem_yumi | wo_mem_yumi | ro_grant_lo;

    bsg_mem_1rw_sync #(.width_p(data_width_p), .els_p(bank_els_p))
        memory
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.addr_i(mem_addr_li)
            ,.data_i(mem_data_li)
            ,.w_i(mem_w_li)
            ,.v_i(mem_v_li)

            ,.data_o(mem_data_lo)
            );
    
    assign ro_mem_data_o = mem_data_lo;
    assign rw_mem_data_o = mem_data_lo;
    assign rw_mem_yumi_o = rw_mem_yumi;

endmodule // gb_tile_refactor