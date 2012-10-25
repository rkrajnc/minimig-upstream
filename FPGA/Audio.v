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
// This is the audio part of Paula
//
// 27-12-2005		-started coding
// 28-12-2005		-done lots of work
// 29-12-2005		-done lots of work
// 01-01-2006		-we are having OK sound in dma mode now
// 02-01-2006		-fixed last state
// 03-01-2006		-added dmas to avoid interference with copper cycles
// 04-01-2006		-experimented with DAC
// 06-01-2006		-experimented some more with DAC and decided to leave it as it is for now
// 07-01-2006		-cleaned up code
// 21-02-2006		-improved audio state machine
// 22-02-2006		-fixed dma interrupt timing, Turrican-3 theme now plays correct!

module audio(clk,reset,horbeam,regaddress,datain,dmacon,audint,audpen,dmal,dmas,left,right);
input 	clk;		    			//bus clock
input 	reset;			   	//reset 
input	[8:0]horbeam;			//horizontal beamcounter
input 	[8:1]regaddress;		//register address input
input	[15:0]datain;			//bus data in
input	[3:0]dmacon;			//audio dma register input
output	[3:0]audint;			//audio interrupt request
input	[3:0]audpen;			//audio interrupt pending
output	dmal;				//dma request 
output	dmas;				//dma special 
output	left;				//audio bitstream out left
output	right;				//audio bitstream out right

//register names and addresses
parameter	AUD0BASE=9'h0a0;
parameter	AUD1BASE=9'h0b0;
parameter	AUD2BASE=9'h0c0;
parameter	AUD3BASE=9'h0d0;

//local signals 
reg		dmal;				//see above 
reg		dmas;				//see above
reg		tick;				//audio clock enable
wire		[3:0]aen;				//address enable 0-3
wire		[3:0]dmareq;			//dma request 0-3
wire		[3:0]dmaspc;			//dma restart 0-3
wire		[7:0]sample0;			//channel 0 audio sample 
wire		[7:0]sample1;			//channel 1 audio sample 
wire		[7:0]sample2;			//channel 2 audio sample 
wire		[7:0]sample3;			//channel 3 audio sample 
wire		[6:0]vol0;			//channel 0 volume 
wire		[6:0]vol1;			//channel 1 volume 
wire		[6:0]vol2;			//channel 2 volume 
wire		[6:0]vol3;			//channel 3 volume 

//--------------------------------------------------------------------------------------

//address decoder
assign aen[0]=(regaddress[8:4]==AUD0BASE[8:4])?1:0;
assign aen[1]=(regaddress[8:4]==AUD1BASE[8:4])?1:0;
assign aen[2]=(regaddress[8:4]==AUD2BASE[8:4])?1:0;
assign aen[3]=(regaddress[8:4]==AUD3BASE[8:4])?1:0;

//--------------------------------------------------------------------------------------

//generate audio clock enable
always @(posedge clk)
	if(reset)
		tick<=0;
	else
		tick<=~tick;

//--------------------------------------------------------------------------------------

//dma request logic
//slot 0x000010011 (channel #0)
//slot 0x000010111 (channel #1)
//slot 0x000011011 (channel #2)
//slot 0x000011111 (channel #3)
always @(horbeam or dmareq or dmaspc)
begin
	if((horbeam[8:4]==5'b00001) && (horbeam[1:0]==2'b11))
	begin
		case(horbeam[3:2])
			2'b00: dmal=dmareq[0];
			2'b01: dmal=dmareq[1];
			2'b10: dmal=dmareq[2];
			2'b11: dmal=dmareq[3];
		endcase
		case(horbeam[3:2])
			2'b00: dmas=dmaspc[0];
			2'b01: dmas=dmaspc[1];
			2'b10: dmas=dmaspc[2];
			2'b11: dmas=dmaspc[3];
		endcase
	end
	else
	begin
		dmal=0;
		dmas=0;
	end
end


//--------------------------------------------------------------------------------------

//instantiate audio channel 0
audiochannel ach0 (		.clk(clk),
					.reset(reset),
					.tick(tick),
					.aen(aen[0]),
					.den(dmacon[0]),
					.regaddress(regaddress[3:1]),
					.data(datain),
					.volume(vol0),
					.sample(sample0),
					.intreq(audint[0]),
					.intpen(audpen[0]),
					.dmareq(dmareq[0]),
					.dmas(dmaspc[0])	);

