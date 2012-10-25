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

//JB:
// 2008-07-17
//	- scan doubler with vertical and horizontal interpolation
//	- transparent osd window
//	- selected osd line highlight
//	- osd control by joystick (up and down pressed simultaneously invoke menu) 
//	- memory configuration from osd (512KB chip, 1MB chip, 512KB chip/512KB slow, 1MB chip/512KB slow)
//	- video interpolation filter configuration from osd (vertical and horizontal)
//	- user reset accessible from osd
//	- user reset to bootloader (kickstart reloading)
//	- new bootloader (text messages during kickstart loading)
//	- ECS blittter
//	- PAL/NTSC selection
//	- modified display dma engine (better compatibility)
//	- modified sprite dma engine (better compatibility)
//	- modified copper timing (better compatibility) 
//	- modified floppy interface (better read and write support)
//	- Action Replay III module for debugging (takes 512KB memory bank)
//
// Thanks to:
// Dennis for his great Minimig
// Loriano for impressive enclosure 
// Darrin and Oscar for their ideas, support and help
// Toni for his indispensable help and logic analyzer (and WinUAE :-)
//
// 2008-09-22 	- code clean-up
// 2008-09-23	- added c1 and c3 clock anable signals
//				- adapted sram bridge to use only clk28m clock
// 2008-09-24	- added support for floppy _sel[3:1] signals
// 2008-11-14	- ram interface synchronous with clk28m, 70ns access cycle
// 2009-04-21	- code clean up
//
// Thanks to Loriano, Darrin, Richard, Edwin, Sascha, Peter and others for their help, support, ideas, testing, bug reports and feature requests.
//

module Minimig1
(
	//m68k pins
	inout 	[15:0]cpudata,		//m68k data bus
	input	[23:1]cpuaddress,	//m68k address bus
	output	[2:0]_ipl,			//m68k interrupt request
	input	_as,				//m68k address strobe
	input	_uds,				//m68k upper data strobe
	input	_lds,				//m68k lower data strobe
	input	r_w,				//m68k read / write
	output	_dtack,				//m68k data acknowledge
	output	_cpureset,			//m68k reset
	output	cpuclk,				//m68k clock
	//sram pins
	inout	[15:0]ramdata,		//sram data bus
	output	[19:1]ramaddress,	//sram address bus
	output	_ramsel0,			//sram enable bank 0
	output	_ramsel1,			//sram enable bank 1
	output	_ub,				//sram upper byte select
	output	_lb,				//sram lower byte select
	output	_we,				//sram write enable
	output	_oe,				//sram output enable
	//system	pins
	input	mclk,				//master system clock (4.433619MHz)
	//rs232 pins
	input	rxd,				//rs232 receive
	output	txd,				//rs232 send
	input	cts,				//rs232 clear to send
	output	rts,				//rs232 request to send
	//I/O
	input	[5:0]_joy1,			//joystick 1 [fire2,fire,up,down,left,right] (default mouse port)
	input	[5:0]_joy2,			//joystick 2 [fire2,fire,up,down,left,right] (default joystick port)
	input	_15khz,				//scandoubler disable
	output	pwrled,				//power led
	inout	msdat,				//PS2 mouse data
	inout	msclk,				//PS2 mouse clk
	inout	kbddat,				//PS2 keyboard data
	inout	kbdclk,				//PS2 keyboard clk
	//host controller interface (SPI)
	input	_spisel0,			//SPI enable 0
	input	_spisel1,			//SPI enable 1
	input	_spisel2,			//SPI enable 2
	input	spidin,				//SPI data input
	inout	spidout,			//SPI data output
	input	spiclk,				//SPI clock
	//video
	output	_hsyncout,			//horizontal sync
	output	_vsyncout,			//vertical sync
	output	[3:0]redout,		//red
	output	[3:0]greenout,		//green
	output	[3:0]blueout,		//blue
	//audio
	output	left,				//audio bitstream left
	output	right,				//audio bitstream right
	//user i/o
	output	gpio0,
	output	gpio1,
	output	gpio2
);

//--------------------------------------------------------------------------------------

	parameter NTSC = 0;	//Agnus type (PAL/NTSC)

//--------------------------------------------------------------------------------------

//local signals for data bus
wire		[15:0] data;			//main databus
wire		[15:0] customdatain;	//custom chips databus in
wire		[15:0] pauladataout;	//paula databus out
wire		[15:0] userdataout;		//user IO data out
wire		[15:0] denisedataout;	//denise databus out
wire		[15:0] cpudataout;		//cpu databus out
wire		[15:0] ramdataout;		//ram databus out
wire		[15:0] bootdataout;		//boot rom databus out
wire		[15:0] ciadataout;		//cia A+B databus out
wire		[15:0] agnusdataout;	//agnus data out
wire		[15:0] cartdataout;		//Action Replay data out
wire		[15:0] gayledataout;	//Gayle data out

//local signals for spi bus
wire		paulaspidout; 			//paula spi data out
wire		userspidout;			//userio spi data out

//local signals for address bus
reg			[23:1] address;			//main address bus
wire		[20:1] address_agnus;	//agnus address out

