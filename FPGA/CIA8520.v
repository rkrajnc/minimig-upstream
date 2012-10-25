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
// These are the cia's
// Note that these are simplified implementation of both CIA's, just enough
// to get Minimig going
// NOT implemented is:
// serial data register for CIA B(but keyboard input for CIA A is supported)
// port B for CIA A
// counter inputs for timer A and B other then 'E' clock
// toggling of PB6/PB7 by timer A/B
//
// 30-03-2005		-started coding 
//				-intterupt description finished
// 03-04-2005		-added timers A,B and D
// 05-04-2005		-simplified state machine of timerab
//				-improved timing of timer-reload of timerab
//				-cleaned up timer d
//				-moved intterupt part to seperate module
//				-created nice central address decoder
// 06-04-2005		-added I/O ports
//				-fixed small bug in timerab state machine
// 10-04-2005		-added clock synchronisation latch on input ports
//				-added rd (read) input to detect valid bus states
// 11-04-2005		-removed rd again due to change in address decoder
//				-better reset behaviour for timer D
// 17-04-2005		-even better reset behaviour for timer D and timers A and B
// 17-07-2005		-added pull-up simulation on I/O ports
// 21-12-2005		-added rd input
// 21-11-2006		-splitted in seperate ciaa and ciab
//				-added ps2 keyboard module to ciaa
// 22-11-2006		-added keyboard reset
// 05-12-2006		-added keyboard acknowledge
// 11-12-2006		-ciaa cleanup
// 27-12-2006		-ciab cleanup
// 01-01-2007		-osdctrl[] is now 4 bits/keys


// JB:
// 2008-03-25	- osdctrl[] is 6 bits/keys (Ctrl+Break and PrtScr keys added)
//				- verilog 2001 style declaration
// 2008-04-02	- separate Timer A and Timer B descriptions (they differ a little)
//				- one-shot mode of Timer A/B sets START bit in control register
//				- implemented Timer B counting mode of Timer A underflows
// 2008-04-25	- added transmit interrupt for serial port
// 2008-07-28	- scroll lock led as disk activity led
//
//
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia a*/
module ciaa
(
	input 	clk,	  			//clock
	input 	aen,		    	//adress enable
	input	rd,					//read enable
	input	wr,					//write enable
	input 	reset, 				//reset
	input 	[3:0]rs,	   		//register select (address)
	input 	[7:0]datain,		//bus data in
	output 	[7:0]dataout,		//bus data out
	input 	tick,				//tick (counter input for TOD timer)
	input 	e,	    			//e (counter input for timer A/B)
	output 	irq,	   			//interrupt request out
	input	[7:2]portain, 	//porta in
	output 	[1:0]portaout,	//porta out
	output	kbdrst,				//keyboard reset out
	inout	kbddat,				//ps2 keyboard data
	inout	kbdclk,				//ps2 keyboard clock
	output	[5:0]osdctrl		//osd control
);

//local signals
wire 	[7:0]icrout;
wire	[7:0]tmraout;			
wire	[7:0]tmrbout;
wire	[7:0]tmrdout;
wire	[7:0]sdrout;	
reg		[7:0]paout;
wire	alrm;				//TOD interrupt
wire	ta;					//TIMER A interrupt
wire	tb;					//TIMER B interrupt
wire	tmra_ovf;			//TIMER A underflow (for Timer B)
wire	tmra_start;			//TIMER A is running

//JB:
//Action Replay writes to serial data register when serial port is in output mode
//and timer A is running, then checks if interrupt for serial port has been asserted
//this all if for figuring out if serial port interrupt has been enabled
//if this part is missing keyboard is not working any more after exiting actiorn replay
//
//see: $4147BE: CLR.B  $C00(A0) ; = $BFEC01 (sdr)
//     ...
//     $4147D2: MOVE.B $D00(A0),D0
//     ...
//     $4147DE: BTST   #3,D0
// copy of recovered ICR stored at $44F983.B

wire	spmode;				//TIMER A Serial Port Mode (0-input, 1-output)
wire	ser_tx_irq;

//----------------------------------------------------------------------------------
//address decoder
//----------------------------------------------------------------------------------
wire	pra,ddra,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs,sdr;
wire	enable;

assign enable = aen & (rd | wr);

