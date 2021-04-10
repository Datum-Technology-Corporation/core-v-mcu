// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.


`define REG_EVENT 6'b000000 //BASEADDR+0x00
`define REG_FC_MASK_0 6'b000001 //BASEADDR+0x04
`define REG_FC_MASK_1 6'b000010 //BASEADDR+0x08
`define REG_FC_MASK_2 6'b000011 //BASEADDR+0x0C
`define REG_FC_MASK_3 6'b000100 //BASEADDR+0x10
`define REG_FC_MASK_4 6'b000101 //BASEADDR+0x14
`define REG_FC_MASK_5 6'b000110 //BASEADDR+0x18
`define REG_FC_MASK_6 6'b000111 //BASEADDR+0x1C
`define REG_FC_MASK_7 6'b001000 //BASEADDR+0x20
`define REG_CL_MASK_0 6'b001001 //BASEADDR+0x24
`define REG_CL_MASK_1 6'b001010 //BASEADDR+0x28
`define REG_CL_MASK_2 6'b001011 //BASEADDR+0x2C
`define REG_CL_MASK_3 6'b001100 //BASEADDR+0x30
`define REG_CL_MASK_4 6'b001101 //BASEADDR+0x34
`define REG_CL_MASK_5 6'b001110 //BASEADDR+0x38
`define REG_CL_MASK_6 6'b001111 //BASEADDR+0x3C
`define REG_CL_MASK_7 6'b010000 //BASEADDR+0x40
`define REG_PR_MASK_0 6'b010001 //BASEADDR+0x44
`define REG_PR_MASK_1 6'b010010 //BASEADDR+0x48
`define REG_PR_MASK_2 6'b010011 //BASEADDR+0x4C
`define REG_PR_MASK_3 6'b010100 //BASEADDR+0x50
`define REG_PR_MASK_4 6'b010101 //BASEADDR+0x54
`define REG_PR_MASK_5 6'b010110 //BASEADDR+0x58
`define REG_PR_MASK_6 6'b010111 //BASEADDR+0x5C
`define REG_PR_MASK_7 6'b011000 //BASEADDR+0x60
`define REG_ERR_0 6'b011001 //BASEADDR+0x64
`define REG_ERR_1 6'b011010 //BASEADDR+0x68
`define REG_ERR_2 6'b011011 //BASEADDR+0x6C
`define REG_ERR_3 6'b011100 //BASEADDR+0x70
`define REG_ERR_4 6'b011101 //BASEADDR+0x74
`define REG_ERR_5 6'b011110 //BASEADDR+0x78
`define REG_ERR_6 6'b011111 //BASEADDR+0x7C
`define REG_ERR_7 6'b100000 //BASEADDR+0x80
`define REG_TIMER1_SEL_HI 6'b100001 //BASEADDR+0x84
`define REG_TIMER1_SEL_LO 6'b100010 //BASEADDR+0x88

module soc_event_generator #(
    parameter APB_ADDR_WIDTH = 12,  //APB slaves are 4KB by default
    parameter PER_EVNT_NUM   = 17,  // events coming from peripherals
    parameter APB_EVNT_NUM   = 16,  // events generated by the cluster and going to the FC EU
    parameter EVNT_WIDTH     = 8,
    parameter FC_EVENT_POS   = 3
) (
    input  logic                      HCLK,
    input  logic                      HRESETn,
    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic [              31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic [              31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,
    input  logic                      low_speed_clk_i,
    input  logic [  PER_EVNT_NUM-1:0] per_events_i,  // events coming from peripherals
    output logic [               1:0] fc_events_o,  // events going to the FC EU
    output logic                      err_event_o,
    output logic                      timer_event_lo_o,
    output logic                      timer_event_hi_o,
    output logic                      fc_event_valid_o,
    output logic [    EVNT_WIDTH-1:0] fc_event_data_o,
    input  logic                      fc_event_ready_i,
    output logic                      cl_event_valid_o,
    output logic [    EVNT_WIDTH-1:0] cl_event_data_o,
    input  logic                      cl_event_ready_i,
    output logic                      pr_event_valid_o,
    output logic [    EVNT_WIDTH-1:0] pr_event_data_o,
    input  logic                      pr_event_ready_i
);

  genvar j;

  localparam EVNT_NUM = PER_EVNT_NUM + APB_EVNT_NUM + 1;  //number of events going to the event BUS

  logic [             7:0] r_timer_sel_hi;
  logic [             7:0] r_timer_sel_lo;

  logic [  EVNT_WIDTH-1:0] s_event_data;
  logic                    s_event_valid;
  logic                    s_event_ready;

  logic [    EVNT_NUM-1:0] s_err;
  logic [           255:0] r_err;
  logic [    EVNT_NUM-1:0] s_req;
  logic [    EVNT_NUM-1:0] s_ack;
  logic [    EVNT_NUM-1:0] s_events;
  logic [    EVNT_NUM-1:0] s_grant;

  logic [             5:0] s_apb_addr;

  logic [           255:0] r_fc_mask;
  logic [           255:0] r_cl_mask;
  logic [           255:0] r_pr_mask;

  logic [    EVNT_NUM-1:0] s_fc_mask;
  logic [    EVNT_NUM-1:0] s_cl_mask;
  logic [    EVNT_NUM-1:0] s_pr_mask;

  logic                    s_ready_fc;
  logic                    s_ready_cl;
  logic                    s_ready_pr;

  logic                    s_valid_fc;
  logic                    s_valid_cl;
  logic                    s_valid_pr;

  logic [             2:0] r_ls_sync;
  logic                    s_ls_rise;

  logic [APB_EVNT_NUM-1:0] r_apb_events;

  assign fc_events_o = per_events_i[FC_EVENT_POS+1:FC_EVENT_POS];

  assign s_apb_addr = PADDR[7:2];

  assign s_ls_rise = ~r_ls_sync[2] & r_ls_sync[1];

  assign err_event_o = |(s_err);

  assign s_fc_mask = r_fc_mask[EVNT_NUM-1:0];
  assign s_cl_mask = r_cl_mask[EVNT_NUM-1:0];
  assign s_pr_mask = r_pr_mask[EVNT_NUM-1:0];

  assign fc_event_data_o = s_event_data;
  assign cl_event_data_o = s_event_data;
  assign pr_event_data_o = s_event_data;

  assign fc_event_valid_o = s_valid_fc;
  assign cl_event_valid_o = s_valid_cl;
  assign pr_event_valid_o = s_valid_pr;

  assign s_valid_fc = |(s_grant & ~s_fc_mask);
  assign s_valid_cl = |(s_grant & ~s_cl_mask);
  assign s_valid_pr = |(s_grant & ~s_pr_mask);

  assign s_ready_fc = s_valid_fc ? fc_event_ready_i : 1'b1;
  assign s_ready_cl = s_valid_cl ? cl_event_ready_i : 1'b1;
  assign s_ready_pr = s_valid_pr ? pr_event_ready_i : 1'b1;

  assign s_event_ready = s_ready_fc & s_ready_cl & s_ready_pr;

  assign s_events = {s_ls_rise, r_apb_events, per_events_i};

  assign s_ack = s_grant & {EVNT_NUM{s_event_ready}};

  assign timer_event_lo_o = s_events[r_timer_sel_lo];
  assign timer_event_hi_o = s_events[r_timer_sel_hi];

  generate
    for (j = 0; j < EVNT_NUM; j++) begin
      soc_event_queue u_soc_event_queue (
          .clk_i      (HCLK),
          .rstn_i     (HRESETn),
          .event_i    (s_events[j]),
          .err_o      (s_err[j]),
          .event_o    (s_req[j]),
          .event_ack_i(s_ack[j])
      );
    end
  endgenerate

  soc_event_arbiter #(
      .EVNT_NUM(EVNT_NUM)
  ) u_arbiter (
      .clk_i      (HCLK),
      .rstn_i     (HRESETn),
      .req_i      (s_req),
      .grant_o    (s_grant),
      .grant_ack_i(s_event_ready),
      .anyGrant_o (s_event_valid)
  );

  always_comb begin : proc_data_o
    s_event_data = 'h0;
    for (int i = 0; i < EVNT_NUM; i++) if (s_grant[i]) s_event_data = i;
  end

  always @(posedge HCLK or negedge HRESETn) begin
    if (~HRESETn) r_ls_sync <= 'h0;
    else r_ls_sync <= {r_ls_sync[1:0], low_speed_clk_i};
  end

  always @(posedge HCLK or negedge HRESETn) begin
    if (~HRESETn) begin
      r_apb_events = 'h0;
      r_fc_mask      <= {256{1'b1}};
      r_cl_mask      <= {256{1'b1}};
      r_pr_mask      <= {256{1'b1}};
      r_timer_sel_lo <= 'h0;
      r_timer_sel_hi <= 'h0;
      r_err = 'h0;
    end else begin
      for (int i = 0; i < EVNT_NUM; i++) if (s_err[i]) r_err[i] = 1'b1;
      r_apb_events = 'h0;
      if (PSEL && PENABLE && PWRITE) begin
        case (s_apb_addr)
          `REG_EVENT: begin
            r_apb_events = PWDATA[APB_EVNT_NUM-1:0];
          end
          `REG_FC_MASK_0: begin
            r_fc_mask[31:0] <= PWDATA;
          end
          `REG_FC_MASK_1: begin
            r_fc_mask[63:32] <= PWDATA;
          end
          `REG_FC_MASK_2: begin
            r_fc_mask[95:64] <= PWDATA;
          end
          `REG_FC_MASK_3: begin
            r_fc_mask[127:96] <= PWDATA;
          end
          `REG_FC_MASK_4: begin
            r_fc_mask[159:128] <= PWDATA;
          end
          `REG_FC_MASK_5: begin
            r_fc_mask[191:160] <= PWDATA;
          end
          `REG_FC_MASK_6: begin
            r_fc_mask[223:192] <= PWDATA;
          end
          `REG_FC_MASK_7: begin
            r_fc_mask[255:224] <= PWDATA;
          end
          `REG_CL_MASK_0: begin
            r_cl_mask[31:0] <= PWDATA;
          end
          `REG_CL_MASK_1: begin
            r_cl_mask[63:32] <= PWDATA;
          end
          `REG_CL_MASK_2: begin
            r_cl_mask[95:64] <= PWDATA;
          end
          `REG_CL_MASK_3: begin
            r_cl_mask[127:96] <= PWDATA;
          end
          `REG_CL_MASK_4: begin
            r_cl_mask[159:128] <= PWDATA;
          end
          `REG_CL_MASK_5: begin
            r_cl_mask[191:160] <= PWDATA;
          end
          `REG_CL_MASK_6: begin
            r_cl_mask[223:192] <= PWDATA;
          end
          `REG_CL_MASK_7: begin
            r_cl_mask[255:224] <= PWDATA;
          end
          `REG_PR_MASK_0: begin
            r_pr_mask[31:0] <= PWDATA;
          end
          `REG_PR_MASK_1: begin
            r_pr_mask[63:32] <= PWDATA;
          end
          `REG_PR_MASK_2: begin
            r_pr_mask[95:64] <= PWDATA;
          end
          `REG_PR_MASK_3: begin
            r_pr_mask[127:96] <= PWDATA;
          end
          `REG_PR_MASK_4: begin
            r_pr_mask[159:128] <= PWDATA;
          end
          `REG_PR_MASK_5: begin
            r_pr_mask[191:160] <= PWDATA;
          end
          `REG_PR_MASK_6: begin
            r_pr_mask[223:192] <= PWDATA;
          end
          `REG_PR_MASK_7: begin
            r_pr_mask[255:224] <= PWDATA;
          end
          `REG_TIMER1_SEL_LO: begin
            r_timer_sel_lo <= PWDATA[7:0];
          end
          `REG_TIMER1_SEL_HI: begin
            r_timer_sel_hi <= PWDATA[7:0];
          end
        endcase  // s_apb_addr
      end else if (PSEL && PENABLE && ~PWRITE) begin
        case (s_apb_addr)
          `REG_ERR_0: r_err[31:0] = 'h0;
          `REG_ERR_1: r_err[63:32] = 'h0;
          `REG_ERR_2: r_err[95:64] = 'h0;
          `REG_ERR_3: r_err[127:96] = 'h0;
          `REG_ERR_4: r_err[159:128] = 'h0;
          `REG_ERR_5: r_err[191:160] = 'h0;
          `REG_ERR_6: r_err[223:192] = 'h0;
          `REG_ERR_7: r_err[255:224] = 'h0;
        endcase  // s_apb_addr
      end
    end
  end  //always

  always_comb begin
    PRDATA = 'h0;
    case (s_apb_addr)
      `REG_FC_MASK_0: PRDATA = r_fc_mask[31:0];
      `REG_FC_MASK_1: PRDATA = r_fc_mask[63:32];
      `REG_FC_MASK_2: PRDATA = r_fc_mask[95:64];
      `REG_FC_MASK_3: PRDATA = r_fc_mask[127:96];
      `REG_FC_MASK_4: PRDATA = r_fc_mask[159:128];
      `REG_FC_MASK_5: PRDATA = r_fc_mask[191:160];
      `REG_FC_MASK_6: PRDATA = r_fc_mask[223:192];
      `REG_FC_MASK_7: PRDATA = r_fc_mask[255:224];
      `REG_CL_MASK_0: PRDATA = r_cl_mask[31:0];
      `REG_CL_MASK_1: PRDATA = r_cl_mask[63:32];
      `REG_CL_MASK_2: PRDATA = r_cl_mask[95:64];
      `REG_CL_MASK_3: PRDATA = r_cl_mask[127:96];
      `REG_CL_MASK_4: PRDATA = r_cl_mask[159:128];
      `REG_CL_MASK_5: PRDATA = r_cl_mask[191:160];
      `REG_CL_MASK_6: PRDATA = r_cl_mask[223:192];
      `REG_CL_MASK_7: PRDATA = r_cl_mask[255:224];
      `REG_PR_MASK_0: PRDATA = r_pr_mask[31:0];
      `REG_PR_MASK_1: PRDATA = r_pr_mask[63:32];
      `REG_PR_MASK_2: PRDATA = r_pr_mask[95:64];
      `REG_PR_MASK_3: PRDATA = r_pr_mask[127:96];
      `REG_PR_MASK_4: PRDATA = r_pr_mask[159:128];
      `REG_PR_MASK_5: PRDATA = r_pr_mask[191:160];
      `REG_PR_MASK_6: PRDATA = r_pr_mask[223:192];
      `REG_PR_MASK_7: PRDATA = r_pr_mask[255:224];
      `REG_ERR_0: PRDATA = r_err[31:0];
      `REG_ERR_1: PRDATA = r_err[63:32];
      `REG_ERR_2: PRDATA = r_err[95:64];
      `REG_ERR_3: PRDATA = r_err[127:96];
      `REG_ERR_4: PRDATA = r_err[159:128];
      `REG_ERR_5: PRDATA = r_err[191:160];
      `REG_ERR_6: PRDATA = r_err[223:192];
      `REG_ERR_7: PRDATA = r_err[255:224];
      `REG_TIMER1_SEL_LO: PRDATA = {24'h0, r_timer_sel_lo};
      `REG_TIMER1_SEL_HI: PRDATA = {24'h0, r_timer_sel_hi};
      default: PRDATA = 'h0;
    endcase
  end

  assign PREADY  = 1'b1;
  assign PSLVERR = 1'b0;

endmodule  // soc_event_generator
