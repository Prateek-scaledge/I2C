//////////////////////////////////////////////////////////////////
////
////
//// 	APB module to I2C Core
////
////
////
//// This file is part of the APB to I2C project
////
//// http://www.opencores.org/cores/apbi2c/
////
////
////
//// Description
////
//// Implementation of APB IP core according to
////
//// apbi2c_spec IP core specification document.
////
////
////
//// To Do: Things are right here but always all block can suffer changes
////
////
////
////
////
//// Author(s): - Felipe Fernandes Da Costa, fefe2560@gmail.com
////		  Ronal Dario Celaya
////
///////////////////////////////////////////////////////////////// 
////
////
//// Copyright (C) 2009 Authors and OPENCORES.ORG
////
////
////
//// This source file may be used and distributed without
////
//// restriction provided that this copyright statement is not
////
//// removed from the file and that any derivative work contains
//// the original copyright notice and the associated disclaimer.
////
////
//// This source file is free software; you can redistribute it
////
//// and/or modify it under the terms of the GNU Lesser General
////
//// Public License as published by the Free Software Foundation;
//// either version 2.1 of the License, or (at your option) any
////
//// later version.
////
////
////
//// This source is distributed in the hope that it will be
////
//// useful, but WITHOUT ANY WARRANTY; without even the implied
////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
////
//// PURPOSE. See the GNU Lesser General Public License for more
//// details.
////
////
////
//// You should have received a copy of the GNU Lesser General
////
//// Public License along with this source; if not, download it
////
//// from http://www.opencores.org/lgpl.shtml
////
////
///////////////////////////////////////////////////////////////////


module apb(
			//standard ARM
	    		input PCLK,
			input PRESETn,
			input PSELx,
			input PWRITE,
			input PENABLE,
			input [31:0] PADDR,
			input [31:0] PWDATA,

			//internal pin
			input [31:0] READ_DATA_ON_RX,
			input ERROR,
			input TX_EMPTY,
			input RX_EMPTY,
			input TX_FULL,
			input RX_FULL,
			
			//external pin
			output [31:0] PRDATA,

			//internal pin 
			output reg [13:0] INTERNAL_I2C_REGISTER_CONFIG,
			output reg [13:0] INTERNAL_I2C_REGISTER_TIMEOUT,
			output [31:0] WRITE_DATA_ON_TX,
			output  WR_ENA,
			output  RD_ENA,
			
			//outside port 
			output PREADY,
			output PSLVERR,

			//interruption
			output INT_RX,
			output INT_TX
	   

	  );

//internal wires for address-decode error checking
wire ADDR_VALID;
wire ADDR_ERROR;

//NEW: read-only STATUS register at offset 0x10 (16) so SW/testbench
//can poll FIFO occupancy instead of using fixed delays.
//  bit0 = TX_EMPTY   bit1 = RX_EMPTY
//  bit2 = TX_FULL    bit3 = RX_FULL
//  bit4 = ERROR
localparam [31:0] ADDR_STATUS = 32'd16;

wire [31:0] STATUS_REG;
assign STATUS_REG = {27'd0, ERROR, RX_FULL, TX_FULL, RX_EMPTY, TX_EMPTY};

//ENABLE WRITE ON TX FIFO
assign WR_ENA = (PWRITE == 1'b1 & PENABLE == 1'b1 & PADDR == 32'd0 & PSELx == 1'b1)?  1'b1:1'b0;

//ENABLE READ ON RX FIFO
assign RD_ENA = (PWRITE == 1'b0 & PENABLE == 1'b1  & PADDR == 32'd4 & PSELx == 1'b1)?  1'b1:1'b0;

//ADDRESS DECODE: 0,4,8,12,16 are valid registers
assign ADDR_VALID = (PADDR == 32'd0) | (PADDR == 32'd4) | (PADDR == 32'd8) | (PADDR == 32'd12) | (PADDR == ADDR_STATUS);

//ADDRESS ERROR: selected + enabled + address not in valid map
assign ADDR_ERROR = (PSELx == 1'b1 & PENABLE == 1'b1 & !ADDR_VALID);

//WRITE ON I2C MODULE (also complete the transfer on an invalid address, instead of hanging)
assign PREADY = ((WR_ENA == 1'b1 | RD_ENA == 1'b1 | PADDR == 32'd8 | PADDR == 32'd12 | PADDR == ADDR_STATUS | ADDR_ERROR == 1'b1) &  (PENABLE == 1'b1 & PSELx == 1'b1))? 1'b1:1'b0;

//INPUT TO WRITE ON TX FIFO
assign WRITE_DATA_ON_TX = (PSELx == 1'b1 & PENABLE == 1'b1 & PWRITE ==1'b1 & PADDR == 32'd0)? PWDATA:32'd0;

//OUTPUT DATA FROM RX/STATUS TO PRDATA
assign PRDATA = (PADDR == 32'd4 & PWRITE == 1'b0)   ? READ_DATA_ON_RX :
                 (PADDR == ADDR_STATUS) ? STATUS_REG  :
                                       32'd0;

//ERROR FROM I2C CORE OR FROM INVALID ADDRESS DECODE
assign PSLVERR = ERROR | ADDR_ERROR; 

//INTERRUPTION FROM I2C
assign INT_TX = TX_EMPTY;

//INTERRUPTION FROM I2C
assign INT_RX = RX_EMPTY;

always @(posedge PCLK)
begin
    if (!PRESETn)
    begin
        INTERNAL_I2C_REGISTER_CONFIG  <= 14'd0;
        INTERNAL_I2C_REGISTER_TIMEOUT <= 14'd0;
    end
    else
    begin
        if (PSELx && PENABLE && PWRITE && PREADY)
        begin
            case (PADDR)
                32'd8:  INTERNAL_I2C_REGISTER_CONFIG  <= PWDATA[13:0];
                32'd12: INTERNAL_I2C_REGISTER_TIMEOUT <= PWDATA[13:0];
                default: ;
            endcase
        end
    end
end


endmodule