//decoder
assign	pra  = (enable && rs==0)?1:0;
assign	ddra = (enable && rs==2)?1:0;
assign	talo = (enable && rs==4)?1:0;
assign	tahi = (enable && rs==5)?1:0;
assign	tblo = (enable && rs==6)?1:0;
assign	tbhi = (enable && rs==7)?1:0;
assign	tdlo = (enable && rs==8)?1:0;
assign	tdme = (enable && rs==9)?1:0;
assign	tdhi = (enable && rs==10)?1:0;
assign	sdr  = (enable && rs==12)?1:0;
assign	icrs = (enable && rs==13)?1:0;
assign	cra  = (enable && rs==14)?1:0;
assign	crb  = (enable && rs==15)?1:0;

//----------------------------------------------------------------------------------
//dataout multiplexer
//----------------------------------------------------------------------------------
assign dataout=icrout|tmraout|tmrbout|tmrdout|sdrout|paout;

//----------------------------------------------------------------------------------
//instantiate keyboard module
//----------------------------------------------------------------------------------
wire	keystrobe,keyack;
reg		[7:0]sdrlatch;
wire	[7:0]keydat;

ps2keyboard	kbd1
(
	.clk(clk),
	.reset(reset),
	.ps2kdat(kbddat),
	.ps2kclk(kbdclk),
	.leda(~portaout[1]),	//power led
	.ledb(~portain[5]),	//disk ready, active while motor on and drive selected
	.kbdrst(kbdrst),
	.keydat(keydat[7:0]),
	.keystrobe(keystrobe),
	.keyack(keyack),
	.osdctrl(osdctrl)
);

//sdr register
//!!! Amiga receives keycode ONE STEP ROTATED TO THE RIGHT AND INVERTED !!!
always @(posedge clk)
	if(reset)
		sdrlatch[7:0] <= 8'h00;
	else if(keystrobe)
		sdrlatch[7:0] <= ~{keydat[6:0],keydat[7]};

//sdr register	read
assign sdrout = (!wr && sdr) ? sdrlatch[7:0] : 8'h00;
//keyboard acknowledge
assign keyack = (!wr && sdr) ? 1 : 0;

//interrupt on serial port data port write when serial port is in output mode and Timer A is running

assign ser_tx_irq = sdr & wr & spmode & tmra_start;	

//----------------------------------------------------------------------------------
//porta
//----------------------------------------------------------------------------------
reg [7:2]portain2;
reg [1:0]regporta;
reg [7:0]ddrporta;

//synchronizing of input data
always @(posedge clk)
	portain2[7:2] <= portain[7:2];

//writing of output port
always @(posedge clk)
	if(reset)
		regporta[1:0] <= 0;
	else if(wr && pra)
		regporta[1:0] <= datain[1:0];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrporta[7:0] <= 0;
	else if(wr && ddra)
 		ddrporta[7:0] <= datain[7:0];

//reading of port/ddr register
always @(wr or pra or portain2 or portaout or ddra or ddrporta)
begin
	if(!wr && pra)
		paout[7:0] = {portain2[7:2],portaout[1:0]};
	else if(!wr && ddra)
		paout[7:0] = ddrporta[7:0];
	else
		paout[7:0] = 8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portaout[1:0] = (~ddrporta[1:0]) | regporta[1:0];	
 
//----------------------------------------------------------------------------------
//instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.icrs(icrs),
	.ta(ta),
	.tb(tb),
	.alrm(alrm),
	.flag(1'b0),
	.ser(keystrobe | ser_tx_irq ),
	.datain(datain),
	.dataout(icrout),
	.irq(irq)	
);

//----------------------------------------------------------------------------------
//instantiate timer A
//----------------------------------------------------------------------------------
timera tmra 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(talo),
	.thi(tahi),
	.tcr(cra),
	.datain(datain),
	.dataout(tmraout),
	.eclk(e),
	.spmode(spmode),
	.tmra_ovf(tmra_ovf),
	.start(tmra_start),
	.irq(ta) 
);

//----------------------------------------------------------------------------------
//instantiate timer B
//----------------------------------------------------------------------------------
timerb tmrb 
(	
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tblo),
	.thi(tbhi),
	.tcr(crb),
	.datain(datain),
	.dataout(tmrbout),
	.eclk(e),
	.tmra_ovf(tmra_ovf),
	.irq(tb) 
);

