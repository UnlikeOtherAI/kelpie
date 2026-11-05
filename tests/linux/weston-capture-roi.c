// Private-Weston test helper: one output-capture connection, fixed synthetic ROI.
// Wire signatures follow weston-output-capture v1 (Collabora, MIT).
#define _GNU_SOURCE
#include <wayland-client.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>

static const struct wl_interface source_interface;
static const struct wl_interface *create_types[] = { &wl_output_interface, NULL, &source_interface };
static const struct wl_message factory_requests[] = {{"destroy","",NULL},{"create","oun",create_types}};
static const struct wl_interface factory_interface = {"weston_capture_v1",1,2,factory_requests,0,NULL};
static const struct wl_interface *capture_types[] = { &wl_buffer_interface };
static const struct wl_message source_requests[] = {{"destroy","",NULL},{"capture","o",capture_types}};
static const struct wl_message source_events[] = {{"format","u",NULL},{"size","ii",NULL},{"complete","",NULL},{"retry","",NULL},{"failed","?s",NULL}};
static const struct wl_interface source_interface = {"weston_capture_source_v1",1,2,source_requests,5,source_events};
struct State {struct wl_shm *shm;struct wl_output *output;struct wl_proxy *factory,*source;int width,height;uint32_t format;bool done,failed;};
static void global(void *data,struct wl_registry *registry,uint32_t id,const char *name,uint32_t version) {
 (void)version;struct State *s=data;
 if(!strcmp(name,"wl_shm"))s->shm=wl_registry_bind(registry,id,&wl_shm_interface,1);
 else if(!strcmp(name,"wl_output")&&!s->output)s->output=wl_registry_bind(registry,id,&wl_output_interface,1);
 else if(!strcmp(name,"weston_capture_v1"))s->factory=wl_registry_bind(registry,id,&factory_interface,1);
}
static void removed(void *data,struct wl_registry *registry,uint32_t id){(void)data;(void)registry;(void)id;}
static const struct wl_registry_listener registry_listener={global,removed};
static void format(void *data,struct wl_proxy *source,uint32_t value){(void)source;((struct State*)data)->format=value;}
static void size(void *data,struct wl_proxy *source,int32_t width,int32_t height){(void)source;struct State *s=data;s->width=width;s->height=height;}
static void complete(void *data,struct wl_proxy *source){(void)source;((struct State*)data)->done=true;}
static void retry(void *data,struct wl_proxy *source){(void)source;((struct State*)data)->failed=true;}
static void failed(void *data,struct wl_proxy *source,const char *message){(void)source;(void)message;((struct State*)data)->failed=true;}
static void (*source_listener[])(void)={(void(*)(void))format,(void(*)(void))size,(void(*)(void))complete,(void(*)(void))retry,(void(*)(void))failed};
static uint64_t now_ns(void){struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))exit(2);return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec;}
static void require(bool value,const char *reason){if(!value){fprintf(stderr,"%s\n",reason);exit(1);}}
static void write_all(int fd,const void *data,size_t size){const char *p=data;while(size){ssize_t n=write(fd,p,size);if(n<0&&errno==EINTR)continue;require(n>0,"WRITE_FAILED");p+=n;size-=n;}}
int main(int argc,char **argv) {
 require(argc==2,"ARGUMENTS");const char *runtime=getenv("XDG_RUNTIME_DIR"),*socket=getenv("WAYLAND_DISPLAY");
 require(getenv("KELPIE_ISOLATED_WAYLAND")&&!strcmp(getenv("KELPIE_ISOLATED_WAYLAND"),"1"),"ISOLATION_REQUIRED");
 require(runtime&&!strncmp(runtime,"/tmp/kelpie-wayland-",20)&&socket&&!strncmp(socket,"kelpie-",7)&&!strchr(socket,'/'),"PRIVATE_SOCKET_REQUIRED");
 struct stat st;require(!lstat(runtime,&st)&&S_ISDIR(st.st_mode)&&st.st_uid==getuid()&&(st.st_mode&0777)==0700,"PRIVATE_RUNTIME_INVALID");
 char socketpath[512];require(snprintf(socketpath,sizeof socketpath,"%s/%s",runtime,socket)<(int)sizeof socketpath,"SOCKET_PATH");
 require(!lstat(socketpath,&st)&&S_ISSOCK(st.st_mode)&&st.st_uid==getuid(),"PRIVATE_SOCKET_INVALID");
 int out=open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);require(out>=0&&!fstat(out,&st)&&st.st_uid==getuid()&&(st.st_mode&0777)==0700,"OUTPUT_INVALID");
 struct State s={0};struct wl_display *display=wl_display_connect(NULL);require(display,"CONNECT_FAILED");
 struct wl_registry *registry=wl_display_get_registry(display);wl_registry_add_listener(registry,&registry_listener,&s);
 require(wl_display_roundtrip(display)>=0&&s.shm&&s.output&&s.factory,"PROTOCOL_UNAVAILABLE");
 s.source=wl_proxy_marshal_flags(s.factory,1,&source_interface,1,0,s.output,1,NULL);
 require(s.source&&!wl_proxy_add_listener(s.source,source_listener,&s),"SOURCE_FAILED");
 require(wl_display_roundtrip(display)>=0&&s.width==1280&&s.height==900,"OUTPUT_GEOMETRY");
 uint32_t shm_format;if(s.format==0x34325258)shm_format=WL_SHM_FORMAT_XRGB8888;else if(s.format==0x34325241)shm_format=WL_SHM_FORMAT_ARGB8888;else {fprintf(stderr,"UNSUPPORTED_FORMAT\n");return 1;}
 size_t total=(size_t)s.width*s.height*4;int fd=memfd_create("kelpie-private-capture",MFD_CLOEXEC);require(fd>=0&&!ftruncate(fd,total),"SHM_FAILED");
 uint8_t *memory=mmap(NULL,total,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);require(memory!=MAP_FAILED,"MMAP_FAILED");
 struct wl_shm_pool *pool=wl_shm_create_pool(s.shm,fd,total);struct wl_buffer *buffer=wl_shm_pool_create_buffer(pool,0,s.width,s.height,s.width*4,shm_format);
 require(buffer,"BUFFER_FAILED");int manifest=openat(out,"frames.jsonl",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);require(manifest>=0,"MANIFEST_FAILED");
 uint64_t origin=now_ns();int frames=0;
 while(frames<160 && now_ns()-origin<4000000000ull){
  s.done=false;s.failed=false;uint64_t begin=now_ns();wl_proxy_marshal_flags(s.source,1,NULL,1,0,buffer);
  while(!s.done&&!s.failed)require(wl_display_dispatch(display)>=0,"CAPTURE_DISPATCH_FAILED");
  uint64_t end=now_ns();require(!s.failed,"CAPTURE_REFUSED");
  char name[32];snprintf(name,sizeof name,"frame-%03d.bgra",frames);int file=openat(out,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);require(file>=0,"FRAME_CREATE_FAILED");
  for(int y=0;y<320;y++)write_all(file,memory+(size_t)y*s.width*4,256*4);
  require(!close(file),"FRAME_CLOSE_FAILED");char line[192];int len=snprintf(line,sizeof line,"{\"index\":%d,\"startNs\":%llu,\"endNs\":%llu}\n",frames,(unsigned long long)begin,(unsigned long long)end);
  write_all(manifest,line,len);frames++;usleep(12000);
 }
 require(!close(manifest),"MANIFEST_CLOSE_FAILED");wl_buffer_destroy(buffer);wl_shm_pool_destroy(pool);munmap(memory,total);close(fd);
 wl_proxy_marshal_flags(s.source,0,NULL,1,WL_MARSHAL_FLAG_DESTROY);wl_proxy_marshal_flags(s.factory,0,NULL,1,WL_MARSHAL_FLAG_DESTROY);
 wl_output_destroy(s.output);wl_shm_destroy(s.shm);wl_registry_destroy(registry);wl_display_disconnect(display);close(out);
 printf("{\"frames\":%d,\"width\":256,\"height\":320,\"originNs\":%llu}\n",frames,(unsigned long long)origin);return 0;
}
