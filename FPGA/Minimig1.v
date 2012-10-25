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
// This is the top module for the Minimig rev1.0 board
//
// 19-03-2005 		-started coding
// 10-04-2005		-added cia's 
//				-verified timers a/b and I/O ports
// 11-04-2005		-adapted top to cleaned up address decoder
//				-connected cia's to .clk(~qclk) and .tick(e) for testing
// 13-04-2005		-_foe and _loe are now made with clocks driving FF's
//				-sram_bridge now also gets .clk(clk)
// 18-04-2005		-added second synchronisation latch for mreset
// 19-04-2005		-bootrom is now 2Kbyte large
// 05-05-2005		-made preparations for dma (bus multiplexers between agnus and cpu)
// 15-05-2005		-added denise
// 				-connected vertb (vertical blank intterupt) to int3 input of paula
// 18-05-2005		-removed interlaced top input pin
// 28-06-2005		-done some experimentation to solve logic loop in Agnus
// 17-07-2005		-connected second ram bank to hold kickstart rom
// 				-added ovl (kickstart overlay) and boot (bootrom overlay) signals
//				-wired cia in/out ports more correctly
//				-wired vsync/hsync to cia's
// 18-07-2005		-experimented to get kickstart running
// 20-07-2005		-still experimenting..
// 07-08-2005		-Jahoeee!! kickstart doesn't guru anymore but 'clicks' the floppy drive !
//				-the guru's were caused by spurious writes to ram which is fixed now in the sram controller
//				-unfortunately still no insert workbench screen but that may be caused by the missing blitter
// 04-09-2005		-added blitter finished interrupt
// 11-09-2005		-added 2meg addressing for Agnus
// 13-09-2005		-added 4bit (per color) video output
// 16-10-2005		-added user IO module
// 23-10-2005		-added dmal signal wire
// 08-11-2005		-fixed typo in instantiation of Paula
// 21-11-2005		-added some signals to handle floppy
// 22-11-2005		-adapted to new add-on develop board
//				-added joystick 1 port
// 10-12-2005		-done some experimentation to find floppy bug
// 21-12-2005		-reworked code to use new style gary module
// 27-12-2005		-added dskindx interrupt
// 03-01-2006		-added dmas to avoid interference with copper cycles
// 11-01-2006		-added Amber
// 15-01-2006		-added syscontrol module to handle automatic boot sequence
// 22-01-2006		-removed _csync port from agnus
// 23-01-2006		-added fastblit input
// 24-01-2006		-cia's now count positive _hsync/_vsync transitions
// 14-02-2006		-code clean up
//				-added fastchip input
// 19-02-2006		-improved indx disk interrupt timing
//				-cia timers now connect to sol/sof
// 12-11-2006		-started porting code to Minimig rev1.0 board
// 17-11-2006		-added address decoding for Minimig rev1.0 ram
// 22-11-2006		-added keyboard reset
// 27-11-2006		-code adapted to new synchronous bootrom
// 03-12-2006		-added dimming powerled
// 11-12-2006		-updated code to new ciaa
// 27-12-2006		-updated code to new ciab
// 24-06-2007		-moved cpu/sram/clock and syscontrol to this file to reduce number of source files
//
// TODO: 			-fixs bug and implement things I forgot.....

module Minimig1(	cpudata,cpuaddress,_ipl,_as,_uds,_lds,r_w,_dtack,_cpureset,cpuclk,
				ramdata,ramaddress,_ramsel0,_ramsel1,_ub,_lb,_we,_oe,
				mclk,
				txd,rxd,cts,rts,
				_joy1,_joy2,_15khz,pwrled,msdat,msclk,kbddat,kbdclk,
				_spisel0,_spisel1,_spisel2,spidin,spidout,spiclk,
				_hsyncout,_vsyncout,redout,greenout,blueout,
				left,right);
