`include "bsg_defines.v"
`include "bsg_global_buffer_pkg.vh"

module mesh2_node_priv

import bsg_global_buffer_pkg::*;
    #( parameter data_width_p           = -1
    , parameter rw_addr_width_p         = -1
    , parameter bank_els_p              = -1
    , parameter num_tiles_x_p           = -1
    , parameter num_tiles_y_p           = -1
    , parameter max_outstanding_p      = -1
    , parameter lg_req_resp_ports_p     = -1

    , parameter fwd_rx_fifo_els_p       =  2

    // , localparam id_width_lp           = `BSG_SAFE_CLOG2(max_outstanding_p)
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

// routed packets coming from cardinal direction
, input  logic [S:W][link_sif_width_lp-1:0]     links_sif_i
, output logic [S:W][link_sif_width_lp-1:0]     links_sif_o

// req/resp port connections, passed through overall mesh module to create packets here
,  input   logic  [rw_addr_width_p-1:0]         req_addr_i //this becomes fwd_pkt
,  input   logic  [data_width_p-1:0]            req_data_i
,  input   logic                                req_w_i
,  input   logic                                req_v_i
,  output  logic                                req_ready_o

,  output  logic  [data_width_p-1:0]            req_data_o //this is rev_pkt on way to requester
,  output  logic                                req_v_o
,  input   logic                                req_yumi_i
,  output  logic                                req_fence_o //TODO: implement

,  output  logic  [rw_addr_width_p-1:0]         resp_addr_o //this is fwd_pkt on way to sram
,  output  logic  [data_width_p-1:0]            resp_data_o
,  output  logic                                resp_w_o
,  output  logic                                resp_v_o
,  input   logic                                resp_yumi_i

