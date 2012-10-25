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

JB:
2008-02-09      -added error handling
				number of blinks:
				1: neither mmc nor sd card detected
				2: fat16 filesystem not detected
				3: FPGA configuration error (INIT low or DONE high before config)
				4: no MINIMIG1.BIN file found
				5: FPGA configuration error (DONE is low after config)
				6: no kickstart file found

2008-07-18		-better read support (sector loaders are now less confused)
				-write support added (strict sector format checking - may not work with non DOS games)
				-removed bug in filename filtering (initial directory fill didn't filter)
				-communication interface with new bootloader
				-OSD control of reset, ram configuration, interpolation filters and kickstart

				WriteTrack errors:
				#20 : unexpected dma transfer end (sector header)
				#21 : no second sync word found
				#22 : first header byte not 0xFF
				#23 : second header byte (track number) not within 0..159 range
				#24 : third header byte (sector number) not within 0..10 range
				#25 : fourth header byte (sectors to gap number) not within 1..11 range
				#26 : header checksum error
				#27 : track number in sector header not the same as drive head position
				#28 : unexpected dma transfer end (sector data)
				#29 : data checksum error
				#30 : write attempt to protected disk

2008-07-25		-update of write sector header format checking
				-disk led active during writes to disk
*/

#include <pic18.h>
#include <stdio.h>
#include <string.h>
#include "hardware.h"
#include "osd.h"
#include "ata18.h"
#include "fat1618_2.h"

#define DEBUG

void CheckTrack(struct adfTYPE *drive);
void ReadTrack(struct adfTYPE *drive);
void SendFile(struct file2TYPE *file);
void WriteTrack(struct adfTYPE *drive);
unsigned char FindSync(struct adfTYPE *drive);
unsigned char GetHeader(unsigned char *pTrack, unsigned char *pSector);
unsigned char GetData();

char BootPrint(const char* text);
char BootUpload(struct file2TYPE *file, unsigned char base, unsigned char size);
void BootExit(void);
void ErrorMessage(const char* message, unsigned char code);
unsigned short SectorToFpga(unsigned char sector,unsigned char track);
void SectorGapToFpga(void);
void SectorHeaderToFpga(unsigned char);
char UploadKickstart(const unsigned char *name);
unsigned char Open(const unsigned char *name);
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

#define		ST_READREQ	0x02

/*floppy status*/
#define		DSK_INSERTED		0x01	/*disk is inserted*/
#define		DSK_WRITABLE		0x02	/*disk is writable*/

/*menu states*/
#define		MENU_NONE1			0		/*no menu*/		
#define		MENU_NONE2			1		/*no menu*/		
#define		MENU_MAIN1			2		/*main menu*/
#define		MENU_MAIN2			3		/*main menu*/
#define		MENU_FILE1			4		/*file requester menu*/
#define		MENU_FILE2			5		/*file requester menu*/
#define		MENU_RESET1			6		/*reset menu*/
#define		MENU_RESET2			7		/*reset menu*/
#define		MENU_SETTINGS1		8		/*settings menu*/
#define		MENU_SETTINGS2		9		/*settings menu*/
#define		MENU_ROMSELECT1		10		/*rom select menu*/
#define		MENU_ROMSELECT2		11		/*rom select menu*/
#define		MENU_ROMFILE1		12		/*rom file select menu*/
#define		MENU_ROMFILE2		13		/*rom file select menu*/
#define		MENU_ERROR			127		/*error message menu*/

/*other constants*/
#define		DIRSIZE				8		/*size of directory display window*/
#define		REPEATTIME			50		/*repeat delay in 10ms units*/
#define		REPEATRATE			5		/*repeat rate in 10ms units*/

#define		EEPROM_LRFILTER		0x10
#define		EEPROM_HRFILTER		0x11
#define		EEPROM_MEMCFG		0x12
#define		EEPROM_KICKNAME		0x18	//size 8

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

unsigned char menustate = MENU_NONE1;
unsigned char menusub = 0;

unsigned char s[25];					/*used to build strings*/

bdata unsigned char kickname[12];

unsigned char lr_filter;
unsigned char hr_filter;
const char* filter_msg[] = {"none","HOR ","VER ","H+V "};
unsigned char memcfg;
const char* memcfg_msg[] = {"512K CHIP","1Meg CHIP","512K/512K","1Meg/512K"};

unsigned char Error;

void FatalError(unsigned char code)
{
// code = number of blinks
	unsigned long t;
	unsigned char i;
	while (1)
	{
		i = code;
		do
		{
			t = 38000;
			while (--t) //wait 100ms
				DISKLED = 1;
			t = 2*38000;	
			while (--t) //wait 200ms
				DISKLED = 0;
		} while (--i);
		t = 8*38000;
		while (--t) //wait 900ms
			DISKLED = 0;
	}
}


/*This is where it all starts after reset*/
void main(void)
{
	unsigned char c1,c2,c3,c4;
	unsigned short t;
	unsigned char c;
	unsigned char i;

	/*initialize hardware*/
	HardwareInit();

	lr_filter = eeprom_read(EEPROM_LRFILTER);
	if (lr_filter&0xFC)
		lr_filter = 0;

	hr_filter = eeprom_read(EEPROM_HRFILTER);
	if (hr_filter&0xFC)
		hr_filter = 0;

	memcfg = eeprom_read(EEPROM_MEMCFG);
	if (memcfg&0xFC)
		memcfg = 0;

	//check correctness of kickstart file name
	for (i=0;i<8;i++)
	{
		c = eeprom_read(EEPROM_KICKNAME+i);
		if (c==' ' || (c>='0' && c<='9') || (c>='A' && c<='Z'))	//only 0-9,A-Z and space allowed
			kickname[i] = c;
		else
		{
			strncpy(kickname,"KICK    ",8);	//if illegal character detected revert to default name
			break;
		}
	}
	strncpy(&kickname[8],"ROM",3);	//add rom file extension

	printf("\rMinimig Controller by Dennis van Weeren\r");
	printf("Bug fixes, mods and extensions by Jakub Bednarski\r\r");
	printf("Version PYQ080725\r\r");

	/*intialize mmc card*/
	if (SDCARD_Init()==0)
	{
		FatalError(1);
	}	

	/*initalize FAT partition*/
	if (FindDrive2())
	{	
		printf("FAT16 filesystem found!\r");
	}
	else
	{
		printf("No FAT16 filesystem!\r");
		FatalError(2);
	}
	
/*	if (DONE) //FPGA has not been configured yet
	{
		printf("FPGA already configured\r");
	}
	else
*/	{
		/*configure FPGA*/
		if (ConfigureFpga())
		{	
			printf("FPGA configured\r");
		}
		else
		{
			printf("FPGA configuration failed\r");
			FatalError(3);
		}
	}		

	BootPrint("** PIC firmware PYQ080725 **\n");

	if (UploadKickstart(kickname))
	{
		strcpy(kickname,"KICK    ROM");	
		if (UploadKickstart(kickname))
			FatalError(6);
	}

	if (!CheckButton())	//if menu button pressed don't load Action Replay
		if (Open("AR3     ROM"))
		{
			if (file.len == 0x40000)
			{//256KB Action Replay 3 ROM
				BootPrint("\nUploading Action Replay ROM...");
				BootUpload(&file,0x40,0x04);
			}
			else
			{
				BootPrint("\nUnsupported AR3.ROM file size!!!");
				FatalError(6);		
			}
		}

	OsdFilter(lr_filter,hr_filter);	//set interpolation filters
	OsdMemoryConfig(memcfg);		//set memory config

	printf("Bootloading complete.\r");

	BootPrint("Exiting bootloader...");
	BootExit();

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
		if (CheckTimer(t))
		{
			t=GetTimer(2);
			User();
		}
	}
}

