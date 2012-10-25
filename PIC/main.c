/*
Copyright 2005, 2006, 2007 Dennis van Weeren

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Minimig boot controller / floppy emulator / on screen display

27-11-2005		-started coding
29-01-2005		-done a lot of work
06-02-2006		-it start to look like something!
19-02-2006		-improved floppy dma offset code
02-01-2007		-added osd support
11-02-2007		-added insert floppy progress bar
01-07-2007		-added filetype filtering for directory routines
*/

#include <pic18.h>
#include <hardware.h>
#include <osd.h>
#include <stdio.h>
#include <string.h>
#include <ata18.h>
#include <fat1618_2.h>

void CheckTrack(struct adfTYPE *drive);
void ReadTrack(struct adfTYPE *drive);
void ReadRom(unsigned char track);
void WriteTrack(struct adfTYPE *drive);
void SectorToFpga(unsigned char sector,unsigned char track);
void Open(const unsigned char *name);
unsigned char ConfigureFpga(void);
void HandleFpgaCmd(unsigned char c1, unsigned char c2);
void InsertFloppy(struct adfTYPE *drive);
void ScrollDir(const unsigned char *type, unsigned char mode);
void PrintDir(void);
void User(void);

/*FPGA commands <c1> argument*/
#define		CMD_USERSELECT		0x80	/*user interface SELECT*/
#define		CMD_USERUP			0x40	/*user interface UP*/
#define		CMD_USERDOWN		0x20	/*user interface DOWN*/
#define		CMD_GETDSKSTAT		0x04	/*FPGA requests status of disk drive*/
#define		CMD_RDTRCK			0x02	/*FPGA requests reading of track <c2>*/
#define		CMD_WRTRCK			0x01	/*FPGA requests writing of trck <c2>*/

/*floppy status*/
#define		DSK_INSERTED		0x01	/*disk is inserted*/
#define		DSK_WRITEABLE		0x02	/*disk is writeable*/

/*menu states*/
#define		MENU_NONE1			0		/*no menu*/		
#define		MENU_NONE2			1		/*no menu*/		
#define		MENU_MAIN1			2		/*main menu*/
#define		MENU_MAIN2			3		/*main menu*/
#define		MENU_FILE1			4		/*file requester menu*/
#define		MENU_FILE2			5		/*file requester menu*/

/*other constants*/
#define		DIRSIZE				8		/*size of directory display window*/
#define		REPEATTIME			50		/*repeat delay in 10ms units*/
#define		REPEATRATE			5		/*repeat rate in 10ms units*/


/*variables*/
struct adfTYPE
{
	unsigned char status;				/*status of floppy*/
	unsigned short cache[160];			/*cluster cache*/
	unsigned short clusteroffset;		/*cluster offset to handle tricky loaders*/
	unsigned char sectoroffset;			/*sector offset to handle tricky loaders*/
	unsigned char track;				/*current track*/
	unsigned char trackprev;			/*previous track*/
	unsigned char name[12];				/*floppy name*/
};
struct adfTYPE df0;						/*drive 0 information structure*/
struct file2TYPE file;					/*global file handle*/
struct file2TYPE directory[DIRSIZE];	/*directory array*/
unsigned char dirptr;					/*pointer into directory array*/

unsigned char s[25];					/*used to build strings*/

