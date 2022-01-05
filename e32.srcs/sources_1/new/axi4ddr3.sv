`timescale 1ns / 1ps

// TODO: interface to either MIG7 generated code or 3rd party one

module axi4ddr3(
	axi4.SLAVE axi4if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	output wire calib_done,
	output wire ui_clk);

wire ui_clk, ui_clk_sync_rst;

mig_7series_0 DDR3Instance (
    // Memory interface ports
    .ddr3_addr                      (wires.ddr3_addr),
    .ddr3_ba                        (wires.ddr3_ba),
    .ddr3_cas_n                     (wires.ddr3_cas_n),
    .ddr3_ck_n                      (wires.ddr3_ck_n),
    .ddr3_ck_p                      (wires.ddr3_ck_p),
    .ddr3_cke                       (wires.ddr3_cke),
    .ddr3_ras_n                     (wires.ddr3_ras_n),
    .ddr3_reset_n                   (wires.ddr3_reset_n),
    .ddr3_we_n                      (wires.ddr3_we_n),
    .ddr3_dq                        (wires.ddr3_dq),
    .ddr3_dqs_n                     (wires.ddr3_dqs_n),
    .ddr3_dqs_p                     (wires.ddr3_dqs_p),
	.ddr3_cs_n                      (wires.ddr3_cs_n),
    .ddr3_dm                        (wires.ddr3_dm),
    .ddr3_odt                       (wires.ddr3_odt),

    // Application interface ports
    .ui_clk                         (ui_clk),          // Seems like we get a 100MHz clock with 200MHz sys clock
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .init_calib_complete            (calib_done),
    .device_temp					(), // Unused

    .mmcm_locked                    (), // Unused
    .aresetn                        (axi4if.ARESETn),

    .app_sr_req                     (1'b0), // Unused
    .app_ref_req                    (1'b0), // Unused
    .app_zq_req                     (1'b0), // Unused
    .app_sr_active                  (), // Unused
    .app_ref_ack                    (), // Unused
    .app_zq_ack                     (), // Unused

    // Slave Interface Write Address Ports
    .s_axi_awid                     (4'h0),
    .s_axi_awaddr                   (axi4if.AWADDR[27:0]),
    .s_axi_awlen                    (8'h00),  // 1 transfer
    .s_axi_awsize                   (3'b010), // 4 bytes
    .s_axi_awburst                  (2'b00),  // FIXED
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
    .s_axi_bid                      (), // Unused
    .s_axi_bresp                    (axi4if.BRESP),
    .s_axi_bvalid                   (axi4if.BVALID),
    .s_axi_bready                   (axi4if.BREADY),

    // Slave Interface Read Address Ports
    .s_axi_arid                     (4'h0),
    .s_axi_araddr                   (axi4if.ARADDR[27:0]),
    .s_axi_arlen                    (8'h00),  // 1 transfer
    .s_axi_arsize                   (3'b010), // 4 bytes
    .s_axi_arburst                  (2'b00),  // FIXED
    .s_axi_arlock                   (1'b0),
    .s_axi_arcache                  (4'h0),
    .s_axi_arprot                   (3'b000),
    .s_axi_arqos                    (4'h0),
    .s_axi_arvalid                  (axi4if.ARVALID),
    .s_axi_arready                  (axi4if.ARREADY),

    // Slave Interface Read Data Ports
    .s_axi_rid                      (), // Unused
    .s_axi_rdata                    (axi4if.RDATA),
    .s_axi_rresp                    (axi4if.RRESP),
    .s_axi_rlast                    (), // Unused
    .s_axi_rvalid                   (axi4if.RVALID),
    .s_axi_rready                   (axi4if.RREADY),
    // System Clock Ports
    .sys_clk_i                      (clocks.clk_sys_i), // 200MHz - should this be axi4if.ACLK ?
    // Reference Clock Ports
    .clk_ref_i                      (clocks.clk_ref_i), // 200MHz
    .sys_rst                        (axi4if.ARESETn) );

// ----------------------------------------------------------------------------
// DDR3 frontend
// ----------------------------------------------------------------------------

/*localparam WAIDLE = 2'd0;
localparam WAACK = 2'd1;

localparam WIDLE = 2'd0;
localparam WACCEPT = 2'd1;
localparam WDELAY = 2'd2;

localparam RIDLE = 2'd0;
localparam RREAD = 2'd1;
localparam RDELAY = 2'd2;

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] waddr;
logic [31:0] raddr;
logic [31:0] din = 32'd0;
wire [31:0] dout = 32'd0; // TODO: Remove this assignment
logic re = 1'b0;
logic [3:0] we = 4'h0;

// Write address
always @(posedge axi4if.ACLK) begin
	case (waddrstate)
		WAIDLE: begin
			if (axi4if.AWVALID) begin
				waddr <= axi4if.AWADDR;
				axi4if.AWREADY <= 1'b1;
				waddrstate <= WAACK;
			end
		end
		default: begin // WAACK
			axi4if.AWREADY <= 1'b0;
			waddrstate <= WAIDLE;
		end
	endcase
end

// Write data
always @(posedge axi4if.ACLK) begin
	we <= 4'h0;
	case (writestate)
		WIDLE: begin
			if (axi4if.WVALID) begin // & canActuallyWrite
				axi4if.WREADY <= 1'b1;
				we <= axi4if.WSTRB;
				din <= axi4if.WDATA;
				writestate <= WACCEPT;
			end
		end
		WACCEPT: begin
			axi4if.WREADY <= 1'b0;
			if(axi4if.BREADY) begin
				// Done
				axi4if.BVALID <= 1'b1;
				axi4if.BRESP = 2'b00; // OKAY
				writestate <= WDELAY;
			end
		end
		default: begin // WDELAY
			axi4if.BVALID <= 1'b0;
			writestate <= WIDLE;
		end
	endcase
end

// Read data
always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b0;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin
		re <= 1'b0;
		case (raddrstate)
			RIDLE: begin
				if (axi4if.ARVALID) begin
					raddr <= axi4if.ARADDR;
					re <= 1'b1;
					// Ready now
					axi4if.ARREADY <= 1'b1;
					raddrstate <= RREAD;
				end
			end
			RREAD: begin
				axi4if.ARREADY <= 1'b0;
				// Master ready to accept
				if (axi4if.RREADY) begin // & dataActuallyRead
					axi4if.RDATA <= dout;
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= RDELAY; // Delay one clock for master to pull down ARVALID
				end
			end
			default: begin // RDELAY
				// At this point master should have responded properly with ARVALID=0
				axi4if.RVALID <= 1'b0;
				//axi4if.RLAST <= 1'b0;
				raddrstate <= RIDLE;
			end
		endcase
	end
end*/

endmodule
