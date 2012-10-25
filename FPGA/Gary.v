// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//
// This is Gary
// It is the equivalent of Gary in a real Amiga
// Gary handles the address decoding and cpu/chip bus multiplexing
// Gary handles kickstart area and bootrom overlay
// Gary handles CIA e clock synchronization
//
// 20-12-2005		-started coding
// 21-12-2005		-done more coding
// 25-12-2005		-changed blitter nasty handling
// 15-01-2006		-fixed sensitivity list
// 12-11-2006		-debugging for new Minimig rev1.0 board
// 17-11-2006		-removed debugging and added decode for $C0000 ram

module gary(	clk,e,cpuaddress,cpurd,cpuhwr,cpulwr,cpuok,
			dma,dmawr,dmapri,ovl,boot,
			rd,hwr,lwr,selreg,selchip,selslow,selciaa,selciab,selkick,selboot);
input	clk;				//bus clock
input	e;				//e clock enable

input 	[23:12]cpuaddress;	//cpu address inputs
input	cpurd;			//cpu read
input	cpuhwr;			//cpu high write
input	cpulwr;			//cpu low write
output	cpuok;			//cpu slot ok
input	dma;				//agnus needs bus
input	dmawr;			//agnus does a write cycle
input	dmapri;			//agnus blitter has priority
input	ovl;				//overlay kickstart rom over chipram
input	boot;			//overlay bootrom over chipram

output	rd;				//bus read
output	hwr;				//bus high write
output	lwr;				//bus low write
output 	selreg;  			//select chip register bank
output 	selchip; 			//select chip memory
output	selslow;			//select slowfast memory ($C0000)
output 	selciaa;			//select cia A
output 	selciab; 			//select cia B
output 	selkick;	    		//select kickstart rom
output	selboot;			//select boot room


//local signals
reg		cpuok;			//see above
reg		selreg;			//see above
reg		selchip;			//see above
reg		selslow;			//see above
reg		selkick;			//see above
reg		selboot;			//see above
reg		ecpu;			//e clock synchronized to CPU available cycles

//--------------------------------------------------------------------------------------

//synchronize e clock to CPU available cycles
always @(posedge clk)
	if(!dma)
		ecpu<=e;
	else if(dma && e)
		ecpu<=e;

//--------------------------------------------------------------------------------------

//read write control signals
assign rd=cpurd|(~dmawr&dma);
assign hwr=cpuhwr|(dmawr&dma);
assign lwr=cpulwr|(dmawr&dma);

//--------------------------------------------------------------------------------------

//bus master logic
always @(	dma or dmapri or ecpu or selchip or selreg or selciaa or selciab)
begin
	if(dma)//bus slot allocated to agnus
		cpuok=0;
	else if((selreg||selchip) && dmapri)//cpu wait state, dma has priority in register and chipram area
		cpuok=0;
	else if((selciaa||selciab) && !ecpu)//cpu wait state, slow access to CIA's
		cpuok=0;
	else//bus slot allocated to cpu
		cpuok=1;
end

//--------------------------------------------------------------------------------------

//chipram, kickstart and bootrom address decode
always @(dma or cpuaddress or boot or ovl)
begin
	if(dma)//agnus always accesses chipram
	begin
		selchip=1;
		selkick=0;
		selboot=0;
	end
	else if(cpuaddress[23:19]==5'b11111)//kickstart
	begin
		selchip=0;
		selkick=1;
		selboot=0;
	end
	else if((cpuaddress[23:21]==3'b000) && boot)//chipram area in boot mode
	begin
		if(cpuaddress[20:12]==0)//lower part bootrom area
		begin
			selchip=0;
			selkick=0;
			selboot=1;
		end
		else//upper part chipram area
		begin
			selchip=1;
			selkick=0;
			selboot=0;
		end
	end
	else if((cpuaddress[23:21]==3'b000) && !boot)//chipram area in normal mode
	begin
		selchip=~ovl;//chipram when no rom overlay
		selkick=ovl;//kickstart when rom overlay
		selboot=0;
	end
	else//no kickstart, bootrom or chipram selected
	begin
		selchip=0;
		selkick=0;
		selboot=0;
	end
end

//chip register bank and slowram address decode
always @(cpuaddress or dma)
begin
	if((cpuaddress[23:19]==5'b11000) && !dma)//slow ram at $C00000 - $C7FFFF
	begin
		selreg=0;
		selslow=1;
	end
	else if ((cpuaddress[23:21]==3'b110) && !dma)//chip registers at &C80000 - $DFFFFF
	begin
		selreg=1;
		selslow=0;
	end
	else
	begin
		selreg=0;
		selslow=0;
	end
end

//assign selreg=((cpuaddress[23:21]==3'b110) && !dma)?1:0;
//assign selslow=0;

//cia a address decode
assign selciaa=((cpuaddress[23:21]==3'b101) && !cpuaddress[12] && !dma)?1:0;

//cia b address decode
assign selciab=((cpuaddress[23:21]==3'b101) && !cpuaddress[13] && !dma)?1:0;

endmodule
