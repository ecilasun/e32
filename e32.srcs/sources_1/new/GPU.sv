`timescale 1ns / 1ps

module axi4gpu(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks,
	GPUDataOutput.DEFAULT gpudata );

// ----------------------------------------------------------------------------
// Color palette unit
// ----------------------------------------------------------------------------

wire [7:0] paletteReadAddress;
logic [7:0] paletteWriteAddress;
logic palettewe = 1'b0;
logic [23:0] palettedin = 24'd0;
wire [23:0] palettedout;

colorpalette Palette(
	.gpuclock(clocks.gpubaseclock),
	.we(palettewe),
	.waddress(paletteWriteAddress),
	.raddress(paletteReadAddress),
	.din(palettedin),
	.dout(palettedout) );

// ----------------------------------------------------------------------------
// Video units
// ----------------------------------------------------------------------------

wire [11:0] video_x;
wire [11:0] video_y;

logic videopagesel = 1'b0;
logic [3:0] videowe = 4'h0;
logic [31:0] videodin = 32'd0;
logic [14:0] videowaddr = 15'd0;

//wire paletteReadAddressA, paletteReadAddressB;

wire dataEnable;
wire inDisplayWindow;

wire [11:0] actual_y = video_y-12'd16;
wire [3:0] video_tile_x = video_x[9:6];		// x10 horizontal tiles of width 32
wire [3:0] video_tile_y = actual_y[9:6];	// x7 vertical tiles of width 32 (/64 instead of 32 since pixels are x2 in size)
wire [4:0] tile_pixel_x = video_x[5:1];
wire [4:0] tile_pixel_y = actual_y[5:1];

videounit VideoUnitA (
		.clocks(clocks),
		.writesenabled(1'b1),//~videopagesel), // 0->active for writes, inactive for output
		.video_x(video_x),
		.video_y(video_y),
		.waddr(videowaddr),
		.we(videowe),
		.din(videodin),
		.lanemask(15'd0), // TODO: enable to allow simultaneous writes
		.paletteindexout(paletteReadAddress/*A*/),
		.dataEnable(dataEnable/*A*/),
		.inDisplayWindow(inDisplayWindow/*A*/) );

/*videounit VideoUnitB (
		.gpuclock(clocks.gpubaseclock),
		.vgaclock(clocks.videoclock),
		.writesenabled(videopagesel), // 1->active for writes, inactive for output
		.video_x(video_x),
		.video_y(video_y),
		.waddr(videowaddr),
		.we(videowe),
		.din(videodin),
		.lanemask(15'd0),
		.paletteindexout(paletteReadAddressB),
		.dataEnable(dataEnableB),
		.inDisplayWindow(inDisplayWindowB) );

assign inDisplayWindow = videopagesel ? inDisplayWindowA : inDisplayWindowB;
assign dataEnable = videopagesel ? dataEnableA : dataEnableB;
assign paletteReadAddress = videopagesel ? paletteReadAddressA : paletteReadAddressB;*/

// ----------------------------------------------------------------------------
// Video output unit
// ----------------------------------------------------------------------------

//wire vsync_we;
wire [31:0] vsynccounter;

// TODO: find a better way to range-compress this
wire [3:0] VIDEO_B = palettedout[7:4];
wire [3:0] VIDEO_R = palettedout[15:12];
wire [3:0] VIDEO_G = palettedout[23:20];

assign gpudata.DVI_R = inDisplayWindow ? (dataEnable ? VIDEO_R : 4'b0010) : 4'h0;
assign gpudata.DVI_G = inDisplayWindow ? (dataEnable ? VIDEO_G : 4'b0010) : 4'h0;
assign gpudata.DVI_B = inDisplayWindow ? (dataEnable ? VIDEO_B : 4'b0010) : 4'h0;
assign gpudata.DVI_CLK = clocks.videoclock;
assign gpudata.DVI_DE = dataEnable;

videosignalgen VideoScanOutUnit(
	.rst_i(~axi4if.ARESETn),
	.clk_i(clocks.videoclock),		// Video clock input for 640x480 image
	.hsync_o(gpudata.DVI_HS),		// DVI horizontal sync
	.vsync_o(gpudata.DVI_VS),		// DVI vertical sync
	.counter_x(video_x),			// Video X position (in actual pixel units)
	.counter_y(video_y),			// Video Y position
	.vsynctrigger_o(vsync_we),		// High when we're OK to queue a VSYNC in FIFO
	.vsynccounter(vsynccounter) );	// Each vsync has a unique marker so that we can wait for them by name

// ----------------------------------------------------------------------------
// Domain crossing vsync fifo
// ----------------------------------------------------------------------------

/*wire [31:0] vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifovalid;

logic vsync_re;
DomainCrossSignalFifo GPUVGAVSyncQueue(
	.full(), // Not really going to get full (read clock faster than write clock)
	.din(vsynccounter),
	.wr_en(vsync_we),
	.empty(vsyncfifoempty),
	.dout(vsync_fastdomain),
	.rd_en(vsync_re),
	.wr_clk(videoclock),
	.rd_clk(gpuclock),
	.rst(reset),
	.valid(vsyncfifovalid) );

// Drain the vsync fifo and set a new vsync signal for the GPU every time we find one
// This is done in GPU clocks so we don't need to further sync the read data to GPU
always @(posedge gpuclock) begin
	vsync_re <= 1'b0;
	if (~vsyncfifoempty) begin
		vsync_re <= 1'b1;
	end
	if (vsyncfifovalid) begin
		vsyncID <= vsync_fastdomain;
	end
end*/

// ----------------------------------------------------------------------------
// GPU
// ----------------------------------------------------------------------------

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;
logic re = 1'b0;
wire [31:0] dout = 32'hFFFFFFFF;

always @(posedge axi4if.ACLK) begin
	// Write address
	case (waddrstate)
		2'b00: begin
			if (axi4if.AWVALID) begin
				writeaddress <= axi4if.AWADDR;
				axi4if.AWREADY <= 1'b1;
				waddrstate <= 2'b01;
			end
		end
		default/*2'b01*/: begin
			axi4if.AWREADY <= 1'b0;
			waddrstate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	// Write data
	videowe <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID /*& canActuallyWrite*/) begin
				// Latch the data and byte select
				// TODO: Detect which video page or command stream we're writing to via address
				//0000-7FFF: page 0
				//8000-8FFF: page 1 (i.e. writeaddress[15]==pageselect)
				//9000-....: command stream and control registers
				videowaddr <= writeaddress[16:2]; // Word aligned
				videowe <= axi4if.WSTRB;
				videodin <= axi4if.WDATA;
				axi4if.WREADY <= 1'b1;
				writestate <= 2'b01;
			end
		end
		2'b01: begin
			axi4if.WREADY <= 1'b0;
			if(axi4if.BREADY) begin
				axi4if.BVALID <= 1'b1;
				axi4if.BRESP = 2'b00; // OKAY
				writestate <= 2'b10;
			end
		end
		default/*2'b10*/: begin
			axi4if.BVALID <= 1'b0;
			writestate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b0;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin
		// Read address
		re <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					// We're ready with the addres
					axi4if.ARREADY <= 1'b1;
					// Set up for read
					re <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				axi4if.ARREADY <= 1'b0; // Can take this down after arvalid/ready handshake
				// Master ready to accept?
				if (axi4if.RREADY /*& dataActuallyRead*/) begin
					// Actually read
					axi4if.RDATA <= dout;
					// Read valid
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last entry in burst
					raddrstate <= 2'b10; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b10*/: begin
				axi4if.RVALID <= 1'b0;
				//axi4if.RLAST <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
