module arbiter(
    input wire [3:0] req,
    output bit [3:0] gnt = 4'hF );

// request -> grant gray

always @(*) begin
	casex (req)
		4'b0000: gnt = 4'b0000; // No req
		4'bxxx1: gnt = 4'b0001;
		4'bxx10: gnt = 4'b0010;
		4'bx100: gnt = 4'b0100;
		4'b1000: gnt = 4'b1000;
	endcase
end

endmodule