//m68k pins
inout 	[15:0]cpudata;		//m68k data bus
input	[23:1]cpuaddress;	//m68k address bus
output	[2:0]_ipl;		//m68k interrupt request
input	_as;				//m68k address strobe
input	_uds;			//m68k upper data strobe
input	_lds;			//m68k lower data strobe
input	r_w;				//m68k read / write
output	_dtack;			//m68k data acknowledge
output	_cpureset;		//m68k reset
output	cpuclk;			//m68k clock
//sram pins
inout	[15:0]ramdata;		//sram data bus
output	[19:1]ramaddress;	//sram address bus
output	_ramsel0;			//sram enable bank 0
output	_ramsel1;			//sram enable bank 1
output	_ub;				//sram upper byte select
output	_lb;				//sram lower byte select
output	_we;				//sram write enable
output	_oe;				//sram output enable
//system	pins
input	mclk;			//master system clock (4.433619MHz)
//rs232 pins
input	rxd;				//rs232 receive
output	txd;				//rs232 send
input	cts;				//rs232 clear to send
output	rts;				//rs232 request to send
//I/O
input	[5:0]_joy1;		//joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
input	[5:0]_joy2;		//joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
input	_15khz;			//scandoubler disable
output	pwrled;			//power led
inout	msdat;			//PS2 mouse data
inout	msclk;			//PS2 mouse clk
inout	kbddat;			//PS2 keyboard data
inout	kbdclk;			//PS2 keyboard clk
//host controller interface (SPI)
input	_spisel0;			//SPI enable 0
input	_spisel1;			//SPI enable 1
input	_spisel2;			//SPI enable 2
input	spidin;			//SPI data input
output	spidout;			//SPI data output
input	spiclk;			//SPI clock
//video
output	_hsyncout;		//horizontal sync
output	_vsyncout;		//vertical sync
output	[3:0]redout;		//red
output	[3:0]greenout;		//green
output	[3:0]blueout;		//blue
//audio
output	left;			//audio bitstream left
output	right;			//audio bitstream right

//--------------------------------------------------------------------------------------

//local signals for data bus
wire		[15:0]data;		//main databus
wire		[15:0]pauladataout;	//paula databus out
wire		[15:0]userdataout;	//user IO data out
wire		[15:0]denisedataout;//denise databus out
wire		[15:0]cpudataout;	//cpu databus out
wire		[15:0]ramdataout;	//ram databus out
wire		[15:0]bootdataout;	//boot rom databus out
wire		[15:0]ciadataout;	//cia A+B databus out
wire		[15:0]agnusdataout;	//agnus data out

//local signals for spi bus
wire		paulaspidout; 		//paula spi data out
wire		userspidout;		//userio spi data out

//local signals for address bus
reg		[23:1]address;		//main address bus
wire		[20:1]address_agnus;//agnus address out

//local signals for control bus
wire		hwr;				//main high write enable 
wire		lwr;				//main low write enable 
wire		rd;				//main read enable
wire		cpurd; 			//cpu read enable
wire		cpuhwr;			//cpu high write enable
wire		cpulwr;			//cpu low write enable
wire		dma;				//agnus gets bus
wire		dmawr;			//agnus write
wire		dmapri;			//agnus has priority	

//register address bus
wire		[8:1]regaddress; 	//main register address bus

//rest of local signals
wire		kbdrst;			//keyboard reset
wire		reset;			//global reset
wire		clk;				//bus clock
wire		qclk;			//qudrature bus clock
wire		vgaclk;			//scandoubler clock
wire		e;				//e clock enable
wire		ovl;				//kickstart overlay enable
wire		_led;			//power led
wire		boot;    			//bootrom overlay enable
wire		selchip;			//chip ram select
wire		selslow;			//slow ram select
wire		selkick;			//rom select
wire		selreg;			//chip register select
wire		selciaa;			//cia A select
wire		selciab;			//cia B select
wire		selboot;			//boot rom select
wire		int2;			//intterrupt 2
wire		int3;			//intterrupt 3 
wire		int6;			//intterrupt 6
wire		[3:0]osdctrl;		//OSD control (minimig->host, [menu,select,down,up])
wire		_fire0;			//joystick 1 fire signal	to cia A
wire		_fire1;			//joystick 2 fire signal to cia A
wire		[2:0]user;		//user control signals
wire		dmal;			//dma request from Paula to Agnus
wire		dmas;			//dma special from Paula to Agnus
wire		indx;			//disk index interrupt

