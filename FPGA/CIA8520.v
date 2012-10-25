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

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia a*/
module ciaa(clk,aen,rd,wr,reset,rs,datain,dataout,tick,e,irq,portain,portaout,kbdrst,kbddat,kbdclk,osdctrl);
input 	clk;	  				//clock
input 	aen;		    			//adress enable
input	rd;					//read enable
input	wr;					//write enable
input 	reset; 				//reset
input 	[3:0] rs;	   			//register select (address)
input 	[7:0] datain;			//bus data in
output 	[7:0] dataout;			//bus data out
input 	tick;				//tick (counter input for TOD timer)
input 	e;	    				//e (counter input for timer A/B)
output 	irq;	   				//interrupt request out
input	[7:2]portain; 			//porta in
output 	[1:0]portaout;			//porta out
output	kbdrst;				//keyboard reset out
inout	kbddat;				//ps2 keyboard data
inout	kbdclk;				//ps2 keyboard clock
output	[3:0]osdctrl;			//osd control

//local signals
wire 	[7:0]icrout;
wire		[7:0]tmraout;			
wire		[7:0]tmrbout;
wire		[7:0]tmrdout;
wire		[7:0]sdrout;	
reg		[7:0]paout;
wire		alrm;				//TOD interrupt
wire		ta;					//TIMER A interrupt
wire		tb;					//TIMER B interrupt


//----------------------------------------------------------------------------------
//address decoder
//----------------------------------------------------------------------------------
wire		pra,ddra,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs,sdr;
wire		enable;

assign enable=aen&(rd|wr);

//decoder
assign	pra=(enable && rs==0)?1:0;
assign	ddra=(enable && rs==2)?1:0;
assign	talo=(enable && rs==4)?1:0;
assign	tahi=(enable && rs==5)?1:0;
assign	tblo=(enable && rs==6)?1:0;
assign	tbhi=(enable && rs==7)?1:0;
assign	tdlo=(enable && rs==8)?1:0;
assign	tdme=(enable && rs==9)?1:0;
assign	tdhi=(enable && rs==10)?1:0;
assign	sdr=(enable && rs==12)?1:0;
assign	icrs=(enable && rs==13)?1:0;
assign	cra=(enable && rs==14)?1:0;
assign	crb=(enable && rs==15)?1:0;

//----------------------------------------------------------------------------------
//dataout multiplexer
//----------------------------------------------------------------------------------
assign dataout=icrout|tmraout|tmrbout|tmrdout|sdrout|paout;

//----------------------------------------------------------------------------------
//instantiate keyboard module
//----------------------------------------------------------------------------------
wire keystrobe,keyack;
reg	[7:0]sdrlatch;
wire	[7:0]keydat;

ps2keyboard	kbd1(	.clk(clk),
					.reset(reset),
					.ps2kdat(kbddat),
					.ps2kclk(kbdclk),
					.leda(~portaout[1]),
					.ledb(1'b0),
					.kbdrst(kbdrst),
					.keydat(keydat[7:0]),
					.keystrobe(keystrobe),
					.keyack(keyack),
					.osdctrl(osdctrl)		);

//sdr register
//!!! Amiga receives keycode ONE STEP ROTATED TO THE RIGHT AND INVERTED !!!
always @(posedge clk)
	if(reset)
		sdrlatch[7:0]<=8'h00;
	else if(keystrobe)
		sdrlatch[7:0]<=~{keydat[6:0],keydat[7]};

//sdr register	read
assign sdrout=(!wr && sdr)?sdrlatch[7:0]:8'h00;
//keyboard acknowledge
assign keyack=(!wr && sdr)?1:0;

//----------------------------------------------------------------------------------
//porta
//----------------------------------------------------------------------------------
reg [7:2]portain2;
reg [1:0]regporta;
reg [7:0]ddrporta;

//synchronizing of input data
always @(posedge clk)
	portain2[7:2]<=portain[7:2];

//writing of output port
always @(posedge clk)
	if(reset)
		regporta[1:0]<=0;
	else if(wr && pra)
		regporta[1:0]<=datain[1:0];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrporta[7:0]<=0;
	else if(wr && ddra)
 		ddrporta[7:0]<=datain[7:0];

//reading of port/ddr register
always @(wr or pra or portain2 or portaout or ddra or ddrporta)
begin
	if(!wr && pra)
		paout[7:0]={portain2[7:2],portaout[1:0]};
	else if(!wr && ddra)
		paout[7:0]=ddrporta[7:0];
	else
		paout[7:0]=8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portaout[1:0]=(~ddrporta[1:0])|regporta[1:0];	
 
//----------------------------------------------------------------------------------
//instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.icrs(icrs),
			.ta(ta),
			.tb(tb),
			.alrm(alrm),
			.flag(1'b0),
			.ser(keystrobe),
			.datain(datain),
			.dataout(icrout),
			.irq(irq)		);


//----------------------------------------------------------------------------------
//instantiate timer A
//----------------------------------------------------------------------------------
timerab tmra (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(talo),
			.thi(tahi),
			.tcr(cra),
			.datain(datain),
			.dataout(tmraout),
			.count(e),
			.irq(ta) );

//----------------------------------------------------------------------------------
//instantiate timer B
//----------------------------------------------------------------------------------
timerab tmrb (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(tblo),
			.thi(tbhi),
			.tcr(crb),
			.datain(datain),
			.dataout(tmrbout),
			.count(e),
			.irq(tb) );

//----------------------------------------------------------------------------------
//instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(tdlo),
			.tme(tdme),
			.thi(tdhi),
			.tcr(crb),
			.datain(datain),
			.dataout(tmrdout),
			.count(tick),
			.irq(alrm)	); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

