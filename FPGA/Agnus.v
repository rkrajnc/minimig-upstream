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
// This is Agnus 
// The copper, blitter and sprite dma have a reqdma output and an ackdma input
// if they are ready for dma they do a dma request by asserting reqdma
// the dma priority logic circuit then checks which module is granted access by 
// looking at their priorities and asserting the ackdma signal of the module that
// has the highest priority
//
// Other dma channels (bitplane, audio and disk) only have an enable input (bitplane)
// or only a dma request input from Paula (dmal input, disk and audio) 
// and an dma output to indicate that they are using their slot.
// this is because they have the highest priority in the system and cannot be hold up
//
// The bus clock runs at 7.09MHz which is twice as fast as in the original amiga and
// the same as the pixel clock / horizontal beam counter.
//
// general cycle allocation is as follows:
// (lowest 2 bits of horizontal beam counter)
//
// slot 0:	68000 (priority in that order, extra slots because of higher bus speed)
// slot 1:	disk, bitplanes, copper, blitter and 68000 (priority in that order)   	
// slot 2:	blitter and 68000 (priority in that order, extra slots because of higher bus speed)
// slot 3:	disk, bitplanes, sprites, audio and 68000 (priority in that order)
//
// because only the odd slots are used by the chipset, the chipset runs at the same 
// virtual speed as the original. The cpu gets the extra even slots allowing for
// faster cpu's without the need for an extra fastram controller
// Blitter timing is not completely accurate, it uses slot 1 and 2 instead of 1 and 3, this is to let
// the blitter not slow down too much dma contention. (most compatible solution for now)
// Blitter nasty mode activates the buspri signal to indicate to gary to stop access to the chipram/chipregisters.
// Blitter nasty mode is only activated if blitter activates bltpri cause it depends on blitter settings if blitter
// will really block the cpu.
//
// 19-03-2005		-first serious version
//				-added clock generator
// 20-03-2005		-fixed regaddress idle state
// 				-more reliable 3-state timing
// 27-03-2005		-fixed bug in regadress generator, adress was not set to idle if
//				 chip bus was idle (hwr,lwr and rd low)
// 10-04-2005		-added real clock generator
// 11-04-2005		-removed rd,hwr and lwr signals due to change in address decoder
// 24-04-2005		-adapted to new 7.09 MHz bus clock
// 				-added more complete dmaslot controller
// 25-04-2005		-continued work on beam counters
// 26-04-2005		-continued work on beam counters
// 02-05-2005		-moved beam counter to seperate module
//				-done work on bitplane dma engine
// 05-05-2005		-completed first version of bitplane dma engine (will it work ?)
//				-adapted code for bitplane dma engine
// 15-05-2005		-added horbeam reset output and start of vertical blank interrupt output
//				-fixed small bug in bpldma_engine
//				-changed horizontal sync/blank timing so image is centered on screen
//				-made some changes to interlaced vertical sync timing
//17-05-2005		-fixed bug in bpldma_engine, modulo was not added right
//18-05-2005		-fixed hires bitplane data fetch
//				-interlaced is now selected through bplcon0
//22-05-2005		-changed name of diwstrt/stop to vdiwstrt/stop to make code clearer
//29-05-2005		-added copper but its needs some more work to be integrated properly
//31-05-2005		-added support for negative modulo in bitplane dma engine
//				-integrated copper better
//06-06-2005		-started coding of sprite dma engine
//				-cleaned up code a bit (comments, spaces between lines and so on)
//07-06-2005		-done work on sprite dma engine
//08-06-2005		-done more work on sprite dma engine
//12-06-2005		-first finished version of sprite dma engine
//				-integrated sprite dma engine into agnus
//28-06-2005		-delayed horizontal sync/blanking by 2 low res pixels to compensate
//				 for pipelining delay in Denise
//19-07-2005		-changed phase of cpu clock in an attempt to solve kickstart boot problem
//20-07-2005		-changed phase of cpu clock back again, it was not the problem..
//31-07-2005		-fixed bbusy to 1 as it is not yet implemented
//07-08-2005		-added ersy bit, if enabled the beamcounters stop counting
//				-bit 11 and 12 of dmacon are now also implemented
//04-09-2005		-added blitter finished interrupt
//				-added blitter
//05-09-2005		-did some dma cycle allocation testing
//11-09-2005		-testing
//18-09-2005		-removed ersy support, this seems to cure part of the kickstart 1.2 problems
//20-09-2005		-testing
//21-09-2005		-added copper disable input for testing
//23-09-2005		-moved VPOSR/VHPOSR handling to beamcounter module
//				-added VPOS/VHPOSW registers
//19-10-2005		-removed burst clock and cck (color clock enable) outputs
//				-removed hcres,vertb and intb outputs
//				-added sol,sof and int3 outputs
//				-adapted code to use new signals
//23-10-2005		-added dmal signal
//				-added disk dma engine
//21-10-2005		-fixed bug in disk dma engine, DSKDATR and DSKDAT addresses were swapped
//04-12-2005		-added magic mystery logic to handle ddfstrt/ddfstop
//14-12-2005		-fixed some sensitivity lists
//21-12-2005		-added rd,hwr and lwr inputs
//				-added bus,buswr and buspri outputs
//26-12-2005		-fixed buspri output
//				-changed blitter nasty mode altogether, it is now not according to the HRM,
//				 but at least this solution seems to work for most games/demos
//27-12-2005		-added audio dma engine
//28-12-2005		-fixed audio dma engine
//29-12-2005		-rewritten audio dma engine
//03-01-2006		-added dmas to avoid interference with copper cycles
//07-01-2006		-also added dmas to disk dma engine
//11-01-2006		-removed ability to write beam counters
//22-01-2006		-removed composite sync output
//				-added ddfstrt/ddfstop HW limits
//23-01-2006		-added fastblitter enable input
//25-01-2006		-improved blitter nasty timing
//14-02-2006		-again improved blitter timing, this seems the most compatible solution for now..
//19-02-2006		-again improved blitter timing, this is an even more compatible solution