//local signals for control bus
wire		hwr;					//main high write enable 
wire		lwr;					//main low write enable 
wire		rd;						//main read enable
wire		cpurd; 					//cpu read enable
wire		cpuhwr;					//cpu high write enable
wire		cpulwr;					//cpu low write enable
wire		dma;					//agnus gets bus
wire		dmawr;					//agnus write
wire		dmapri;					//agnus has priority	
wire		cck;					//colour clock (chipset dma slots indication)

//register address bus
wire		[8:1]regaddress; 		//main register address bus

//rest of local signals
wire		kbdrst;					//keyboard reset
wire		reset;					//global reset
wire		clk;					//bus clock
wire		clk28m;					//28MHz clock for Amber (and ECS Denise in future)
wire		c1,c3;					//clock enable signals
wire		e;						//e clock enable
wire		dbr;					//data bus request, Gary tells CPU bridge that current bus cycle is not available (dbr=1)
reg			dbr_del;				//delayed dbr
wire		ovl;					//kickstart overlay enable
wire		_led;					//power led
wire		boot;    				//bootrom overlay enable
wire		selchip;				//chip ram select
wire		selslow;				//slow ram select
wire		selkick;				//rom select
wire		selreg;					//chip register select
wire		selciaa;				//cia A select
wire		selciab;				//cia B select
wire		selboot;				//boot rom select
wire		int2;					//intterrupt 2
wire		int3;					//intterrupt 3 
wire		int6;					//intterrupt 6
wire		[7:0] osdctrl;			//OSD control
wire		freeze;					//Action Replay freeze button
wire		_fire0;					//joystick 1 fire signal	to cia A
wire		_fire1;					//joystick 2 fire signal to cia A
wire		[3:0] audio_dmal;		//audio dma data transfer request from Paula to Agnus
wire		[3:0] audio_dmas;		//audio dma location pointer restart from Paula to Agnus
wire		disk_dmal;				//disk dma data transfer request from Paula to Agnus
wire		disk_dmas;				//disk dma special request from Paula to Agnus
wire		indx;					//disk index interrupt

//local video signals
wire		blank;					//blanking signal
wire		sol;					//start of video line
wire		sof;					//start of video frame
wire		strhor_denise;			//horizontal strobe for Denise
wire		strhor_paula;			//horizontal strobe for Paula
wire		[3:0]nred;				//denise (pal) red
wire		[3:0]ngreen;			//denise (pal) green
wire		[3:0]nblue;				//denise (pal) blue
wire		osdblank;				//osd blanking 
wire		osdpixel;				//osd pixel(video) data
wire		_hsync;					//horizontal sync
wire		_vsync;					//vertical sync
wire		_csync;					//composite sync
wire		[8:0] htotal;			//video line length (140ns units)

//local floppy signals (CIA<-->Paula)
wire		_step;					//step heads of disk
wire		direc;					//step heads direction
wire		_sel0;					//disk0 select 	
wire		_sel1;					//disk1 select 	
wire		_sel2;					//disk2 select 	
wire		_sel3;					//disk3 select 	
wire		side;					//upper/lower disk head
wire		_motor;					//disk motor control
wire		_track0;				//track zero detect
wire		_change;				//disk has been removed from drive
wire		_ready;					//disk is ready
wire		_wprot;					//disk is write-protected


//--------------------------------------------------------------------------------------
//JB:
wire	bls;					//blitter slowdown - required for sharing bus cycles between Blitter and CPU

wire	int7;					//int7 interrupt request from Action Replay
wire	[2:0] _iplx;			//interrupt request lines from Paula
wire	selcart;				//Action Replay RAM select
wire	ovr;					//overide chip memmory decoding

wire	usrrst;					//user reset from osd interface
wire	bootrst;				//user reset to bootloader
wire	[1:0] lr_filter;		//lowres interpolation filter mode: bit 0 - horizontal, bit 1 - vertical
wire	[1:0] hr_filter;		//hires interpolation filter mode: bit 0 - horizontal, bit 1 - vertical
wire	[1:0] scanline;			//scanline effect configuration
wire	hires;					//hires signal from Denise for interpolation filter enable in Amber
wire	aron;					//Action Replay is enabled
wire	cpu_speed;				//requests CPU to switch speed mode
wire	turbo;					//CPU is working in turbo mode
wire	[3:0] memory_config;	//memory configuration
wire	[3:0] floppy_config;	//floppy drives configuration (drive number and speed)
wire	[3:0] chipset_config;	//CPU & blitter speed and video mode selection
wire	hdd_ena;				//hdd and gayle enable

//gayle stuff
wire	selide;					//select IDE drive registers
wire	selgayle;				//select GAYLE control registers
wire	gayleint;				//interrupt request
//emulated hard disk drive signals
wire	hdd_cmd_req;			//hard disk controller has has written command register and requests processing
wire	hdd_dat_req;			//hard disk controller requests data from emulated hard disk drive
wire	[2:0] hdd_addr;			//emulated hard disk drive register address bus
wire	[15:0] hdd_data_out;	//data output port of emulated hard disk drive
wire	[15:0] hdd_data_in;		//data input port of emulated hard disk drive
wire	hdd_wr;					//register write strobe
wire	hdd_status_wr;			//status register write strobe
wire	hdd_data_wr;			//data port write strobe
wire	hdd_data_rd;			//data pport read strobe