/*cia b*/
module ciab(clk,aen,rd,wr,reset,rs,datain,dataout,tick,e,flag,irq,portain,portaout,portbout);
input 	clk;	  				//clock
input 	aen;		    			//adress enable
input	rd;					//read enable
input	wr;					//write enable
input 	reset; 				//reset
input 	[3:0] rs;	   			//register select (address)
input 	[7:0] datain;			//bus data in
output 	[7:0] dataout;			//bus data out
input 	tick;				//tick (counter input for TOD timer)
input 	e;	    				//e (counter input for timer A/B)
input 	flag; 				//flag (set FLG bit in ICR register)
output 	irq;	   				//interrupt request out
input	[5:3]portain; 			//input port
output 	[7:6]portaout;			//output port
output	[7:0]portbout;			//output port

//local signals
wire 	[7:0]icrout;
wire		[7:0]tmraout;			
wire		[7:0]tmrbout;
wire		[7:0]tmrdout;	
reg		[7:0]paout;
reg		[7:0]pbout;		
wire		alrm;				//TOD interrupt
wire		ta;					//TIMER A interrupt
wire		tb;					//TIMER B interrupt


//----------------------------------------------------------------------------------
//address decoder
//----------------------------------------------------------------------------------
wire		pra,prb,ddra,ddrb,cra,talo,tahi,crb,tblo,tbhi,tdlo,tdme,tdhi,icrs;
wire		enable;

assign enable=aen&(rd|wr);

//decoder
assign	pra=(enable && rs==0)?1:0;
assign	prb=(enable && rs==1)?1:0;
assign	ddra=(enable && rs==2)?1:0;
assign	ddrb=(enable && rs==3)?1:0;
assign	talo=(enable && rs==4)?1:0;
assign	tahi=(enable && rs==5)?1:0;
assign	tblo=(enable && rs==6)?1:0;
assign	tbhi=(enable && rs==7)?1:0;
assign	tdlo=(enable && rs==8)?1:0;
assign	tdme=(enable && rs==9)?1:0;
assign	tdhi=(enable && rs==10)?1:0;
assign	icrs=(enable && rs==13)?1:0;
assign	cra=(enable && rs==14)?1:0;
assign	crb=(enable && rs==15)?1:0;

//----------------------------------------------------------------------------------
//dataout multiplexer
//----------------------------------------------------------------------------------
assign dataout=icrout|tmraout|tmrbout|tmrdout|paout|pbout;

//----------------------------------------------------------------------------------
//porta
//----------------------------------------------------------------------------------
reg [5:3]portain2;
reg [7:6]regporta;
reg [7:0]ddrporta;

//synchronizing of input data
always @(posedge clk)
	portain2[5:3]<=portain[5:3];

//writing of output port
always @(posedge clk)
	if(reset)
		regporta[7:6]<=0;
	else if(wr && pra)
		regporta[7:6]<=datain[7:6];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrporta[7:0]<=0;
	else if(wr && ddra)
 		ddrporta[7:0]<=datain[7:0];