//----------------------------------------------------------------------------------
//instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tdlo),
	.tme(tdme),
	.thi(tdhi),
	.tcr(crb),
	.datain(datain),
	.dataout(tmrdout),
	.count(tick),
	.irq(alrm)	
); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia b*/
module ciab
(
	input 	clk,	  			//clock
	input 	aen,		    	//adress enable
	input	rd,					//read enable
	input	wr,					//write enable
	input 	reset, 				//reset
	input 	[3:0]rs,	   		//register select (address)
	input 	[7:0]datain,		//bus data in
	output 	[7:0]dataout,		//bus data out
	input 	tick,				//tick (counter input for TOD timer)
	input 	e,	    			//e (counter input for timer A/B)
	input 	flag, 				//flag (set FLG bit in ICR register)
	output 	irq,	   			//interrupt request out
	input	[5:3]portain, 	//input port
	output 	[7:6]portaout,	//output port
	output	[7:0]portbout		//output port
);

//local signals
	wire 	[7:0]icrout;
	wire	[7:0]tmraout;			
	wire	[7:0]tmrbout;
	wire	[7:0]tmrdout;	
	reg		[7:0]paout;
	reg		[7:0]pbout;		
	wire	alrm;				//TOD interrupt
	wire	ta;					//TIMER A interrupt
	wire	tb;					//TIMER B interrupt
	wire	tmra_ovf;		//TIMER A underflow (for Timer B)

//----------------------------------------------------------------------------------
//address decoder
//----------------------------------------------------------------------------------
	wire	pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs;
	wire	enable;

assign enable = aen & (rd | wr);

//decoder
assign	pra  = (enable && rs==0)?1:0;
assign	prb  = (enable && rs==1)?1:0;
assign	ddra = (enable && rs==2)?1:0;
assign	ddrb = (enable && rs==3)?1:0;
assign	talo = (enable && rs==4)?1:0;
assign	tahi = (enable && rs==5)?1:0;
assign	tblo = (enable && rs==6)?1:0;
assign	tbhi = (enable && rs==7)?1:0;
assign	tdlo = (enable && rs==8)?1:0;
assign	tdme = (enable && rs==9)?1:0;
assign	tdhi = (enable && rs==10)?1:0;
assign	icrs = (enable && rs==13)?1:0;
assign	cra  = (enable && rs==14)?1:0;
assign	crb  = (enable && rs==15)?1:0;

//----------------------------------------------------------------------------------
//dataout multiplexer
//----------------------------------------------------------------------------------
assign dataout = icrout | tmraout | tmrbout | tmrdout | paout | pbout;

//----------------------------------------------------------------------------------
//porta
//----------------------------------------------------------------------------------
	reg [5:3]portain2;
	reg [7:6]regporta;
	reg [7:0]ddrporta;

//synchronizing of input data
always @(posedge clk)
	portain2[5:3] <= portain[5:3];

//writing of output port
always @(posedge clk)
	if(reset)
		regporta[7:6] <= 0;
	else if(wr && pra)
		regporta[7:6] <= datain[7:6];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrporta[7:0] <= 0;
	else if(wr && ddra)
 		ddrporta[7:0] <= datain[7:0];

//reading of port/ddr register
always @(wr or pra or portain2 or portaout or ddra or ddrporta)
begin
	if(!wr && pra)
		paout[7:0] = {portaout[7:6],portain2[5:3],3'b111};
	else if(!wr && ddra)
		paout[7:0] = ddrporta[7:0];
	else
		paout[7:0] = 8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portaout[7:6] = (~ddrporta[7:6]) | regporta[7:6];	

//----------------------------------------------------------------------------------
//portb
//----------------------------------------------------------------------------------
	reg [7:0]regportb;
	reg [7:0]ddrportb;

//writing of output port
always @(posedge clk)
	if(reset)
		regportb[7:0] <= 0;
	else if(wr && prb)
		regportb[7:0] <= datain[7:0];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrportb[7:0] <= 0;
	else if(wr && ddrb)
 		ddrportb[7:0] <= datain[7:0];

//reading of port/ddr register
always @(wr or prb or portbout or ddrb or ddrportb)
begin
	if(!wr && prb)
		pbout[7:0] = portbout[7:0];
	else if(!wr && ddrb)
		pbout[7:0] = ddrportb[7:0];
	else
		pbout[7:0] = 8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portbout[7:0] = (~ddrportb[7:0]) | regportb[7:0];	
 
//----------------------------------------------------------------------------------
//instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.icrs(icrs),
	.ta(ta),
	.tb(tb),
	.alrm(alrm),
	.flag(flag),
	.ser(1'b0),
	.datain(datain),
	.dataout(icrout),
	.irq(irq)
);

//----------------------------------------------------------------------------------
//instantiate timer A
//----------------------------------------------------------------------------------
timera tmra
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(talo),
	.thi(tahi),
	.tcr(cra),
	.datain(datain),
	.dataout(tmraout),
	.eclk(e),
	.tmra_ovf(tmra_ovf),
	.irq(ta) 
);

