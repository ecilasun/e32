`timescale 1ns / 1ps

// TODO: interface to either MIG7 generated code or 3rd party one

module axi4ddr3(
	axi4.SLAVE axi4if );

axi4 dummyif(axi4if.ACLK, axi4if.ARESETn);
axi4dummy DummyDDR3(
	.axi4if(dummyif.SLAVE) );

/*
// ----------------------------------------------------------------------------
// Cache wiring
// ----------------------------------------------------------------------------

// The division of address into cache, device and byte index data is as follows
// device  tag                 line       offset  byteindex
// 0000    000 0000 0000 0000  0000 0000  000     00

// The cache behavior:
// - On cache miss:
//   - Is old cache line dirty?
//     - Y: Flush old line to DDR3, load new line
//     - N: Load new line, discard old contents
// - On cache hit:
//   - Proceed with read or write at same speed as S-RAM

logic [31:0] cwidemask	= 32'd0;	// Wide mask generate from write mask
logic [15:0] oldtag		= 16'd0;	// Previous ctag + dirty bit

logic ifetch = 1'b0;	// High for instruction load, low for data load/store
logic [14:0] ctag;		// Ignore 4 highest bits (device ID) since only r/w for DDR3 are routed here
logic [7:0] cline;		// D$:0..255, I$:256..511 via ifetch flag used as extra upper bit: {ifetch,cline}
logic [2:0] coffset;	// 8xDWORD (256bits), DWORD select line

logic cwe = 1'b0;
logic [255:0] cdin = 256'd0;
logic [15:0] ctagin = 16'd0;
wire [255:0] cdout;
wire [15:0] ctagout;

// NOTE: D$ lines with dirty bits set won't make it to I$ without a write back to DDR3
// (which only happens when tag for the cache line changes in Neko architecture)
// For now, software will read of first 2048 DWORDs from DDR3 to force writebacks of
// dirty pages to memory, ensuring I$ can see these when it tries to access them.
// However, if I$ has already accessed these pages, it will think it's already read them.
// Therefore, it's essential to implement the FENCE.I instruction.
cache IDCache(
	.clock(axi4if.ACLK),
	.we(cwe),
	.ifetch(ifetch),
	.cline(cline),
	.cdin(cdin),
	.ctagin(ctagin),
	.cdout(cdout),
	.ctagout(ctagout) );

logic loadindex = 1'b0;
logic [255:0] currentcacheline;
logic [14:0] ctagreg;

// ----------------------------------------------------------------------------
// DDR3 frontend
// ----------------------------------------------------------------------------

localparam WAIDLE = 2'd0;
localparam WAACK = 2'd1;

localparam WIDLE = 2'd0;
localparam WACCEPT = 2'd1;
localparam WDELAY = 2'd2;

localparam RIDLE = 2'd0;
localparam RCACHESETUP = 2'd1;
localparam RREAD = 2'd2;
localparam RDELAY = 2'd3;

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

always @(posedge axi4if.ACLK) begin
	// Write address
	case (waddrstate)
		WAIDLE: begin
			if (axi4if.AWVALID) begin

				ifetch <= 1'b0; // This will have to be non-instruction write at all times, with an atached FLUSH
				ctag <= axi4if.AWADDR[27:13];
				cline <= axi4if.AWADDR[12:5];
				coffset <= axi4if.AWADDR[4:2];

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

always @(posedge axi4if.ACLK) begin

	// Write data
	cwe <= 1'b0;
	case (writestate)
		WIDLE: begin
			if (axi4if.WVALID) begin // & canActuallyWrite
				// Set up wide write mask
				cwidemask <= {{8{axi4if.WSTRB[3]}}, {8{axi4if.WSTRB[2]}}, {8{axi4if.WSTRB[1]}}, {8{axi4if.WSTRB[0]}}};

				// Populate the current cache line (assuming address was written one clock earlier)
				currentcacheline <= cdout;
				oldtag <= ctagout;

				axi4if.WREADY <= 1'b1;
				writestate <= WACCEPT;
			end
		end
		WACCEPT: begin
			axi4if.WREADY <= 1'b0;
			if(axi4if.BREADY) begin
				if (oldtag[14:0] == ctag) begin // Cache hit
					cwe <= 1'b1; // Write to cache
					case (coffset)
						3'b000: cdin[31:0] <= ((~cwidemask)&currentcacheline[31:0]) | (cwidemask&axi4if.WDATA);
						3'b001: cdin[63:32] <= ((~cwidemask)&currentcacheline[63:32]) | (cwidemask&axi4if.WDATA);
						3'b010: cdin[95:64] <= ((~cwidemask)&currentcacheline[95:64]) | (cwidemask&axi4if.WDATA);
						3'b011: cdin[127:96] <= ((~cwidemask)&currentcacheline[127:96]) | (cwidemask&axi4if.WDATA);
						3'b100: cdin[159:128] <= ((~cwidemask)&currentcacheline[159:128]) | (cwidemask&axi4if.WDATA);
						3'b101: cdin[191:160] <= ((~cwidemask)&currentcacheline[191:160]) | (cwidemask&axi4if.WDATA);
						3'b110: cdin[223:192] <= ((~cwidemask)&currentcacheline[223:192]) | (cwidemask&axi4if.WDATA);
						3'b111: cdin[255:224] <= ((~cwidemask)&currentcacheline[255:224]) | (cwidemask&axi4if.WDATA);
					endcase
					// This cache line is now dirty
					ctagin[15] <= 1'b1;
					// Done
					axi4if.BVALID <= 1'b1;
					axi4if.BRESP = 2'b00; // OKAY
					writestate <= WDELAY;
				end else begin
					// Cache miss
					//ddr3rw <= 1'b1;
					//// Do we need to flush then populate?
					//if (oldtag[15]) begin
					//	// Write back old cache line contents to old address
					//	ddr3cmdin <= {1'b1, oldtag[14:0], cline, 1'b0, currentcacheline[127:0]};
					//	ddr3cmdwe <= 1'b1;
					//	busmode <= BUS_DDR3CACHESTOREHI;
					//end else begin
					//	// Load contents to new address, discarding current cache line (either evicted or discarded)
					//	ddr3cmdin <= {1'b0, ctagreg, cline, 1'b0, 128'd0};
					//	ddr3cmdwe <= 1'b1;
					//	busmode <= BUS_DDR3CACHELOADHI;
					//end
				end
			end
		end
		default: begin // WDELAY
			axi4if.BVALID <= 1'b0;
			writestate <= WIDLE;
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
		case (raddrstate)
			RIDLE: begin
				if (axi4if.ARVALID) begin

					ifetch <= 1'b0; // TODO: Need this hint from CPU side to use the correct cache
					ctag <= axi4if.AWADDR[27:13];
					cline <= axi4if.AWADDR[12:5];
					coffset <= axi4if.AWADDR[4:2];

					raddrstate <= RCACHESETUP;
				end
			end
			RCACHESETUP: begin
				// Populate the current cache line (assuming address was written at least one clock earlier)
				currentcacheline <= cdout;
				oldtag <= ctagout;
				// Ready now
				axi4if.ARREADY <= 1'b1;
				raddrstate <= RREAD;
			end
			RREAD: begin
				// Master ready to accept
				if (axi4if.RREADY) begin // & dataActuallyRead
					if (oldtag[14:0] == ctagreg) begin
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
						axi4if.ARREADY <= 1'b0;
						axi4if.RVALID <= 1'b1;
						//axi4if.RLAST <= 1'b1; // Last in burst
						raddrstate <= RDELAY; // Delay one clock for master to pull down ARVALID
					end else begin
						// Cache miss
					end
				end
			end
			default: begin // RDELAY
				// At this point master should have responded properly with ARVALID=0
				//axi4if.RLAST <= 1'b0;
				axi4if.ARREADY <= 1'b0;
				axi4if.RVALID <= 1'b0;
				raddrstate <= RIDLE;
			end
		endcase
	end
end*/

endmodule