char UploadKickstart(const unsigned char *name)
{
	if (Open(name))
	{
		if (file.len == 0x80000)
		{//512KB Kickstart ROM
			BootPrint("Uploading 512KB Kickstart...");
			BootUpload(&file,0xF8,0x08);
		}
		else if (file.len == 0x40000)
		{//256KB Kickstart ROM
			BootPrint("Uploading 256KB Kickstart...");
			BootUpload(&file,0xF8,0x04);
		}
		else
		{
			BootPrint("Unsupported Kickstart ROM file size!");
			return 41;
		}
	}
	else
	{
		sprintf(s,"No \"%11s\" file!",name);
		BootPrint(s);
		return 40;
	}
	return 0;
}

char BootPrint(const char* text)
{
	char c1,c2,c3,c4;
	char cmd;
	const char* p;
	unsigned char n;
	
 	p = text;
	n = 0;
	while (*(p++) != 0)
		n++; //calculating string length

	cmd = 1;
	while (1)
	{
		EnableFpga();
		c1=SPI(0);
		c2=SPI(0);
		c3=SPI(0);
		c4=SPI(1);	//disk present
		//printf("CMD%d:%02X,%02X,%02X,%02X\r",cmd,c1,c2,c3,c4);
		if (c1 == CMD_RDTRCK)
		{
			if (cmd)
			{//command phase
				if (c3==0x80 && c4==0x06)	//command packet size 12 bytes
				{
					cmd = 0;;
					SPI(0xAA);	//command header
					SPI(0x55);
					SPI(0x00);	//cmd: 0001 = print
					SPI(0x01);
					//data packet size in bytes
					SPI(0x00);
					SPI(0x00);
					SPI(0x00);
					SPI(n+2); //+2 because only even byte count is possible to send and we have to send termination zero byte
					//don't care
					SPI(0x00);
					SPI(0x00);
					SPI(0x00);
					SPI(0x00);
				}
				else break;
			}
			else
			{//data phase
				if (c3==0x80 && c4==((n+2)>>1))
				{
					p = text;
					n = c4<<1;
					while (n--)
					{
						c4 = *p;
						SPI(c4);
						if (c4) //if current character is not zero go to next one
							p++;
					}
					DisableFpga();	
					return 1;
				}
				else break;
			}
		}
		DisableFpga();	
	}
	DisableFpga();	
	return 0;
}

char BootUpload(struct file2TYPE *file, unsigned char base, unsigned char size)
// this function sends given file to minimig's memory
// base - memory base address (bits 23..16)
// size - memory size (bits 23..16)
{
	char c1,c2,c3,c4;
	char cmd;
	
	cmd = 1;
	while (1)
	{
		EnableFpga();
		c1=SPI(0);
		c2=SPI(0);
		c3=SPI(0);
		c4=SPI(1);	//disk present
		//printf("CMD%d:%02X,%02X,%02X,%02X\r",cmd,c1,c2,c3,c4);
		if (c1 == CMD_RDTRCK)
		{
			if (cmd)
			{//command phase
				if (c3==0x80 && c4==0x06)	//command packet size 12 bytes
				{
					cmd = 0;
					SPI(0xAA);
					SPI(0x55);	//command header 0xAA55
					SPI(0x00);
					SPI(0x02);	//cmd: 0x0002 = upload memory
					//memory base address
					SPI(0x00);
					SPI(base);
					SPI(0x00);
					SPI(0x00);
					//memory size
					SPI(0x00);
					SPI(size);
					SPI(0x00);
					SPI(0x00);
				}
				else break;
			}
			else
			{//data phase
				DisableFpga();	
				printf("uploading ROM file\r");
				//send rom image to FPGA
				SendFile(file);
				printf("\rROM file uploaded\r");
				return 0;
			}
		}
		DisableFpga();	
	}
	DisableFpga();
	return -1;
}