wire	[7:0] bank;				//memory bank select
wire	_ramsel2;				//memory chip select for extra RAM chip
wire	_ramsel3;				//memory chip select for extra RAM chip

wire	keyboard_disable;		//disables Amiga keyboard while OSD is active
wire	disk_led;				//floppy disk activity LED

reg		ntsc = NTSC;			//PAL/NTSC video mode selection

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// NTSC/PAL switching is controlled by OSD menu, change requires reset to take effect
always @(posedge clk)
	if (reset)
		ntsc <= chipset_config[2];
		
//power led control
//when _led=0, pwrled=on
//when _led=1, pwrled=powered by weak pullup
assign pwrled = _led ? 1'bz : 1'b1;

//extra memory Chip Selects for additional RAM chips
assign {gpio2,gpio1,gpio0} = {_ramsel2,1'bz,_ramsel3};

//--------------------------------------------------------------------------------------

//indx signal generation, this signal is the disk index interrupt and is needed to let some
//loaders function correctly
//indx is asserted every 10 scanlines to simulate disk at 300 RPM
reg [3:0] indxcnt;

always @(posedge clk)
	if (indx)
		indxcnt[3:0] <= 0;
	else if (sof)
		indxcnt[3:0] <= indxcnt[3:0] + 1;
		
assign indx = (indxcnt[3:0]==9) ? 1 : 0;

//--------------------------------------------------------------------------------------

//switch address and control bus between agnus and cpu
always @(dma or cpuaddress or address_agnus)
	if (!dma)//address bus and control bus belongs to cpu
		address[23:1] = cpuaddress[23:1];
	else//address bus and control bus belongs to agnus
		address[23:1] = {cpuaddress[23:21],address_agnus[20:1]};

//--------------------------------------------------------------------------------------

//custom chips data input (workaround for reading of write-only registers)
assign customdatain = rd && !dma ? 16'hFFFF : data;

//--------------------------------------------------------------------------------------

//instantiate agnus
Agnus A1
(
	.clk(clk),
	.clk28m(clk28m),
	.cck(cck),
	.reset(reset),
	.aen(selreg),
	.rd(rd),
	.hwr(hwr),
	.lwr(lwr),
	.datain(customdatain),
	.dataout(agnusdataout),
	.addressin(address[8:1]),
	.addressout(address_agnus),
	.regaddress(regaddress),
	.bus(dma),
	.buswr(dmawr),
	.buspri(dmapri),
	._hsync(_hsync),
	._vsync(_vsync),
	._csync(_csync),
	.blank(blank),
	.sol(sol),
	.sof(sof),
	.strhor_denise(strhor_denise),
	.strhor_paula(strhor_paula),
	.htotal(htotal),
	.int3(int3),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	.bls(bls),
	.ntsc(ntsc),
	.floppy_speed(floppy_config[0]),
	.fastblitter((turbo|dbr_del)&chipset_config[1])	//in non-turbo mode blitter is blocked in any consecutive memory cycle accessed by chipset
);

//instantiate paula
Paula P1
(
	.clk(clk),
	.cck(cck),
	.reset(reset),
	.regaddress(regaddress),
	.datain(customdatain),
	.dataout(pauladataout),
	.txd(txd),
	.rxd(rxd),
	.strhor(strhor_paula),
	.sof(sof),
	.int2(int2|gayleint),
	.int3(int3),
	.int6(int6),
	._ipl(_iplx),
	.audio_dmal(audio_dmal),
	.audio_dmas(audio_dmas),
	.disk_dmal(disk_dmal),
	.disk_dmas(disk_dmas),
	._step(_step),
	.direc(direc),
	._sel({_sel3,_sel2,_sel1,_sel0}),
	.side(side),
	._motor(_motor),
	._track0(_track0),
	._change(_change),
	._ready(_ready),
	._wprot(_wprot),
	.disk_led(disk_led),
	._den(_spisel0),
	.din(spidin),
	.dout(paulaspidout),
	.dclk(spiclk),
	.left(left),
	.right(right),

	.floppy_drives(floppy_config[3:2]),
	//ide stuff
	.direct_sel(~_spisel2),
	.direct_din(spidout),
	.hdd_cmd_req(hdd_cmd_req),	
	.hdd_dat_req(hdd_dat_req),
	.hdd_addr(hdd_addr),
	.hdd_data_out(hdd_data_out),
	.hdd_data_in(hdd_data_in),
	.hdd_wr(hdd_wr),
	.hdd_status_wr(hdd_status_wr),
	.hdd_data_wr(hdd_data_wr),
	.hdd_data_rd(hdd_data_rd)
);

//instantiate user IO
userio UI1 
(	
	.clk(clk),
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
	._joy1(_joy1),
	._joy2(_joy2),
	.osdctrl(osdctrl),
	.keydis(keyboard_disable),
	._den(_spisel1),
	.din(spidin),
	.dout(userspidout),
	.dclk(spiclk),
	.osdblank(osdblank),
	.osdpixel(osdpixel),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.memory_config(memory_config),
	.chipset_config(chipset_config),
	.floppy_config(floppy_config),
	.scanline(scanline),
	.hdd_ena(hdd_ena),
	.usrrst(usrrst),
	.bootrst(bootrst)
);

assign cpu_speed = chipset_config[0];

//instantiate Denise
Denise DN1
(		
	.clk(clk),
	.reset(reset),
	.strhor(strhor_denise),
	.regaddress(regaddress),
	.datain(customdatain),
	.dataout(denisedataout),
	.blank(blank),
	.red(nred),
	.green(ngreen),
	.blue(nblue),
	.hires(hires)
);

//instantiate Amber
Amber AMB1
(		
	.clk(clk),
	.clk28m(clk28m),
	.dblscan(_15khz),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.scanline(scanline),
	.htotal(htotal),
	.hires(hires),
	.osdblank(osdblank),
	.osdpixel(osdpixel),
	.redin(nred),
	.bluein(nblue),
	.greenin(ngreen),
	._hsyncin(_hsync),
	._vsyncin(_vsync),
	._csyncin(_csync),
	.redout(redout),
	.blueout(blueout),
	.greenout(greenout),
	._hsyncout(_hsyncout),
	._vsyncout(_vsyncout)
);

//instantiate cia A
ciaa ciaa
(
	.clk(clk),
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
	.portain({_fire1,_fire0,_ready,_track0,_wprot,_change}),
	.portaout({_led,ovl}),
	.kbdrst(kbdrst),
	.kbddat(kbddat),
	.kbdclk(kbdclk),
	.keydis(keyboard_disable),
	.osdctrl(osdctrl),
	.freeze(freeze),
	.disk_led(disk_led)
);

//instantiate cia B
ciab ciab 
(
	.clk(clk),
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
	.portbout({_motor,_sel3,_sel2,_sel1,_sel0,side,direc,_step})
);


//instantiate cpu bridge
m68k_bridge M1 
(
	.cpuaddress(cpuaddress),
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),
	.cck(cck),
	.clk(clk),
	.dbr(dbr),
	.bls(bls),
	.cpuclk(cpuclk),
	.cpu_speed(cpu_speed),
	.turbo(turbo),
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
	.datain(data)
);

