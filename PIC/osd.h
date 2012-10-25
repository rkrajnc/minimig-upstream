#ifndef OSD_H_INCLUDED
#define	OSD_H_INCLUDED


#define OSDCMDREAD      0x00        //OSD read controller/key status
#define OSDCMDWRITE     0x20        //OSD write video data command
#define OSDCMDENABLE    0x60        //OSD enable command
#define OSDCMDDISABLE   0x40        //OSD disable command
#define OSDCMDRST       0x80        //OSD reset command
#define OSDCMDCFGSCL    0xA0        //OSD settings: scanline effect
#define OSDCMDENAHDD    0xB0        //OSD enable HDD command
#define OSDCMDCFGFLP    0xC0        //OSD settings: floppy config
#define OSDCMDCFGCPU    0xD0        //OSD settings: cpu config
#define OSDCMDCFGFLT    0xE0        //OSD settings: filter
#define OSDCMDCFGMEM    0xF0        //OSD settings: memory config

#define REPEATDELAY		50			// repeat delay in 10ms units
#define REPEATRATE		2			// repeat rate in 10ms units


/*constants*/
#define KEY_MENU  0x88
#define KEY_ESC   0x45
#define KEY_ENTER 0x44
#define KEY_SPACE 0x40
#define KEY_UP    0x4C
#define KEY_DOWN  0x4D
#define KEY_LEFT  0x4F
#define KEY_RIGHT 0x4E
#define KEY_F1    0x50
#define KEY_F2    0x51
#define KEY_F3    0x52
#define KEY_F4    0x53
#define KEY_F5    0x54
#define KEY_F6    0x55
#define KEY_F7    0x56
#define KEY_F8    0x57
#define KEY_F9    0x58
#define KEY_F10   0x59

// Chipset Config bits 
#define CONFIG_CPU_28MHZ	0x01	// PYQ090405 - CPU 7.09MHz/28.36MHz
#define CONFIG_CPU_TURBO	0x01	// PYQ090911 - CPU Normal/Turbo
#define CONFIG_BLITTER_FAST	0x02	// PYQ090405 - Blitter Normal/Fast
#define CONFIG_AGNUS_NTSC	0x04	// PYQ090405 & PYQ090911 - Agnus PAL/NTSC
#define CONFIG_AGNUS_ECS	0x08	// PYQ090911 - Agnus: OCS/ECS

// Floppy speed
#define	CONFIG_FLOPPY1X		0x00	// Normal floppy speed
#define	CONFIG_FLOPPY2X 	0x01	// Double floppy speed

// OSD Reset type
#define RESET_NORMAL		0x00	// Reset Amiga
#define RESET_BOOTLOADER	0x01	// Reset To Boot Loader

/*functions*/
void OsdWrite(unsigned char n,const unsigned char *s, char invert);
void OsdClear(void);
void OsdEnable(void);
void OsdDisable(void);
void OsdReset(unsigned char boot);
void ConfigFilter(unsigned char lores, unsigned char hires);
void ConfigMemory(unsigned char memory);
void ConfigChipset(unsigned char chipset);
void ConfigFloppy(unsigned char drives, unsigned char speed);
void ConfigScanline(unsigned char scanline);
void ConfigIDE(unsigned char gayle, unsigned char master, unsigned char slave);
unsigned char OsdGetCtrl(void);
unsigned char GetASCIIKey(unsigned char keycode);

#endif
