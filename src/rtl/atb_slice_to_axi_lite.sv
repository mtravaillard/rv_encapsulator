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

// Author:  Maxime Travaillard <mtravaillard@student.ethz.ch>

module atb_slice_to_axi_lite #(
    parameter AxiDataWidth = 32,
    // LITE AXI structs
    parameter type  req_lite_t = logic,
    parameter type resp_lite_t = logic
) (
    input logic clk_i,
    input logic rst_ni,

    // fifo atb slice
    input  logic [AxiDataWidth-1:0]         slice_i, //slicer_fifo.slice
    input  logic [$clog2(AxiDataWidth)-4:0] valid_bytes_i, //slicer_fifo.valid_bytes
    input  logic                        fifo_full_i,
    input  logic                        fifo_empty_i,
    output logic                        fifo_pop_o

    // Slave AXI LITE port
    output req_lite_t  req_lite_o,
    input  resp_lite_t resp_lite_i
);
    
endmodule