//instantiate RAM banks mapper
bank_mapper BM1
(
	.clk(clk),
	.reset(reset),
	.chip0((~ovr|~cpurd) & selchip & ~address[20] & ~address[19]),
	.chip1(selchip & ~address[20] & address[19]),
	.chip2(selchip & address[20] & ~address[19]),
	.chip3(selchip & address[20] & address[19]),	
	.slow0(selslow & ~address[20] & ~address[19]),
	.slow1(selslow & ~address[20] & address[19]),
	.slow2(selslow & address[20] & ~address[19]),
	.rom(selkick&(boot|rd)),
	.cart(selcart),
	.aron(aron),
	.memory_config(memory_config),
	.bank(bank)
);

//instantiate sram bridge
sram_bridge S1 
(
	.clk28m(clk28m),
	.c1(c1),
	.c3(c3),	
	.clk(clk),
	.bank(bank),
	.address(address[18:1]),
	.datain(data),
	.dataout(ramdataout),
	.rd(rd),
	.hwr(hwr),
	.lwr(lwr),
	._ub(_ub),
	._lb(_lb),
	._we(_we),
	._oe(_oe),
	._ce({_ramsel3,_ramsel2,_ramsel1,_ramsel0}),
	.ramaddress(ramaddress),
	.ramdata(ramdata)	
);

ActionReplay AR1
(
	.clk(clk),
	.reset(reset),
	.cpuaddress(cpuaddress[23:1]),
	.cpuclk(cpuclk),
	._as(_as),
	.regaddress(regaddress),
	.datain(data),
	.dataout(cartdataout),
	.cpurd(cpurd),
	.cpuhwr(cpuhwr),
	.cpulwr(cpulwr),
	.dma(dma),
	.boot(boot),
	.freeze(freeze),
	.int7(int7),
	.ovr(ovr),
	.selmem(selcart),
	.aron(aron)
);

//level 7 interrupt for CPU
assign _ipl = int7 ? 3'b000 : _iplx;	//m68k interrupt request

//instantiate gary
gary G1 
(
	.clk(clk),
	.cck(cck),
	.e(e),
	.cpuaddress(cpuaddress[23:12]),
	.cpurd(cpurd),
	.cpuhwr(cpuhwr),
	.cpulwr(cpulwr),
	.dbr(dbr),
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
	.selboot(selboot),
	.selide(selide),
	.selgayle(selgayle)
);