//----------------------------------------------------------------------------------
//instantiate timer B
//----------------------------------------------------------------------------------
timerb tmrb
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tblo),
	.thi(tbhi),
	.tcr(crb),
	.datain(datain),
	.dataout(tmrbout),
	.eclk(e),
	.tmra_ovf(tmra_ovf),
	.irq(tb)
);

//----------------------------------------------------------------------------------
//instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd 
(
	.clk(clk),
	.wr(wr),
	.reset(reset),
	.tlo(tdlo),
	.tme(tdme),
	.thi(tdhi),
	.tcr(crb),
	.datain(datain),
	.dataout(tmrdout),
	.count(tick),
	.irq(alrm)
); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//interrupt control
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module ciaint
(
	input 	clk,	  			//clock
	input	wr,					//write enable
	input 	reset, 				//reset
	input 	icrs,				//intterupt control register select
	input	ta,					//ta (set TA bit in ICR register)
	input	tb,				    //tb (set TB bit in ICR register)
	input	alrm,	 			//alrm (set ALRM bit ICR register)
	input 	flag, 				//flag (set FLG bit in ICR register)
	input 	ser,				//ser (set SP bit in ICR register)
	input 	[7:0]datain,		//bus data in
	output 	reg [7:0]dataout,	//bus data out
	output	irq					//intterupt out
);

	reg		[4:0]icr;				//interrupt register
	reg		[4:0]icrmask;			//interrupt mask register