//reading of port/ddr register
always @(wr or pra or portain2 or portaout or ddra or ddrporta)
begin
	if(!wr && pra)
		paout[7:0]={portaout[7:6],portain2[5:3],3'b111};
	else if(!wr && ddra)
		paout[7:0]=ddrporta[7:0];
	else
		paout[7:0]=8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portaout[7:6]=(~ddrporta[7:6])|regporta[7:6];	

//----------------------------------------------------------------------------------
//portb
//----------------------------------------------------------------------------------
reg [7:0]regportb;
reg [7:0]ddrportb;

//writing of output port
always @(posedge clk)
	if(reset)
		regportb[7:0]<=0;
	else if(wr && prb)
		regportb[7:0]<=datain[7:0];

//writing of ddr register 
always @(posedge clk)
	if(reset)
		ddrportb[7:0]<=0;
	else if(wr && ddrb)
 		ddrportb[7:0]<=datain[7:0];

//reading of port/ddr register
always @(wr or prb or portbout or ddrb or ddrportb)
begin
	if(!wr && prb)
		pbout[7:0]=portbout[7:0];
	else if(!wr && ddrb)
		pbout[7:0]=ddrportb[7:0];
	else
		pbout[7:0]=8'h00;
end
		
//assignment of output port while keeping in mind that the original 8520 uses pull-ups
assign portbout[7:0]=(~ddrportb[7:0])|regportb[7:0];	
 
//----------------------------------------------------------------------------------
//instantiate cia interrupt controller
//----------------------------------------------------------------------------------
ciaint cnt (	.clk(clk),
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
			.irq(irq)		);


//----------------------------------------------------------------------------------
//instantiate timer A
//----------------------------------------------------------------------------------
timerab tmra (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(talo),
			.thi(tahi),
			.tcr(cra),
			.datain(datain),
			.dataout(tmraout),
			.count(e),
			.irq(ta) );

//----------------------------------------------------------------------------------
//instantiate timer B
//----------------------------------------------------------------------------------
timerab tmrb (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(tblo),
			.thi(tbhi),
			.tcr(crb),
			.datain(datain),
			.dataout(tmrbout),
			.count(e),
			.irq(tb) );

//----------------------------------------------------------------------------------
//instantiate timer D
//----------------------------------------------------------------------------------
timerd tmrd (	.clk(clk),
			.wr(wr),
			.reset(reset),
			.tlo(tdlo),
			.tme(tdme),
			.thi(tdhi),
			.tcr(crb),
			.datain(datain),
			.dataout(tmrdout),
			.count(tick),
			.irq(alrm)	); 

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//interrupt control
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module ciaint(clk,wr,reset,icrs,ta,tb,alrm,flag,ser,datain,dataout,irq);
input 	clk;	  				//clock
input	wr;					//write enable
input 	reset; 				//reset
input 	icrs;				//intterupt control register select
input	ta;					//ta (set TA bit in ICR register)
input	tb;				    	//tb (set TB bit in ICR register)
input	alrm;	 			//alrm (set ALRM bit ICR register)
input 	flag; 				//flag (set FLG bit in ICR register)
input 	ser;					//ser (set SP bit in ICR register)
input 	[7:0]datain;			//bus data in
output 	[7:0]dataout;			//bus data out
output	irq;					//intterupt out

reg		[7:0]dataout;			//see above
reg		[4:0]icr;				//interrupt register
reg		[4:0]icrmask;			//interrupt mask register

//reading of interrupt data register 
always @(wr or irq or icrs or icr)
	if(icrs && !wr)
		dataout[7:0]={irq,2'b0,icr[4:0]};
	else
		dataout[7:0]=0;

//writing of interrupt mask register
always @(posedge clk)
	if(reset)
		icrmask[4:0]<=0;
	else if(icrs && wr)
	begin
		if(datain[7])
			icrmask[4:0]<=icrmask[4:0]|datain[4:0];
		else
			icrmask[4:0]<=icrmask[4:0]&(~datain[4:0]);
	end

//register new interrupts and/or changes by user reads
always @(posedge clk)
	if(reset)//synchronous reset	
		icr[4:0]<=0;
	else	if (icrs && !wr)
	begin//clear latched intterupts on read
		icr[0]<=ta;			//timer a
		icr[1]<=tb;			//timer b
		icr[2]<=alrm;   		//timer tod
		icr[3]<=ser;	 		//external ser input
		icr[4]<=flag;			//external flag input
	end
	else
	begin//keep latched intterupts
		icr[0]<=icr[0]|ta;		//timer a
		icr[1]<=icr[1]|tb;		//timer b
		icr[2]<=icr[2]|alrm;   	//timer tod
		icr[3]<=icr[3]|ser;	 	//external ser input
		icr[4]<=icr[4]|flag;	//external flag input
	end

//generate irq output (interrupt request)
assign irq=(icrmask[0]&icr[0])|(icrmask[1]&icr[1])|(icrmask[2]&icr[2])|(icrmask[3]&icr[3])|(icrmask[4]&icr[4]);

endmodule

//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//timer A/B
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module timerab(clk,wr,reset,tlo,thi,tcr,datain,dataout,count,irq);
input 	clk;	  				//clock
input	wr;					//write enable
input 	reset; 				//reset
input 	tlo;					//timer low byte select
input	thi;		 			//timer high byte select
input	tcr;					//timer control register
input 	[7:0] datain;			//bus data in
output 	[7:0] dataout;			//bus data out
input	count;	  			//count enable
output	irq;					//intterupt out

reg		irq;	  				//see above
reg 		[7:0]dataout;			//see above

reg		[15:0]tmr;			//timer 
reg		[7:0]tmlh;			//timer latch high byte
reg		[7:0]tmll;			//timer latch low byte
reg		[6:0]tmcr;			//timer control register
wire		forceload;			//force load strobe
wire		oneshot;				//oneshot mode
wire		start;				//timer start (enable)
wire		write;				//write to timer latch high byte

reg		stop; 				//stop (clear start bit)
reg		load;    				//load tmr
reg		countenable; 			//count down enable
reg		zero;				//tmr==0

reg		[1:0]tmrstate;			//timer current state
reg		[1:0]tmrnextstate;		//timer next state


//writing timer control register
always @(posedge clk)
	if(reset)//synchronous reset
		tmcr[6:0]<=0;
	else if (tcr && wr)//load control register, bit 4(strobe) is always 0
		tmcr[6:0]<={datain[6:5],1'b0,datain[3:0]};
	else if(stop)//timer state machine overrules bit 0
		tmcr[0]<=0;

//force load strobe, timer latch high byte write, oneshot alias and start alias
assign forceload=tcr&wr&datain[4];
assign write=thi&wr;
assign oneshot=tmcr[3];
assign start=tmcr[0];

//timer A latches for high and low byte
always @(posedge clk)
	if(reset)
		tmll[7:0]<=8'b11111111;
	else if( tlo && wr )
		tmll[7:0]<=datain[7:0];
always @(posedge clk)
	if(reset)
		tmlh[7:0]<=8'b11111111;
	else if( thi && wr )
		tmlh[7:0]<=datain[7:0];

//reading of timer high/low and control
always @(tmr or tmcr or wr or tlo or thi or tcr)
	if(!wr)
	begin
		if( tlo )
			dataout=tmr[7:0];
		else if( thi )
			dataout=tmr[15:8];
		else if( tcr )
			dataout={1'b0,tmcr[6:0]};
		else
			dataout=0;
	end 
	else
		dataout=0;

//main timer
always @(posedge clk)
	if (reset)
		tmr[15:0]<=0;
	else if(load || forceload)
		tmr[15:0]<={tmlh[7:0],tmll[7:0]};
	else if(count && countenable)
		tmr[15:0]<=tmr[15:0]-1;
always @(tmr or count)
	if((tmr[15:0]==16'b0000000000000000) && count)
		zero=1;
	else
		zero=0;

//timer state machine
parameter	IDLE		=	2'b00;
parameter	COUNT	=	2'b01;
parameter	RLDIRQ	=	2'b11;
parameter	RLD		=	2'b10;
						  
always @(posedge clk)
	if(reset)
		tmrstate<=IDLE;
	else
		tmrstate<=tmrnextstate;
always @(tmrstate or write or start or zero or oneshot)
begin
	case(tmrstate)
		IDLE://timer is stopped
			begin
			load=0;
			irq=0;
			stop=0;
			countenable=0;
 			if(write)
				tmrnextstate=RLD;
			else if(start)
				tmrnextstate=COUNT;
			else
				tmrnextstate=IDLE;
			end
					
		COUNT://timer is counting down
			begin
			load=0;
			irq=0;
			stop=0;
			countenable=1;
 			if(zero)
				tmrnextstate=RLDIRQ;
			else if(!start && !oneshot)
				tmrnextstate=IDLE;
			else
				tmrnextstate=COUNT;
			end

		RLDIRQ://timer is generating interupt AND reloading
			begin
			load=1;
			irq=1;
			if(oneshot)//stop timer if oneshot mode
				stop=1;
			else
				stop=0;
			countenable=0;
 			if(oneshot)
				tmrnextstate=IDLE;
			else
				tmrnextstate=COUNT;
			end

		RLD://timer is only reloading
			begin
			load=1;
			irq=0;
			stop=0;
			countenable=0;
 			if(oneshot)
				tmrnextstate=COUNT;
			else
				tmrnextstate=IDLE;
			end

		default://unknown state, stop timer
			begin
			load=0;
			irq=0;
			stop=0;
			countenable=0;
 			tmrnextstate=IDLE;
			end
	endcase			
end

endmodule


//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------
//timer D
//----------------------------------------------------------------------------------
//----------------------------------------------------------------------------------

module timerd(clk,wr,reset,tlo,tme,thi,tcr,datain,dataout,count,irq);
input 	clk;	  				//clock
input	wr;					//write enable
input 	reset; 				//reset
input 	tlo;					//timer low byte select
input 	tme;					//timer mid byte select
input	thi;		 			//timer high byte select
input	tcr;					//timer control register
input 	[7:0] datain;			//bus data in
output 	[7:0] dataout;			//bus data out
input	count;	  			//count enable
output	irq;					//intterupt out

reg		[7:0]dataout;			//see above
reg		irq;					//see above

reg		le;					//timer d output latch enable
reg 		ce;					//timer d count enable
reg		crb7;				//bit 7 of control register B
reg		[23:0]tod;			//timer d
reg		[23:0]alarm;			//alarm
reg		[15:0]todl;			//timer d latch

//timer D output latch control
always @(posedge clk)
	if(reset)
		le<=1;
	else if(!wr)
	begin
		if(thi)//if MSB read, hold data for subsequent reads
			le<=0;
		else if (tlo)//if LSB read, update data every clock
			le<=1;
	end
always @(posedge clk)
	if(le)
		todl[15:0]<=tod[15:0];

//timer D and crb7 read 
always @(wr or tlo or tme or thi or tcr or tod or todl or crb7)
	if(!wr)
	begin
		if(thi)//high byte of timer D
			dataout[7:0]=tod[23:16];
		else if (tme)//medium byte of timer D (latched)
			dataout[7:0]=todl[15:8];
		else if (tlo)//low byte of timer D (latched)
			dataout[7:0]=todl[7:0];
		else if (tcr)//bit 7 of crb
			dataout[7:0]={crb7,7'b0000000};
		else
			dataout[7:0]=0;
	end
	else
		dataout[7:0]=0;  

//timer D count enable control
always @(posedge clk)
	if(reset)
		ce<=1;
	else if(wr && !crb7)//crb7==0 enables writing to TOD counter
	begin
		if(thi || tme)//stop counting
			ce<=0;
		else if(tlo)//write to LSB starts counting again
			ce<=1;			
	end

//timer D counter
always @(posedge clk)
	if(reset)//synchronous reset
	begin
		tod[7:0]<=0;
		tod[15:8]<=0;
		tod[23:16]<=0;
	end
	else if(wr && !crb7)//crb7==0 enables writing to TOD counter
	begin
		if(tlo)
			tod[7:0]<=datain[7:0];
		if(tme)
			tod[15:8]<=datain[7:0];
		if(thi)
			tod[23:16]<=datain[7:0];
	end
	else if(ce && count)
		tod[23:0]<=tod[23:0]+1;

//alarm write
always @(posedge clk)
	if(reset)//synchronous (p)reset
	begin
		alarm[7:0]<=8'b11111111;
		alarm[15:8]<=8'b11111111;
		alarm[23:16]<=8'b11111111;
	end
	else if(wr && crb7)//crb7==1 enables writing to ALARM
	begin
		if(tlo)
			alarm[7:0]<=datain[7:0];
		if(tme)
			alarm[15:8]<=datain[7:0];
		if(thi)
			alarm[23:16]<=datain[7:0];
	end

//crb7 write
always @(posedge clk)
	if (reset)
		crb7<=0;
	else if(wr && tcr)
		crb7<=datain[7];

//alarm interrupt
always @(tod or alarm or count)
	if( (tod[23:0]==alarm[23:0]) && count)
		irq=1;
	else 
		irq=0;

endmodule