gayle GL1
(
	.clk(clk),
	.reset(reset),
	.address(cpuaddress),
	.datain(data),
	.dataout(gayledataout),
	.rd(cpurd),
	.hwr(cpuhwr),
	.lwr(cpulwr),
	.selide(selide),
	.selgayle(selgayle),
	.irq(gayleint),

	.hdd_ena(hdd_ena),	
	.hdd_cmd_req(hdd_cmd_req),
	.hdd_dat_req(hdd_dat_req),
	.hdd_data_in(hdd_data_in),
	.hdd_addr(hdd_addr),
	.hdd_data_out(hdd_data_out),
	.hdd_wr(hdd_wr),
	.hdd_status_wr(hdd_status_wr),
	.hdd_data_wr(hdd_data_wr),
	.hdd_data_rd(hdd_data_rd)
	
);
	
//instantiate boot rom
bootrom R1 
(	
	.clk(clk),
	.aen(selboot),
	.rd(rd),
	.address(cpuaddress[10:1]),
	.dataout(bootdataout)	
);

//instantiate system control
syscontrol L1 
(	
	.clk(clk),
	.mrst(kbdrst|usrrst),
	.bootdone(selciaa&selciab),
	.reset(reset),
	.boot(boot),
	.bootrst(bootrst)
);

//instantiate clock generator
clock_generator CG1
(	
	.mclk(mclk),
	.clk28m(clk28m),	// 28.37516 MHz clock output
	.c1(c1),			// clock enable signal
	.c3(c3),			// clock enable signal
	.cck(cck),			// colour clock enable
	.clk(clk),			// 7.09379  MHz clock output
	.e(e)				// ECLK enable (1/10th of CLK)
);

//used for blocking blitter access in compatibility mode
always @(posedge clk)
	dbr_del <= dbr;

//-------------------------------------------------------------------------------------

//data multiplexer
assign data[15:0] = ramdataout[15:0]
				  | cpudataout[15:0]
				  | pauladataout[15:0]
				  | userdataout
				  | denisedataout[15:0]
				  | bootdataout[15:0]
				  | ciadataout[15:0]
				  | agnusdataout[15:0]
				  | cartdataout[15:0]
				  | gayledataout[15:0];

//--------------------------------------------------------------------------------------

//spi multiplexer
assign spidout=(!_spisel0 || !_spisel1) ? (paulaspidout|userspidout) : 1'bz;

//--------------------------------------------------------------------------------------

//cpu reset and clock
assign _cpureset = ~reset;

//--------------------------------------------------------------------------------------

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
//JB:
//2008-07-11	- reset to bootloader
//2009-03-13	- shorter reset

module syscontrol
(
	input	clk,			//bus clock
	input	mrst,			//master/user reset input
	input	bootdone,		//bootrom program finished input
	output	reg reset,		//global synchronous system reset
	output	reg boot,		//bootrom overlay enable output
	input	bootrst			//reset to bootloader
);

//local signals
reg		smrst;					//registered input
reg		bootff = 0;				//boot control SHOULD BE CLEARED BY CONFIG
reg		[7:0] rstcnt = 0;		//reset timer SHOULD BE CLEARED BY CONFIG

//asynchronous mrst input synchronizer (JB: hmmm, it seems that all reset inputs are synchronous)
always @(posedge clk)
	smrst <= mrst;

//reset timer and mrst control
always @(posedge clk)
	if (smrst || (boot && bootdone && rstcnt[7]))
		rstcnt <= 0;
	else if (!rstcnt[7])
		rstcnt <= rstcnt+1;

//boot control
always @(posedge clk)
	if (bootrst)
		bootff <= 0;
	else if (bootdone && rstcnt[7])
		bootff <= 1;

//global reset output
always @(posedge clk)
	reset <= ~rstcnt[7];

//boot output
always @(posedge clk)
	boot <= ~bootff;

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//This module maps physical 512KB blocks of every memory chip to different memory ranges in Amiga
module bank_mapper
(
	input	clk,				// system clock
	input	reset,				// system reset
	input	chip0,				// chip ram select: 1st 512 KB block
	input	chip1,				// chip ram select: 2nd 512 KB block
	input	chip2,				// chip ram select: 3rd 512 KB block
	input	chip3,				// chip ram select: 4th 512 KB block
	input	slow0,				// slow ram select: 1st 512 KB block 
	input	slow1,				// slow ram select: 2nd 512 KB block 
	input	slow2,				// slow ram select: 3rd 512 KB block 
	input	rom,				// ROM address range select
	input	cart,				// Action Reply memory range select
	input	aron,				// Action Reply enable
	input	[3:0] memory_config,// memory configuration
	output	reg [7:0] bank		// bank select
);

reg	[3:0] memcfg;

//memory configuration changes takes effect after reset
always @(posedge clk)
	if (reset)
		memcfg <= memory_config;
		