/*This is where it all starts after reset*/
void main(void)
{
	unsigned char c1,c2;
	unsigned short t;

	/*initialize hardware*/
	HardwareInit();

	printf("\rMinimig Controller\r");
	printf("\rby Dennis van Weeren\r");

	/*intialize mmc card*/
	SDCARD_Init();
	
	/*initalize FAT partition*/
	if(FindDrive2())
	{	
		printf("MMC card found!\r");
	}
	else
	{
		printf("MMC card error\r");
	}
	
	/*configure FPGA*/
	if(ConfigureFpga())
		printf("FPGA configured\r");
	else
		printf("FPGA configuration failed\r");
		
	/*wait for FPGA to load kickstart*/
	df0.status=1;
	while(1)
	{
		/*read command from FPGA*/
		EnableFpga();
		c1=SPI(0);
		c2=SPI(0);
		DisableFpga();	
		
		/*FPGA asking for kickstart by reading track 0 ?*/
		if((c1==CMD_RDTRCK) && (c2==0))
		{
			printf("loading kickstart\r");
			/*send rom image to FPGA and exit this loop*/
			ReadRom(c2);
			printf("\rkickstart loaded\r");
			break;
		}
		
		/*else dispatch to standard command handler*/
		HandleFpgaCmd(c1,c2);		
	}
	df0.status=0;
	

	/******************************************************************************/
	/******************************************************************************/
	/*System is up now*/
	/******************************************************************************/
	/******************************************************************************/


	/*fill initial directory*/
	ScrollDir("ADF",0);
	
	/*get initial timer for checking user interface*/
	t=GetTimer(5);

	while(1)
	{
		/*read command from FPGA*/
		EnableFpga();
		c1=SPI(0);
		c2=SPI(0);
		DisableFpga();	
		
		/*handle command*/
			HandleFpgaCmd(c1,c2);
		
		/*handle user interface*/
		if(CheckTimer(t))
		{
			t=GetTimer(2);
			User();
		}
	}
}

/*user interface*/
void User(void)
{
	static unsigned char menustate,menusub;
	unsigned char c,up,down,select,menu;
	
	/*get user control codes*/
	c=OsdGetCtrl();
	
	/*decode and set events*/
	up=0;
	down=0;
	select=0;
	menu=0;
	if(c&OSDCTRLUP)
		up=1;
	if(c&OSDCTRLDOWN)
		down=1;
	if(c&OSDCTRLSELECT)
		select=1;
	if(c&OSDCTRLMENU)
		menu=1;
	
		
	/*menu state machine*/
	switch(menustate)
	{
		/******************************************************************/
		/*no menu selected / menu exited / menu not displayed*/
		/******************************************************************/
		case MENU_NONE1:
			OsdDisable();
			menustate=MENU_NONE2;
			break;
			
		case MENU_NONE2:
			if(menu)/*check if user wants to go to menu*/
			{
				menustate=MENU_MAIN1;
				menusub=0;
				OsdClear();
				OsdEnable();
			}
			break;
			
		/******************************************************************/
		/*main menu: insert/eject floppy, reset and exit*/
		/******************************************************************/
		case MENU_MAIN1:
			/*menu title*/
			OsdWrite(0," ** Minimig Menu **");
			
			/*df0 info*/
			strcpy(s,"     df0: ");
			if(df0.status&DSK_INSERTED)/*floppy currently in df0*/
				strncpy(&s[10],df0.name,8);
			else/*no floppy in df0*/
				strncpy(&s[10],"--------",8);
			s[18]=0x0d;
			s[19]=0x00;
			OsdWrite(2,s);	
			
			/*eject/insert df0 options*/
			if(df0.status&DSK_INSERTED)/*floppy currently in df0*/
				sprintf(s,"     eject df0 ");
			else/*no floppy in df0*/
				sprintf(s,"     insert df0");
			OsdWrite(3,s);	

			/*reset system*/
			OsdWrite(4,"     reset");
			
			/*exit menu*/
			OsdWrite(5,"     exit\n");
			
			/*display arrow indicating currently selected item*/
			if(menusub==0)
				OsdWrite(3,"--> ");
			else if(menusub==1)
				OsdWrite(4,"--> ");
			else if(menusub==2)
				OsdWrite(5,"--> ");
							
			/*goto to second state of main menu*/
			menustate=MENU_MAIN2;
			break;
			
		case MENU_MAIN2:
			
			if(menu)/*menu pressed*/
				menustate=MENU_NONE1;
			else if(up)/*up pressed*/
			{
				if(menusub>0)
					menusub--;
				menustate=MENU_MAIN1;
			}
			else if(down)/*down pressed*/
			{
				if(menusub<2)
					menusub++;
				menustate=MENU_MAIN1;
			}
			else if(select)/*select pressed*/
			{
				if(menusub==0 && (df0.status&DSK_INSERTED))/*eject floppy*/
				{
					df0.status=0;
					menustate=MENU_MAIN1;	
				}
				else if(menusub==0)/*insert floppy*/
				{
					df0.status=0;
					menustate=MENU_FILE1;
					OsdClear();
				}
				else if(menusub==2)/*exit menu*/
					menustate=MENU_NONE1;
			}
			
			break;
			
		/******************************************************************/
		/*adf file requester menu*/
		/******************************************************************/
		case MENU_FILE1:
			PrintDir();
			menustate=MENU_FILE2;
			break;

		case MENU_FILE2:
			if(down)/*scroll down through file requester*/
			{
				ScrollDir("ADF",1);
				menustate=MENU_FILE1;
			}
			
			if(up)/*scroll up through file requester*/
			{
				ScrollDir("ADF",2);
				menustate=MENU_FILE1;
			}
			
			if(select)/*insert floppy*/
			{
				file=directory[dirptr];
				InsertFloppy(&df0);
				menustate=MENU_MAIN1;
				menusub=2;
				OsdClear();
			}
			
			if(menu)/*exit menu*/
				menustate=MENU_NONE1;
				
			break;
			
		/******************************************************************/
		/*we should never come here*/
		/******************************************************************/
		default:
			break;
	}
}