//JB:
//2008-07-17		- modified display dma engine to be more compatible
//					- moved beamcounters to separate module
//					- heavily modified sprite dma engine

module Agnus
(
	input 	clk,					//clock
	input	clk28m,					//28MHz clock
	input	reset,					//reset
	input 	aen,					//bus adress enable (register bank)
	input	rd,						//bus read
	input	hwr,					//bus high write
	input	lwr,					//bus low write
	input	[15:0]datain,			//data bus in
	output	[15:0]dataout,		//data bus out
	input 	[8:1]addressin,		//256 words (512 bytes) adress input,
	output	reg [20:1]addressout,	//chip address output,
	output 	reg [8:1]regaddress,	//256 words (512 bytes) register address out,
	output	reg bus,				//agnus needs bus
	output	reg buswr,				//agnus does a write cycle
	output	buspri,					//agnus blitter has priority in chipram
	output	_hsync,					//horizontal sync
	output	_vsync,					//vertical sync
	output	blank,					//video blanking
	output	sol,					//start of video line (active during last pixel of previous line) 
	output	sof,					//start of video frame (active during last pixel of previous frame)
	output	strhor,					//horizontal strobe for Denise (helps to solve some extreme overscan isues)
	output	int3,					//blitter finished interrupt (to Paula)
	input	dmal,					//dma request (from Paula)
	input	dmas,					//dma special (from Paula)
	input	ntsc,					//chip is NTSC
	input	fastchip				//DEBUG fast chipram access enable
);

//register names and adresses		
parameter DMACON  = 9'h096;
parameter DMACONR = 9'h002;
parameter DIWSTRT = 9'h08e;
parameter DIWSTOP = 9'h090;

//local signals
reg		[15:0]dmaconr;		//dma control read register

wire	[8:0]horbeam;			//horizontal beam counter
wire	[10:0]verbeam;		//vertical beam counter
wire	interlace;				//interlace enable

wire	vbl;					///JB: vertical blanking
wire	vblend;					///JB: last line of vertical blanking

wire	bbusy;					//blitter busy status
wire	bzero;					//blitter zero status
wire	bblck;					//blitter blocks cpu
wire	bltpri;					//blitter nasty
wire	bplen;					//bitplane dma enable
wire	copen;					//copper dma enable
wire	blten;					//blitter dma enable
wire	spren;					//sprite dma enable

reg		[15:8]vdiwstrt;		//vertical window start position
reg		[15:8]vdiwstop;		//vertical window stop position

wire	dma_bpl;				//bitplane dma engine uses it's slot
wire	dma_dsk;				//disk dma uses it's slot
wire	dma_aud;				//audio dma uses it's slot
reg		ack_cop;				//copper dma acknowledge
wire	req_cop; 				//copper dma request
reg		ack_blt;				//blitter dma acknowledge
wire	req_blt; 				//blitter dma request
reg		ack_spr;				//sprite dma acknowledge
wire	req_spr; 				//sprite dma request
wire	[15:0]data_bmc;		//beam counter data out
wire	[20:1]address_dsk;	//disk dma engine chip address out
wire	[8:1]regaddress_dsk; 	//disk dma engine register address out
wire	wr_dsk;					//disk dma engine write enable out
wire	[20:1]address_aud;	//audio dma engine chip address out
wire	[8:1]regaddress_aud; 	//audio dma engine register address out
wire	[20:1]address_bpl;	//bitplane dma engine chip address out
wire	[8:1]regaddress_bpl; 	//bitplane dma engine register address out
wire	[20:1]address_spr;	//sprite dma engine chip address out
wire	[8:1]regaddress_spr; 	//sprite dma engine register address out
wire	[20:1]address_cop;	//copper dma engine chip address out
wire	[8:1]regaddress_cop; 	//copper dma engine register address out
wire	[20:1]address_blt;	//blitter dma engine chip address out
wire	[15:0]data_blt;		//blitter dma engine data out
wire	wr_blt;					//blitter dma engine write enable out
wire	[8:1]regaddress_cpu;	//cpu register address

//--------------------------------------------------------------------------------------

//data out multiplexer
assign dataout=data_bmc|dmaconr|data_blt;

//cpu address decoder
assign regaddress_cpu=(aen&(rd|hwr|lwr))?addressin:8'hff;

//blitter nasty mode output (blocks cpu)
//(when blitter dma is active AND blitter nasty mode is on AND blitter indicates to block cpu)
//(also when fastchip is false, all even cycles are also blocked giving A500 chipram speed)
assign buspri=(blten&bltpri&bblck) | (~horbeam[0]&~fastchip);

//--------------------------------------------------------------------------------------

//chip address, register address and control signal multiplexer
//AND dma priority handler
//first item in this if else if list has highest priority
always @(	dma_dsk or address_dsk or regaddress_dsk or wr_dsk or
		dma_aud or address_aud or regaddress_aud or
		dma_bpl or address_bpl or regaddress_bpl or req_cop or 
		copen or address_cop or regaddress_cop or regaddress_cpu
		or spren or req_spr or address_spr or regaddress_spr
		or blten or req_blt or address_blt or wr_blt)
