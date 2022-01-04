`timescale 1ns / 1ps

module videounit(
		FPGADeviceClocks.DEFAULT clocks,
		input wire writesenabled,
		input wire [11:0] video_x,
		input wire [11:0] video_y,
		input wire [14:0] waddr,
		input wire [3:0] we,
		input wire [31:0] din,
		input wire [14:0] lanemask,
		output wire [7:0] paletteindexout,
		output wire dataEnable,
		output wire inDisplayWindow );

logic [31:0] scanlinecache [0:127];

// Each line in the video buffer contains 48 additional dwords (192 bytes) of extra storage at the end
// This area can only be written to by the GPU
// TODO: Find a nice use for this unused memory region
//           80 DWORDS              +48 DWORDS
// |------------------------------|............|

wire [11:0] pixelY = video_y;
// In 640x400 region
assign dataEnable = (video_x < 640) && (video_y < 480);
// In 640*416 region (with no borders)
assign inDisplayWindow = (video_x < 640) && (video_y < 480); // 320*240 -> 640*480

// video addrs = (Y<<9) + X where X is from 0 to 512 but we only use the 320 section for scanout
wire [31:0] scanoutaddress = {pixelY[9:1], video_x[6:0]}; // stride of 48 at the end of scanline

wire isCachingRow = video_x > 128 ? 1'b0 : 1'b1;	// Scanline cache enabled during the first 128 clocks of scanline
wire [6:0] cachewriteaddress = video_x[6:0]-7'd1;	// One behind so that delayed clock can catch up
wire [6:0] cachereadaddress = video_x[9:3];

wire [1:0] videobyteselect = video_x[2:1];

wire [31:0] vram_data[0:14];
logic [7:0] videooutbyte;

assign paletteindexout = videooutbyte;

// Generate 13 slices of 512*16 pixels of video memory (out of which we use 320 pixels for each row)
genvar slicegen;
generate for (slicegen = 0; slicegen < 15; slicegen = slicegen + 1) begin : vram_slices
	vramslice vramslice_inst(
		// Write to the matching slice
		.addra(waddr[10:0]),
		.clka(clocks.gpubaseclock),
		.dina(din),
		.ena(1'b1),
		// If lane mask is enabled or if this vram slice is in the correct address range, enable writes
		// NOTE: lane mask enable still uses the 'we' to control which bytes to update
		.wea( writesenabled & (lanemask[slicegen] | (waddr[14:11]==slicegen[3:0])) ? we : 4'b0000 ),
		// Read out to respective vram_data elements for each slice
		.addrb(scanoutaddress[10:0]),
		.enb((scanoutaddress[14:11]==slicegen[3:0] ? 1'b1:1'b0)),
		.clkb(clocks.videoclock),
		.doutb(vram_data[slicegen]) );
end endgenerate

always @(posedge(clocks.videoclock)) begin
	if (isCachingRow) begin
		scanlinecache[cachewriteaddress] = vram_data[scanoutaddress[14:11]];
	end
end

// Copes with clock delay by shifting pixels one over
always_comb begin
	case (videobyteselect)
		2'b00: begin
			videooutbyte = scanlinecache[cachereadaddress][15:8];
		end
		2'b01: begin
			videooutbyte = scanlinecache[cachereadaddress][23:16];
		end
		2'b10: begin
			videooutbyte = scanlinecache[cachereadaddress][31:24];
		end
		default/*2'b11*/: begin
			videooutbyte = scanlinecache[cachereadaddress][7:0];
		end
	endcase
end

endmodule
