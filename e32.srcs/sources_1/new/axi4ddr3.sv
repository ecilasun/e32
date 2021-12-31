`timescale 1ns / 1ps

module axi4ddr3(
	axi4 axi4if,
	input wire enable,
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

// DDR3 R/W controller
localparam MAIN_INIT = 3'd0;
localparam MAIN_IDLE = 3'd1;
localparam MAIN_WAIT_WRITE = 3'd2;
localparam MAIN_WAIT_READ = 3'd3;
localparam MAIN_FINISH_READ = 3'd4;
logic [2:0] mainstate = MAIN_INIT;

wire calib_done;
wire [11:0] device_temp;
logic calib_done1=1'b0, calib_done2=1'b0;

logic [27:0] app_addr = 0;
logic [2:0]  app_cmd = 0;
logic app_en;
wire app_rdy;

logic [127:0] app_wdf_data;
logic app_wdf_wren;
wire app_wdf_rdy;

wire [127:0] app_rd_data;
wire app_rd_data_end;
wire app_rd_data_valid;

wire app_sr_req = 0;
wire app_ref_req = 0;
wire app_zq_req = 0;
wire app_sr_active;
wire app_ref_ack;
wire app_zq_ack;

wire ddr3cmdfull, ddr3cmdempty, ddr3cmdvalid;
logic ddr3cmdre = 1'b0, ddr3cmdwe = 1'b0;
logic [152:0] ddr3cmdin;
wire [152:0] ddr3cmdout;

wire ddr3readfull, ddr3readempty, ddr3readvalid;
logic ddr3readwe = 1'b0, ddr3readre = 1'b0;
logic [127:0] ddr3readin = 128'd0;

wire ui_clk;
wire ui_clk_sync_rst;

// System memory - SLOW section
DDR3MIG7 ddr3memoryinterface (
   .ddr3_addr   (ddr3_addr),
   .ddr3_ba     (ddr3_ba),
   .ddr3_cas_n  (ddr3_cas_n),
   .ddr3_ck_n   (ddr3_ck_n),
   .ddr3_ck_p   (ddr3_ck_p),
   .ddr3_cke    (ddr3_cke),
   .ddr3_ras_n  (ddr3_ras_n),
   .ddr3_reset_n(ddr3_reset_n),
   .ddr3_we_n   (ddr3_we_n),
   .ddr3_dq     (ddr3_dq),
   .ddr3_dqs_n  (ddr3_dqs_n),
   .ddr3_dqs_p  (ddr3_dqs_p),
   .ddr3_cs_n   (ddr3_cs_n),
   .ddr3_dm     (ddr3_dm),
   .ddr3_odt    (ddr3_odt),

   .init_calib_complete (calib_done),
   .device_temp(device_temp), // TODO: Can map this to a memory location if needed

   // User interface ports
   .app_addr    (app_addr),
   .app_cmd     (app_cmd),
   .app_en      (app_en),
   .app_wdf_data(app_wdf_data),
   .app_wdf_end (app_wdf_wren),
   .app_wdf_wren(app_wdf_wren),
   .app_rd_data (app_rd_data),
   .app_rd_data_end (app_rd_data_end),
   .app_rd_data_valid (app_rd_data_valid),
   .app_rdy     (app_rdy),
   .app_wdf_rdy (app_wdf_rdy),
   .app_sr_req  (app_sr_req),
   .app_ref_req (app_ref_req),
   .app_zq_req  (app_zq_req),
   .app_sr_active(app_sr_active),
   .app_ref_ack (app_ref_ack),
   .app_zq_ack  (app_zq_ack),
   .ui_clk      (ui_clk),
   .ui_clk_sync_rst (ui_clk_sync_rst),
   .app_wdf_mask(16'h0000), // Active low, therefore 0000 is enable all bytes
   // Clock and Reset input ports
   .sys_clk_i (clk_sys_i),
   .clk_ref_i (clk_ref_i),
   .sys_rst (axi4if.ARESETn) // Note: reset is synced to bus clock...
);

localparam INIT = 3'd0;
localparam IDLE = 3'd1;
localparam DECODECMD = 3'd2;
localparam WRITE = 3'd3;
localparam WRITE_DONE = 3'd4;
localparam READ = 3'd5;
localparam READ_DONE = 3'd6;
localparam PARK = 3'd7;
logic [2:0] state = INIT;

localparam CMD_WRITE = 3'b000;
localparam CMD_READ = 3'b001;

always @ (posedge ui_clk) begin
	calib_done1 <= calib_done;
	calib_done2 <= calib_done1;
end

// ddr3 driver
always @ (posedge ui_clk) begin
	if (ui_clk_sync_rst) begin
		state <= INIT;
		app_en <= 0;
		app_wdf_wren <= 0;
	end else begin
	
		unique case (state)
			INIT: begin
				if (calib_done2) begin
					state <= IDLE;
				end
			end
			
			IDLE: begin
				ddr3readwe <= 1'b0;
				if (~ddr3cmdempty) begin
					ddr3cmdre <= 1'b1;
					state <= DECODECMD;
				end
			end
			
			DECODECMD: begin
				ddr3cmdre <= 1'b0;
				if (ddr3cmdvalid) begin
					if (ddr3cmdout[152]==1'b1) // Write request?
						state <= WRITE;
					else
						state <= READ;
				end
			end
			
			WRITE: begin
				if (app_rdy & app_wdf_rdy) begin
					state <= WRITE_DONE;
					app_en <= 1;
					app_wdf_wren <= 1;
					app_addr <= {1'b0, ddr3cmdout[151:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit (rank) is supposed to stay zero
					app_cmd <= CMD_WRITE;
					app_wdf_data <= ddr3cmdout[127:0]; // 128bit value from cache
				end
			end

			WRITE_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end

				if (app_wdf_rdy & app_wdf_wren) begin
					app_wdf_wren <= 0;
				end

				if (~app_en & ~app_wdf_wren) begin
					state <= IDLE;
				end
			end

			READ: begin
				if (app_rdy) begin
					app_en <= 1;
					app_addr <= {1'b0, ddr3cmdout[151:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
					app_cmd <= CMD_READ;
					state <= READ_DONE;
				end
			end

			READ_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
			
				if (app_rd_data_valid) begin
					// After this step, full 128bit value will be available on the
					// ddr3readre when read is asserted and ddr3readvalid is high
					ddr3readwe <= 1'b1;
					ddr3readin <= app_rd_data;
					state <= IDLE;
				end
			end

			default: state <= INIT;
		endcase
	end
end

// command fifo
DDR3RWCmd ddr3cmdfifo(
	.full(ddr3cmdfull),
	.din(ddr3cmdin),
	.wr_en(ddr3cmdwe),
	.wr_clk(axi4if.ACLK),
	.empty(ddr3cmdempty),
	.dout(ddr3cmdout),
	.rd_en(ddr3cmdre),
	.valid(ddr3cmdvalid),
	.rd_clk(ui_clk),
	.rst(~axi4if.ARESETn) );

// read done queue
wire [127:0] ddr3readout;
DDR3ReadData ddr3readdonequeue(
	.full(ddr3readfull),
	.din(ddr3readin),
	.wr_en(ddr3readwe),
	.wr_clk(ui_clk),
	.empty(ddr3readempty),
	.dout(ddr3readout),
	.rd_en(ddr3readre),
	.valid(ddr3readvalid),
	.rd_clk(axi4if.ACLK),
	.rst(ui_clk_sync_rst) );

// ------------------
// DDR3 cache
// ------------------

// 256 bit wide cache lines, 256 lines total
logic [15:0] cachetags[0:255];
logic [255:0] cache[0:255];

initial begin
	integer i;
	// All pages are 'clean', but all tags are invalid and cache is zeroed out by default
	for (int i=0;i<256;i=i+1) begin
		cachetags[i] = 16'h7FFF;
		cache[i] = 256'd0;
	end
end

logic [15:0] oldtag = 16'd0;
logic [14:0] ctag = 15'd0;
logic [7:0] cline = 8'h00;
logic [2:0] coffset = 3'd0;
logic [31:0] cwidemask = 32'd0;
logic readpart = 1'b0;
logic [255:0] currentcacheline = 256'd0;

localparam WAIDLE = 2'd0;
localparam WADELAY = 2'd1;

localparam WCACHECHECK = 4'd0;
localparam WRESPONSE = 4'd1;
localparam WWBACK2 = 4'd2;
localparam WPOPULATE = 4'd3;
localparam WPOPULATE2 = 4'd4;
localparam WWAIT = 4'd5;
localparam WUPDATECACHE = 4'd6;
localparam WDELAY = 4'd7;

localparam RADDRESSCHECK = 4'd0;
localparam RCACHECHECK =4'd1;
localparam RWBACK2 = 4'd2;
localparam RPOPULATE = 4'd3;
localparam RPOPULATE2 = 4'd4;
localparam RWAIT = 4'd5;
localparam RUPDATECACHE = 4'd6;
localparam RDELAY = 4'd7;

logic [1:0] waddrstate = WAIDLE;
logic [3:0] writestate = WCACHECHECK;
logic [3:0] raddrstate = RADDRESSCHECK;

always_comb begin
	if (enable) begin
		currentcacheline = cache[cline];
		oldtag = cachetags[cline];
	end
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b0;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin

		// Write address
		case (waddrstate)
			WAIDLE: begin
				if (axi4if.AWVALID) begin
					// Set up cache info
					//ctag <= axi4if.AWADDR[27:13]; No need to generate tag since we won't use it here
					cline <= axi4if.AWADDR[12:5];
					coffset <= axi4if.AWADDR[4:2];
					cwidemask <= {{8{axi4if.WSTRB[3]}}, {8{axi4if.WSTRB[2]}}, {8{axi4if.WSTRB[1]}}, {8{axi4if.WSTRB[0]}}};
					axi4if.AWREADY <= 1'b1;
					waddrstate <= WADELAY;
				end
			end
			default/*WADELAY*/: begin
				axi4if.AWREADY <= 1'b0;
				waddrstate <= WAIDLE;
			end
		endcase

		// Write data
		case (writestate)
			WCACHECHECK: begin
				if (axi4if.WVALID) begin
					if (oldtag[14:0] == ctag) begin // Same cacheline as before, simply write value to cache
						case (coffset)
							3'b000: cache[cline][31:0] <= ((~cwidemask)&currentcacheline[31:0]) | (cwidemask&axi4if.WDATA);
							3'b001: cache[cline][63:32] <= ((~cwidemask)&currentcacheline[63:32]) | (cwidemask&axi4if.WDATA);
							3'b010: cache[cline][95:64] <= ((~cwidemask)&currentcacheline[95:64]) | (cwidemask&axi4if.WDATA);
							3'b011: cache[cline][127:96] <= ((~cwidemask)&currentcacheline[127:96]) | (cwidemask&axi4if.WDATA);
							3'b100: cache[cline][159:128] <= ((~cwidemask)&currentcacheline[159:128]) | (cwidemask&axi4if.WDATA);
							3'b101: cache[cline][191:160] <= ((~cwidemask)&currentcacheline[191:160]) | (cwidemask&axi4if.WDATA);
							3'b110: cache[cline][223:192] <= ((~cwidemask)&currentcacheline[223:192]) | (cwidemask&axi4if.WDATA);
							3'b111: cache[cline][255:224] <= ((~cwidemask)&currentcacheline[255:224]) | (cwidemask&axi4if.WDATA);
						endcase
						// This cache line is now dirty
						cachetags[cline][15] <= 1'b1;
						axi4if.WREADY <= 1'b1;
						writestate <= WRESPONSE;
					end else begin
						if (oldtag[15]) begin
							// Write back old cache line contents to old address then populate
							ddr3cmdin <= {1'b1, oldtag[14:0], cline[7:0], 1'b0, cache[cline][127:0]};
							ddr3cmdwe <= 1'b1;
							writestate <= WWBACK2; // WRITEBACK2 chains to POPULATE
						end else begin // Cache line not dirty for old tag, simply load from new line
							ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b0, 128'd0};
							ddr3cmdwe <= 1'b1;
							writestate <= WPOPULATE2;
						end
					end
				end
			end
			WWBACK2: begin
				ddr3cmdin <= {1'b1, oldtag[14:0], cline[7:0], 1'b1, cache[cline][255:128]};
				//ddr3cmdwe <= 1'b1; already set
				writestate <= WPOPULATE;
			end
			WPOPULATE: begin
				// Load contents to new address, discarding current cache line (either evicted or discarded)
				ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b0, 128'd0};
				//ddr3cmdwe <= 1'b1; allready set
				writestate <= WPOPULATE2;
			end
			WPOPULATE2: begin
				// Load contents to new address, discarding current cache line (either evicted or discarded)
				ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b1, 128'd0};
				//ddr3cmdwe <= 1'b1; already set
				// Wait for read result
				readpart <= 1'b0;
				writestate <= WWAIT;
			end
			WWAIT: begin
				ddr3cmdwe <= 1'b0;
				if (~ddr3readempty) begin
					// Read result available for this cache line
					// Request to read it
					ddr3readre <= 1'b1;
					writestate <= WUPDATECACHE;
				end else begin
					writestate <= WWAIT;
				end
			end
			WUPDATECACHE: begin
				// Stop result read request
				ddr3readre <= 1'b0;
				if (ddr3readvalid) begin
					// Grab the data output at this address
					if (readpart == 1'b0) begin
						cache[cline][127:0] <= ddr3readout;
						readpart <= 1'b1;
						writestate <= WWAIT;
					end else begin
						cache[cline][255:128] <= ddr3readout;
						// Update tag and mark not-dirty
						cachetags[cline] <= {1'b0, ctag};
						writestate <= WCACHECHECK;
					end
				end else begin
					// Wait in this state until a 
					writestate <= WUPDATECACHE;
				end
			end
			WRESPONSE: begin
				axi4if.WREADY <= 1'b0;
				if (axi4if.BREADY) begin
					axi4if.BVALID <= 1'b1;
					axi4if.BRESP <= 2'b00; // OKAY
					writestate <= WDELAY;
				end
			end
			default/*WDELAY*/: begin
				axi4if.BVALID <= 1'b0;
				writestate <= WCACHECHECK;
			end
		endcase

		// Read address / read data
		case (raddrstate)
			RADDRESSCHECK: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b1;
					// Set up cache info
					ctag <= axi4if.AWADDR[27:13];
					cline <= axi4if.AWADDR[12:5];
					coffset <= axi4if.AWADDR[4:2];
					raddrstate <= RCACHECHECK;
				end
			end
			RCACHECHECK: begin
				// Master ready to accept
				if (axi4if.RREADY) begin
					if (oldtag[14:0] == ctag) begin // Entry in I$ or D$ and master ready to accept
						axi4if.ARREADY <= 1'b0;
						case (coffset)
							3'b000: axi4if.RDATA <= currentcacheline[31:0];
							3'b001: axi4if.RDATA <= currentcacheline[63:32];
							3'b010: axi4if.RDATA <= currentcacheline[95:64];
							3'b011: axi4if.RDATA <= currentcacheline[127:96];
							3'b100: axi4if.RDATA <= currentcacheline[159:128];
							3'b101: axi4if.RDATA <= currentcacheline[191:160];
							3'b110: axi4if.RDATA <= currentcacheline[223:192];
							3'b111: axi4if.RDATA <= currentcacheline[255:224];
						endcase
						axi4if.RVALID <= 1'b1; // Done reading
						raddrstate <= RDELAY; // DELAY (Delay one clock for master to pull down ARVALID)
					end else begin // Data not in cache
						// Do we need to flush then populate?
						if (oldtag[15]) begin
							// Write back old cache line contents to old address
							ddr3cmdin <= {1'b1, oldtag[14:0], cline[7:0], 1'b0, cache[cline][127:0]};
							ddr3cmdwe <= 1'b1;
							raddrstate <= RWBACK2; // WRITEBACK2 chains to POPULATE
						end else begin // Cache line not dirty for old tag, simply load from new line
							ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b0, 128'd0};
							ddr3cmdwe <= 1'b1;
							raddrstate <= RPOPULATE2; // POPULATE2
						end
					end
				end
			end
			RWBACK2: begin
				ddr3cmdin <= {1'b1, oldtag[14:0], cline[7:0], 1'b1, cache[cline][255:128]};
				//ddr3cmdwe <= 1'b1; already set
				raddrstate <= RPOPULATE; // POPULATE
			end
			RPOPULATE: begin
				// Load contents to new address, discarding current cache line (either evicted or discarded)
				ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b0, 128'd0};
				//ddr3cmdwe <= 1'b1; allready set
				raddrstate <= RPOPULATE2;
			end
			RPOPULATE2: begin
				// Load contents to new address, discarding current cache line (either evicted or discarded)
				ddr3cmdin <= {1'b0, ctag, cline[7:0], 1'b1, 128'd0};
				//ddr3cmdwe <= 1'b1; already set
				// Wait for read result
				readpart <= 1'b0;
				raddrstate <= RWAIT;
			end
			RWAIT: begin
				ddr3cmdwe <= 1'b0;
				if (~ddr3readempty) begin
					// Read result available for this cache line
					// Request to read it
					ddr3readre <= 1'b1;
					raddrstate <= RUPDATECACHE;
				end else begin
					raddrstate <= RWAIT;
				end
			end
			RUPDATECACHE: begin
				// Stop result read request
				ddr3readre <= 1'b0;
				if (ddr3readvalid) begin
					// Grab the data output at this address
					if (readpart == 1'b0) begin
						cache[cline][127:0] <= ddr3readout;
						readpart <= 1'b1;
						raddrstate <= RWAIT;
					end else begin
						cache[cline][255:128] <= ddr3readout;
						// Update tag and mark not-dirty
						cachetags[cline] <= {1'b0, ctag};
						raddrstate <= RCACHECHECK;
					end
				end else begin
					// Wait in this state until a 
					raddrstate <= RUPDATECACHE;
				end
			end
			default/*RDELAY*/: begin
				axi4if.ARREADY <= 1'b0;
				axi4if.RVALID <= 1'b0;
				raddrstate <= RADDRESSCHECK;
			end
		endcase

	end
end

endmodule