//local video signals
wire		blank;			//blanking signal
wire		sol;				//start of video line
wire		sof;				//start of video frame
wire		[3:0]nred;		//denise (pal) red
wire		[3:0]ngreen;		//denise (pal) green
wire		[3:0]nblue;		//denise (pal) blue
wire		osdblank;			//osd blanking 
wire		osdpixel;			//osd pixel(video) data
wire		_hsync;			//horizontal sync
wire		_vsync;			//vertical sync

//local floppy signals (CIA<-->Paula)
wire		_step;			//step heads of disk
wire		direc;			//step heads direction
wire		_sel0;			//disk0 select 	
wire		_sel1;			//disk1 select 	
wire		_sel2;			//disk2 select 	
wire		_sel3;			//disk3 select 	
wire		side;			//upper/lower disk head
wire		_motor;			//disk motor control
wire		_track0;			//track zero detect
wire		_change;			//disk has been removed from drive
wire		_ready;			//disk is ready

//--------------------------------------------------------------------------------------

//power led control
//when _led=0, pwrled=on
//when _led=1, pwrled=powered by weak pullup
assign pwrled=(_led)?1'bz:1'b1;

//--------------------------------------------------------------------------------------

//indx signal generation, this signal is the disk index interrupt and is needed to let some
//loaders function correctly
//indx is asserted every 10 scanlines to simulate disk at 300 RPM
reg [3:0]indxcnt;
always @(posedge clk)
	if(indx)
		indxcnt[3:0]<=0;
	else if(sof)
		indxcnt[3:0]<=indxcnt[3:0]+1;
assign indx=(indxcnt[3:0]==9)?1:0;

//--------------------------------------------------------------------------------------

//switch address and control bus between agnus and cpu
always @(dma or cpuaddress or address_agnus)
	if(!dma)//address bus and control bus belongs to cpu
		address[23:1]=cpuaddress[23:1];
	else//address bus and control bus belongs to agnus
		address[23:1]={cpuaddress[23:21],address_agnus[20:1]};

assign ramaddress[18:1]=address[18:1];

//--------------------------------------------------------------------------------------

