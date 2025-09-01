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

// ATB (slice) to AXI-Lite (32 and 64-bits support)
// This module transform the data comming from the slicer into AXI-Lite.
// It does not handle reading transaction, as it is not useful in this case.
// We consider that there is a FIFO before this module.

module atb_slice_to_axi_lite #(
    parameter AxiDataWidth = 32,
    parameter AxiAddrWidth = 32,
    // LITE AXI structs
    parameter type  req_lite_t = logic,
    parameter type resp_lite_t = logic,
    // Register
    parameter addr_start = 32'b0;
    parameter addr_end = 32'b10000000;
) (
    input logic clk_i,
    input logic rst_ni,

    // fifo atb slice
    input  logic [AxiDataWidth-1:0]         slice_i, //slicer_fifo.slice
    input  logic [$clog2(AxiDataWidth)-4:0] valid_bytes_i, //slicer_fifo.valid_bytes
    input  logic                        fifo_empty_i,
    output logic                        fifo_pop_o

    // Master AXI LITE port
    output req_lite_t  req_lite_o,
    input  resp_lite_t resp_lite_i
);

// defines internal req signals
logic [AxiAddrWidth-1:0] aw_addr; // address always on 32 bits
logic                    aw_valid;
logic                     w_valid;
logic [AxiDataWidth-1:0]  w_data;
logic [DataWidth/8-1:0]   w_strb;
logic                     b_ready;

// defines internal resp signals
logic      aw_ready;
logic       w_ready;
logic       b_valid;
logic [1:0] b_resp;

// Assign inputs with internal resp signals
assign aw_ready = resp_lite_i.aw_ready;
assign  w_ready = resp_lite_i.w_ready;
assign  b_valid = resp_lite_i.b_valid;
assign  b_resp  = resp_lite_i.b.resp;

// ##################################################
// Valid bytes (ATB) to write bytes strobe (AXI-LITE)
// ##################################################
// Valid bytes : the number of bytes on data - 1 starting from lower bytes in ATB_DATA
// wstrb : index of bytes that should be written in AXI-Lite
// vbytes_to_wstrb : valid bytes from ATB to wstrb for AXI-Lite
// In ATB, the lower bytes is the header, so always valid, vbytes_to_wstrb[0] is always 1
logic [DataWidth/8-1:0]   vbytes_to_wstrb;

if (AxiDataWidth == 64) begin
    always @(*) begin
        case (valid_bytes_i)
            3'd0: vbytes_to_wstrb = 8'b00000001;
            3'd1: vbytes_to_wstrb = 8'b00000011;
            3'd2: vbytes_to_wstrb = 8'b00000111;
            3'd3: vbytes_to_wstrb = 8'b00001111;
            3'd4: vbytes_to_wstrb = 8'b00011111;
            3'd5: vbytes_to_wstrb = 8'b00111111;
            3'd6: vbytes_to_wstrb = 8'b01111111;
            3'd7: vbytes_to_wstrb = 8'b11111111;
            default: vbytes_to_wstrb = 8'b00000001; 
        endcase
    end
end else begin
    always @(*) begin
        case (valid_bytes_i)
            2'd0: vbytes_to_wstrb = 4'b0001;
            2'd1: vbytes_to_wstrb = 4'b0011;
            2'd2: vbytes_to_wstrb = 4'b0111;
            2'd3: vbytes_to_wstrb = 4'b1111;
            default: vbytes_to_wstrb = 4'b0001; 
        endcase
    end
end

// #########################################
// Finnite State Machine for ATB to AXI-Lite
// #########################################
// Define the states
typedef enum {StIdle, StWrite, StWait, StPopNIncr} atb_to_axilite_state_e;

atb_to_axilite_state_e state_d, state_q;

// Combinational decode of the state
always_comb begin
    state_d = state_q;
    aw_addr_d = aw_addr_q;
    unique case (state_q)
        // StIdle: waiting for data in fifo
        StIdle:
        if (!fifo_empty_i) begin
            state_d = StWrite;
        end
        // StWrite: write data and wait for ready signals
        StWrite: 
        if(aw_ready && w_ready) begin
            state_d = StWait;
        end
        // StWait : waiting for resp so still resp ready
        StWait:
        if(b_valid) begin
            state_d = StPop;
        end
        // StPopNIncr : Popping the fifo and Incrementing the addr counter
        StPopNIncr: begin
        if(aw_addr_q == addr_end) begin
            aw_addr_d = addr_start;
        end else begin 
            aw_addr_d += AxiDataWidth/8;
        end
        state_d = (fifo_empty_i) ? StIdle : StWrite;
        end
        // may be empty or used to catch parasitic states
        default: begin
            aw_addr_d = addr_start; //don't know how to handle this case or if we have too...
            state_d = StIdle;
        end
    endcase
end

// Combinational for FSM outputs
always_comb begin
    unique case (state_q)
        // StIdle: nothing to be done
        StIdle: begin
            aw_addr = 32'b0;
            aw_valid = 1'b0;
            w_valid = 1'b0;
            w_data = 'b0;
            w_strb = 'b0;
            b_ready = 1'b0;
            fifo_pop_o = 1'b0;
        end
        // StWrite: write data and wait for ready signals
        StWrite: begin
            aw_addr = aw_addr_d;
            aw_valid = 1'b1;
            w_valid = 1'b1;
            w_data = slice_i;
            w_strb = vbytes_to_wstrb;
            b_ready = 1'b1;
            fifo_pop_o = 1'b0;
        end
        // StWait : waiting for resp so still resp ready
        StWait: begin
            aw_addr = 32'b0;
            aw_valid = 1'b0;
            w_valid = 1'b0;
            w_data = 'b0;
            w_strb = 'b0;
            b_ready = 1'b1;
            fifo_pop_o = 1'b0;
        end
        // StPopNIncr : Popping the fifo and Incrementing the addr counter
        StPopNIncr: begin
            aw_addr = 32'b0;
            aw_valid = 1'b0;
            w_valid = 1'b0;
            w_data = 'b0;
            w_strb = 'b0;
            b_ready = 1'b0;
            fifo_pop_o = 1'b1;
        end
        // may be empty or used to catch parasitic states
        default: begin
            aw_addr = 32'b0;
            aw_valid = 1'b0;
            w_valid = 1'b0;
            w_data = 'b0;
            w_strb = 'b0;
            b_ready = 1'b0;
            fifo_pop_o = 1'b0;
        end
    endcase
end

// Register the state
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    state_q <= StIdle;
    aw_addr_q <= addr_start;
  end else begin
    state_q <= state_d;
    aw_addr_q <= aw_addr_d;
  end
end

// Assign right signals to axi req
assign req_lite_o.aw.addr  = aw_addr;
assign req_lite_o.aw.prot  = '0; // (no protection considered?)
assign req_lite_o.aw_valid = aw_valid;
assign req_lite_o.w.data   = w_data;
assign req_lite_o.w.strb   = w_strb
assign req_lite_o.w_valid  = w_valid;
assign req_lite_o.b_ready  = b_ready;
// reading transaction does not exist in our case.
assign req_lite_o.ar       = '0;
assign req_lite_o.ar_valid = '0;
assign req_lite_o.r_ready  = '0;

// Assertions
assert((b_resp == 2'b00) && (b_ready && b_valid)) 
else   $error("Response on AXI-Lite is not OKAY, write transaction UNSUCCESSFULL");

endmodule