//reading of interrupt data register 
always @(wr or irq or icrs or icr)
	if(icrs && !wr)
		dataout[7:0] = {irq,2'b0,icr[4:0]};
	else
		dataout[7:0] = 0;

//writing of interrupt mask register
always @(posedge clk)
	if(reset)
		icrmask[4:0] <= 0;
	else if(icrs && wr)
	begin
		if(datain[7])
			icrmask[4:0] <= icrmask[4:0] | datain[4:0];
		else
			icrmask[4:0] <= icrmask[4:0] & (~datain[4:0]);
	end

//register new interrupts and/or changes by user reads
always @(posedge clk)
	if(reset)//synchronous reset	
		icr[4:0] <= 0;
	else	if (icrs && !wr)
	begin//clear latched intterupts on read
		icr[0] <= ta;				//timer a
		icr[1] <= tb;				//timer b
		icr[2] <= alrm;   		//timer tod
		icr[3] <= ser;	 		//external ser input
		icr[4] <= flag;			//external flag input
	end
	else
	begin//keep latched intterupts
		icr[0] <= icr[0]|ta;		//timer a
		icr[1] <= icr[1]|tb;		//timer b
		icr[2] <= icr[2]|alrm;	//timer tod
		icr[3] <= icr[3]|ser;	//external ser input
		icr[4] <= icr[4]|flag;	//external flag input
	end

//generate irq output (interrupt request)
assign irq 	= (icrmask[0]&icr[0]) 
			| (icrmask[1]&icr[1])
			| (icrmask[2]&icr[2])
			| (icrmask[3]&icr[3])
			| (icrmask[4]&icr[4]);

endmodule

//----------------------------------------------------------------------------------
//timer A/B
//----------------------------------------------------------------------------------

module timera
(
	input 	clk,	  				//clock
	input	wr,						//write enable
	input 	reset, 					//reset
	input 	tlo,					//timer low byte select
	input	thi,		 			//timer high byte select
	input	tcr,					//timer control register
	input 	[7:0]datain,			//bus data in
	output 	[7:0]dataout,			//bus data out
	input	eclk,	  				//count enable
	output	tmra_ovf,				//timer A underflow
	output	spmode,					//serial port mode
	output	start,					//timer start (enable)
	output	irq						//intterupt out
);

	reg		[15:0]tmr;			//timer 
	reg		[7:0]tmlh;			//timer latch high byte
	reg		[7:0]tmll;			//timer latch low byte
	reg		[6:0]tmcr;			//timer control register
	reg		forceload;				//force load strobe
	wire	oneshot;				//oneshot mode
	//wire	start;					//timer start (enable)
	reg		oneshot_load;    		//load tmr after writing thi in one-shot mode
	wire	reload;					//reload timer counter
	wire	zero;					//timer counter is zero
	wire	underflow;				//timer is going to underflow
	wire	count;					//count enable signal
	
//count enable signal	
assign count = eclk;
	
//writing timer control register
always @(posedge clk)
	if(reset)	//synchronous reset
		tmcr[6:0] <= 0;
	else if (tcr && wr)	//load control register, bit 4(strobe) is always 0
		tmcr[6:0] <= {datain[6:5],1'b0,datain[3:0]};
	else if (oneshot_load)	//start timer if thi is written in one-shot mode
		tmcr[0] <= 1;
	else if (underflow && oneshot) //stop timer in one-shot mode
		tmcr[0] <= 0;

always @(posedge clk)
	forceload <= tcr & wr & datain[4];	//force load strobe 
	
assign oneshot = tmcr[3];		//oneshot alias
assign start = tmcr[0];		//start alias
assign spmode = tmcr[6];		//serial port mode (0-input, 1-output)

//timer A latches for high and low byte
always @(posedge clk)
	if (reset)
		tmll[7:0] <= 8'b11111111;
	else if (tlo && wr)
		tmll[7:0] <= datain[7:0];
		
always @(posedge clk)
	if (reset)
		tmlh[7:0] <= 8'b11111111;
	else if (thi && wr)
		tmlh[7:0] <= datain[7:0];

//thi is written in one-shot mode so tmr must be reloaded
always @(posedge clk)
	oneshot_load <= thi & wr & oneshot;

//timer counter reload signal
assign reload = oneshot_load | forceload | underflow;

//timer counter	
always @(posedge clk)
	if (reset)
		tmr[15:0] <= 0;
	else if (reload)
		tmr[15:0] <= {tmlh[7:0],tmll[7:0]};
	else if (start && count)
		tmr[15:0] <= tmr[15:0] - 1;

//timer counter equals zero		
assign zero = ~|tmr;		

//timer counter is going to underflow
assign underflow = zero & start & count;

//Timer A underflow signal for Timer B
assign tmra_ovf = underflow;

//timer underflow interrupt request
assign irq = underflow;

//data output
assign dataout[7:0] = ({8{~wr&tlo}} & tmr[7:0]) 
					  | ({8{~wr&thi}} & tmr[15:8])
					  | ({8{~wr&tcr}} & {1'b0,tmcr[6:0]});		
				
endmodule

module timerb
(
	input 	clk,	  				//clock
	input	wr,						//write enable
	input 	reset, 					//reset
	input 	tlo,					//timer low byte select
	input	thi,		 			//timer high byte select
	input	tcr,					//timer control register
	input 	[7:0]datain,			//bus data in
	output 	[7:0]dataout,			//bus data out
	input	eclk,	  				//count enable
	input	tmra_ovf,			//timer A underflow
	output	irq						//intterupt out
);

	reg		[15:0]tmr;			//timer 
	reg		[7:0]tmlh;			//timer latch high byte
	reg		[7:0]tmll;			//timer latch low byte
	reg		[6:0]tmcr;			//timer control register
	reg		forceload;				//force load strobe
	wire	oneshot;				//oneshot mode
	wire	start;					//timer start (enable)
	reg		oneshot_load; 			//load tmr after writing thi in one-shot mode
	wire	reload;					//reload timer counter
	wire	zero;					//timer counter is zero
	wire	underflow;				//timer is going to underflow
	wire	count;					//count enable signal

//Timer B count signal source
assign count = tmcr[6] ? tmra_ovf : eclk;

//writing timer control register
always @(posedge clk)
	if(reset)	//synchronous reset
		tmcr[6:0] <= 0;
	else if (tcr && wr)	//load control register, bit 4(strobe) is always 0
		tmcr[6:0] <= {datain[6:5],1'b0,datain[3:0]};
	else if (oneshot_load)	//start timer if thi is written in one-shot mode
		tmcr[0] <= 1;
	else if (underflow && oneshot) //stop timer in one-shot mode
		tmcr[0] <= 0;

always @(posedge clk)
	forceload <= tcr & wr & datain[4];	//force load strobe 
	
assign oneshot = tmcr[3];					//oneshot alias
assign start = tmcr[0];					//start alias

//timer B latches for high and low byte
always @(posedge clk)
	if (reset)
		tmll[7:0] <= 8'b11111111;
	else if (tlo && wr)
		tmll[7:0] <= datain[7:0];
		
always @(posedge clk)
	if (reset)
		tmlh[7:0] <= 8'b11111111;
	else if (thi && wr)
		tmlh[7:0] <= datain[7:0];

//thi is written in one-shot mode so tmr must be reloaded
always @(posedge clk)
	oneshot_load <= thi & wr & oneshot;

//timer counter reload signal
assign reload = oneshot_load | forceload | underflow;

//timer counter	
always @(posedge clk)
	if (reset)
		tmr[15:0] <= 0;
	else if (reload)
		tmr[15:0] <= {tmlh[7:0],tmll[7:0]};
	else if (start && count)
		tmr[15:0] <= tmr[15:0] - 1;

//timer counter equals zero		
assign zero = ~|tmr;		

//timer counter is going to underflow
assign underflow = zero & start & count;

//timer underflow interrupt request
assign irq = underflow;

//data output
assign dataout[7:0] = ({8{~wr&tlo}} & tmr[7:0]) 
				| ({8{~wr&thi}} & tmr[15:8])
				| ({8{~wr&tcr}} & {1'b0,tmcr[6:0]});		
				
endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//timer D
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module timerd
(
	input 	clk,	  				//clock
	input	wr,						//write enable
	input 	reset, 					//reset
	input 	tlo,					//timer low byte select
	input 	tme,					//timer mid byte select
	input	thi,		 			//timer high byte select
	input	tcr,					//timer control register
	input 	[7:0]datain,			//bus data in
	output 	reg [7:0]dataout,		//bus data out
	input	count,	  				//count enable
	output	reg irq					//intterupt out
);

	reg		le;						//timer d output latch enable
	reg 	ce;						//timer d count enable
	reg		crb7;					//bit 7 of control register B
	reg		[23:0]tod;			//timer d
	reg		[23:0]alarm;			//alarm
	reg		[15:0]todl;			//timer d latch

//timer D output latch control
always @(posedge clk)
	if(reset)
		le <= 1;
	else if(!wr)
	begin
		if(thi)//if MSB read, hold data for subsequent reads
			le <= 0;
		else if (tlo)//if LSB read, update data every clock
			le <= 1;
	end
always @(posedge clk)
	if(le)
		todl[15:0] <= tod[15:0];

//timer D and crb7 read 
always @(wr or tlo or tme or thi or tcr or tod or todl or crb7)
	if (!wr)
	begin
		if(thi)//high byte of timer D
			dataout[7:0] = tod[23:16];
		else if (tme)//medium byte of timer D (latched)
			dataout[7:0] = todl[15:8];
		else if (tlo)//low byte of timer D (latched)
			dataout[7:0] = todl[7:0];
		else if (tcr)//bit 7 of crb
			dataout[7:0] = {crb7,7'b0000000};
		else
			dataout[7:0] = 0;
	end
	else
		dataout[7:0] = 0;  

//timer D count enable control
always @(posedge clk)
	if(reset)
		ce <= 1;
	else if(wr && !crb7)//crb7==0 enables writing to TOD counter
	begin
		if(thi || tme)//stop counting
			ce <= 0;
		else if(tlo)//write to LSB starts counting again
			ce <= 1;			
	end

//timer D counter
always @(posedge clk)
	if(reset)//synchronous reset
	begin
		tod[7:0] <= 0;
		tod[15:8] <= 0;
		tod[23:16] <= 0;
	end
	else if(wr && !crb7)//crb7==0 enables writing to TOD counter
	begin
		if(tlo)
			tod[7:0] <= datain[7:0];
		if(tme)
			tod[15:8] <= datain[7:0];
		if(thi)
			tod[23:16] <= datain[7:0];
	end
	else if(ce && count)
		tod[23:0] <= tod[23:0]+1;

//alarm write
always @(posedge clk)
	if(reset)//synchronous (p)reset
	begin
		alarm[7:0] <= 8'b11111111;
		alarm[15:8] <= 8'b11111111;
		alarm[23:16] <= 8'b11111111;
	end
	else if(wr && crb7)//crb7==1 enables writing to ALARM
	begin
		if(tlo)
			alarm[7:0] <= datain[7:0];
		if(tme)
			alarm[15:8] <= datain[7:0];
		if(thi)
			alarm[23:16] <= datain[7:0];
	end

//crb7 write
always @(posedge clk)
	if (reset)
		crb7 <= 0;
	else if(wr && tcr)
		crb7 <= datain[7];

//alarm interrupt
always @(tod or alarm or count)
	if( (tod[23:0]==alarm[23:0]) && count)
		irq = 1;
	else 
		irq = 0;

endmodule