always @(aron or memcfg or chip0 or chip1 or chip2 or chip3 or slow0 or slow1 or slow2 or rom or cart)
begin
	case ({aron,memcfg})
		5'b0_0000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom,  1'b0,  1'b0, chip0};	//0.5M CHIP
		5'b0_0001 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom,  1'b0, chip1, chip0}; //1.0M CHIP
		5'b0_0010 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom, chip2, chip1, chip0}; //1.5M CHIP
		5'b0_0011 : bank = {  1'b0,  1'b0, chip3,  1'b0,     rom, chip2, chip1, chip0}; //2.0M CHIP
		5'b0_0100 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom, slow0,  1'b0, chip0};	//0.5M CHIP + 0.5MB SLOW
		5'b0_0101 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom, slow0, chip1, chip0}; //1.0M CHIP + 0.5MB SLOW
		5'b0_0110 : bank = {  1'b0,  1'b0,  1'b0, slow0,     rom, chip2, chip1, chip0}; //1.5M CHIP + 0.5MB SLOW
		5'b0_0111 : bank = {  1'b0,  1'b0, chip3, slow0,     rom, chip2, chip1, chip0}; //2.0M CHIP + 0.5MB SLOW
		5'b0_1000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom, slow0, slow1, chip0};	//0.5M CHIP + 1.0MB SLOW
		5'b0_1001 : bank = {  1'b0,  1'b0, slow1,  1'b0,     rom, slow0, chip1, chip0}; //1.0M CHIP + 1.0MB SLOW
		5'b0_1010 : bank = {  1'b0,  1'b0, slow1, slow0,     rom, chip2, chip1, chip0}; //1.5M CHIP + 1.0MB SLOW
		5'b0_1011 : bank = { slow1,  1'b0, chip3, slow0,     rom, chip2, chip1, chip0}; //2.0M CHIP + 1.0MB SLOW
		5'b0_1100 : bank = {  1'b0,  1'b0,  1'b0, slow2,     rom, slow0, slow1, chip0};	//0.5M CHIP + 1.5MB SLOW
		5'b0_1101 : bank = {  1'b0,  1'b0, slow1, slow2,     rom, slow0, chip1, chip0}; //1.0M CHIP + 1.5MB SLOW
		5'b0_1110 : bank = {  1'b0, slow2, slow1, slow0,     rom, chip2, chip1, chip0}; //1.5M CHIP + 1.5MB SLOW
		5'b0_1111 : bank = { slow1, slow2, chip3, slow0,     rom, chip2, chip1, chip0}; //2.0M CHIP + 1.5MB SLOW
		
		5'b1_0000 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom,  cart,  1'b0, chip0};	//0.5M CHIP
		5'b1_0001 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom,  cart, chip1, chip0}; //1.0M CHIP
		5'b1_0010 : bank = {  1'b0,  1'b0,  1'b0, chip2,     rom,  cart, chip1, chip0}; //1.5M CHIP
		5'b1_0011 : bank = {  1'b0,  1'b0, chip3, chip2,     rom,  cart, chip1, chip0}; //2.0M CHIP
		5'b1_0100 : bank = {  1'b0,  1'b0,  1'b0,  1'b0,     rom,  cart, slow0, chip0};	//0.5M CHIP + 0.5MB SLOW
		5'b1_0101 : bank = {  1'b0,  1'b0,  1'b0, slow0,     rom,  cart, chip1, chip0}; //1.0M CHIP + 0.5MB SLOW
		5'b1_0110 : bank = {  1'b0,  1'b0, slow0, chip2,     rom,  cart, chip1, chip0}; //1.5M CHIP + 0.5MB SLOW
		5'b1_0111 : bank = {  1'b0, slow0, chip3, chip2,     rom,  cart, chip1, chip0}; //2.0M CHIP + 0.5MB SLOW
		5'b1_1000 : bank = {  1'b0,  1'b0, slow1,  1'b0,     rom,  cart, slow0, chip0};	//0.5M CHIP + 1.0MB SLOW
		5'b1_1001 : bank = {  1'b0,  1'b0, slow1, slow0,     rom,  cart, chip1, chip0}; //1.0M CHIP + 1.0MB SLOW
		5'b1_1010 : bank = { slow1,  1'b0, slow0, chip2,     rom,  cart, chip1, chip0}; //1.5M CHIP + 1.0MB SLOW
		5'b1_1011 : bank = { slow1, slow0, chip3, chip2,     rom,  cart, chip1, chip0}; //2.0M CHIP + 1.0MB SLOW
		5'b1_1100 : bank = {  1'b0,  1'b0, slow1, slow2,     rom,  cart, slow0, chip0};	//0.5M CHIP + 1.5MB SLOW
		5'b1_1101 : bank = {  1'b0, slow2, slow1, slow0,     rom,  cart, chip1, chip0}; //1.0M CHIP + 1.5MB SLOW
		5'b1_1110 : bank = { slow1, slow2, slow0, chip2,     rom,  cart, chip1, chip0}; //1.5M CHIP + 1.5MB SLOW
		5'b1_1111 : bank = { slow1, slow0, chip3, chip2,     rom,  cart, chip1, chip0}; //2.0M CHIP + 1.5MB SLOW
	endcase
end

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces the minimig's synchronous bus to the asynchronous sram
// on the Minimig rev1.0 board
//
// JB:
// 2008-09-23	- generation of write strobes moved to clk28m clock domain

