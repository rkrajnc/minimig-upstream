#ifndef _ATA_H_INCLUDED
#define _ATA_H_INCLUDED

unsigned char SDCARD_Init(void);
unsigned char AtaReadSector(unsigned long lba, unsigned char *ReadData);
unsigned char AtaWriteSector(unsigned long lba, unsigned char *WriteData);

#endif
