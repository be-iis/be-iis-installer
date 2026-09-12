// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
#include <fcntl.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PAGE 16
#define EXPECTED_ID 0x012b9043U

static int xfer(int fd, uint8_t *tx, uint8_t *rx, size_t n) {
 struct spi_ioc_transfer t={.tx_buf=(unsigned long)tx,.rx_buf=(unsigned long)rx,.len=n,.speed_hz=1000000,.bits_per_word=8};
 return ioctl(fd,SPI_IOC_MESSAGE(1),&t)==(int)n ? 0 : -1;
}
static uint32_t cmd_read(int fd,uint8_t op) {
 uint8_t tx[8]={op,0,0,0,0,0,0,0},rx[8]={0};
 if(xfer(fd,tx,rx,8)) { perror("SPI"); exit(1); }
 return ((uint32_t)rx[4]<<24)|((uint32_t)rx[5]<<16)|((uint32_t)rx[6]<<8)|rx[7];
}
static void cmd(int fd,uint8_t op,uint8_t a,uint8_t b,uint8_t c) {
 uint8_t tx[4]={op,a,b,c},rx[4]={0}; if(xfer(fd,tx,rx,4)){perror("SPI");exit(1);}
}
static uint32_t status(int fd) { return cmd_read(fd,0x3c); }
static void wait_ready(int fd) {
 for(int i=0;i<2000;i++){ uint32_t s=status(fd); if(!(s&(1U<<12))){if(s&(1U<<13)){fprintf(stderr,"MachXO2 FAIL: %08x\n",s);exit(1);}return;} usleep(5000); }
 fprintf(stderr,"MachXO2 busy timeout\n"); exit(1);
}
static uint8_t *load_jed(const char *name, size_t *len) {
 FILE *f=fopen(name,"r"); char *s=NULL,*p,*e; long qf=-1; size_t n=0; uint8_t *out;
 if(!f){perror(name);exit(1);} fseek(f,0,SEEK_END); n=(size_t)ftell(f); rewind(f);
 s=calloc(n+1,1); if(!s || fread(s,1,n,f)!=n){perror("read JED");exit(1);} fclose(f);
 p=strstr(s,"QF"); if(!p || sscanf(p+2,"%ld",&qf)!=1 || qf<=0){fprintf(stderr,"invalid JEDEC QF record\n");exit(1);}
 if(qf%128){fprintf(stderr,"JEDEC fuse map is not page aligned\n");exit(1);} *len=(size_t)qf/8;
 out=calloc(*len,1); if(!out){perror("calloc");exit(1);}
 for(p=s;(p=strchr(p,'L'));p++) { long a; char *d=p+1; if(sscanf(d,"%ld",&a)!=1 || a<0) continue; while(*d>='0'&&*d<='9') d++; while(*d==' '||*d=='\t'||*d=='\r'||*d=='\n') d++; for(e=d;*e=='0'||*e=='1';e++,a++) { if((size_t)a>=*len*8){fprintf(stderr,"JEDEC L record out of range\n");exit(1);} if(*e=='1') out[a/8]|=(uint8_t)(1u<<(a%8)); } }
 free(s); return out;
}
int main(int ac,char **av) {
 if(ac!=4 || strcmp(av[1],"--program")) { fprintf(stderr,"usage: %s --program /dev/spidev0.0 firmware.jed\n",av[0]); return 2; }
 size_t image_len; uint8_t *image=load_jed(av[3],&image_len); int spi=open(av[2],O_RDWR); if(spi<0){perror("open SPI");return 1;}
 uint8_t mode=SPI_MODE_0,bits=8; uint32_t speed=1000000;
 if(ioctl(spi,SPI_IOC_WR_MODE,&mode)||ioctl(spi,SPI_IOC_WR_BITS_PER_WORD,&bits)||ioctl(spi,SPI_IOC_WR_MAX_SPEED_HZ,&speed)){perror("SPI setup");return 1;}
 uint32_t id=cmd_read(spi,0xe0); printf("MachXO2 IDCODE: 0x%08x\n",id);
 if(id!=EXPECTED_ID){fprintf(stderr,"unexpected device ID\n");return 1;}
 printf("Status: 0x%08x\n",status(spi));
 cmd(spi,0xc6,0x08,0x00,0x00); wait_ready(spi);
 cmd(spi,0x0e,0x04,0x00,0x00); wait_ready(spi);
 cmd(spi,0x46,0,0,0);
 uint8_t tx[4+PAGE],rx[4+PAGE]; unsigned long pages=0;
 for(size_t off=0;off<image_len;off+=PAGE){ tx[0]=0x70;tx[1]=0;tx[2]=0;tx[3]=1;memcpy(tx+4,image+off,PAGE);memset(rx,0,sizeof(rx));if(xfer(spi,tx,rx,sizeof(tx))){perror("program");return 1;} pages++; }
 free(image); wait_ready(spi); cmd(spi,0x5e,0,0,0); wait_ready(spi); cmd(spi,0x79,0,0,0); usleep(500000); wait_ready(spi);
 printf("Programmed %lu pages; status: 0x%08x\n",pages,status(spi)); return 0;
}