/*print the contents of directory[] and the pointer dirptr onto the OSD*/
void PrintDir(void)
{
	unsigned char i;

	for(i=0;i<DIRSIZE;i++)
	{
			if(i==dirptr)
				sprintf(s,"--> ");
			else
				sprintf(s,"    ");

			strncpy(&s[4],directory[i].name,8);
			s[12]=0x0d;
			s[13]=0x00;
			OsdWrite(i,s);
	}	
}

/*This function "scrolls" through the flashcard directory and fills the directory[] array to be printed later.
modes set by <mode>:
0: fill directory[] starting at beginning of directory on flashcard
1: move down through directory
2: move up through directory
This function can also filter on filetype. <type> must point to a string containing the 3-letter filetype
to filter on. If the first character is a '*', no filter is applied (wildcard)*/
void ScrollDir(const unsigned char *type, unsigned char mode)
{
	unsigned char i,m,r;
	
	switch(mode)
	{
		/*reset directory to beginning*/
		case 0:
		default:
			i=0;
			m=FILESEEK_START;
			/*fill directory with available files*/
			while(i<DIRSIZE)
			{
				if(!FileSearch2(&file,m))/*search file*/
					break;
				m=FILESEEK_NEXT;
				if((type[0]=='*')||(strncmp(&file.name[8],type,3)));/*check filetype*/
					directory[i++]=file;
			}
			/*clear rest of directory*/
			while(i<DIRSIZE)
				directory[i++].len=0;
			/*preset pointer*/
			dirptr=0;
			
			break;
			
		/*scroll down*/
		case 1:
			if(dirptr>=DIRSIZE-1)/*pointer is at bottom of directory window*/
			{
				file=directory[(DIRSIZE-1)];
				
				/*search next file and check for filetype/wildcard and/or end of directory*/
				do
					r=FileSearch2(&file,FILESEEK_NEXT);
				while((type[0]!='*')&&(strncmp(&file.name[8],type,3))&&r);
				
				/*update directory[] if file found*/
				if(r)
				{
					for(i=0;i<DIRSIZE-1;i++)
						directory[i]=directory[i+1];
					directory[DIRSIZE-1]=file;
				}
			}
			else/*just move pointer in window*/
			{
				dirptr++;
				if(directory[dirptr].len==0)
					dirptr--;
			}
			break;
			
		/*scroll up*/
		case 2:
			if(dirptr==0)/*pointer is at top of directory window*/
			{
				file=directory[0];
				
				/*search previous file and check for filetype/wildcard and/or end of directory*/
				do
					r=FileSearch2(&file,FILESEEK_PREV);
				while((type[0]!='*')&&(strncmp(&file.name[8],type,3))&&r);
				
				/*update directory[] if file found*/
				if(r)
				{
					for(i=DIRSIZE-1;i>0;i--)
						directory[i]=directory[i-1];
					directory[0]=file;
				}
			}
			else/*just move pointer in window*/
				dirptr--;
			break;
	}
}