//instantiate audio channel 1
audiochannel ach1 (		.clk(clk),
					.reset(reset),
					.tick(tick),
					.aen(aen[1]),
					.den(dmacon[1]),
					.regaddress(regaddress[3:1]),
					.data(datain),
					.volume(vol1),
					.sample(sample1),
					.intreq(audint[1]),
					.intpen(audpen[1]),
					.dmareq(dmareq[1]),
					.dmas(dmaspc[1])	);

//instantiate audio channel 2
audiochannel ach2 (		.clk(clk),
					.reset(reset),
					.tick(tick),
					.aen(aen[2]),
					.den(dmacon[2]),
					.regaddress(regaddress[3:1]),
					.data(datain),
					.volume(vol2),
					.sample(sample2),
					.intreq(audint[2]),
					.intpen(audpen[2]),
					.dmareq(dmareq[2]),
					.dmas(dmaspc[2])	);

//instantiate audio channel 3
audiochannel ach3 (		.clk(clk),
					.reset(reset),
					.tick(tick),
					.aen(aen[3]),
					.den(dmacon[3]),
					.regaddress(regaddress[3:1]),
					.data(datain),
					.volume(vol3),
					.sample(sample3),
					.intreq(audint[3]),
					.intpen(audpen[3]),
					.dmareq(dmareq[3]),
					.dmas(dmaspc[3])	);

//instantiate volume control and sigma/delta modulator
sigmadelta dac0 (		.clk(clk),
					.sample0(sample0),
					.sample1(sample1),
					.sample2(sample2),
					.sample3(sample3),
					.vol0(vol0),
					.vol1(vol1),
					.vol2(vol2),
					.vol3(vol3),
					.left(left),
					.right(right)		);

//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

// audio data processing
// stereo volume control
// stereo sigma/delta bitstream modulator
// channel 1&2 --> left
// channel 0&3 --> right
module sigmadelta(clk,sample0,sample1,sample2,sample3,vol0,vol1,vol2,vol3,left,right);
input 	clk;					//bus clock
input	[7:0]sample0;			//sample 0 input
input	[7:0]sample1;			//sample 1 input
input	[7:0]sample2;			//sample 2 input
input	[7:0]sample3;			//sample 3 input
input	[6:0]vol0;			//volume 0 input
input	[6:0]vol1;			//volume 1 input
input	[6:0]vol2;			//volume 2 input
input	[6:0]vol3;			//volume 3 input
output	left;				//left bitstream output
output	right;				//right bitsteam output

//local signals
reg		[14:0]acculeft;		//sigma/delta accumulator left		
reg		[14:0]accuright;		//sigma/delta accumulator right
wire		[7:0]leftsmux;			//left mux sample
wire		[7:0]rightsmux;		//right mux sample
wire		[6:0]leftvmux;			//left mux volum
wire		[6:0]rightvmux;		//right mux volume
wire		[13:0]ldata;			//left DAC data
wire		[13:0]rdata; 			//right DAC data
reg		mxc;					//multiplex control

//--------------------------------------------------------------------------------------

//multiplexer control
always @(posedge clk)
		mxc<=~mxc;

//sample multiplexer
assign leftsmux=(mxc)?sample1:sample2;
assign rightsmux=(mxc)?sample0:sample3;

//volume multiplexer
assign leftvmux=(mxc)?vol1:vol2;
assign rightvmux=(mxc)?vol0:vol3;

//left volume control
//when volume MSB is set, volume is always maximum
svmul sv0(	.sample(leftsmux),
			.volume({	(leftvmux[6]|leftvmux[5]),
					(leftvmux[6]|leftvmux[4]),
					(leftvmux[6]|leftvmux[3]),
					(leftvmux[6]|leftvmux[2]),
					(leftvmux[6]|leftvmux[1]),
					(leftvmux[6]|leftvmux[0])}),
			.out(ldata)	);

//right volume control
//when volume MSB is set, volume is always maximum
svmul sv1(	.sample(rightsmux),
			.volume({	(rightvmux[6]|rightvmux[5]),
					(rightvmux[6]|rightvmux[4]),
					(rightvmux[6]|rightvmux[3]),
					(rightvmux[6]|rightvmux[2]),
					(rightvmux[6]|rightvmux[1]),
					(rightvmux[6]|rightvmux[0])}),
			.out(rdata)	);

//--------------------------------------------------------------------------------------

//left sigma/delta modulator
always @(posedge clk)
	acculeft[14:0]<={1'b0,acculeft[13:0]}+{1'b0,~ldata[13],ldata[12:0]};
assign left=acculeft[14];

//right sigma/delta modulator
always @(posedge clk)
	accuright[14:0]<={1'b0,accuright[13:0]}+{1'b0,~rdata[13],rdata[12:0]};