module sram_bridge
(
	//clocks
	input	clk28m,						// 28 MHz system clock
	input	c1,							// clock enable signal
	input	c3,							// clock enable signal	
	input	clk,						// bus clock
	//chipset internal port
	input	[7:0] bank,					// memory bank select (512KB)
	input	[18:1] address,				// bus address
	input	[15:0] datain,				// bus data in
	output	[15:0] dataout,				// bus data out
	input	rd,			   				// bus read
	input	hwr,						// bus high byte write
	input	lwr,						// bus low byte write
	//SRAM external signals
	output	reg _ub = 1,				// sram upper byte
	output	reg _lb = 1,   				// sram lower byte
	output	reg _we = 1,				// sram write enable
	output	reg _oe = 1,				// sram output enable
	output	reg [3:0] _ce = 4'b1111,	// sram chip enable
	output	reg [19:1] ramaddress,		// sram address bus
	inout	[15:0] ramdata	  			// sram data das
);	 

/* basic timing diagram

phase          : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  : Q2  : Q3  : Q0  : Q1  :
               :     :     :     :     :     :     :     :     :     :     :
			    ___________             ___________             ___________
clk			___/           \___________/           \___________/           \_____ (7.09 MHz - dedicated clock)

               :     :     :     :     :     :     :     :     :     :     :
			    __    __    __    __    __    __    __    __    __    __    __
clk28m		___/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__ (28.36 MHz - dedicated clock)
               :     :     :     :     :     :     :     :     :     :     :
			    ___________             ___________             ___________
c1			___/           \___________/           \___________/           \_____ (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
			          ___________             ___________             ___________
c3			_________/           \___________/           \___________/            (7.09 MHz)
               :     :     :     :     :     :     :     :     :     :     :
			_________                   _____                   _____   
_ce			         \_________________/     \_________________/     \___________ (ram chip enable)
               :     :     :     :     :     :     :     :     :     :     :
			_______________             ___________             ___________   
_we			               \___________/           \___________/           \_____ (ram write strobe)
               :     :     :     :     :     :     :     :     :     :     :
			_________                   _____                   _____
_oe			         \_________________/     \_________________/     \___________ (ram output enable)
               :     :     :     :     :     :     :     :     :     :     :
			          _________________       _________________       ___________
doe			_________/                 \_____/                 \_____/            (data bus output enable)
               :     :     :     :     :     :     :     :     :     :     :
*/

wire	enable;				// indicates memory access cycle
reg		doe;				// data output enable (activates ram data bus buffers during write cycle)

// generate enable signal if any of the banks is selected
assign enable = |bank[7:0];

// generate _we
always @(posedge clk28m)
	if (!c1 && !c3) // deassert write strobe in Q0
		_we <= 1'b1;
	else if (c1 && c3 && enable && !rd)	//assert write strobe in Q2
		_we <= 1'b0;

// generate ram output enable _oe
always @(posedge clk28m)
	if (!c1 && !c3) // deassert output enable in Q0
		_oe <= 1'b1;
	else if (c1 && !c3 && enable && rd)	//assert output enable in Q1 during read cycle
		_oe <= 1'b0;

// generate ram upper byte enable _ub
always @(posedge clk28m)
	if (!c1 && !c3) // deassert upper byte enable in Q0
		_ub <= 1'b1;
	else if (c1 && !c3 && enable && rd) // assert upper byte enable in Q1 during read cycle
		_ub <= 1'b0;
	else if (c1 && c3 && enable && hwr) // assert upper byte enable in Q2 during write cycle
		_ub <= 1'b0;
		
// generate ram lower byte enable _lb
always @(posedge clk28m)
	if (!c1 && !c3) // deassert lower byte enable in Q0
		_lb <= 1'b1;
	else if (c1 && !c3 && enable && rd) // assert lower byte enable in Q1 during read cycle
		_lb <= 1'b0;	
	else if (c1 && c3 && enable && lwr) // assert lower byte enable in Q2 during write cycle
		_lb <= 1'b0;
			
//generate data buffer output enable
always @(posedge clk28m)
	if (!c1 && !c3)  // deassert output enable in Q0
		doe <= 1'b0;
	else if (c1 && !c3 && enable && !rd) // assert output enable in Q1 during write cycle
		doe <= 1'b1;	

// generate sram chip selects (every sram chip is 512K x 16bits)
always @(posedge clk28m)
	if (!c1 && !c3) // deassert chip selects in Q0
		_ce[3:0] <= 4'b1111;
	else if (c1 && !c3) // assert chip selects in Q1
		_ce[3:0] <= {~|bank[7:6],~|bank[5:4],~|bank[3:2],~|bank[1:0]};

// ram address bus
always @(posedge clk28m)
	if (c1 && !c3 && enable)	// set address in Q1		
		ramaddress <= {bank[7]|bank[5]|bank[3]|bank[1],address[18:1]};
			
// dataout multiplexer
assign dataout[15:0] = (enable && rd) ? ramdata[15:0] : 16'b0000000000000000;

// data bus output buffers
assign ramdata[15:0] = doe ? datain[15:0] : 16'bz;

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// This module interfaces the minimig's synchronous bus to the asynchronous 
// MC68SEC000 bus on the Minimig rev1.0 board

