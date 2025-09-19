// Copyright 2025 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
// SPDX-License-Identifier: SHL-0.51

// Author:  Umberto Laghi
// Contact: umberto.laghi2@unibo.it
// Github:  @ubolakes

/* TOP LEVEL */ 

`include "axi/typedef.svh"

module rv_encapsulator_axi #(
    parameter FIFO_DEPTH = 16,
    parameter int unsigned AxiAddrWidth = 32'd0,
    parameter int unsigned AxiDataWidth = 32'd0,
    parameter type         axi_req_t    = logic,
    parameter type         axi_resp_t   = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // inputs
    input logic                              valid_i,
    input logic [encap_pkg::P_LEN-1:0]       packet_length_i,
    input logic                              notime_i,
    //input logic                            srcid_i,
    input logic [encap_pkg::T_LEN-1:0]       timestamp_i,
    //input logic [encap_pkg::TYPE_LEN-1:0]  type_i,
    input logic [encap_pkg::PAYLOAD_LEN-1:0] trace_payload_i,
    
    // output
    output logic encapsulator_ready_o,

    // axi signals
    output axi_req_t axi_req_o,
    input  axi_resp_t axi_resp_i  ,
    input  logic [AxiAddrWidth-1:0] addr_start_i,
    input  logic [AxiAddrWidth-1:0] addr_end_i,

    // reg
    output logic [AxiAddrWidth-1:0] addr_last_w_o
);

    `AXI_LITE_TYPEDEF_ALL(axi_lite, logic [AxiAddrWidth-1:0], logic [AxiDataWidth-1:0], logic [AxiDataWidth/8-1:0])
    axi_lite_req_t  axi_lite_req;
    axi_lite_resp_t axi_lite_resp;

    // this struct is defined here because it requires the access to the AxiDataWidth parameter
    typedef struct packed {
        logic [AxiDataWidth-1:0]         slice;
        logic [$clog2(AxiDataWidth)-4:0] valid_bytes;
    } slicer_fifo_entry_s;

    // encapsulator
    logic                           encap_valid;
    encap_pkg::encap_fifo_entry_s   encap_fifo_entry_i;
    encap_pkg::encap_fifo_entry_s   encap_fifo_entry_o;
    logic                           encap_fifo_full;
    logic                           encap_fifo_empty;
    logic                           encap_fifo_pop;
    // slicer
    logic                            slicer_valid;
    logic [AxiDataWidth-1:0]         slice;
    logic [$clog2(AxiDataWidth)-4:0] valid_bytes;
    slicer_fifo_entry_s              slicer_fifo_entry_i;
    slicer_fifo_entry_s              slicer_fifo_entry_o;
    logic                            slicer_fifo_full;
    logic                            slicer_fifo_empty;
    logic                            slicer_fifo_pop;
    
    // slicer_fifo
    assign slicer_fifo_entry_i.valid_bytes = valid_bytes;
    assign slicer_fifo_entry_i.slice = slice;
    // output
    assign encapsulator_ready_o = !encap_fifo_full;

    encapsulator i_encapsulator (
        .valid_i            (valid_i),
        .packet_length_i    (packet_length_i),
        .flow_i             ('0),
        .timestamp_present_i(notime_i),
        //.srcid_i(),
        .timestamp_i        (timestamp_i),
        //.type_i(),
        .trace_payload_i    (trace_payload_i),
        .valid_o            (encap_valid),
        .encap_fifo_entry_o (encap_fifo_entry_i)
    );

    fifo_v3 # (
        .DEPTH(FIFO_DEPTH),
        .dtype(encap_pkg::encap_fifo_entry_s)
    ) i_fifo_encap (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   ('0),
        .testmode_i('0),
        .full_o    (encap_fifo_full),
        .empty_o   (encap_fifo_empty),
        .usage_o   (),
        .data_i    (encap_fifo_entry_i),
        .push_i    (encap_valid),
        .data_o    (encap_fifo_entry_o),
        .pop_i     (encap_fifo_pop)
    );

    slicer #(
        .SLICE_LEN(AxiDataWidth)
    ) i_slicer (
        .clk_i             (clk_i),
        .rst_ni            (rst_ni),
        .valid_i           (!encap_fifo_empty),
        .encap_fifo_entry_i(encap_fifo_entry_o),
        .fifo_full_i       (slicer_fifo_full), // downstream fifo
        .valid_o           (slicer_valid),
        .slice_o           (slice),
        .valid_bytes_o     (valid_bytes),
        .fifo_pop_o        (encap_fifo_pop)
    );

    fifo_v3 # (
        .DEPTH(FIFO_DEPTH),
        .dtype(slicer_fifo_entry_s)
    ) i_fifo_slicer (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   ('0),
        .testmode_i('0),
        .full_o    (slicer_fifo_full),
        .empty_o   (slicer_fifo_empty),
        .usage_o   (),
        .data_i    (slicer_fifo_entry_i),
        .push_i    (slicer_valid),
        .data_o    (slicer_fifo_entry_o),
        .pop_i     (slicer_fifo_pop)
    );

    // to axi_lite
    atb_slice_to_axi_lite #(
        .AxiDataWidth (AxiDataWidth),
        .AxiAddrWidth (AxiAddrWidth),
        .req_lite_t   (axi_lite_req_t),
        .resp_lite_t  (axi_lite_resp_t)
    ) i_atb_slice_to_axi_lite (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .fifo_empty_i (slicer_fifo_empty),
        .slice_i      (slicer_fifo_entry_o.slice),
        .valid_bytes_i(slicer_fifo_entry_o.valid_bytes),
        .fifo_pop_o   (slicer_fifo_pop),
        .req_lite_o   (axi_lite_req),
        .resp_lite_i  (axi_lite_resp),
        .addr_start_i (addr_start_i),
        .addr_end_i   (addr_end_i),
        .addr_last_w_o(addr_last_w_o)
    );

        // to axi
    axi_lite_to_axi #(
        .AxiDataWidth (AxiDataWidth),
        .req_lite_t   (axi_lite_req_t),
        .resp_lite_t  (axi_lite_resp_t),
        .axi_req_t    (axi_req_t),
        .axi_resp_t   (axi_resp_t)
    ) i_axi_lite_to_axi (
        .slv_req_lite_i (axi_lite_req),
        .slv_resp_lite_o(axi_lite_resp),
        .slv_aw_cache_i ('0), // connect to anything ??
        .slv_ar_cache_i ('0), // read not used
        .mst_req_o      (axi_req_o),
        .mst_resp_i     (axi_resp_i)
    );

    /*
    // debug print
    always @(negedge clk_i) begin
        if (encap_valid) begin
            $display("%b", {encap_fifo_entry_i.payload, encap_fifo_entry_i.timestamp, encap_fifo_entry_i.header});
        end
    end*/


endmodule