,  input   logic  [lg_req_resp_ports_lp-1:0]    resp_dest_id_i //this becomes rev_pkt ; dest_id unused rn because managed
,  input   logic  [data_width_p-1:0]            resp_data_i
,  input   logic                                resp_v_i
,  output  logic                                resp_ready_o
);

    `bsg_global_buffer_declare_structs;

    bsg_global_buffer_link_sif_s [S:W] links_sif_in, links_sif_out; //directional, excludes P
    bsg_global_buffer_link_sif_s proc_link_sif_in, proc_link_sif_out;

    bsg_global_buffer_fwd_packet_s fwd_src_pkt, fwd_sink_pkt;
    logic fwd_src_pkt_v, fwd_src_pkt_ready, fwd_sink_pkt_v, fwd_sink_pkt_ready;

    bsg_global_buffer_rev_packet_s rev_src_pkt, rev_sink_pkt;
    logic rev_src_pkt_v, rev_src_pkt_ready, rev_sink_pkt_v, rev_sink_pkt_ready;

    logic [id_width_lp-1:0] alloc_id_lo;
    logic alloc_v_lo, alloc_yumi_li;
    logic wen_lo, fifo_v_li, fifo_v_lo, fifo_yumi_li;

    //router in and out
    bsg_global_buffer_fwd_link_sif_s [S:P] link_fwd_sif_li, link_fwd_sif_lo;
    bsg_global_buffer_rev_link_sif_s [S:P] link_rev_sif_li, link_rev_sif_lo;

    //"casting" to make use of structs
    assign links_sif_in = links_sif_i;
    assign links_sif_o = links_sif_out;

////////////////////////////////////////////////////////////////////////////////
// DEFINITIONS
//

    //// FWD_SRC (REQ) PKT
    assign fwd_src_pkt.dest_y = req_addr_i[ 0                                  +: y_cord_width_lp    ] + 1'b1;
    assign fwd_src_pkt.addr   = req_addr_i[ y_cord_width_lp                    +: bank_addr_width_lp ];
    assign fwd_src_pkt.dest_x = req_addr_i[ y_cord_width_lp+bank_addr_width_lp +: x_cord_width_lp    ];

    assign fwd_src_pkt.data     = req_data_i;
    assign fwd_src_pkt.wen      = req_w_i;
    assign fwd_src_pkt.id       = '0; //TODO: helper module?
    assign fwd_src_pkt.src_y    = my_y_i;
    assign fwd_src_pkt.src_x    = my_x_i;

    //// REV_SRC (RESP) PKT
    assign rev_src_pkt.data     = resp_data_i;
    assign rev_src_pkt_v = proc_link_sif_out.rev.ready_and_rev;
    //rest of rev_src_pkt signals come from manager DFF below


    //// PORT LINKS
    // fwd-src
    assign proc_link_sif_in.fwd.data = fwd_src_pkt;
    assign proc_link_sif_in.fwd.v = req_v_i;
    //proc_link_sif_in.fwd.ready_and_rev set by fifo

    // fwd-sink
    assign resp_data_o = fwd_sink_pkt.data;
    assign resp_v_o = fwd_sink_pkt_v & rev_src_pkt_ready;
    assign resp_w_o = fwd_sink_pkt.wen;

    // rev-src
    assign proc_link_sif_in.rev.data = rev_src_pkt;
    assign proc_link_sif_in.rev.v = rev_src_pkt_v;
    assign proc_link_sif_in.rev.ready_and_rev = 1'b1; //for SRAM, change later?
    assign resp_ready_o = 1'b1;

    // rev-sink
    assign rev_sink_pkt = proc_link_sif_out.rev.data;
    assign rev_sink_pkt_v = proc_link_sif_out.rev.v;
    assign rev_sink_pkt_ready = req_yumi_i;
    assign req_v_o = fifo_v_lo & ~wen_lo;
    



    //bottom wire of link_sifs are the req/resp connections
    assign link_fwd_sif_li[0] = proc_link_sif_in.fwd;
    assign link_rev_sif_li[0] = proc_link_sif_in.rev;
    assign proc_link_sif_out.fwd = link_fwd_sif_lo[0];
    assign proc_link_sif_out.rev = link_rev_sif_lo[0];

    //cardinal wires for routers
    for (genvar dir = W; dir <= S; dir++) begin
        assign link_fwd_sif_li[dir]     = links_sif_in[dir].fwd;
        assign link_rev_sif_li[dir]     = links_sif_in[dir].rev;
        assign links_sif_out[dir].fwd   = link_fwd_sif_lo[dir];
        assign links_sif_out[dir].rev   = link_rev_sif_lo[dir];
    end

////////////////////////////////////////////////////////////////////////////////
// COMPONENTS
//

    //router for fwd
    bsg_mesh_router_buffered #(.width_p(fwd_packet_width_lp)
                              ,.x_cord_width_p(x_cord_width_lp)
                              ,.y_cord_width_p(y_cord_width_lp)
                              ,.XY_order_p(0)
                              ,.debug_p(0))
        fwd_rtr
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.my_x_i(my_x_i)
            ,.my_y_i(my_y_i)

            ,.link_i(link_fwd_sif_li)
            ,.link_o(link_fwd_sif_lo)
            );

    //router for rev
    bsg_mesh_router_buffered #(.width_p(fwd_packet_width_lp)
                              ,.x_cord_width_p(x_cord_width_lp)
                              ,.y_cord_width_p(y_cord_width_lp)
                              ,.XY_order_p(1)
                              ,.debug_p(0))
        fwd_rtr
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.my_x_i(my_x_i)
            ,.my_y_i(my_y_i)

            ,.link_i(link_rev_sif_li)
            ,.link_o(link_rev_sif_lo)
            );

    //fwd-rx
    bsgs_fifo_1r1w_small #(.width_p(fwd_packet_width_lp)
                          ,.els_p(fwd_rx_fifo_els_p))
        fwd_rx_fifo
            (.clk_i(clk_i)
            ,.reset_i(reset_i)

            ,.data_i(proc_link_sif_out.fwd.data)
            ,.v_i(proc_link_sif_out.fwd.v)
            ,.ready_o(proc_link_sif_in.fwd.ready_and_rev)

            ,.data_o(fwd_sink_pkt)
            ,.v_o(fwd_sink_pkt_v)
            ,.yumi_i(proc_link_sif_in.rev.v) //not sure if this is right
            );

    
    // REMOVE LATER, TO MAKE THIS MODULE UNMANAGED
    bsg_dff_en #(.width_p(x_cord_width_lp + y_cord_width_lp + 1 + id_width_lp))
        src_xy_cord_reg
            (.clk_i(clk_i)
            ,.en_i(resp_yumi_i)
            ,.data_i({fwd_sink_pkt.src_x,  fwd_sink_pkt.src_y,  fwd_sink_pkt.wen, fwd_sink_pkt.id})
            ,.data_o({rev_src_pkt.dest_x, rev_src_pkt.dest_y, rev_src_pkt.wen, rev_src_pkt.id})
            );
    
    // REMOVE LATER, TO MAKE THIS MODULE UNMANAGED
    bsg_fifo_reorder #(.width_p(data_width_p + 1)
                    ,.els_p(max_outstanding_p))
    returned_fifo
        (.clk_i(clk_i)
        ,.reset_i(reset_i)

        ,.fifo_alloc_id_o(alloc_id_lo)
        ,.fifo_alloc_v_o(alloc_v_lo)
        ,.fifo_alloc_yumi_i(alloc_yumi_li)

        ,.write_data_i({rev_sink_pkt.data, rev_sink_pkt.wen})
        ,.write_id_i(rev_sink_pkt.id)
        ,.write_v_i(fifo_v_li)

        ,.fifo_deq_data_o({req_data_o, wen_lo})
        ,.fifo_deq_id_o()
        ,.fifo_deq_v_o(fifo_v_lo)
        ,.fifo_deq_yumi_i(fifo_yumi_li)

        ,.empty_o(req_fence_o)
        );


endmodule //mesh2_node_priv