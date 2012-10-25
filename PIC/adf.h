#ifndef ADF_H_INCLUDED
#define ADF_H_INCLUDED

// Enable/Disable ADF Debuging
//#define DEBUG_ADF

// Maximum avaliable floppy drives
#define		MAX_FLOPPY_DRIVES		0x04

/*floppy status*/
#define		DSK_INSERTED		0x01	/*disk is inserted*/
#define		DSK_WRITABLE		0x10	/*disk is writable*/

// Type for storing active floppy-es
struct adfTYPE
{
	unsigned char	status;			// status of floppy
	unsigned long	firstCluster;	// First cluster of floppy file
	unsigned long	clusteroffset;	// cluster offset to handle tricky loaders
	unsigned char	sectoroffset;	// sector offset to handle tricky loaders
	unsigned char	track;			// current track
	unsigned char	trackprev;		// previous track
	unsigned char	name[12];		// floppy name
};

// Extern structs needed for other modules
extern struct adfTYPE *pdfx;					// drive select pointer
extern struct adfTYPE df[MAX_FLOPPY_DRIVES];	// drives information structure

// Functions
void HandleFDD(unsigned char c1, unsigned char c2);
void UpdateDriveStatus(void);
void InsertFloppy(struct adfTYPE *drive);
void CheckTrack(struct adfTYPE *drive);
void ReadTrack(struct adfTYPE *drive);
void WriteTrack(struct adfTYPE *drive);
void PrepareGlobalFileHandle(struct adfTYPE *drive);
unsigned char FindSync(struct adfTYPE *drive);
unsigned char GetHeader(unsigned char *pTrack, unsigned char *pSector);
unsigned char GetData(void);
unsigned short SectorToFpga(unsigned char sector, unsigned char track, unsigned char dsksynch, unsigned char dsksyncl);
void SectorGapToFpga(void);
void SectorHeaderToFpga(unsigned char n, unsigned char dsksynch, unsigned char dsksyncl);

#endif /*ADF_H_INCLUDED*/
