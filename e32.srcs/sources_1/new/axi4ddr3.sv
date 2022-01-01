`timescale 1ns / 1ps

module axi4ddr3(
	axi4 axi4if,
	input wire enable,
	output wire calib_done,
	input wire clk_sys_i,
	input wire clk_ref_i,
    output wire ddr3_reset_n,
    output wire [0:0] ddr3_cke,
    output wire [0:0] ddr3_ck_p, 
    output wire [0:0] ddr3_ck_n,
    output wire [0:0] ddr3_cs_n,
    output wire ddr3_ras_n, 
    output wire ddr3_cas_n, 
    output wire ddr3_we_n,
    output wire [2:0] ddr3_ba,
    output wire [13:0] ddr3_addr,
    output wire [0:0] ddr3_odt,
    output wire [1:0] ddr3_dm,
    inout wire [1:0] ddr3_dqs_p,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [15:0] ddr3_dq );

wire ui_clk, ui_clk_sync_rst;

DDR3MIG7 DDR3Instance (
    // Memory interface ports
    .ddr3_addr                      (ddr3_addr),
    .ddr3_ba                        (ddr3_ba),
    .ddr3_cas_n                     (ddr3_cas_n),
    .ddr3_ck_n                      (ddr3_ck_n),
    .ddr3_ck_p                      (ddr3_ck_p),
    .ddr3_cke                       (ddr3_cke),
    .ddr3_ras_n                     (ddr3_ras_n),
    .ddr3_reset_n                   (ddr3_reset_n),
    .ddr3_we_n                      (ddr3_we_n),
    .ddr3_dq                        (ddr3_dq),
    .ddr3_dqs_n                     (ddr3_dqs_n),
    .ddr3_dqs_p                     (ddr3_dqs_p),
	.ddr3_cs_n                      (ddr3_cs_n),
    .ddr3_dm                        (ddr3_dm),
    .ddr3_odt                       (ddr3_odt),

    // Application interface ports
    .ui_clk                         (ui_clk),
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .init_calib_complete            (calib_done),

    .mmcm_locked                    (),
    .aresetn                        (axi4if.ARESETn),

    .app_sr_req                     (1'b0),
    .app_ref_req                    (1'b0),
    .app_zq_req                     (1'b0),
    .app_sr_active                  (),
    .app_ref_ack                    (),
    .app_zq_ack                     (),

    // Slave Interface Write Address Ports
    .s_axi_awid                     (4'h0),
    .s_axi_awaddr                   (axi4if.AWADDR[27:0]),
    .s_axi_awlen                    (8'h00),
    .s_axi_awsize                   (3'd4),
    .s_axi_awburst                  (2'b00),
    .s_axi_awlock                   (1'b0),
    .s_axi_awcache                  (4'h0),
    .s_axi_awprot                   (3'b000),
    .s_axi_awqos                    (4'h0),
    .s_axi_awvalid                  (axi4if.AWVALID),
    .s_axi_awready                  (axi4if.AWREADY),

    // Slave Interface Write Data Ports
    .s_axi_wdata                    (axi4if.WDATA),
    .s_axi_wstrb                    (axi4if.WSTRB),
    .s_axi_wlast                    (1'b1),
    .s_axi_wvalid                   (axi4if.WVALID),
    .s_axi_wready                   (axi4if.WREADY),

    // Slave Interface Write Response Ports
    .s_axi_bid                      (),
    .s_axi_bresp                    (axi4if.BRESP),
    .s_axi_bvalid                   (axi4if.BVALID),
    .s_axi_bready                   (axi4if.BREADY),

    // Slave Interface Read Address Ports
    .s_axi_arid                     (4'h0),
    .s_axi_araddr                   (axi4if.ARADDR[27:0]),
    .s_axi_arlen                    (8'h00),
    .s_axi_arsize                   (3'd4),
    .s_axi_arburst                  (2'b00),
    .s_axi_arlock                   (1'b0),
    .s_axi_arcache                  (4'h0),
    .s_axi_arprot                   (3'b000),
    .s_axi_arqos                    (4'h0),
    .s_axi_arvalid                  (axi4if.ARVALID),
    .s_axi_arready                  (axi4if.ARREADY),

    // Slave Interface Read Data Ports
    .s_axi_rid                      (),
    .s_axi_rdata                    (axi4if.RDATA),
    .s_axi_rresp                    (axi4if.RRESP),
    .s_axi_rlast                    (),
    .s_axi_rvalid                   (axi4if.RVALID),
    .s_axi_rready                   (axi4if.RREADY),
    // System Clock Ports
    .sys_clk_i                      (clk_sys_i),
    // Reference Clock Ports
    .clk_ref_i                      (clk_ref_i),
    .sys_rst                        (axi4if.ARESETn) );

endmodule