/*insert floppy image pointed to to by global <file> into <drive>*/
void InsertFloppy(struct adfTYPE *drive)
{
	unsigned char i,j;

	/*clear OSD and prepare progress bar*/
	OsdClear();
	OsdWrite(0,"  Inserting floppy");
	OsdWrite(1,"       in DF0");
	strcpy(s,"[                  ]");

	/*fill cache*/
	for(i=0;i<160;i++)
	{
		if(i%9==0)
		{
			s[(i/9)+1]='*';
			OsdWrite(3,s);
		}
			
		drive->cache[i]=file.cluster;
		for(j=0;j<11;j++)
			FileNextSector2(&file);
	}
	
	/*copy name*/
	for(i=0;i<12;i++)
		drive->name[i]=file.name[i];
	
	/*initialize rest of struct*/
	drive->status=DSK_INSERTED;
	drive->clusteroffset=drive->cache[0];		
	drive->sectoroffset=0;		
	drive->track=0;				
	drive->trackprev=0;					
}



/*Handle an FPGA command*/
void HandleFpgaCmd(unsigned char c1, unsigned char c2)
{
	/*c1 is command byte*/
	switch(c1&(CMD_GETDSKSTAT|CMD_RDTRCK|CMD_WRTRCK))
	{
		/*FPGA is requesting track status*/
		case CMD_GETDSKSTAT:
			CheckTrack(&df0);
			break;
			
		/*FPGA wants to read a track
		c2 is track number*/
		case CMD_RDTRCK:
			df0.track=c2;
			DISKLED=1;
			ReadTrack(&df0);
			DISKLED=0;
			break;
			
		/*FPGA wants to write a track
		c2 is track number*/
		case CMD_WRTRCK:
			df0.track=c2;
			WriteTrack(&df0);
			break;
			
		/*no command*/
		default:
			break;
	}
}

/*CheckTrack, respond with disk status*/
void CheckTrack(struct adfTYPE *drive)
{
	EnableFpga();
	SPI(0x00);
	SPI(0x00);	
	SPI(0x00);
	SPI(drive->status);
	DisableFpga();	
}

/*load kickstart rom*/
void ReadRom(unsigned char track)
{
	unsigned char c1,c2;
	unsigned char j;
	unsigned short n;
	unsigned char *p;

	/*open kickstart file*/
	Open("KICK    ROM");
	
	/*do for 1024 sectors of 512 bytes each --> 512kbyte*/
	n=0;
	while(n<1024)
	{
		do
		{
			/*read command from FPGA*/
			EnableFpga();
			c1=SPI(0);
			c2=SPI(0);
			if(c1&0x04)
			{
				SPI(0x00);
				SPI(0x01);
			}
			DisableFpga();
		}
		while(!(c1&0x02));
			
		putchar('.');	

		/*read sector from mmc*/
		SSPCON1=0x30;
		FileRead2(&file);
		SSPCON1=0x31;

		/*send sector to fpga*/
		EnableFpga();
		c1=SPI(0);
		c2=SPI(0);
		p=secbuf;
		j=128;
		do
		{
			SSPBUF=*(p++);
			while(!BF);		
			SSPBUF=*(p++);
			while(!BF);		
			SSPBUF=*(p++);
			while(!BF);		
			SSPBUF=*(p++);
			while(!BF);		
		}
		while(--j);
		DisableFpga();
	
		/*go to next sector*/
		SSPCON1=0x30;
		FileNextSector2(&file);
		SSPCON1=0x31;
	
		/*increment track counter*/
		n++;
	}
}

