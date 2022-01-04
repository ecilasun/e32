`timescale 1ns / 1ps

// TODO: interface to either MIG7 generated code or 3rd party one

module axi4ddr3(
	axi4.SLAVE axi4if );

// ----------------------------------------------------------------------------
// DDR3 frontend
// ----------------------------------------------------------------------------

localparam WAIDLE = 2'd0;
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
end

endmodule