void BootExit(void)
{
	char c1,c2,c3,c4;
	while (1)
	{
		EnableFpga();
		c1 = SPI(0);
		c2 = SPI(0);
		c3 = SPI(0);
		c4 = SPI(1);	//disk present
		if (c1 == CMD_RDTRCK)
		{
			if (c3==0x80 && c4==0x06)	//command packet size 12 bytes
			{
				SPI(0xAA);	//command header
				SPI(0x55);
				SPI(0x00);	//cmd: 0003 = restart
				SPI(0x03);
				//don't care
				SPI(0x00);
				SPI(0x00);
				SPI(0x00);
				SPI(0x00);
				//don't care
				SPI(0x00);
				SPI(0x00);
				SPI(0x00);
				SPI(0x00);
			}
			DisableFpga();	
			return;
		}
		DisableFpga();	
	}
}

/*user interface*/
void User(void)
{
	unsigned char i,c,up,down,select,menu;
	
	/*get user control codes*/
	c=OsdGetCtrl();
	
	/*decode and set events*/
	up=0;
	down=0;
	select=0;
	menu=0;
	if (c&OSDCTRLUP)
		up=1;
	if (c&OSDCTRLDOWN)
		down=1;
	if (c&OSDCTRLSELECT)
		select=1;
	if (c&OSDCTRLMENU)
		menu=1;
	
		
	/*menu state machine*/
	switch (menustate)
	{
		/******************************************************************/
		/*no menu selected / menu exited / menu not displayed*/
		/******************************************************************/
		case MENU_NONE1:
			OsdDisable();
			menustate=MENU_NONE2;
			break;
			
		case MENU_NONE2:
			if (menu)/*check if user wants to go to menu*/
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
			OsdWrite(0," ** Minimig Menu **",0);
			
			/*df0 info*/
			strcpy(s,"     df0: ");
			if (df0.status&DSK_INSERTED)/*floppy currently in df0*/
				strncpy(&s[10],df0.name,8);
			else/*no floppy in df0*/
				strncpy(&s[10],"--------",8);
			s[18]=0x0d;
			s[19]=0x00;
			OsdWrite(2,s,0);	
			
			if (df0.status&DSK_INSERTED)/*floppy currently in df0*/
				if (df0.status&DSK_WRITABLE)/*floppy is writable*/
					strcpy(s,"     writable ");
				else
					strcpy(s,"     read only");
			else	/*no floppy in df0*/
				strcpy(s,"     no disk  ");
			OsdWrite(3,s,0);	

			/*eject/insert df0 options*/
			if (df0.status&DSK_INSERTED)/*floppy currently in df0*/
				sprintf(s,"     eject df0 ");
			else/*no floppy in df0*/
				sprintf(s,"     insert df0");
			OsdWrite(4,s,menusub==0);	

			OsdWrite(5,"     settings",menusub==1);
			
			/*reset system*/
			OsdWrite(6,"     reset",menusub==2);
			
			/*exit menu*/
			OsdWrite(7,"     exit",menusub==3);

			/*goto to second state of main menu*/
			menustate = MENU_MAIN2;
			break;
			
		case MENU_MAIN2:
			
			if (menu)/*menu pressed*/
				menustate=MENU_NONE1;
			else if (up)/*up pressed*/
			{
				if (menusub>0)
					menusub--;
				menustate=MENU_MAIN1;
			}
			else if (down)/*down pressed*/
			{
				if (menusub<3)
					menusub++;
				menustate=MENU_MAIN1;
			}
			else if (select)/*select pressed*/
			{
				if (menusub==0 && (df0.status&DSK_INSERTED))/*eject floppy*/
				{
					df0.status = 0;
					menustate = MENU_MAIN1;	
				}
				else if (menusub==0)/*insert floppy*/
				{
					df0.status = 0;
					menustate = MENU_FILE1;
					OsdClear();
				}
				else if (menusub==1)/*settings*/
				{
					menusub = 4;
					menustate = MENU_SETTINGS1;
					OsdClear();
				}
				else if (menusub==2)/*reset*/
				{
					menusub = 1;
					menustate = MENU_RESET1;
					OsdClear();
				}
				else if (menusub==3)/*exit menu*/
					menustate = MENU_NONE1;

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
			if (down)/*scroll down through file requester*/
			{
				ScrollDir("ADF",1);
				menustate=MENU_FILE1;
			}
			
			if (up)/*scroll up through file requester*/
			{
				ScrollDir("ADF",2);
				menustate=MENU_FILE1;
			}
			
			if (select)/*insert floppy*/
			{
				if (directory[dirptr].len)
				{
					file = directory[dirptr];
					InsertFloppy(&df0);
				}
				menustate = MENU_MAIN1;
				menusub = 3;
				OsdClear();
			}
			
			if (menu)/*return to main menu*/
			{
				menustate = MENU_MAIN1;
				menusub = 0;
				OsdClear();	
			}			
			break;
		/******************************************************************/
		/*reset menu*/
		/******************************************************************/
		case MENU_RESET1:
			/*menu title*/
			OsdWrite(0,"    Reset Minimig?",0);
			OsdWrite(2,"      yes",menusub==0);
			OsdWrite(3,"      no",menusub==1);
		
			/*goto to second state of reset menu*/
			menustate = MENU_RESET2;
			break;

		case MENU_RESET2:
			if (down && menusub<1)
			{
				menusub++;
				menustate = MENU_RESET1;
			}
			
			if (up && menusub>0)
			{
				menusub--;
				menustate = MENU_RESET1;
			}
			
			if (select)
			{
				if (menusub==0)
				{
					OsdReset(0);
					menustate = MENU_NONE1;
				}
			}
			
			if (menu || (select && menusub==1))/*exit menu*/
			{
					menustate = MENU_MAIN1;
					menusub = 2;
					OsdClear();
			}
			break;			
		/******************************************************************/
		/*settings menu*/
		/******************************************************************/
		case MENU_SETTINGS1:
			/*menu title*/
			OsdWrite(0,"   ** SETTINGS **",0);

			strcpy(s,"  Lores Filter: ");
			strcpy(&s[16],filter_msg[lr_filter]);
			OsdWrite(2,s,menusub==0);
	
			strcpy(s,"  Hires Filter: ");
			strcpy(&s[16],filter_msg[hr_filter]);
			OsdWrite(3,s,menusub==1);

			strcpy(s,"  RAM: ");
			strcpy(&s[7],memcfg_msg[memcfg]);
			OsdWrite(4,s,menusub==2);

			strcpy(s,"  ROM:           ");
			strncpy(&s[7],kickname,8);
			OsdWrite(5,s,menusub==3);


			OsdWrite(7,"        exit",menusub==4);
		
			/*goto to second state of reset menu*/
			menustate = MENU_SETTINGS2;
			break;

		case MENU_SETTINGS2:
			if (down && menusub<4)
			{
				menusub++;
				menustate = MENU_SETTINGS1;
			}
			
			if (up && menusub>0)
			{
				menusub--;
				menustate = MENU_SETTINGS1;
			}
			
			if (select)
			{
				if (menusub==0)
				{
					lr_filter++;
					lr_filter &= 0x03;
					menustate = MENU_SETTINGS1;
					OsdFilter(lr_filter,hr_filter);
				}
				else if (menusub==1)
				{
					hr_filter++;
					hr_filter &= 0x03;
					menustate = MENU_SETTINGS1;
					OsdFilter(lr_filter,hr_filter);
				}
				else if (menusub==2)
				{
					memcfg++;
					memcfg &= 0x03;
					menustate = MENU_SETTINGS1;
					OsdMemoryConfig(memcfg);
				}
				else if (menusub==3)
				{
					if (df0.status&DSK_INSERTED)
						OsdWrite(5,"   Remove floppy!",1);
					else
					{
						menustate = MENU_ROMSELECT1;
						OsdClear();
					}
				}

				else if (menusub==4)
				{
					if 	(lr_filter != eeprom_read(EEPROM_LRFILTER))
						eeprom_write(EEPROM_LRFILTER,lr_filter);

					if 	(hr_filter != eeprom_read(EEPROM_HRFILTER))
						eeprom_write(EEPROM_HRFILTER,hr_filter);

					if 	(memcfg != eeprom_read(EEPROM_MEMCFG))
						eeprom_write(EEPROM_MEMCFG,memcfg);
				}
			}
			
			if (menu || (select && menusub==4)) /*return to main menu*/
			{
					menustate = MENU_MAIN1;
					menusub = 1;
					OsdClear();
			}
			break;			

		/******************************************************************/
		/*kickstart rom select menu*/
		/******************************************************************/
		case MENU_ROMSELECT1:
			/*menu title*/
			OsdWrite(0,"   ** Kickstart **",0);

			strcpy(s,"    ROM: ");
			strncpy(&s[9],kickname,8);
			s[9+8] = 0;
			OsdWrite(2,s,0);
			OsdWrite(3,"    select",menusub==0);
			OsdWrite(4,"    rekick",menusub==1);
			OsdWrite(5,"    rekick & save",menusub==2);
	
			OsdWrite(7,"        exit",menusub==3);
		
			/*goto to second state of reset menu*/
			menustate = MENU_ROMSELECT2;
			break;

		case MENU_ROMSELECT2:
			if (down && menusub<3)
			{
				menusub++;
				menustate = MENU_ROMSELECT1;
			}
			
			if (up && menusub>0)
			{
				menusub--;
				menustate = MENU_ROMSELECT1;
			}
			
			if (select)
			{
				if (menusub==0)
				{
					ScrollDir("ROM",0);
					menustate = MENU_ROMFILE1;
					OsdClear();
				}
				else if (menusub==1 || menusub==2)
				{
					OsdDisable();
					menustate = MENU_NONE1;
					OsdReset(1);
					if (UploadKickstart(kickname)==0)
					{
						BootExit();
						if (menusub==2)
						{
							for (i=0;i<8;i++)
							{
								if (kickname[i] != eeprom_read(EEPROM_KICKNAME+i))
									eeprom_write(EEPROM_KICKNAME+i,kickname[i]);
								
							}
						}
					}
				}
			}
			if (menu || (select && menusub==3))/*return to settings menu*/
			{
				menustate = MENU_SETTINGS1;
				menusub = 3;
				OsdClear();
			}
				
			break;
		/******************************************************************/
		/*rom file requester menu*/
		/******************************************************************/
		case MENU_ROMFILE1:
			PrintDir();
			menustate = MENU_ROMFILE2;
			break;

		case MENU_ROMFILE2:
			if (down)/*scroll down through file requester*/
			{
				ScrollDir("ROM",1);
				menustate = MENU_ROMFILE1;
			}
			
			if (up)/*scroll up through file requester*/
			{
				ScrollDir("ROM",2);
				menustate=MENU_ROMFILE1;
			}
			
			if (select)/*select rom file*/
			{
				menusub = 3;
				if (directory[dirptr].len)
				{
					file = directory[dirptr];
					strncpy(kickname,file.name,8+3);
					menusub = 1;
				}
				ScrollDir("ADF",0);
				menustate = MENU_ROMSELECT1;
				OsdClear();
			}
			
			if (menu)/*return to kickstrat rom select menu*/
			{
				ScrollDir("ADF",0);
				menustate = MENU_ROMSELECT1;
				menusub = 0;
				OsdClear();
			}
				
			break;
		/******************************************************************/
		/*error message menu*/
		/******************************************************************/
		case MENU_ERROR:
			if (menu) /*exit when menu button is pressed*/
			{
				menustate = MENU_NONE1;
			}
			break;
		/******************************************************************/
		/*we should never come here*/
		/******************************************************************/
		default:
			break;
	}
}

void ErrorMessage(const char* message, unsigned char code)
{
	unsigned char i;
	menustate = MENU_ERROR;
	OsdClear();
	OsdWrite(0,"    *** ERROR ***",1);
	strncpy(s,message,21);
	s[21] = 0;
	OsdWrite(2,s,0);
	if (code)
	{
		sprintf(s,"  error #%d",code);
		OsdWrite(4,s,0);
	}
	OsdEnable();
}

/*print the contents of directory[] and the pointer dirptr onto the OSD*/
void PrintDir(void)
{
	unsigned char i;

	for(i=0;i<21;i++)
		s[i] = ' ';
	s[21] = 0;

	if (directory[0].len==0)
		OsdWrite(1,"   No files!",1);
	else
	for(i=0;i<DIRSIZE;i++)
	{
		strncpy(&s[3],directory[i].name,8);
		OsdWrite(i,s,i==dirptr);
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
	unsigned char i,rc;
	
	switch (mode)
	{
		/*reset directory to beginning*/
		case 0:
		default:
			i = 0;
			mode = FILESEEK_START;
			memset(directory,0,sizeof(directory));
			/*fill directory with available files*/
			while (i<DIRSIZE)
			{
				if (!FileSearch2(&file,mode))/*search file*/
					break;
				mode = FILESEEK_NEXT;
				if ((type[0]=='*') || (strncmp(&file.name[8],type,3)==0))/*check filetype*/
					directory[i++] = file;
			}
			/*clear rest of directory*/
			while (i<DIRSIZE)
				directory[i++].len = 0;
			/*preset pointer*/
			dirptr = 0;
			
			break;
			
		/*scroll down*/
		case 1:
			if (dirptr >= DIRSIZE-1)/*pointer is at bottom of directory window*/
			{
				file = directory[(DIRSIZE-1)];
				
				/*search next file and check for filetype/wildcard and/or end of directory*/
				do
					rc = FileSearch2(&file,FILESEEK_NEXT);
				while ((type[0]!='*') && (strncmp(&file.name[8],type,3)) && rc);
				
				/*update directory[] if file found*/
				if (rc)
				{
					for (i=0;i<DIRSIZE-1;i++)
						directory[i] = directory[i+1];
					directory[DIRSIZE-1] = file;
				}
			}
			else/*just move pointer in window*/
			{
				dirptr++;
				if (directory[dirptr].len==0)
					dirptr--;
			}
			break;
			
		/*scroll up*/
		case 2:
			if (dirptr==0)/*pointer is at top of directory window*/
			{
				file = directory[0];
				
				/*search previous file and check for filetype/wildcard and/or end of directory*/
				do
					rc = FileSearch2(&file,FILESEEK_PREV);
				while ((type[0]!='*') && (strncmp(&file.name[8],type,3)) && rc);
				
				/*update directory[] if file found*/
				if (rc)
				{
					for (i=DIRSIZE-1;i>0;i--)
						directory[i] = directory[i-1];
					directory[0] = file;
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
	OsdWrite(0,"  Inserting floppy",0);
	OsdWrite(1,"       in DF0",0);
	strcpy(s,"[                  ]");

	/*fill cache*/
	for(i=0;i<160;i++)
	{
		if (i%9==0)
		{
			s[(i/9)+1]='*';
			OsdWrite(3,s,0);
		}
			
		drive->cache[i]=file.cluster;
		for(j=0;j<11;j++)
			FileNextSector2(&file);
	}
	
	/*copy name*/
	for(i=0;i<12;i++)
		drive->name[i]=file.name[i];
	
	/*initialize rest of struct*/
	drive->status = DSK_INSERTED;
	if (!(file.attributes&0x01))//read-only attribute
		drive->status |= DSK_WRITABLE;
	drive->clusteroffset=drive->cache[0];		
	drive->sectoroffset=0;		
	drive->track=0;				
	drive->trackprev=-1;
	printf("Inserting floppy: \"%s\", attributes: %02X\r",file.name,file.attributes);
	printf("drive status: %02X\r",drive->status);
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
			DISKLED=1;
			WriteTrack(&df0);
			DISKLED=0;
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
void SendFile(struct file2TYPE *file)
{
	unsigned char c1,c2;
	unsigned char j;
	unsigned short n;
	unsigned char *p;

	n = file->len/512;	//sector count (rounded up)
	while (n--)
	{
		/*read sector from mmc*/
		FileRead2(file);

		do
		{
			/*read command from FPGA*/
			EnableFpga();
			c1=SPI(0);
			c2=SPI(0);
			SPI(0);
			SPI(1);	// disk present status
			DisableFpga();
		}
		while(!(c1&0x02));
			
		putchar('.');	

		/*send sector to fpga*/
		EnableFpga();
		c1=SPI(0); 
		c2=SPI(0);
		SPI(0);
		SPI(1);
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
	
		FileNextSector2(file);
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
		if (--t==0)
		{
			printf("FPGA init is NOT high!\r");
			FatalError(3);
			//return(0);
		}
			
	printf("FPGA init is high\r");
			
	if (DONE)
	{
		printf("FPGA done is high before configuration!\r");
		FatalError(3);
	}

	/*open bitstream file*/
	if (Open("MINIMIG1BIN")==0)
	{
		printf("No FPGA configuration file found!\r");
		FatalError(4);
	}

	printf("FPGA bitstream file opened\r");
	
	/*send all bytes to FPGA in loop*/
	t=0;	
	do
	{
		/*read sector if 512 (64*8) bytes done*/
		if (t%64==0)
		{
			DISKLED = !((t>>9)&1);
			putchar('*');
			if (!FileRead2(&file))
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
		if (t%64==0)
		{
			FileNextSector2(&file);
		}
	}
	while(t<26549);
	
	printf("\rFPGA bitstream loaded\r");
	DISKLED = 0;
	
	/*check if DONE is high*/
	if (DONE)
		return(1);
	else
	{
		printf("FPGA done is NOT high!\r");
		FatalError(5);
	}
	return 0;
}

/*read a track from disk*/
void ReadTrack(struct adfTYPE *drive)
{	//track number is updated in drive struct before calling this function

	unsigned char sector;
	unsigned char c,c1,c2,c3,c4;
	unsigned short n;

	/*display track number: cylinder & head*/
#ifdef DEBUG
	printf("*%d:",drive->track);
#endif

	if (drive->track != drive->trackprev)
	{/*track step or track 0, start at beginning of track*/
		drive->trackprev = drive->track;
		sector           = 0;
		file.cluster     = drive->cache[drive->track];
		file.sec         = drive->track*11;
		drive->sectoroffset = sector;
		drive->clusteroffset = file.cluster;
	}
	else
	{/*same track, start at next sector in track*/
		sector       = drive->sectoroffset;
		file.cluster = drive->clusteroffset;
		file.sec     = (drive->track*11)+sector;
	}
	
	EnableFpga();

	c1 = SPI(0);		//read request signal
	c2 = SPI(0);		//track number (cylinder & head)
	c3 = 0x3F&SPI(0);	//msb of mfm words to transfer 
	c4 = SPI(drive->status);		//lsb of mfm words to transfer

	DisableFpga();

	// if dma read count is bigger than 11 sectors then we start the transfer from the begining of current track
	if ((c3>0x17) || (c3==0x17 && c4>=0x60))
	{
		sector           = 0;
		file.cluster     = drive->cache[drive->track];
		file.sec         = drive->track*11;
	}

	while (1)
	{
		FileRead2(&file);

		EnableFpga();

		/*check if FPGA is still asking for data*/
		c1 = SPI(0);	//read request signal
		c2 = SPI(0);	//track number (cylinder & head)
		c3 = SPI(0);	//msb of mfm words to transfer 
		c4 = SPI(drive->status);	//lsb of mfm words to transfer

	#ifdef DEBUG
		c = sector + '0';
		if (c>'9')
			c += 'A'-'9'-1;
		putchar(c);
		putchar(':');
		c = ((c3>>4)&0xF) + '0';
		if (c>'9')
			c += 'A'-'9'-1;
		putchar(c);
		c = (c3&0xF) + '0';
		if (c>'9')
			c += 'A'-'9'-1;
		putchar(c);

		c = ((c4>>4)&0xF) + '0';
		if (c>'9')
			c += 'A'-'9'-1;
		putchar(c);
		c = (c4&0xF) + '0';
		if (c>'9')
			c += 'A'-'9'-1;
		putchar(c);
	#endif

		c3 &= 0x3F;

		//some loaders stop dma if sector header isn't what they expect
		//we don't check dma transfer count after sending every word
		//so the track can be changed while we are sending the rest of the previous sector
		//in this case let's start transfer from the beginning
		if (c2 == drive->track)				
		/*send sector if fpga is still asking for data*/
		if (c1&0x02)
		{
			if (c3==0 && c4<4)
				SectorHeaderToFpga(c4);
			else 
			{
				n = SectorToFpga(sector,drive->track);

				
			#ifdef DEBUG					// printing remaining dma count 
				putchar('-');
				c = ((n>>12)&0xF) + '0';
				if (c>'9')
					c += 'A'-'9'-1;
				putchar(c);
				c = ((n>>8)&0xF) + '0';
				if (c>'9')
					c += 'A'-'9'-1;
				putchar(c);
		
				c = ((n>>4)&0xF) + '0';
				if (c>'9')
					c += 'A'-'9'-1;
				putchar(c);
				c = (n&0xF) + '0';
				if (c>'9')
					c += 'A'-'9'-1;
				putchar(c);					
			#endif

				n--;
				c3 = (n>>8)&0x3F;
				c4 = n;

				if (c3==0 && c4<4)
				{
					SectorHeaderToFpga(c4);
				#ifdef DEBUG
					putchar('+');
					c4 += '0';
					putchar(c4);	
				#endif
				}
				else 
				if (sector==10)
				{
					SectorGapToFpga();
				#ifdef DEBUG
					putchar('+');
					putchar('+');
					putchar('+');
				#endif
				}
			}	
		}
		
		/*we are done accessing FPGA*/
		DisableFpga();

		//track has changed
		if (c2 != drive->track)
			break;

		//read dma request
		if (!(c1&0x02))
			break;


		//don't go to the next sector if there is not enough data in the fifo
		if (c3==0 && c4<4)
			break;

		// go to the next sector
		sector++;
		if (sector<11)
		{			
			FileNextSector2(&file);
		}
		else	//go to the start of current track
		{
			sector       = 0;
			file.cluster = drive->cache[drive->track];
			file.sec     = drive->track*11;
		}
		
		//remember current sector and cluster
		drive->sectoroffset  = sector;
		drive->clusteroffset = file.cluster;

	#ifdef DEBUG
		putchar('-');
		putchar('>');
	#endif

	}

#ifdef DEBUG
	putchar(':');
	putchar('O');
	putchar('K');
	putchar('\r');
#endif

}

void WriteTrack(struct adfTYPE *drive)
{
	unsigned char sector;
	unsigned char Track;
	unsigned char Sector;
	
	//setting file pointer to begining of current track
	file.cluster = drive->cache[drive->track];
	file.sec     = drive->track*11;
	sector = 0;

	drive->trackprev = drive->track+1;	//just to force next read from the start of current track

#ifdef DEBUG
	printf("*%d:\r",drive->track);
#endif

	while (FindSync(drive))
	{
		if (GetHeader(&Track,&Sector))
		{
			if (Track == drive->track)
			{
				while (sector != Sector)
				{
					if (sector < Sector)
					{
						FileNextSector2(&file);
						sector++;
					}
					else
					{
						file.cluster = drive->cache[drive->track];
						file.sec     = drive->track*11;
						sector = 0;
					}
				}				
	
				if (GetData())
				{
					if (drive->status&DSK_WRITABLE)
						FileWrite2(&file);
					else
					{
						Error = 30;
						printf("Write attempt to protected disk!\r");
					}
				}
			}
			else
				Error = 27;		//track number reported in sector header is not the same as current drive track
		}
		if (Error)
		{
			printf("WriteTrack: error %d\r",Error);
			ErrorMessage("  WriteTrack",Error);
		}
	}

}

unsigned char FindSync(struct adfTYPE *drive)
//this function reads data from fifo till it finds sync word
// or fifo is empty and dma inactive (so no more data is expected)
{
	unsigned char c1,c2,c3,c4;
	unsigned short n;

	while (1)
	{
		EnableFpga();
		c1 = SPI(0);			//write request signal
		c2 = SPI(0);			//track number (cylinder & head)
		if (!(c1&CMD_WRTRCK))
			break;
		if (c2 != drive->track)
			break;
		c3 = SPI(0)&0xBF;		//msb of mfm words to transfer 
		c4 = SPI(0);			//lsb of mfm words to transfer

		if (c3==0 && c4==0)
			break;

		n = ((c3&0x3F)<<8) + c4;

		while (n--)
		{
			c3 = SPI(0);
			c4 = SPI(0);
			if (c3==0x44 && c4==0x89)
			{
				DisableFpga();
			#ifdef DEBUG
				printf("#SYNC:");
			#endif
				return 1;
			}
		}
		DisableFpga();
	}
	DisableFpga();
	return 0;
}

unsigned char GetHeader(unsigned char *pTrack, unsigned char *pSector)
//this function reads data from fifo till it finds sync word or dma is inactive
{
	unsigned char c,c1,c2,c3,c4;
	unsigned char i;
	unsigned char checksum[4];

	Error = 0;
	while (1)
	{
		EnableFpga();
		c1 = SPI(0);			//write request signal
		c2 = SPI(0);			//track number (cylinder & head)
		if (!(c1&CMD_WRTRCK))
			break;
		c3 = SPI(0);			//msb of mfm words to transfer 
		c4 = SPI(0);			//lsb of mfm words to transfer

		if ((c3&0x3F)!=0 || c4>24)	//remaining header data is 25 mfm words
		{
			c1 = SPI(0);		//second sync lsb
			c2 = SPI(0);		//second sync msb
			if (c1!=0x44 || c2!=0x89)
			{
				Error = 21;
				printf("\rSecond sync word missing...\r",c1,c2,c3,c4);
				break;
			}

			c = SPI(0);
			checksum[0] = c;
			c1 = (c&0x55)<<1;
			c = SPI(0);
			checksum[1] = c;
			c2 = (c&0x55)<<1;
			c = SPI(0);
			checksum[2] = c;
			c3 = (c&0x55)<<1;
			c = SPI(0);
			checksum[3] = c;
			c4 = (c&0x55)<<1;

			c = SPI(0);
			checksum[0] ^= c;
			c1 |= c&0x55;
			c = SPI(0);
			checksum[1] ^= c;
			c2 |= c&0x55;
			c = SPI(0);
			checksum[2] ^= c;
			c3 |= c&0x55;
			c = SPI(0);
			checksum[3] ^= c;
			c4 |= c&0x55;

			if (c1 != 0xFF)		//always 0xFF
				Error = 22;
			else if (c2 > 159)		//Track number (0-159)
				Error = 23;
			else if (c3 > 10)		//Sector number (0-10)
				Error = 24;
			else if (c4>11 || c4==0)	//Number of sectors to gap (1-11)
				Error = 25;

			if (Error)
			{
				printf("\rWrong header: %d.%d.%d.%d\r",c1,c2,c3,c4);
				break;
			}

		#ifdef DEBUG
			printf("T%dS%d\r",c2,c3);
		#endif

			*pTrack = c2;
			*pSector = c3;

			for (i=0;i<8;i++)
			{
				checksum[0] ^= SPI(0);
				checksum[1] ^= SPI(0);
				checksum[2] ^= SPI(0);
				checksum[3] ^= SPI(0);
			}

			checksum[0] &= 0x55;
			checksum[1] &= 0x55;
			checksum[2] &= 0x55;
			checksum[3] &= 0x55;

			c1 = (SPI(0)&0x55)<<1;
			c2 = (SPI(0)&0x55)<<1;
			c3 = (SPI(0)&0x55)<<1;
			c4 = (SPI(0)&0x55)<<1;

			c1 |= SPI(0)&0x55;
			c2 |= SPI(0)&0x55;
			c3 |= SPI(0)&0x55;
			c4 |= SPI(0)&0x55;

			if (c1!=checksum[0] || c2!=checksum[1] || c3!=checksum[2] || c4!=checksum[3])
			{
				Error = 26;
				break;
			}

			DisableFpga();
			return 1;
		}
		else				//not enough data for header
		if ((c3&0x80)==0)	//write dma is not active
		{
			Error = 20;
			break;
		}

		DisableFpga();
	}

	DisableFpga();
	return 0;
}

unsigned char GetData()
{
	unsigned char c,c1,c2,c3,c4;
	unsigned char i;
	unsigned char *p;
	unsigned short n;
	unsigned char checksum[4];

	Error = 0;
	while (1)
	{
		EnableFpga();
		c1 = SPI(0);			//write request signal
		c2 = SPI(0);			//track number (cylinder & head)
		if (!(c1&CMD_WRTRCK))
			break;
		c3 = SPI(0);			//msb of mfm words to transfer 
		c4 = SPI(0);			//lsb of mfm words to transfer

		n = ((c3&0x3F)<<8) + c4;

		if (n >= 0x204)
		{
			c1 = (SPI(0)&0x55)<<1;
			c2 = (SPI(0)&0x55)<<1;
			c3 = (SPI(0)&0x55)<<1;
			c4 = (SPI(0)&0x55)<<1;

			c1 |= SPI(0)&0x55;
			c2 |= SPI(0)&0x55;
			c3 |= SPI(0)&0x55;
			c4 |= SPI(0)&0x55;

			checksum[0] = 0;
			checksum[1] = 0;
			checksum[2] = 0;
			checksum[3] = 0;

			/*odd bits of data field*/	
			i = 128;
			p = secbuf;
			do
			{
				c = SPI(0);
				checksum[0] ^= c;
				*p++ = (c&0x55)<<1;
				c = SPI(0);
				checksum[1] ^= c;
				*p++ = (c&0x55)<<1;
				c = SPI(0);
				checksum[2] ^= c;
				*p++ = (c&0x55)<<1;
				c = SPI(0);
				checksum[3] ^= c;
				*p++ = (c&0x55)<<1;
			}
			while(--i);

			/*even bits of data field*/	
			i = 128;
			p = secbuf;
			do
			{
				c = SPI(0);
				checksum[0] ^= c;
				*p++ |= c&0x55;
				c = SPI(0);
				checksum[1] ^= c;
				*p++ |= c&0x55;
				c = SPI(0);
				checksum[2] ^= c;
				*p++ |= c&0x55;
				c = SPI(0);
				checksum[3] ^= c;
				*p++ |= c&0x55;
			}
			while(--i);

			checksum[0] &= 0x55;
			checksum[1] &= 0x55;
			checksum[2] &= 0x55;
			checksum[3] &= 0x55;

			if (c1!=checksum[0] || c2!=checksum[1] || c3!=checksum[2] || c4!=checksum[3])
			{
				Error = 29;
				break;
			}

			DisableFpga();
			return 1;
		}
		else				//not enough data in fifo
		if ((c3&0x80)==0)	//write dma is not active
		{
			Error = 28;
			break;
		}	

		DisableFpga();
	}
	DisableFpga();
	return 0;
}

unsigned char Open(const unsigned char *name)
{
	unsigned char i,j;
	
	if (FileSearch2(&file,0))
	{
		do
		{
			i=0;
			for(j=0;j<11;j++)
				if (file.name[j]==name[j])
					i++;
			if (i==11)
			{
				printf("file \"%s\" found\r",name);
				return 1;	
			}
		}
		while(FileSearch2(&file,1));
	}
	printf("file \"%s\" not found\r",name);
	return 0;
}

/*this function sends the data in the sector buffer to the FPGA, translated
into an Amiga floppy format sector
sector is the sector number in the track
track is the track number
note that we do not insert clock bits because they will be stripped
by the Amiga software anyway*/
unsigned short SectorToFpga(unsigned char sector,unsigned char track)
{
	unsigned char c,i;
	unsigned char csum[4];
	unsigned char *p;
	unsigned char c3,c4;
	
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
		c3 = SSPBUF;
		c=*(p++);
		SSPBUF=c|0xaa;
		while(!BF);
		c4 = SSPBUF;
	}
	while(--i);
	
	return((c3<<8)|c4);
}
	

void SectorGapToFpga()
{
	unsigned char i;
	i = 190;
	do
	{
		SPI(0xAA);
		SPI(0xAA);
	}	
	while (--i);
}
	
void SectorHeaderToFpga(unsigned char n)
{
	if (n)
	{
		SPI(0xAA);
		SPI(0xAA);
		
		if (--n)
		{
			SPI(0xAA);
			SPI(0xAA);
	
			if (--n)
			{
				SPI(0x44);
				SPI(0x89);
			}
		}
	}
}