/*configure FPGA*/
unsigned char ConfigureFpga(void)
{
	unsigned short t;
	unsigned char *ptr;
	
	/*reset FGPA configuration sequence*/
	PROG_B=0;
	PROG_B=1;
	
	/*now wait for INIT to go high*/
	t=50000;
	while(!INIT_B)
		if(--t==0)
			return(0);
			
	printf("FPGA init is high\r");
			
	/*open bitstream file*/
	Open("MINIMIG1BIN");

	printf("FPGA bitstream file opened\r");
	
	/*send all bytes to FPGA in loop*/
	t=0;	
	do
	{
		/*read sector if 512 (64*8) bytes done*/
		if(t%64==0)
		{
			putchar('*');
			if(!FileRead2(&file))
				return(0);				
			ptr=secbuf;
		}
		
		/*send data in packets of 8 bytes*/
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		ShiftFpga(*(ptr++));
		t++;	

		/*read next sector if 512 (64*8) bytes done*/
		if(t%64==0)
		{
			FileNextSector2(&file);
		}
	}
	while(t<26549);
	
	printf("\rFPGA bitstream loaded\r");
	
	/*check if DONE is high*/
	if(DONE)
		return(1);
	else
		return(0);
}

/*read a track from disk*/
void ReadTrack(struct adfTYPE *drive)
{
	unsigned char sector,c1,c2;

	/*search track*/
	putchar((drive->track/10)+48);
	putchar((drive->track%10)+48);

	/*check if we are accessing new track or first track*/
	if((drive->track!=drive->trackprev) || (drive->track==0))
	{/*track step or track 0, start at beginning of track*/
		drive->trackprev=drive->track;

		sector=0;
		file.cluster=drive->cache[drive->track];
		file.sec=drive->track*11;
	}
	else if(drive->clusteroffset!=0)
	{/*same track, start at next sector in track*/
		sector=drive->sectoroffset;
		file.cluster=drive->clusteroffset;
		file.sec=(drive->track*11)+sector;
	}
	else
	{/*???? --> start at beginning of track*/
		sector=0;
		file.cluster=drive->cache[drive->track];
		file.sec=drive->track*11;
	}
	
	drive->clusteroffset=0;

	while(1)
	{
		/*read sector*/
		SSPCON1=0x30;
		FileRead2(&file);
		SSPCON1=0x31;
		
		/*we are now going to access FPGA*/
		EnableFpga();

		/*check if FPGA is still asking for data*/
		c1=SPI(0);
		c2=SPI(0);
				
		/*send sector if fpga is still asking for data*/
		if(c1&0x02)
		{
			SectorToFpga(sector,drive->track);
			putchar('.');
		}
		
		/*we are done accessing FPGA*/
		DisableFpga();
		
		/*point to next sector*/
		if(++sector>=11)
		{
			sector=0;
			file.cluster=drive->cache[drive->track];
			file.sec=drive->track*11;
		}
		else
		{			
			SSPCON1=0x30;
			FileNextSector2(&file);
			SSPCON1=0x31;
		}
		
		/*remember second cluster of this track read, skip last sector*/
		/*if(drive->clusteroffset==0 && sector!=10)*/
		if(drive->clusteroffset==0)
		{
			drive->sectoroffset=sector;
			drive->clusteroffset=file.cluster;
		}
		
		/*if track done, exit*/
		if(!(c1&0x02))
			break;
	}		

	putchar('O');
	putchar('K');
	putchar(0x0d);
}

void WriteTrack(struct adfTYPE *drive)
{
	printf("Write track not supported yet\r");
}


void Open(const unsigned char *name)
{
	unsigned char i,j;
	
	if(FileSearch2(&file,0))
	{
		do
		{
			i=0;
			for(j=0;j<11;j++)
				if(file.name[j]==name[j])
					i++;
			if(i==11)
			{
				printf("file found\r");
				return;	
			}
		}
		while(FileSearch2(&file,1));
	}
	printf("file not found\r");
}