begin
	if(dma_dsk)//busses allocated to disk dma engine
	begin
		bus=1;
		ack_cop=0;
		ack_blt=0;
		ack_spr=0;
		addressout=address_dsk;
		regaddress=regaddress_dsk;
		buswr=wr_dsk;
	end
	else if(dma_aud)//busses allocated to audio dma engine
	begin
		bus=1;
		ack_cop=0;
		ack_blt=0;
		ack_spr=0;
		addressout=address_aud;
		regaddress=regaddress_aud;
		buswr=0;
	end
	else if(dma_bpl)//busses allocated to bitplane dma engine
	begin
		bus=1;
		ack_cop=0;
		ack_blt=0;
		ack_spr=0;
		addressout=address_bpl;
		regaddress=regaddress_bpl;
		buswr=0;
	end
	else if(req_spr && spren)//busses allocated to sprite dma engine
	begin
		bus=1;
		ack_cop=0;
		ack_blt=0;
		ack_spr=1;
		addressout=address_spr;
		regaddress=regaddress_spr;
		buswr=0;
	end
	else if(req_cop && copen)//busses allocated to copper
	begin
		bus=1;
		ack_cop=1;
		ack_blt=0;
		ack_spr=0;
		addressout=address_cop;
		regaddress=regaddress_cop;
		buswr=0;
	end
	else if(req_blt && blten)//busses allocated to blitter
	begin
		bus=1;
		ack_cop=0;
		ack_blt=1;
		ack_spr=0;
		addressout=address_blt;
		regaddress=8'hff;
		buswr=wr_blt;
	end
	else//busses not allocated by agnus
	begin
		bus=0;
		ack_cop=0;
		ack_blt=0;
		ack_spr=0;
		addressout=0;
		regaddress=regaddress_cpu;//pass register addresses from cpu address bus
		buswr=0;
	end
end

//--------------------------------------------------------------------------------------

reg	[12:0]dmacon;