//instantiate agnus
Agnus A1 (		.clk(clk),
				.reset(reset),
				.aen(selreg),
				.rd(rd),
				.hwr(hwr),
				.lwr(lwr),
				.datain(data),
				.dataout(agnusdataout),
				.addressin(address[8:1]),
				.addressout(address_agnus),
				.regaddress(regaddress),
				.bus(dma),
				.buswr(dmawr),
				.buspri(dmapri),
				._hsync(_hsync),
				._vsync(_vsync),
				.blank(blank),
				.sol(sol),
				.sof(sof),
				.int3(int3),
				.dmal(dmal),
				.dmas(dmas),
				.fastchip(1'b0)		);

//instantiate paula
Paula P1 (		.clk(clk),
				.reset(reset),
				.regaddress(regaddress),
				.datain(data),
				.dataout(pauladataout),
				.txd(txd),
				.rxd(rxd),
				.sol(sol),
				.sof(sof),
				.int2(int2),
				.int3(int3),
				.int6(int6),
				._ipl(_ipl),
				.dmal(dmal),
				.dmas(dmas),
				._step(_step),
				.direc(direc),
				._sel(_sel0),
				.side(side),
				._motor(_motor),
				._track0(_track0),
				._change(_change),
				._ready(_ready),
				._den(_spisel0),
				.din(spidin),
				.dout(paulaspidout),
				.dclk(spiclk),
				.user(user),
				.left(left),
				.right(right)			);

//instantiate user IO
userio UI1 (		.clk(clk),
				.reset(reset),
				.sol(sol),
				.sof(sof),
				.regaddress(regaddress),
				.datain(data),
				.dataout(userdataout),
				.ps2mdat(msdat),
				.ps2mclk(msclk),
				._fire0(_fire0),
				._fire1(_fire1),
				.user(user),
				._joy1(_joy1),
				._joy2(_joy2),
				.osdctrl(osdctrl),
				._den(_spisel1),
				.din(spidin),
				.dout(userspidout),
				.dclk(spiclk),
				.osdblank(osdblank),
				.osdpixel(osdpixel)		);

//instantiate Denise
Denise DN1 (		.clk(clk),
				.reset(reset),
				.sol(sol),
				.sof(sof),
				.regaddress(regaddress),
				.datain(data),
				.dataout(denisedataout),
				.blank(blank),
				.red(nred),
				.green(ngreen),
				.blue(nblue)			);

//instantiate Amber
amber B1 (		.clk(clk),
				.vgaclk(vgaclk),
				.dblscan(_15khz),
				.osdblank(osdblank),
				.osdpixel(osdpixel),
				.redin(nred),
				.bluein(nblue),
				.greenin(ngreen),
				._hsyncin(_hsync),
				._vsyncin(_vsync),
				.redout(redout),
				.blueout(blueout),
				.greenout(greenout),
				._hsyncout(_hsyncout),
				._vsyncout(_vsyncout)	);

//instantiate cia A
ciaa	ciaa (		.clk(clk),
				.aen(selciaa),
				.rd(rd),
				.wr(lwr),
				.reset(reset),
				.rs(address[11:8]),
				.datain(data[7:0]),
				.dataout(ciadataout[7:0]),
				.tick(sof),//vsync count
				.e(e),
				.irq(int2),
				.portain({_fire1,_fire0,_ready,_track0,_sel0,_change}),
				.portaout({_led,ovl}),
				.kbdrst(kbdrst),
				.kbddat(kbddat),
				.kbdclk(kbdclk),
				.osdctrl(osdctrl)		);

//instantiate cia B
ciab	ciab (		.clk(clk),
				.aen(selciab),
				.rd(rd),
				.wr(hwr),
				.reset(reset),
				.rs(address[11:8]),
				.datain(data[15:8]),
				.dataout(ciadataout[15:8]),
				.tick(sol),//hsync count
				.e(e),
				.flag(indx),
				.irq(int6),
				.portain({1'b0,cts,1'b0}),
				.portaout({dtr,rts}),
				.portbout({_motor,_sel3,_sel2,_sel1,_sel0,side,direc,_step})		);


//instantiate cpu bridge
m68k_bridge M1 (	.clk(clk),
				.qclk(qclk),
				.cen(cpuok),
				._as(_as),
				._lds(_lds),
				._uds(_uds),
				.r_w(r_w),
				._dtack(_dtack),
				.rd(cpurd),
				.hwr(cpuhwr),
				.lwr(cpulwr),
				.data(cpudata),
				.dataout(cpudataout),
				.datain(data)			);

//instantiate sram bridge
sram_bridge S1 (	.clk(clk),
				.qclk(qclk),
				.aen1(selchip&(~address[19])),//first 512Kbyte of chipram
				.aen2(selchip&address[19]),//second 512Kbyte of chipram
				.aen3(selslow),//512Kbyte of slow ram
				.aen4(selkick&(boot|rd)),//512Kbyte of kickstart rom (write enabled when boot asserted)
				.datain(data),
				.dataout(ramdataout),
				.rd(rd),
				.hwr(hwr),
				.lwr(lwr),
				._ub(_ub),
				._lb(_lb),
				._we(_we),
				._oe(_oe),
				._sel0(_ramsel0),
				._sel1(_ramsel1),
				.data(ramdata),
				.address19(ramaddress[19])	);
//instantiate gary
gary	G1 (			.clk(clk),
				.e(e),
				.cpuaddress(cpuaddress[23:12]),
				.cpurd(cpurd),
				.cpuhwr(cpuhwr),
				.cpulwr(cpulwr),
				.cpuok(cpuok),
				.dma(dma),
				.dmawr(dmawr),
				.dmapri(dmapri),
				.ovl(ovl),
				.boot(boot),
				.rd(rd),
				.hwr(hwr),
				.lwr(lwr),
				.selreg(selreg),
				.selchip(selchip),
				.selslow(selslow),
				.selciaa(selciaa),
				.selciab(selciab),
				.selkick(selkick),
				.selboot(selboot)		);

//instantiate boot rom
bootrom R1 (		.clk(clk),
				.aen(selboot),
				.rd(rd),
				.address(cpuaddress[10:1]),
				.dataout(bootdataout)	);

//instantiate system control
syscontrol L1 (	.clk(clk),
				.mrst(kbdrst),
				.bootdone(selciaa&selciab),
				.reset(reset),
				.boot(boot)			);

//instantiate clock generator
clock_generator C1(	.mclk(mclk),
				.c_28m(vgaclk),
				.c_7m(clk),
				.cq_7m(qclk),
				.e(e)	);
				
//--------------------------------------------------------------------------------------

//data multiplexer
assign data[15:0]=ramdataout[15:0]|cpudataout[15:0]|pauladataout[15:0]|userdataout|denisedataout[15:0]|bootdataout[15:0]|ciadataout[15:0]|agnusdataout[15:0];

//--------------------------------------------------------------------------------------

//spi multiplexer
assign spidout=(!_spisel0 || !_spisel1) ? (paulaspidout|userspidout) : 1'bz;


//--------------------------------------------------------------------------------------

//cpu reset and clock
assign _cpureset=~reset;
assign cpuclk=~clk;


//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//Master clock generator for minimig
//This module generates all necessary clock from the 4.433619 PAL clock
module clock_generator(mclk,c_28m,c_7m,cq_7m,e);
input mclk;			//4.433619 MHz master oscillator input
output c_28m;	 		//28.37516 MHz clock out
output c_7m; 			//7.09379  MHz	clock out
output cq_7m; 			//7.09379  MHz	qudrature clock out
output e;		  		//0.709379 MHz clock enable out

reg ic_14m;			//14.18758 MHz intermediate frequency			
reg ic_7m;			
reg icq_7m;			

reg	[3:0]ediv;		//used to generate e clock enable

// Instantiate the DCM module
// the DCM is configured to generator c_28m from mclk (multiply by 32, divide by 5)
clock_dcm dcm1(
    .CLKIN_IN(mclk), 
    .RST_IN(1'b0), 
    .CLKFX_OUT(c_28m), 
    .CLKIN_IBUFG_OUT(), 
    .LOCKED_OUT()
    );

//generator ic_14m
always @(posedge c_28m)
	ic_14m<=~ic_14m;

//generate ic_7m
always @(posedge ic_14m)
	ic_7m<=~ic_7m;

//generate icq_7m
always @(negedge ic_14m)
	icq_7m<=ic_7m;

//generate e
always @(posedge c_7m)
	if(e)
		ediv<=9;
	else
		ediv<=ediv-1;
assign e=(ediv==4'b0000)?1:0;


//clock buffers
BUFG buf1 (	.I(ic_7m), 
               .O(c_7m)	);
BUFG buf2 (	.I(icq_7m), 
               .O(cq_7m));

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//syscontrol handles the startup of the FGPA,
//after fpga config, it automatically does a global system reset and asserts boot.
//the boot signal puts gary in a special mode so that the bootrom
//is mapped into the system memory map.	The firmware in the bootrom
//then loads the kickstart via the diskcontroller into the kickstart ram area.
//When kickstart has been loaded, the bootrom asserts bootdone by selecting both cia's at once. 
//This resets the system for a second time but it also de-asserts boot.
//Thus, the system now boots as a regular amiga.
//Subsequent resets by asserting mrst will not assert boot again.
module syscontrol(clk,mrst,bootdone,reset,boot);
input	clk;				//bus clock
input	mrst;			//master/user reset input
input	bootdone;			//bootrom program finished input
output	reset;			//global synchronous system reset
output	boot;			//bootrom overlay enable output

//local signals
reg		reset;			//registered output
reg		smrst;			//registered input
reg		boot;			//registered output
reg		bootff=0;			//boot control SHOULD BE CLEARED BY CONFIG
reg		[23:0]rstcnt=24'h0;	//reset timer SHOULD BE CLEARED BY CONFIG

//asynchronous mrst input synchronizer
always @(posedge clk)
	smrst<=mrst;

//reset timer and mrst control
always @(posedge clk)
	if(smrst || (boot && bootdone && rstcnt[23]))
		rstcnt<=0;
	else if(!rstcnt[23])
		rstcnt<=rstcnt+1;

//boot control
always @(posedge clk)
	if(bootdone && rstcnt[23])
		bootff<=1;

//global reset output
always @(posedge clk)
	reset<=~rstcnt[23];

//boot output
always @(posedge clk)
	boot<=~bootff;

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces the minimig's synchronous bus to the asynchronous sram
// on the Minimig rev1.0 board
module sram_bridge(clk,qclk,aen1,aen2,aen3,aen4,datain,dataout,rd,hwr,lwr,_ub,_lb,_we,_oe,_sel0,_sel1,data,address19);
input clk;				//bus clock
input qclk;				//quadrature bus clock
input aen1;				//bus adress enable	sram block 1
input aen2;				//bus adress enable	sram block 2
input aen3;				//bus adress enable	sram block 3
input aen4;				//bus adress enable	sram block 4
input [15:0] datain;	 	//bus data in
output [15:0] dataout;		//bus data out
input rd;			   		//bus read
input hwr;				//bus high write
input lwr;				//bus low write
output _ub;				//sram upper byte
output _lb;   				//sram lower byte
output _we;				//sram write enable
output _oe;    			//sram output enable
output _sel0;	  			//sram bank 0 enable
output _sel1;	  			//sram bank 1 enable
inout [15:0]data;	  		//sram data
output address19;			//sram address line 19	 

wire		enable;			// enable signal
reg		p1;	    			// used to time write and driver enable
reg		p2;				// used to time write and driver enable
reg		p3;				// used to time write and driver enable
wire		write;			// write pulse timing
wire		drive;			// output drive pulse timing
wire		t;				// output drive enable

// generate enable signal if we are adressed
assign enable=aen1|aen2|aen3|aen4;

// generate write pulse and data output drive pulse
always @(posedge clk)
	p1<=~p1;
always @(negedge clk)
	p2<=p1;
always @(negedge qclk)
	p3<=p1;
assign write=(p2^p3);
assign drive=~(p1^p2);

// generate _we
assign _we=~( write&enable&(hwr|lwr) ); 

//generate t
assign t=~( drive&enable&(hwr|lwr) );

// generate _oe
assign _oe=~( enable & rd );

// generate _ub
assign _ub=~( enable & (rd|hwr) );

// generate _lb
assign _lb=~( enable & (rd|lwr) );

// map aen1..aen4 to sram
// the sram is organized in 2 1MBbyte 16bit wide memory banks
// ean1..aen4 select 512kbyte	banks
assign _sel0=~(aen1|aen2);
assign _sel1=~(aen3|aen4);
assign address19=aen2|aen4;

// dataout multiplexer
assign dataout[15:0]=(enable && rd)?data[15:0]:16'b0000000000000000;

// data tristate buffers
assign data[15:0]=(t)?16'bz:datain[15:0];

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces the minimig's synchronous bus to the asynchronous 
// MC68SEC000 bus on the Minimig rev1.0 board
module m68k_bridge(clk,qclk,cen,_as,_lds,_uds,r_w,_dtack,rd,hwr,lwr,data,dataout,datain);
input clk;				// bus clock
input qclk;				// bus quadrature clock
input cen; 				// bus clock enable (dma slot for m68k bridge)
input _as;				// m68k adress strobe
input _lds;				// m68k lower data strobe d0-d7
input _uds;				// m68k upper data strobe d8-d15
input r_w;				// m68k read / write
output _dtack;				// m68k data acknowledge to cpu
output rd;				// bus read 
output hwr;				// bus high write
output lwr;				// bus low write
inout [15:0] data;			// m68k data
output [15:0] dataout;		// bus data out
input [15:0] datain;		// bus data in

reg		_dtack;			// see above
wire		t;				// bidirectional buffer control
reg		[15:0]ldatain;		// latched datain
reg		[15:0]ldataout;	// latched dataout
reg		enable;			// enable
reg 		[15:0]dataout;		// see output description
reg		rd,hwr,lwr;		// see output description
wire		l_as,l_lds,l_uds,lr_w,l_dtack;  // synchronised inputs
wire		valid;			// true if synchronised inputs are valid
reg		[4:0]latcha;
reg		[4:0]latchb;
reg		[9:0]latchc;

// latch input signals phase A
always @(negedge qclk)
begin
	latcha[0]<=_as;
	latcha[1]<=_lds;
	latcha[2]<=_uds;
	latcha[3]<=r_w;
	latcha[4]<=_dtack;
end

// latch input signals phase B
always @(posedge clk)
begin
	latchb[0]<=_as;
	latchb[1]<=_lds;
	latchb[2]<=_uds;
	latchb[3]<=r_w;
	latchb[4]<=_dtack;
end

// latch input signals phase C
always @(posedge qclk)
	latchc[9:0]<={latchb[4:0],latcha[4:0]};

// generate synchronised signals and valid signal
assign valid=(latchc[9:5]==latchc[4:0])?1:0;
assign l_as=latchc[5];
assign l_lds=latchc[6];
assign l_uds=latchc[7];
assign lr_w=latchc[8];
assign l_dtack=latchc[9];	

// generate rd,hwr,lwr and enable
always @(valid or l_as or l_lds or l_uds or lr_w or l_dtack or cen)
begin
	// normal cpu cycle
	if(valid && cen && !l_as && l_dtack && (!l_uds || !l_lds))
	begin
		if(lr_w)
		begin// 16bit read cycle
			enable=1;
			rd=1;
			hwr=0;
			lwr=0;			
		end
		else
		begin// 16bit or 8bit write cycle
			rd=0;
			enable=1;
			if(!l_uds)
				hwr=1;
			else
				hwr=0;
			if(!l_lds)
				lwr=1;
			else
				lwr=0;
		end
	end
	else
	begin// IDLE cycle
		enable=0;
		rd=0;
		hwr=0;
		lwr=0;	
	end
end


// generate t
assign t=(~r_w) | (_lds&_uds);

// dtack control
always @(negedge clk)
	if(l_as && valid)
		_dtack<=1;
	else if(enable)
		_dtack<=0;

//--------------------------------------------------------------------------------------

// dataout multiplexer and latch 
always @(posedge clk)
	ldataout<=data;	  
always @(hwr or lwr or ldataout)
	if(hwr || lwr)
		dataout=ldataout;
	else
		dataout=16'b0000000000000000;

// datain latch
always @(posedge clk)
	if(enable)
		ldatain<=datain;

//--------------------------------------------------------------------------------------

// data tristate buffers
assign data[15:0]=(t)?16'bz:ldatain[15:0];

endmodule
