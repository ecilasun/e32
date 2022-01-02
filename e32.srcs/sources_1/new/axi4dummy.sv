`timescale 1ns / 1ps

module axi4dummy(
	axi4.SLAVE axi4if );

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
	we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID /*& canActuallyWrite*/) begin
				// Latch the data and byte select
				din <= axi4if.WDATA[7:0];
				we <= axi4if.WSTRB;
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
		axi4if.RDATA <= dout;
	end else begin
		// Read address
		re <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b1;
					re <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// Master ready to accept
				if (axi4if.RREADY /*& dataActuallyRead*/) begin
					axi4if.ARREADY <= 1'b0;
					axi4if.RDATA <= dout;
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= 2'b10; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b10*/: begin
				// At this point master should have responded properly with ARVALID=0
				//axi4if.RLAST <= 1'b0;
				axi4if.ARREADY <= 1'b0;
				axi4if.RVALID <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