assign right=accuright[14];

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//this module multiplies a signed 8 bit sample with an unsigned 6 bit volume setting
//it produces a 14bit signed result
module svmul(sample,volume,out);
input 	[7:0]sample;			//signed sample input
input	[5:0]volume;			//unsigned volume input
output	[13:0]out;			//signed product out

wire		[13:0]sesample;   		//sign extended sample
wire		[13:0]sevolume;		//sign extended volume

//sign extend input parameters
assign 	sesample[13:0]={sample[7],sample[7],sample[7],sample[7],sample[7],sample[7],sample[7:0]};
assign	sevolume[13:0]={8'b00000000,volume[5:0]};

//multiply, synthesizer should infer multiplier here
assign out[13:0]=sesample[13:0]*sevolume[13:0];

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//This module handles a single amiga audio channel. attached modes are not supported
module audiochannel(clk,reset,tick,aen,den,regaddress,data,volume,sample,intreq,intpen,dmareq,dmas);
input 	clk;					//bus clock	
input 	reset;		    		//reset
input	tick;				//audio clock enable
input	aen;					//address enable
input	den;					//dma enable
input	[3:1]regaddress;		//register address input
input 	[15:0]data; 			//bus data input
output	[6:0]volume;			//channel volume output
output	[7:0]sample;			//channel sample output
output	intreq;				//interrupt request
input	intpen;				//interrupt pending input
output	dmareq;				//dma request
output	dmas;				//dma special (restart)

//register names and addresses
parameter	AUDLEN=4'h4;
parameter	AUDPER=4'h6;
parameter	AUDVOL=4'h8;
parameter	AUDDAT=4'ha;

//local signals
reg		dmareq;				//see above
reg		dmas;				//see above
reg		intreq;				//see above
reg		[15:0]audlen;			//audio length register
reg		[15:0]audper;			//audio period register
reg		[6:0]audvol;			//audio volume register
reg		[15:0]auddat;			//audio data register
reg		[15:0]percount;		//audio period counter
reg		[15:0]lencount;		//audio length counter
reg		[15:0]datbuf;			//audio data buffer
reg		[2:0]audiostate;		//audio current state
reg		[2:0]audionext;	   	//audio next state
reg		intreq2;				//used to time interrupts

reg		datld;				//load audio buffer from auddat
reg		datsh;				//shift datbuf 8 bits to the left, shift in zero's
reg		lendec;				//decrement length counter
reg		lenload;				//load length counter
reg		perload;				//load period counter
reg		intrst;				//intreq2 latch reset
reg		dma;					//request dma
wire		lenfin;				//length counter is 1
wire		perzero;				//period counter is zero
wire		datwrite;				//data register is written

//--------------------------------------------------------------------------------------
 
//length register bus write
always @(posedge clk)
	if(reset)
		audlen[15:0]<=0;	
	else if(aen && (regaddress[3:1]==AUDLEN[3:1]))
		audlen[15:0]<=data[15:0];

//period register bus write
always @(posedge clk)
	if(reset)
		audper[15:0]<=0;	
	else if(aen && (regaddress[3:1]==AUDPER[3:1]))
		audper[15:0]<=data[15:0];

//volume register bus write
always @(posedge clk)
	if(reset)
		audvol[6:0]<=0;	
	else if(aen && (regaddress[3:1]==AUDVOL[3:1]))
		audvol[6:0]<=data[6:0];

//data register strobe
assign datwrite=(aen && (regaddress[3:1]==AUDDAT[3:1]))?1:0;

//data register bus write
always @(posedge clk)
	if(reset)
		auddat[15:0]<=0;	
	else if(datwrite)
		auddat[15:0]<=data[15:0];
	
//--------------------------------------------------------------------------------------

//period counter 
always @(posedge clk)
	if(perload || perzero)//load period counter from audio period register
		percount[15:0]<=audper[15:0];
	else if(tick)//period counter count down
		percount[15:0]<=percount[15:0]-1;
assign perzero=(percount[15:0]==0)?1:0;

//length counter 
always @(posedge clk)
	if(lenload)//load length counter from audio length register
		lencount[15:0]<=audlen[15:0];
	else if(lendec)//length counter count down
		lencount[15:0]<=lencount[15:0]-1;
assign lenfin=(lencount[15:0]==1)?1:0;

//--------------------------------------------------------------------------------------

//audio buffer
always @(posedge clk)
	if(reset)
		datbuf[15:0]<=0;
	else if(datld)
		datbuf[15:0]<=auddat[15:0];
	else if(datsh)
		datbuf[15:0]<={datbuf[7:0],8'h00};	

//sample output
assign sample[7:0]=datbuf[15:8];

//volume output
assign volume[6:0]=audvol[6:0];

//--------------------------------------------------------------------------------------

//dma request logic
//dma is requested by main state machine
//dma is cleared when auddat is written
//if length counter is being reloaded, dma restart is requested
always @(posedge clk)
begin
	if(reset || datwrite)
	begin
		dmareq<=0;
		dmas<=0;
	end
	else if(dma)
	begin
		dmareq<=1;
		dmas<=lenload;
	end
end

//intreq2 latch
//this signal is used to properly request interrupts in dma mode
//if data from dma restart request has come in --> intreq2 is true
always @(posedge clk)
	if(reset||intrst)
		intreq2<=0;
	else if(dmas && den && datwrite)//(dmas=1 if restart request is pending)
		intreq2<=1;

//audio states
parameter AUDIDLE=0;
parameter AUDGET=1;
parameter AUDSTATE1=2;
parameter AUDSTATE2=3;
parameter AUDSTATE3=4;

//audio channel state machine
always @(posedge clk)
begin
	if(reset)
		audiostate<=AUDIDLE;
	else
		audiostate<=audionext;
end

always @(audiostate or den or datwrite or lenfin or intreq2 or perzero or intpen)
begin
	case(audiostate)
		
		//audio state machine idle state (state 000)
		//mute output
		//reload period counter
		//start dma driven audio immediately if dma enabled
		//start interrupt driven audio immediately when auddat is written
		AUDIDLE:
		begin
			datld=0;
			datsh=1;//this mutes sample output after max 2 clocks
			intrst=0;
			lendec=0;
			lenload=1;//**dma restart enable**
			perload=0;
			intreq=0;
			dma=den;
			if(datwrite)//start interrupt driven audio
				audionext=AUDSTATE1;
			else if(den)//start dma driven audio
				audionext=AUDGET;
			else
				audionext=AUDIDLE;	
		end

		//wait for first word of dma driven audio to arrive (state 101)
		//reset intreq2 latch
		//when it arrives, reload period counter, request interrupt and go to next state
		//if dma is disabled, return to idle state
		AUDGET:
		begin
			datld=0;
			datsh=0;
			intrst=1;
			lendec=0;
			lenload=0;
			perload=1;
			intreq=datwrite;
			dma=0;
			if(!den)
				audionext=AUDIDLE;				
			else if(datwrite)
				audionext=AUDSTATE1;
			else
				audionext=AUDGET;	
		end

		//state transition handling (transition 101->010 and 011->010)
		//load data from auddat to sample buffer
		//reset intreq2 latch
		//decrement length counter if len>1 
		//reload length counter if len=1
		//request interrupt if dma disabled (interrupt driven mode)
		//request interrupt if intreq2 occurred(dma driven mode)
		//request new data by dma if dma enabled
		AUDSTATE1:
		begin
			datld=1;
			datsh=0;
			intrst=1;
			lendec=~lenfin;
			lenload=lenfin;//**dma restart enable**
			perload=0;
			intreq=~den|intreq2;
			dma=den;
			audionext=AUDSTATE2;	
		end

		//first sample of word state (state 010)
		//load second sample when period counter expires
		//go to next state when period counter expires
		AUDSTATE2:
		begin
			datld=0;
			datsh=perzero;
			intrst=0;
			lendec=0;
			lenload=0;
			perload=0;
			intreq=0;
			dma=0;
			if(perzero)//next state
				audionext=AUDSTATE3;
			else//stay here
				audionext=AUDSTATE2;	
		end

		//second sample of word state (state 011)
		//go to idle state when period counter expires and not (enabled or intterupt not pending)
		//else go to next state if period counter expires 
		AUDSTATE3:
		begin
			datld=0;
			datsh=0;
			intrst=0;
			lendec=0;
			lenload=0;
			perload=0;
			intreq=0;
			dma=0;
			if(perzero && !(den || !intpen))//see HRM state diagram
				audionext=AUDIDLE;				
			else if(perzero)
				audionext=AUDSTATE1;
			else
				audionext=AUDSTATE3;	
		end

		//we should never come here (state 100,110,111)
		default:
		begin
			datld=1'bx;
			datsh=1'bx;
			intrst=1'bx;
			lendec=1'bx;
			lenload=1'bx;
			perload=1'bx;
			intreq=1'bx;
			dma=1'bx;
			audionext=AUDIDLE;	
		end
	endcase
end





//--------------------------------------------------------------------------------------

endmodule