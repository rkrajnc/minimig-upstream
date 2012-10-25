* Copyright 2006, 2007 Dennis van Weeren
*
* This file is part of Minimig
*
* Minimig is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 3 of the License, or
* (at your option) any later version.
*
* Minimig is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.


*Some amiga register definitions
SERDATR	equ	$018
SERPER	equ	$032
SERDAT	equ	$030
INTREQ	equ	$09c
INTREQR	equ	$01e
CUSTOM	equ	$dff000
INTENA	equ	$09a
INTENAR	equ	$01c
CIAA	equ	$bfe001
CIAB	equ	$bfd000

CIAPRA	equ	$000	
CIAPRB	equ	$100
CIADDRA	equ	$200
CIADDRB	equ	$300	
CIATALO	equ	$400
CIATAHI	equ	$500
CIATBLO	equ	$600
CIATBHI	equ	$700
CIATODLOW equ	$800
CIATODMID equ	$900
CIATODHI equ	$a00
CIASDR	equ	$c00
CIAICR	equ	$d00
CIACRA	equ	$e00
CIACRB	equ	$f00

VPOSR	equ	$004
DDFSTRT	equ	$092
DDFSTOP	equ	$094
DIWSTRT	equ	$08e
DIWSTOP	equ	$090
BPL1MOD	equ	$108
BPL2MOD	equ	$10a

COP1LCH	equ	$080
COP2LCH	equ	$084
COPJMP1 equ	$088
COPJMP2	equ	$08a


BPL1DAT	equ	$110
BPL1PTH	equ	$0e0
BPL1PTL	equ	$0e2
BPL2PTH	equ	$0e4
BPL2PTL	equ	$0e6
BPL3PTH	equ	$0e8
BPL3PTL	equ	$0ea
BPL4PTH	equ	$0ec
BPL4PTL	equ	$0ee
BPLCON0	equ	$100
BPLCON1	equ	$102
BPLCON2	equ	$104
COLOR00	equ	$180
COLOR01	equ	$182
COLOR02	equ	$184
COLOR03	equ	$186
COLOR09 equ	$192
COLOR10 equ	$194
COLOR11 equ	$196

DMACON	equ	$096
DMACONR	equ	$002

BLTAFWM	equ	$044
BLTALWM	equ	$046
BLTCON0	equ	$040
BLTCON1	equ	$042
BLTSIZE	equ	$058

BLTAMOD	equ	$064
BLTBMOD	equ	$062
BLTCMOD	equ	$060
BLTDMOD	equ	$066

BLTADAT	equ	$074
BLTBDAT	equ	$072
BLTCDAT	equ	$070

BLTAPTH	equ	$050
BLTBPTH	equ	$04c
BLTCPTH	equ	$048
BLTDPTH	equ	$054

DSKLEN	equ	$024
DSKPTH	equ	$020
DSKSYNC	equ	$07e
ADKCON	equ	$09e


* Code starts here

	org	$0

	dc.W	$0007,$0100		;initial stack pointer
	dc.W	$0000,$0100		;reset pointer

	org	$100

Start:	lea	CUSTOM,a0		;pointer to chip registers
	lea	CIAA,a1			;pointer to ciaa
	lea	CIAB,a2			;pointer to ciab
	lea	$f80000,a3		;pointer to chipram area

	move.b	#$f7,CIAPRB(a2)		;select drive 0
	move.b	#$ff,CIADDRB(a2)	;make drive control signals output
	move.W	#30,SERPER(a0)		;set baud to 115200 @ 3.547 MHz
	move.W	#$7000,INTENA(a0)	;disable all intterupts
	move.w	#$7fff,INTREQ(a0)	;clear all intterupts
	move.w	#$8210,DMACON(a0)	;enable only disk dma
	move.w	#$7fff,ADKCON(a0)	;clear ADKCON
	
***************************************************************************
*load kickstart from disk
***************************************************************************
	bsr	Trck0			;go to track 0
	bclr	#1,CIAPRB(a2)		;step upwards
	
BootL	bsr	Rd16k			;read track into buffer
	bsr	Cpy16k			;copy buffer to kickstart area
	cmp.l	#$1000000,a3		;all data done ?
	beq	Exit			;yes --> exit boot code
	bclr	#0,CIAPRB(a2)		;no  --> load next track
	bset	#0,CIAPRB(a2)
	bra	BootL

***************************************************************************
* go to track0
***************************************************************************
Trck0	move.b	#255,d0			;256 _step pulses
	bset	#1,CIAPRB(a2)		;step towards track 0
	
Trck0L	bclr	#0,CIAPRB(a2)		;pulse _step
	bset	#0,CIAPRB(a2)
	dbra	d0,Trck0L
	rts

***************************************************************************
*read 16kbyte block from disk into the chipram buffer
***************************************************************************
Rd16k	move.l	#$10000,DSKPTH(a0)	;pointer to chipram buffer
	move.w	#$0002,INTREQ(a0)	;clear interrupt
	move.w	#$a000,DSKLEN(a0)	;start disk dma
	move.w	#$a000,DSKLEN(a0)
Rd16kL	move.w	INTREQR(a0),d0		;wait for disk dma to finish
	and.w	#$0002,d0
	beq	Rd16kL
	move.w	#$4000,DSKLEN(a0)	;stop disk dma
	rts

***************************************************************************
*copy 16kbyte from the chipram buffer into the kickstart area
***************************************************************************
Cpy16k	move.w	#4095,d0		;4096 words
	lea	$10000,a4		;pointer to chipram buffer
Cpy16kL	move.l	(a4)+,d1		;copy one word
	move.l	d1,(a3)+		;still copying one word
	move.w	d1,COLOR00(a0)		;funny screen flash
	dbra	d0,Cpy16kL
	rts
			
***************************************************************************
* exit boot code
***************************************************************************
Exit	move.b	d0,$bfc000		;access both cia's at once, this will end boot code
	bra	Exit

			

	