//dma control register read
always @(regaddress or bbusy or bzero or dmacon)
	if(regaddress[8:1]==DMACONR[8:1])
		dmaconr[15:0]<={1'b0,bbusy,bzero,dmacon[12:0]};
	else
		dmaconr<=0;

//dma control register write
always @(posedge clk)
	if(reset)
		dmacon<=0;
	else if(regaddress[8:1]==DMACON[8:1])
	begin
		if(datain[15])
			dmacon[12:0]<=dmacon[12:0]|datain[12:0];
		else
			dmacon[12:0]<=dmacon[12:0]&(~datain[12:0]);	
	end

//assign dma enable bits
assign	bltpri=dmacon[10];
assign	bplen=dmacon[8]&dmacon[9];
assign	copen=dmacon[7]&dmacon[9];
assign	blten=dmacon[6]&dmacon[9];
assign	spren=dmacon[5]&dmacon[9];
										
//--------------------------------------------------------------------------------------

//write diwstart and diwstop registers
always @(posedge clk)
	if(regaddress[8:1]==DIWSTRT[8:1])
		vdiwstrt[15:8]<=datain[15:8];
always @(posedge clk)
	if(regaddress[8:1]==DIWSTOP[8:1])
		vdiwstop[15:8]<=datain[15:8];

//--------------------------------------------------------------------------------------

//instantiate disk dma engine
dskdma_engine dsk1
(
	.clk(clk),
	.dma(dma_dsk),
	.dmal(dmal),
	.dmas(dmas),
	.horbeam(horbeam),
	.wr(wr_dsk),
	.regaddressin(regaddress),
	.regaddressout(regaddress_dsk),
	.datain(datain),
	.addressout(address_dsk)	
);

//--------------------------------------------------------------------------------------

//instantiate audio dma engine
auddma_engine aud1
(
	.clk(clk),
	.dma(dma_aud),
	.dmal(dmal),
	.dmas(dmas),
	.horbeam(horbeam),
	.regaddressin(regaddress),
	.regaddressout(regaddress_aud),
	.datain(datain),
	.addressout(address_aud)
);

//--------------------------------------------------------------------------------------

//instantiate bitplane dma
reg	bplenable;
always @(bplen or verbeam or vdiwstrt or vdiwstop)//bitplane dma enabled if vertical beamcounter within limits set by diwstrt and diwstop
	if(bplen && (verbeam[8:0]>={1'b0,vdiwstrt[15:8]}) && (verbeam[8:0]<{~vdiwstop[15],vdiwstop[15:8]}))
		bplenable=1;
	else
		bplenable=0;
		
bpldma_engine bpd1
(
	.clk(clk),
	.reset(reset),
	.enable(bplenable),
	.horbeam(horbeam),
	.dma(dma_bpl),
	.interlace(interlace),
	.regaddressin(regaddress),
	.regaddressout(regaddress_bpl),
	.datain(datain),
	.addressout(address_bpl)	
);

//--------------------------------------------------------------------------------------

//instantiate sprite dma engine
sprdma_engine spr1
(
	.clk(clk),
	.clk28m(clk28m),
	.reqdma(req_spr),
	.ackdma(ack_spr),
	.hpos(horbeam),
	.vpos(verbeam),
	.vbl(vbl),
	.vblend(vblend),
	.regaddressin(regaddress),
	.regaddressout(regaddress_spr),
	.datain(datain),
	.addressout(address_spr)	
);

//--------------------------------------------------------------------------------------

//instantiate copper
copper cp1
(
	.clk(clk),
	.reset(reset),
	.reqdma(req_cop),
	.ackdma(ack_cop),
	.sof(sof),
	.eol(sol),
	.bbusy(bbusy),
	.vpos(verbeam[7:0]),
	.datain(datain),
	.regaddressin(regaddress),
	.regaddressout(regaddress_cop),
	.addressout(address_cop)	
);

//--------------------------------------------------------------------------------------

//instantiate blitter
blitter bl1
(
	.clk(clk),
	.reset(reset),
	.reqdma(req_blt),
	.ackdma(ack_blt),
	.bzero(bzero),
	.bbusy(bbusy),
	.bblck(bblck),
	.horbeam(horbeam[0]^horbeam[1]),//HACK, avoid dma contention a bit
	.wr(wr_blt),
	.datain(datain),
	.dataout(data_blt),
	.regaddressin(regaddress),
	.addressout(address_blt)	
);

//generate blitter finished intterupt (int3)
reg bbusyd;
always @(posedge clk)
	bbusyd<=bbusy;
assign int3=(~bbusy)&bbusyd;

//--------------------------------------------------------------------------------------

//instantiate beam counters
beamcounter	bc1
(	
	.clk(clk),
	.reset(reset),
	.interlace(interlace),
	.ntsc(ntsc),
	.datain(datain),
	.dataout(data_bmc),
	.regaddressin(regaddress),
	.hpos(horbeam),
	.vpos(verbeam),
	._hsync(_hsync),
	._vsync(_vsync),
	.blank(blank),
	.vbl(vbl),
	.vblend(vblend),
	.eol(sol),
	.eof(sof)
);

//horizontal strobe for Denise
assign strhor = horbeam==15 ? 1 : 0;

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//bit plane dma engine
module bpldma_engine
(
	input 	clk,		    			//bus clock
	input	reset,						//reset
	input	enable,						//enable dma input
	input	[8:0]horbeam,				//horizontal beam counter
	output	reg dma,					//true if bitplane dma engine uses it's cycle
	output	reg interlace,				//interlace mode is selected through bplcon0
	input 	[8:1]regaddressin,		//register address inputs
	output 	reg [8:1]regaddressout,	//register address outputs
	input	[15:0]datain,				//bus data in
	output	[20:1]addressout			//chip address out
);

//register names and adresses		
parameter BPLPTBASE=9'h0e0;	//bitplane pointers base address
parameter DDFSTRT=9'h092;		
parameter DDFSTOP=9'h094;
parameter BPL1MOD=9'h108;
parameter BPL2MOD=9'h10a;
parameter BPLCON0=9'h100;
parameter BPLCON1=9'h102;		//JB: needed for better ddfstrt/ddfstop handling

//local signals
reg		[8:2]ddfstrt;			//display data fetch start //JB: added bit #2
reg 	[8:2]ddfstop; 		//display data fetch stop //JB: added bit #2
reg		[15:1]bpl1mod;		//modulo for odd bitplanes
reg		[15:1]bpl2mod;		//modulo for even bitplanes
reg		[15:12]bplcon0;		//bitplane control (HIRES and BPU bits)
reg		[7:0]bplcon1;	 		//JB:
reg 	hires;				 	//JB:
reg		shres;				 	//JB:

reg		[20:1]newpt;			//new pointer				
reg 	[20:16]bplpth[7:0];	//upper 5 bits bitplane pointers
reg 	[15:1]bplptl[7:0];	//lower 16 bits bitplane pointers
reg		[2:0]plane;			//plane pointer select

wire	mod;					//end of data fetch, add modulo	//JB: changed reg to wire

//--------------------------------------------------------------------------------------

//register bank address multiplexer
wire [2:0]select;
assign select=(dma)?plane:regaddressin[4:2];

//high word pointer register bank (implemented using distributed ram)
wire [20:16]bplpth_in;
assign bplpth_in=(dma)?newpt[20:16]:datain[4:0];
always @(posedge clk)
	if(dma || ((regaddressin[8:5]==BPLPTBASE[8:5]) && !regaddressin[1]))//if bitplane dma cycle or bus write
		bplpth[select]<=bplpth_in;
assign addressout[20:16]=bplpth[plane];

//low word pointer register bank (implemented using distributed ram)
wire [15:1]bplptl_in;
assign bplptl_in=(dma)?newpt[15:1]:datain[15:1];
always @(posedge clk)
	if(dma || ((regaddressin[8:5]==BPLPTBASE[8:5]) && regaddressin[1]))//if bitplane dma cycle or bus write
		bplptl[select]<=bplptl_in;
assign addressout[15:1]=bplptl[plane];

//--------------------------------------------------------------------------------------

//write ddfstrt and ddfstop registers
always @(posedge clk)
	if(regaddressin[8:1]==DDFSTRT[8:1])
		if (datain[7:1] < 7'b0001_100)
			ddfstrt[8:2] <= 7'b0001_100;
		else
			ddfstrt[8:2]<=datain[7:1];			//JB: added LSB
		
always @(posedge clk)
	if(regaddressin[8:1]==DDFSTOP[8:1])
		if (datain[7:1] > 7'b1101_100)
			ddfstop[8:2] <= 7'b1101_100;
		else
			ddfstop[8:2] <= datain[7:1];		//JB: added LSB

//write modulo registers
always @(posedge clk)
	if(regaddressin[8:1]==BPL1MOD[8:1])
		bpl1mod[15:1]<=datain[15:1];
always @(posedge clk)
	if(regaddressin[8:1]==BPL2MOD[8:1])
		bpl2mod[15:1]<=datain[15:1];

//write parts of bplcon0 register that are relevant to bitplane dma + interlace and ersy
always @(posedge clk)
	if(reset)
	begin
		bplcon0[15:12]<=4'b0000;
		interlace<=0;
		hires <= 0;	//JB:
		shres <= 0;	//JB:
	end
	else if(regaddressin[8:1]==BPLCON0[8:1])
	begin
		bplcon0[15:12]<=datain[15:12];
		interlace<=datain[2];
		hires <= datain[15];	//JB:
		shres <= datain[6];	//JB:
	end

//JB: needed for better ddf handling
//write part of bplcon1 register
always @(posedge clk)
	if (regaddressin[8:1] == BPLCON1[8:1])
		bplcon1[7:0] <= datain[7:0];


//--------------------------------------------------------------------------------------
// (JB) More on mystical magic investigation after some experiments with my real A4k:
// H3/H2 bits in DDFSTRT and DDFSTOP registers are important in all resolutions.
// LORES:
// if H3 or H2 of DDFSTRT is set the display is delayed by one full dma fetch cycle (8 colour clocks [cck])
// it means that the display stop position is also shifted by 16 lowres pixels eventhough DDFSTOP hasn't changed
// if H3:H2 of DDFSTOP is greater than H3:H2 of DDFSTRT the display is stopped after an extra dma cycle
//   (extra 16 pixels fetched in lowres, 32 in hires and 64 in super hires)
// if the DDFSTOP is close enough to the HTOTAL value in some cases the dma engine doesn't see a display stop
// and total display corruption happens, i.e:
//  DDFSTOP=$D4 and DDFSTRT[3:2]=%01,
//  DDFSTOP=$D6 and (DDFSTRT[3:2]=%01 or DDFSTRT[3:2]=%10),
//  DDFSTOP>=$D8 and DDFSTRT[3:2]!=%00 
//  if DDFSTOP > $D8 and DDFSTRT[3:2]=%00 the display stops at $D8 (hardware stop)
// in lores dma cycles always begin and end on 8 colour clock (cck) cycle boundary
// HIRES:
// dma cycles can start and stop on 4 cck boundary and always last 8 ccks
// if H2 of DDFSTART is set the display starts on next 4 cck boundary
// (the display is a multiple of 32 hires pixels)
// SUPER HIRES:
// dma cycles can start and stop on 2 cck boundary and always last 8 ccks
// (the display is a multiple of 64 super hires pixels)
// in all resolutions the dma engine fetch cycle lasts 8 colour clocks
// it can start at a multiple of: 8 cck's in lowres, 4 cck's in hires and 2 cck's in super hires
// hint: SHRES bit in BPLCON0 takes precedence over HIRES bit
// all tests were performed with FMODE=0
// more magic: ddfstrt is delayed by one fetch cycle only if ddfstrt[3:2]>bplcon1[3:2] (tested only under UAE)


wire	[8:2]ddf_start;
reg 	[3:2]ddfstrt_latched;
reg 	[3:2]ddf_start_latched;
reg		[3:2]bplcon1_latched;
wire	[8:2]ddf_stop;
wire	[8:2]ddf_stop_delay;
reg		ddf_enable;
wire	[8:2]ddf_mask;

assign ddf_mask = shres ? 7'b000_0000 : hires ? 7'b000_0001 : 7'b000_0011;

//this should be rewritten someday to use more efficient code
assign ddf_start = ddfstrt-7'd1-bplcon1[3:2] | ddf_mask;
assign ddf_stop_delay = ddfstop[3:2] > ddfstrt_latched[3:2] ? 7'd4 : 7'd0;
assign ddf_stop = ({ddfstop[8:4],ddfstrt_latched[3:2]}-7'd1-bplcon1_latched[3:2] | ddf_mask) + ddf_stop_delay; 

//display dma last cycle
reg	  ddf_last_fetch;

// changing ddfstrt register value when display has already started doesn't affect the stop condition
// so we have to store the initial value of ddfstrt to determine stop condition (only two bits do matter)
always @(posedge clk)
	if (reset)
	begin
		ddfstrt_latched <= 2'b00;
		ddf_start_latched <= 2'b00;
		bplcon1_latched <= 2'b00;
	end
	else if ({ddf_start,2'b11} == horbeam[8:0])
	begin
		ddfstrt_latched[3:2] <= ddfstrt[3:2];
		ddf_start_latched[3:2] <= ddf_start[3:2];
		bplcon1_latched <= bplcon1[3:2];
	end

always @(posedge clk)
	if (reset)
		ddf_last_fetch <= 0;
	else if ({ddf_stop,2'b11} == horbeam[8:0])
		ddf_last_fetch <= ddf_enable;
	else if ({ddf_start_latched[3:2],2'b11} == horbeam[3:0])
		ddf_last_fetch <= 0;
	
always @(posedge clk)
	if (reset)
		ddf_enable <= 0;
	else if ({ddf_start,2'b11} == horbeam[8:0])
		ddf_enable <= 1;
	else if (ddf_last_fetch && {ddf_start_latched[3:2],2'b11} == horbeam[3:0])
		ddf_enable <= 0;

assign mod = (ddf_last_fetch) & (hires ? horbeam[3]^ddfstrt_latched[3] : shres ? (&(horbeam[3:2]^ddfstrt_latched[3:2])): 1'b1);

assign ddfenable = ddf_enable;

always @(shres or hires or horbeam)
	if (shres)
		plane = {2'b00,~horbeam[1]};
	else if (hires)
		plane = {1'b0,~horbeam[1],~horbeam[2]};
	else
		plane = {~horbeam[1],~horbeam[2],~horbeam[3]};

//generate dma signal
//for a dma to happen plane must be less than BPU (bplcon0), dma must be enabled
//(enable) and datafetch compares must be true (ddfenable)
//because invalid slots are coded as plane=7, the compare with BPU is
//automatically false
always @(plane or bplcon0[14:12] or horbeam[0] or enable or ddfenable)
begin
	if(ddfenable && enable && horbeam[0])//if dma enabled and within ddf limits and dma slot
	begin
		if(plane[2:0]<bplcon0[14:12])//if valid plane
			dma=1;
		else
			dma=0;
	end
	else
		dma=0;
end

//--------------------------------------------------------------------------------------

//dma pointer arithmetic unit
always @(addressout or bpl1mod or bpl2mod or plane[0] or mod)
	if(mod)
	begin
		if(plane[0])//even plane	modulo
			newpt[20:1]=addressout[20:1]+{bpl2mod[15],bpl2mod[15],bpl2mod[15],bpl2mod[15],bpl2mod[15],bpl2mod[15:1]}+1;
		else//odd plane modulo
			newpt[20:1]=addressout[20:1]+{bpl1mod[15],bpl1mod[15],bpl1mod[15],bpl1mod[15],bpl1mod[15],bpl1mod[15:1]}+1;
	end
	else
		newpt[20:1]=addressout[20:1]+1;

//Denise bitplane shift registers address lookup table
always @(plane)
begin
	case(plane)
		3'b000:	regaddressout[8:1]=8'h88;
		3'b001:	regaddressout[8:1]=8'h89;
		3'b010:	regaddressout[8:1]=8'h8a;
		3'b011:	regaddressout[8:1]=8'h8b;
		3'b100:	regaddressout[8:1]=8'h8c;
		3'b101:	regaddressout[8:1]=8'h8d;
		default:	regaddressout[8:1]=8'hff;
	endcase
end

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
/*
JB: some conclusions of sprite engine investigation, it seems to be as follows:
- during vblank sprite dma is disabled by hardware, no automatic fetches occur but copper or cpu
can write to any sprite register, and all SPRxPTR pointers should be refreshed
- during the last line of vblank (PAL: $19, NTSC: $14) if sprite dma is enabled
it fetches SPRxPOS/SPRxCTL registers according to current SPRxPTR pointers
	This is the only chance for DMA to fetch new values of SPRxPOS/SPRxCTL. If DMA isn't enabled
during this line new values won't be placed into SPRxPOS/SPRxCTL registers.
	Enabling DMA after this line can have two results depending on current value of SPRxPOS/SPRxCTL.
- if VSTOP value is matched first with VERBEAM, data from memory is fetched and placed into SPRxPOS/SPRxCTL
- or if VSTART value is matched with VERBEAM, data from memory is fetched and placed into SPRxDATA/SPRxDATB 
  and the situation repeats with every new line until VSTOP condition is met.
The VSTOP condition takes precedence.
	If you set VSTART to value lower or the same (remember that VSTOP takes precedence) as the current VERBEAM
this condition will never be met and sprite engine will wait till VSTOP matches VERBEAM. If it happens then it
fetches another two words into SPRxPOS/SPRxCTL. And again if new VSTART is lower or the same as VERBEAM
it will fetch another new SPRxPOS/SPRxCTL when VSTOP is met (or will wait till next vbl).
	To disable further sprite list processing it's enough to set VSTART and VSTOP to values which are outside
of the screen or has been already achieved.

	When waiting for VSTART condition any write to SPRxDATA (write to SPRxDATB takes no effect) makes the written value
visible on the screen but it doesn't start DMA although it's enabled. The same value is displayed in every subsequent 
line until DMA starts and delivers new data to SPRxDAT or SPRxCTL is written (by DMA, copper or cpu).
It seems like only VSTART condition starts DMA transfer.
	Any write to SPRxCTL while DMA is active doesn't stop display but new value of VSTOP takes effect. Actually 
display is reenabled by DMA write to SPRxDATA in next line.
	The same applies to SPRxPOS writes when sprite is beeing displayed - only HSTART position changes (if new VSTART
is specified to be met before VSTOP nothing interesting happens).

	The DMA engine sees VSTART condition as true even if DMA is dissabled. Enabling DMA after VSTART and before VSTOP
starts sprite display in enabled line (if it's enabled early enough).
	Dissabling DMA in the line when new SPRxPOS/SPRxCTL is fetched and enabling it in the next one results in stopped
DMA transfer but the last line of sprite is displayed till the end of the screen.

VSTART and VSTOP specified within vbl are not met.
vbl stops dma transfer.
The first possible line to display a sprite is line $1A (PAL).
During vbl SPRxPOS/SPRxCTL are not automatically modified, values written before vbl are still present when vbl ends.

algo:
	if vbl or VSTOP : disable data dma
	else if VSTART: start data dma
	
	if vblend or (VSTOP and not vbl): dma transfer to sprxpos/sprxctl
	else if data dma active: transfer to sprxdata/sprcdatb

It doesn't seem to be complicated :)

Sprite which has been triggered by write to SPRxDATA is not disabled by vbl.
It seems that vstop and vstart conditions are checked every cycle. 
Dma doesn't fetch new pos/ctl if vstop is not equal to the current line number.

Feature:
If new vstart is specified to be the same as the line during which it's fetched, display starts in the next line
but is one line shorter.
*/

//sprite dma engine
module sprdma_engine
(
	input 	clk,		    			//bus clock
	input	clk28m,
	output	reg reqdma,				//sprite dma engine requests dma cycle
	input	ackdma,						//agnus dma priority logic grants dma cycle
	input	[8:0]hpos,				//horizontal beam counter
	input	[10:0]vpos,				//vertical beam counter
	input	vbl,						//JB: vertical blanking
	input	vblend,						//JB: last line of vertical blanking
	input	[8:1]regaddressin,		//register address inputs
	output 	reg [8:1]regaddressout,	//register address outputs
	input	[15:0]datain,				//bus data in
	output	[20:1]addressout			//chip address out
);
//register names and adresses		
parameter SPRPTBASE=9'h120;		//sprite pointers base address
parameter SPRPOSCTLBASE=9'h140;	//sprite data, position and control register base address

//local signals
reg 	[20:16]sprpth[7:0];		//upper 5 bits sprite pointers register bank
reg 	[15:1]sprptl[7:0];		//lower 16 bits sprite pointers register bank
reg		[15:8]sprpos[7:0];		//sprite vertical start position register bank
//JB: implementing ECS extended vertical sprite position
reg		[15:4]sprctl[7:0];		//sprite vertical stop position register bank

wire	[9:0]vstart;				//vertical start of selected sprite
wire	[9:0]vstop;				//vertical stop of selected sprite
wire	[2:0]sprite;				//sprite select signal
wire	[20:1]newptr;				//new sprite pointer value

wire 	enable;						//hpos in sprite region

//the following signals change their value during cycle 0 of 4-cycle dma sprite window
reg		sprvstop;					//current line is sprite's vstop
reg		sprdmastate;				//sprite dma state (sprite image data cycles)

reg		dmastate_mem[7:0];		//dma state for every sprite
wire	dmastate;					//output from memory
reg		dmastate_in;				//input to memory

reg		[2:0]sprsel;				//memory selection

//sprite selection signal (in real amiga sprites are evaluated concurently,
//in our solution to save resources they are evaluated sequencially but 8 times faster (28MHz clock)
always @(posedge clk28m)
	if (sprsel[2]==hpos[0])	//sprsel[2] is synced with hpos[0]
		sprsel <= sprsel + 1;

//--------------------------------------------------------------------------------------

//register bank address multiplexer
wire	[2:0]ptsel;			//sprite pointer and state registers select
wire	[2:0]pcsel;			//sprite position and control registers select

assign ptsel = (ackdma) ? sprite : regaddressin[4:2];
assign pcsel = (ackdma) ? sprite : regaddressin[5:3];

//sprite pointer arithmetic unit
assign newptr = addressout[20:1] + 1;

//sprite pointer high word register bank (implemented using distributed ram)
wire [20:16]sprpth_in;
assign sprpth_in = ackdma ? newptr[20:16] : datain[4:0];
always @(posedge clk)
	if(ackdma || ((regaddressin[8:5]==SPRPTBASE[8:5]) && !regaddressin[1]))//if dma cycle or bus write
		sprpth[ptsel] <= sprpth_in;

assign addressout[20:16] = sprpth[sprite];

//sprite pointer low word register bank (implemented using distributed ram)
wire [15:1]sprptl_in;
assign sprptl_in = ackdma ? newptr[15:1] : datain[15:1];
always @(posedge clk)
	if(ackdma || ((regaddressin[8:5]==SPRPTBASE[8:5]) && regaddressin[1]))//if dma cycle or bus write
		sprptl[ptsel] <= sprptl_in;

assign addressout[15:1] = sprptl[sprite];

//sprite vertical start position register bank (implemented using distributed ram)
always @(posedge clk)
	if((regaddressin[8:6]==SPRPOSCTLBASE[8:6]) && (regaddressin[2:1]==2'b00))//if bus write
		sprpos[pcsel] <= datain[15:8];

assign vstart[7:0] = sprpos[sprsel];

//sprite vertical stop position register bank (implemented using distributed ram)
always @(posedge clk)
	if((regaddressin[8:6]==SPRPOSCTLBASE[8:6]) && (regaddressin[2:1]==2'b01))//if bus write
		sprctl[pcsel] <= {datain[15:8],datain[6],datain[5],datain[2],datain[1]};
		
assign {vstop[7:0],vstart[9],vstop[9],vstart[8],vstop[8]} = sprctl[sprsel];

//sprite dma channel state register bank
//update dmastate when hpos is in sprite fetch region
//every sprite has allocated 8 system clock cycles with two active dma slots:
//the first during cycle #3 and the second during cycle #7
//first slot transfers data to sprxpos register during vstop or vblend or to sprxdata when dma is active
//second slot transfers data to sprxctl register during vstop or vblend or to sprxdatb when dma is active
//current dmastate is valid after cycle #1 for given sprite and it's needed during cycle #3 and #7
always @(posedge clk28m)
	dmastate_mem[sprsel] <= dmastate_in;

assign dmastate = dmastate_mem[sprsel];

//evaluating sprite image dma data state
always @(vbl or vpos or vstop or vstart or dmastate) 
	if (vbl || (vstop[9:0]==vpos[9:0]))
		dmastate_in = 0;
	else if (vstart[9:0]==vpos[9:0])
		dmastate_in = 1;
	else
		dmastate_in = dmastate;

always @(posedge clk28m)
	if (sprite==sprsel && hpos[2:1]==2'b00)
		sprdmastate <= dmastate;

always @(posedge clk28m)
	if (sprite==sprsel && hpos[2:1]==2'b00)
		sprvstop <= vstop[9:0]==vpos[9:0] ? 1 : 0;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//check if we are allowed to allocate dma slots for sprites
//dma slots for sprites from cycle 20 till 51
assign enable = hpos[8:1]>=8'b0001_0100 && hpos[8:1]<8'b0011_0100 ? 1: 0;
		
//get sprite number for which we are going to do dma
assign sprite = hpos[5:3] - 3'b101;

//generate regdma signal
always @(vpos or vbl or vblend or hpos or enable or sprite or sprvstop or sprdmastate)
	if (enable && hpos[1:0]==2'b11)
	begin
		if (vblend || (sprvstop && ~vbl))
		begin
			reqdma = 1;
			if (~hpos[2])
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b00};	//SPRxPOS
			else
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b01};	//SPRxCTL
		end
		else if (sprdmastate)
		begin
			reqdma = 1;
			if (~hpos[2])
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b10};	//SPRxDATA
			else
				regaddressout[8:1] = {SPRPOSCTLBASE[8:6],sprite,2'b11};	//SPRxDATB
		end
		else
		begin
			reqdma = 0;
			regaddressout[8:1] = 8'hFF;
		end
	end
	else
	begin
		reqdma = 0;
		regaddressout[8:1] = 8'hFF;
	end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//disk dma engine
//the DMA cycle allocation is not completely according to the HRM,
//there are 4 slots allocated for disk dma instead of 3
//
//slots are: (horbeam[8:0] counts) 
//slot 0x000000011 
//slot 0x000000111 
//slot 0x000001011 
//slot 0x000001111 

module dskdma_engine
(
	input 	clk,		    		//bus clock
	output	dma,					//true if disk dma engine uses it's cycle
	input	dmal,					//Paula requests dma
	input	dmas,					//Paula special dma
	input	[8:0]horbeam,			//horizontal beam counter
	output	wr,						//write (disk dma writes to memory)
	input 	[8:1]regaddressin,	//register address inputs
	output 	[8:1]regaddressout,	//register address outputs
	input	[15:0]datain,			//bus data in
	output	reg [20:1]addressout	//chip address out current disk dma pointer
);
//register names and adresses		
parameter DSKPTH=9'h020;			
parameter DSKPTL=9'h022;			
parameter DSKDAT=9'h026;			
parameter DSKDATR=9'h008;		

//local signals
wire	[20:1]addressoutnew;	//new disk dma pointer

//--------------------------------------------------------------------------------------

//dma cycle allocation
assign dma=(dmal && (horbeam[8:4]==5'b00000) && (horbeam[1:0]==2'b11))?1:0;
//write signal
assign wr=~dmas;

//--------------------------------------------------------------------------------------

//addressout input multiplexer and ALU
assign addressoutnew[20:1] = dma ? addressout[20:1]+1 : {datain[4:0],datain[15:1]}; 

//disk pointer control
always @(posedge clk)
	if(dma || (regaddressin[8:1]==DSKPTH[8:1]))
		addressout[20:16]<=addressoutnew[20:16];//high 5 bits
always @(posedge clk)
	if(dma || (regaddressin[8:1]==DSKPTL[8:1]))
		addressout[15:1]<=addressoutnew[15:1];//low 15 bits

//--------------------------------------------------------------------------------------

//register address output
assign regaddressout[8:1] = wr ? DSKDATR[8:1] : DSKDAT[8:1];

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//Audio dma engine
//2 cycle types are defined, restart pointer, (go back to beginning of sample) and next pointer
//(get next word of sample, dmas indicates restart pointer cycle
//
//
//slots are: (horbeam[8:0] counts) 
//slot 0x000010011 (channel #0)
//slot 0x000010111 (channel #1)
//slot 0x000011011 (channel #2)
//slot 0x000011111 (channel #3)
module auddma_engine(clk,dma,dmal,dmas,horbeam,regaddressin,regaddressout,datain,addressout);
input 	clk;		    			//bus clock
output	dma;					//true if audio dma engine uses it's cycle
input	dmal;				//Paula requests dma
input	dmas;				//Paula special dma
input	[8:0]horbeam;			//horizontal beam counter
input 	[8:1]regaddressin;		//register address inputs
output 	[8:1]regaddressout;		//register address outputs
input	[15:0]datain;			//bus data in
output	[20:1]addressout;		//chip address out

//register names and adresses		
parameter AUD0DAT=9'h0aa;			
parameter AUD1DAT=9'h0ba;			
parameter AUD2DAT=9'h0ca;			
parameter AUD3DAT=9'h0da;			
parameter AUD0LCH=9'h0a0;			
parameter AUD1LCH=9'h0b0;			
parameter AUD2LCH=9'h0c0;			
parameter AUD3LCH=9'h0d0;			

//local signals
reg		[8:1]regaddressout;		//see above
reg		[20:1]aud0lc;			//audio location register channel 0
reg		[20:1]aud1lc;			//audio location register channel 1
reg		[20:1]aud2lc;			//audio location register channel 2
reg		[20:1]aud3lc;			//audio location register channel 3
reg		[20:1]audlcout;		//audio location output
reg		[20:1]audpt[3:0];		//audio pointer bank
wire		[20:1]audptout;		//audio pointer bank output

//--------------------------------------------------------------------------------------

//audio location register channel 0
always @(posedge clk)
	if((regaddressin[8:2]==AUD0LCH[8:2]) && !regaddressin[1])
		aud0lc[20:16]<=datain[4:0];
	else if((regaddressin[8:2]==AUD0LCH[8:2]) && regaddressin[1])
		aud0lc[15:1]<=datain[15:1];

//audio location register channel 1
always @(posedge clk)
	if((regaddressin[8:2]==AUD1LCH[8:2]) && !regaddressin[1])
		aud1lc[20:16]<=datain[4:0];
	else if((regaddressin[8:2]==AUD1LCH[8:2]) && regaddressin[1])
		aud1lc[15:1]<=datain[15:1];

//audio location register channel 2
always @(posedge clk)
	if((regaddressin[8:2]==AUD2LCH[8:2]) && !regaddressin[1])
		aud2lc[20:16]<=datain[4:0];
	else if((regaddressin[8:2]==AUD2LCH[8:2]) && regaddressin[1])
		aud2lc[15:1]<=datain[15:1];

//audio location register channel 3
always @(posedge clk)
	if((regaddressin[8:2]==AUD3LCH[8:2]) && !regaddressin[1])
		aud3lc[20:16]<=datain[4:0];
	else if((regaddressin[8:2]==AUD3LCH[8:2]) && regaddressin[1])
		aud3lc[15:1]<=datain[15:1];

//--------------------------------------------------------------------------------------

//get audio location pointer
always @(horbeam or aud0lc or aud1lc or aud2lc or aud3lc)
	case(horbeam[3:2])
		2'b00: audlcout[20:1]=aud0lc[20:1];
		2'b01: audlcout[20:1]=aud1lc[20:1];
		2'b10: audlcout[20:1]=aud2lc[20:1];
		2'b11: audlcout[20:1]=aud3lc[20:1];
	endcase


//dma cycle allocation
assign dma=(dmal && (horbeam[8:4]==5'b00001) && (horbeam[1:0]==2'b11))?1:0;

//addressout output multiplexer
assign addressout[20:1]=(dmas)?audlcout[20:1]:audptout[20:1]; 

//audio location register bank (implemented using distributed ram)
//and ALU
always @(posedge clk)
	if(dma)//dma cycle
		audpt[horbeam[3:2]]<=(addressout[20:1]+1);
assign audptout[20:1]=audpt[horbeam[3:2]];

//register address output multiplexer
always @(horbeam)
	case(horbeam[3:2])
		2'b00: regaddressout[8:1]=AUD0DAT[8:1];
		2'b01: regaddressout[8:1]=AUD1DAT[8:1];
		2'b10: regaddressout[8:1]=AUD2DAT[8:1];
		2'b11: regaddressout[8:1]=AUD3DAT[8:1];
	endcase

//--------------------------------------------------------------------------------------

endmodule