module m68k_bridge
(
	input	[23:1] cpuaddress,
	input	clk28m,					// 28 MHz system clock
	input	c1,						// clock enable signal
	input	c3,						// clock enable signal
	input	clk,					// bus clock
	input	dbr, 					// data bus request, Gary keeps CPU off the bus
	output	bls,					// blitter slowdown, tells the blitter that CPU wants the bus
	input	cck,					// colour clock enable, active when dma can access the memory bus
	output	cpuclk,					// m68k clock
	input	cpu_speed,				// CPU speed select request
	output	reg turbo,				// indicates current CPU speed mode
	input	_as,					// m68k adress strobe
	input	_lds,					// m68k lower data strobe d0-d7
	input	_uds,					// m68k upper data strobe d8-d15
	input	r_w,					// m68k read / write
	output	reg _dtack,				// m68k data acknowledge to cpu
	output	rd,						// bus read 
	output	hwr,					// bus high write
	output	lwr,					// bus low write
	inout	[15:0] data,			// m68k data
	output	reg [15:0] dataout,		// bus data out
	input	[15:0] datain			// bus data in
);

/*
68000 bus timing diagram

          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
        7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1 . 2 . 3 . 4 . 5 . 6 . 7 . 0 . 1
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
           ___     ___     ___     ___     ___     ___     ___     ___     ___
CLK    ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \___
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________________________________                         _____		  
R/W                 \_ _ _ _ _ _ _ _ _ _ _ _/       \_______________________/     
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _________ _______________________________ _______________________________ _		  
ADDR   _________X_______________________________X_______________________________X_
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________                     ___________                     _________
/AS                 \___________________/           \___________________/         
          .....   .   .   .       .   .   .....   .   .   .   .       .   .....
       _____________        READ         ___________________    WRITE    _________
/DS                 \___________________/                   \___________/         
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
       _____________________     ___________________________     _________________
/DTACK                      \___/                           \___/                 
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                     ___
DIN    -----------------------------<___>-----------------------------------------
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
                                                         ___________________
DOUT   -------------------------------------------------<___________________>-----
          .....   .   .   .   .   .   .   .....   .   .   .   .   .   .   .....
*/

wire	doe;					// data buffer output enable
reg		[15:0] ldatain;			// latched datain
wire	enable;					// enable
reg		lr_w,l_as,l_dtack;  	// synchronised inputs
reg		l_uds,l_lds;

reg		ldbr;					// latched data bus request
reg		_ta;					// transfer acknowledge

//CPU speed mode is allowed to change only when there is no bus access
always @(posedge clk28m)
	if (_as)
		turbo <= cpu_speed;

//latched data bus request (chipset dma cycle)
always @(posedge clk28m)
	ldbr <= dbr;

//latched CPU bus control signals
always @(posedge clk)
	{lr_w,l_as,l_uds,l_lds,l_dtack} <= {r_w,_as,_uds,_lds,_dtack};

//transfer acknowledge
always @(posedge clk28m or posedge _as)
	if (_as)
		_ta <= 1;
	else if (!l_as && cck && !ldbr && c1 && c3 && !turbo)
		_ta <= 0;	
	else if (!l_as && !ldbr && c1 && c3 && turbo)
		_ta <= 0;

// CPU data transfer acknowledge
always @(negedge clk28m or posedge _as)
	if (_as)
		_dtack <= 1;
	else
		_dtack <= _ta;
		
assign enable = (~l_as & ~l_dtack & ~cck & ~turbo) | (~l_as & l_dtack /*~cck*/ & ~dbr & turbo);
assign rd = enable & lr_w;
//during write cycles _uds/_lds are asserted one clock after _as
//in 7MHz operation everything is fine since _as is sampled one 7M clock before asserting _dtack, 
//actual register/memory access cycle takes place when _dtack is asserted (cck is low)
//in 28MHz mode _uds/_lds might be asserted one 28M clock after _as was sampled,
//it's needed at the rising edge of 7M clock for qualifying chipset writes, 
//memory writes use hwr/lwr at the falling edge of 7M clock to assert memory byte enables (_ub/_lb)
assign hwr = enable & ~lr_w & ~_uds; 
assign lwr = enable & ~lr_w & ~_lds;
//blitter slow down signalling, asserted whenever CPU is missing bus access
//to chip ram, slow ram and custom registers 
assign bls = !turbo && (cpuaddress[23:21]==3'b000 || cpuaddress[23:21]==3'b110) ? ~l_as & l_dtack : 0;

// generate data buffer output enable
assign doe = r_w & ~_as;

//--------------------------------------------------------------------------------------

// dataout multiplexer and latch 	
always @(enable or lr_w or data)
	if (enable && !lr_w)
		dataout = data;
	else
		dataout = 16'b0000_0000_0000_0000;

// datain latch
always @(enable or datain)
	if (enable)
		ldatain <= datain;

//--------------------------------------------------------------------------------------

// CPU data bus tristate buffers
assign data[15:0] = doe ? ldatain[15:0] : 16'bz;

//CPU clock multiplexer
BUFGMUX cpuclk_buf 
(
	.O(cpuclk),		// Clock MUX output
	.I0(~clk),		// Clock0 input
	.I1(~clk28m),	// Clock1 input
	.S(turbo)		// Clock select input
);

endmodule

