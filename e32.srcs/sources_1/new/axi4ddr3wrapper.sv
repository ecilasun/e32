`timescale 1ns / 1ps

module axi4ddr3(
	axi4 axi4if,
	input wire clk_ddr_w,
	input wire clk_ddr_dqs_w,
	input wire clk_ref_w,
    output wire [13:0] ddr3_addr,
    output wire [2:0] ddr3_ba,
    output wire ddr3_cas_n,
    output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_ck_p,
    output wire [0:0] ddr3_cke,
    output wire ddr3_ras_n,
    output wire ddr3_reset_n,
    output wire ddr3_we_n,
    inout wire [15:0] ddr3_dq,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [1:0] ddr3_dqs_p,
	output wire [0:0] ddr3_cs_n,
    output wire [1:0] ddr3_dm,
    output wire [0:0] ddr3_odt );


wire [ 13:0]   dfi_address_w;
wire [  2:0]   dfi_bank_w;
wire           dfi_cas_n_w;
wire           dfi_cke_w;
wire           dfi_cs_n_w;
wire           dfi_odt_w;
wire           dfi_ras_n_w;
wire           dfi_reset_n_w;
wire           dfi_we_n_w;
wire [ 31:0]   dfi_wrdata_w;
wire           dfi_wrdata_en_w;
wire [  3:0]   dfi_wrdata_mask_w;
wire           dfi_rddata_en_w;
wire [ 31:0]   dfi_rddata_w;
wire           dfi_rddata_valid_w;
wire [  1:0]   dfi_rddata_dnv_w;

ddr3_axi
#(
     .DDR_WRITE_LATENCY(4)
    ,.DDR_READ_LATENCY(4)
    ,.DDR_MHZ(100)
)
u_ddr
(
    // Inputs
     .clk_i(axi4if.ACLK)
    ,.rst_i(~axi4if.ARESETn)
    ,.inport_awvalid_i(axi4if.AWVALID)
    ,.inport_awaddr_i(axi4if.AWADDR)
    ,.inport_awid_i(4'h0)
    ,.inport_awlen_i(8'h00) // len-1
    ,.inport_awburst_i(2'b00) // No burst
    ,.inport_wvalid_i(axi4if.WVALID)
    ,.inport_wdata_i(axi4if.WDATA)
    ,.inport_wstrb_i(axi4if.WSTRB)
    ,.inport_wlast_i(1'b1) // No burst for now axi4if.WLAST==1
    ,.inport_bready_i(axi4if.BREADY)
    ,.inport_arvalid_i(axi4if.ARVALID)
    ,.inport_araddr_i(axi4if.ARADDR)
    ,.inport_arid_i(4'h0)
    ,.inport_arlen_i(8'h00) // len-1
    ,.inport_arburst_i(2'b00) // No burst
    ,.inport_rready_i(axi4if.RREADY)
    ,.dfi_rddata_i(dfi_rddata_w)
    ,.dfi_rddata_valid_i(dfi_rddata_valid_w)
    ,.dfi_rddata_dnv_i(dfi_rddata_dnv_w)

    // Outputs
    ,.inport_awready_o(axi4if.AWREADY)
    ,.inport_wready_o(axi4if.WREADY)
    ,.inport_bvalid_o(axi4if.BVALID)
    ,.inport_bresp_o(axi4if.BRESP)
    ,.inport_bid_o() // Unused
    ,.inport_arready_o(axi4if.ARREADY)
    ,.inport_rvalid_o(axi4if.RVALID)
    ,.inport_rdata_o(axi4if.RDATA)
    ,.inport_rresp_o(axi4if.RRESP)
    ,.inport_rid_o(axi4_rid_w)
    ,.inport_rlast_o() // Unused, always last, no burst for now axi4if.RLAST==1
    ,.dfi_address_o(dfi_address_w)
    ,.dfi_bank_o(dfi_bank_w)
    ,.dfi_cas_n_o(dfi_cas_n_w)
    ,.dfi_cke_o(dfi_cke_w)
    ,.dfi_cs_n_o(dfi_cs_n_w)
    ,.dfi_odt_o(dfi_odt_w)
    ,.dfi_ras_n_o(dfi_ras_n_w)
    ,.dfi_reset_n_o(dfi_reset_n_w)
    ,.dfi_we_n_o(dfi_we_n_w)
    ,.dfi_wrdata_o(dfi_wrdata_w)
    ,.dfi_wrdata_en_o(dfi_wrdata_en_w)
    ,.dfi_wrdata_mask_o(dfi_wrdata_mask_w)
    ,.dfi_rddata_en_o(dfi_rddata_en_w)
);

ddr3_dfi_phy
#(
     .DQS_TAP_DELAY_INIT(27)
    ,.DQ_TAP_DELAY_INIT(0)
    ,.TPHY_RDLAT(5)
)
u_phy
(
     .clk_i(clk_w)
    ,.rst_i(rst_w)

    ,.clk_ddr_i(clk_ddr_w)			// 400MHz
    ,.clk_ddr90_i(clk_ddr_dqs_w)	// 400MHz +90deg
    ,.clk_ref_i(clk_ref_w)			// 200MHz

    ,.cfg_valid_i(1'b0)
    ,.cfg_i(32'b0)

    ,.dfi_address_i(dfi_address_w)
    ,.dfi_bank_i(dfi_bank_w)
    ,.dfi_cas_n_i(dfi_cas_n_w)
    ,.dfi_cke_i(dfi_cke_w)
    ,.dfi_cs_n_i(dfi_cs_n_w)
    ,.dfi_odt_i(dfi_odt_w)
    ,.dfi_ras_n_i(dfi_ras_n_w)
    ,.dfi_reset_n_i(dfi_reset_n_w)
    ,.dfi_we_n_i(dfi_we_n_w)
    ,.dfi_wrdata_i(dfi_wrdata_w)
    ,.dfi_wrdata_en_i(dfi_wrdata_en_w)
    ,.dfi_wrdata_mask_i(dfi_wrdata_mask_w)
    ,.dfi_rddata_en_i(dfi_rddata_en_w)
    ,.dfi_rddata_o(dfi_rddata_w)
    ,.dfi_rddata_valid_o(dfi_rddata_valid_w)
    ,.dfi_rddata_dnv_o(dfi_rddata_dnv_w)
    
    ,.ddr3_ck_p_o(ddr3_ck_p)
    ,.ddr3_ck_n_o(ddr3_ck_n)
    ,.ddr3_cke_o(ddr3_cke)
    ,.ddr3_reset_n_o(ddr3_reset_n)
    ,.ddr3_ras_n_o(ddr3_ras_n)
    ,.ddr3_cas_n_o(ddr3_cas_n)
    ,.ddr3_we_n_o(ddr3_we_n)
    ,.ddr3_cs_n_o(ddr3_cs_n)
    ,.ddr3_ba_o(ddr3_ba)
    ,.ddr3_addr_o(ddr3_addr[13:0])
    ,.ddr3_odt_o(ddr3_odt)
    ,.ddr3_dm_o(ddr3_dm)
    ,.ddr3_dq_io(ddr3_dq)
    ,.ddr3_dqs_p_io(ddr3_dqs_p)
    ,.ddr3_dqs_n_io(ddr3_dqs_n) );

endmodule