/*this function sends the data in the sector buffer to the FPGA, translated
into an Amiga floppy format sector
sector is the sector number in the track
track is the track number
note that we do not insert clock bits because they will be stripped
by the Amiga software anyway*/
void SectorToFpga(unsigned char sector,unsigned char track)
{
	unsigned char c,i;
	unsigned char csum[4];
	unsigned char *p;
	
	/*preamble*/
	SPI(0xaa);		
	SPI(0xaa);		
	SPI(0xaa);		
	SPI(0xaa);
	
	/*synchronization*/
	SPI(0x44);
	SPI(0x89);		
	SPI(0x44);
	SPI(0x89);		

	/*clear header checksum*/
	csum[0]=0;
	csum[1]=0;
	csum[2]=0;
	csum[3]=0;
	
	/*odd bits of header*/
	c=0x55;
	csum[0]^=c;
	SPI(c);
	c=(track>>1)&0x55;
	csum[1]^=c;
	SPI(c);
	c=(sector>>1)&0x55;
	csum[2]^=c;
	SPI(c);
	c=((11-sector)>>1)&0x55;
	csum[3]^=c;
	SPI(c);

	/*even bits of header*/
	c=0x55;
	csum[0]^=c;
	SPI(c);
	c=track&0x55;
	csum[1]^=c;
	SPI(c);
	c=sector&0x55;
	csum[2]^=c;
	SPI(c);
	c=(11-sector)&0x55;
	csum[3]^=c;
	SPI(c);
	
	/*sector label and reserved area (changes nothing to checksum)*/
	for(i=0;i<32;i++)
		SPI(0x55);
	
	/*checksum over header*/
	SPI((csum[0]>>1)|0xaa);
	SPI((csum[1]>>1)|0xaa);
	SPI((csum[2]>>1)|0xaa);
	SPI((csum[3]>>1)|0xaa);
	SPI(csum[0]|0xaa);
	SPI(csum[1]|0xaa);
	SPI(csum[2]|0xaa);
	SPI(csum[3]|0xaa);
	
	/*calculate data checksum*/
	csum[0]=0;
	csum[1]=0;
	csum[2]=0;
	csum[3]=0;
	i=128;
	p=secbuf;
	do
	{
		c=*(p++);
		csum[0]^=c>>1;
		csum[0]^=c;
		c=*(p++);
		csum[1]^=c>>1;
		csum[1]^=c;
		c=*(p++);
		csum[2]^=c>>1;
		csum[2]^=c;
		c=*(p++);
		csum[3]^=c>>1;
		csum[3]^=c;
	}	
	while(--i);
	csum[0]&=0x55;
	csum[1]&=0x55;
	csum[2]&=0x55;
	csum[3]&=0x55;
	
		
	/*checksum over data*/
	SPI((csum[0]>>1)|0xaa);
	SPI((csum[1]>>1)|0xaa);
	SPI((csum[2]>>1)|0xaa);
	SPI((csum[3]>>1)|0xaa);
	SPI(csum[0]|0xaa);
	SPI(csum[1]|0xaa);
	SPI(csum[2]|0xaa);
	SPI(csum[3]|0xaa);
	
	/*odd bits of data field*/	
	i=128;
	p=secbuf;
	do
	{
		c=*(p++);
		c>>=1;
		c|=0xaa;
		SSPBUF=c;
		while(!BF);		
		
		c=*(p++);
		c>>=1;
		c|=0xaa;
		SSPBUF=c;
		while(!BF);		
		
		c=*(p++);
		c>>=1;
		c|=0xaa;
		SSPBUF=c;
		while(!BF);		
		
		c=*(p++);
		c>>=1;
		c|=0xaa;
		SSPBUF=c;
		while(!BF);
	}
	while(--i);
	
	/*even bits of data field*/	
	i=128;
	p=secbuf;
	do
	{
		c=*(p++);
		SSPBUF=c|0xaa;
		while(!BF);		
		c=*(p++);
		SSPBUF=c|0xaa;
		while(!BF);		
		c=*(p++);
		SSPBUF=c|0xaa;
		while(!BF);		
		c=*(p++);
		SSPBUF=c|0xaa;
		while(!BF);
	}
	while(--i);
	
}
	
