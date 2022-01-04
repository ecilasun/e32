`timescale 1ns / 1ps

module axi4spi(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] writeaddress = 32'd0;
logic [31:0] readaddress = 32'd0;
logic [7:0] writedata = 7'd0;
wire [7:0] readdata;
logic [3:0] we = 4'h0;

// ----------------------------------------------------------------------------
// SPI Master Device
// ----------------------------------------------------------------------------

wire cansend;

wire hasvaliddata;
wire [7:0] spiincomingdata;

// Base clock is @100MHz, therefore we're running at 25MHz (2->2x2 due to 'half'->100/4==25)
SPI_Master #(.SPI_MODE(0), .CLKS_PER_HALF_BIT(2)) SPI(
   // Control/Data Signals,
   .i_Rst_L(axi4if.ARESETn),
   .i_Clk(clocks.spibaseclock),
   
   // TX (MOSI) Signals
   .i_TX_Byte(writedata),
   .i_TX_DV( (|we) ),
   .o_TX_Ready(cansend),
   
   // RX (MISO) Signals
   .o_RX_DV(hasvaliddata),
   .o_RX_Byte(spiincomingdata),

   // SPI Interface
   .o_SPI_Clk(wires.spi_sck),
   .i_SPI_MISO(wires.spi_miso),
   .o_SPI_MOSI(wires.spi_mosi) );

assign wires.spi_cs_n = 1'b0; // Keep attached SPI device selected

// ----------------------------------------------------------------------------
// Main state machine
// ----------------------------------------------------------------------------

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
			if (axi4if.WVALID & cansend) begin
				// Latch the data and byte select
				writedata <= axi4if.WDATA;
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
	end else begin
		// Read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b1;
					readaddress <= axi4if.ARADDR;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				axi4if.ARREADY <= 1'b0;
				// Master ready to accept
				if (axi4if.RREADY & hasvaliddata) begin
					// Produce the data on the bus and assert valid
					axi4if.RDATA <= {24'h0, spiincomingdata}; // Dummy read from unmapped device
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= 2'b10; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b10*/: begin
				// At this point master should have responded properly with ARVALID=0
				axi4if.RVALID <= 1'b0;
				//axi4if.RLAST <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
