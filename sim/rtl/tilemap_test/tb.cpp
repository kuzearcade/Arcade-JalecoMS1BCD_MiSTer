// ms1_tilemap alone, against tools/ms1_video_model.py's layer_indexed().
// Prints "x y pen color opaque" for the visible window so the Python side can
// diff it without any compositing, priority or palette in the way.
#include "Vms1_tilemap.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>
static std::vector<uint8_t> slurp(const std::string&p){FILE*f=fopen(p.c_str(),"rb");
 if(!f){fprintf(stderr,"open %s\n",p.c_str());exit(1);} fseek(f,0,SEEK_END);long n=ftell(f);
 fseek(f,0,SEEK_SET);std::vector<uint8_t>v(n); if(n&&fread(v.data(),1,n,f)!=(size_t)n)exit(1);
 fclose(f);return v;}
int main(int argc,char**argv){
  Verilated::commandArgs(argc,argv);
  if(argc<7){fprintf(stderr,"usage: %s vram gfx sx sy ctrl y0\n",argv[0]);return 1;}
  auto vram=slurp(argv[1]); auto gfx=slurp(argv[2]);
  int sx=strtol(argv[3],0,0), sy=strtol(argv[4],0,0), ctrl=strtol(argv[5],0,0), y0=atoi(argv[6]);
  Vms1_tilemap*t=new Vms1_tilemap;
  t->ce=1; t->scroll_x=sx; t->scroll_y=sy; t->ctrl=ctrl; t->clk=0;
  auto serve=[&](){
    size_t b=(size_t)t->vram_addr*2;
    t->vram_data=(b+1<vram.size())?(vram[b]|(vram[b+1]<<8)):0;
    t->rom_data=(t->rom_addr<gfx.size())?gfx[t->rom_addr]:0;
    t->eval();
  };
  auto tick=[&](){t->clk=0;t->eval();serve();t->clk=1;t->eval();serve();};
  const int W=256,H=224,LAT=2;
  std::vector<int> pen(W*H,0),col(W*H,0),opq(W*H,0);
  std::vector<unsigned> va(W*H,0),ra(W*H,0);
  long total=(long)W*H+LAT;
  for(long i=0;i<total;i++){
    if(i<(long)W*H){ t->sx=i%W; t->sy=(i/W)+y0; }
    tick();
    long o=i-LAT;
    if(o>=0&&o<(long)W*H){ pen[o]=t->pen; col[o]=t->color; opq[o]=t->opaque; }
    long ov=i-1; if(ov>=0&&ov<(long)W*H) va[ov]=t->vram_addr;
    long orr=i-2; if(orr>=0&&orr<(long)W*H) ra[orr]=t->rom_addr;
  }
  for(int i=0;i<W*H;i++) printf("%d %d %d %u %u\n",pen[i],col[i],opq[i],va[i],ra[i]);
  delete t; return 0;
}
