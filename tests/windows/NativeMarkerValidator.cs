using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

public static class NativeMarkerValidator {
  private sealed class Component {
    public int pixels,minX=int.MaxValue,minY=int.MaxValue,maxX=-1,maxY=-1;
    public long sumX,sumY;
  }
  private static Component Largest(bool[] mask,int width,int height) {
    var seen=new bool[mask.Length];var best=new Component();var queue=new Queue<int>();
    for(int start=0;start<mask.Length;start++) {
      if(!mask[start]||seen[start])continue;
      var current=new Component();queue.Enqueue(start);seen[start]=true;
      while(queue.Count>0) {
        int at=queue.Dequeue(),x=at%width,y=at/width;current.pixels++;current.sumX+=x;current.sumY+=y;
        current.minX=Math.Min(current.minX,x);current.maxX=Math.Max(current.maxX,x);
        current.minY=Math.Min(current.minY,y);current.maxY=Math.Max(current.maxY,y);
        foreach(int neighbor in new [] {x>0?at-1:-1,x+1<width?at+1:-1,y>0?at-width:-1,y+1<height?at+width:-1}) {
          if(neighbor>=0&&mask[neighbor]&&!seen[neighbor]){seen[neighbor]=true;queue.Enqueue(neighbor);}
        }
      }
      if(current.pixels>best.pixels)best=current;
    }
    return best;
  }
  private static Dictionary<string,object> Region(byte[] raw,int width,int height,double cx,double cy,double rx,double ry) {
    if(rx<2||ry<2||rx>512||ry>512)throw new InvalidOperationException("Marker radius outside validator bounds");
    int left=Math.Max(0,(int)Math.Floor(cx-rx*1.25)),top=Math.Max(0,(int)Math.Floor(cy-ry*1.25));
    int right=Math.Min(width,(int)Math.Ceiling(cx+rx*1.25)),bottom=Math.Min(height,(int)Math.Ceiling(cy+ry*1.25));
    if(right<=left||bottom<=top)throw new InvalidOperationException("Marker region outside frame");
    int w=right-left,h=bottom-top;var mask=new bool[w*h];
    for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
      int at=((y+top)*width+x+left)*4,b=raw[at],g=raw[at+1],r=raw[at+2],a=raw[at+3];
      mask[y*w+x]=a>=32&&r>40&&r>g+30&&r>b+30;
    }
    var component=Largest(mask,w,h);
    double actualX=component.pixels==0?0:left+(double)component.sumX/component.pixels;
    double actualY=component.pixels==0?0:top+(double)component.sumY/component.pixels;
    int minimum=(int)Math.Ceiling(Math.PI*rx*ry*.25);
    bool center=component.pixels>0&&Math.Abs(actualX-cx)<=rx*.25&&Math.Abs(actualY-cy)<=ry*.25;
    bool radius=component.pixels>0&&component.maxX-component.minX+1>=rx*1.2&&
      component.maxY-component.minY+1>=ry*1.2&&component.maxX-component.minX+1<=rx*2.5&&component.maxY-component.minY+1<=ry*2.5;
    return new Dictionary<string,object>{{"verified",component.pixels>=minimum&&center&&radius},
      {"connectedPixels",component.pixels},{"minimumPixels",minimum},{"centerWithinExpected",center},{"radiusWithinExpected",radius},
      {"expectedCenterX",cx},{"expectedCenterY",cy},{"radiusX",rx},{"radiusY",ry},{"actualCenterX",actualX},{"actualCenterY",actualY}};
  }
  private static double Number(Dictionary<string,object> source,string name) {
    double value=Convert.ToDouble(source[name],CultureInfo.InvariantCulture);
    if(double.IsNaN(value)||double.IsInfinity(value))throw new InvalidOperationException("Nonfinite scene value");
    return value;
  }
  private static Dictionary<string,object> Object(Dictionary<string,object> source,string name) {
    return (Dictionary<string,object>)source[name];
  }
  private static Dictionary<string,object> Read(string path) {
    if(new FileInfo(path).Length>65536)throw new InvalidOperationException("Metadata exceeds bound");
    return new JavaScriptSerializer{MaxJsonLength=65536,RecursionLimit=16}.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
  }
  private static string Hash(string path) {
    using(var file=File.OpenRead(path))using(var hash=SHA256.Create())
      return BitConverter.ToString(hash.ComputeHash(file)).Replace("-","").ToLowerInvariant();
  }
  private static void Need(bool value,string message) {if(!value)throw new InvalidOperationException(message);}
  private static object Validate(string metadataPath,string scenePath) {
    var meta=Read(metadataPath);var scene=Read(scenePath);var viewport=Object(scene,"viewport");var target=Object(scene,"target");
    Need((string)meta["className"]=="KelpieScriptPresentation","Only native presentation HWND can certify marker");
    Need(Convert.ToInt32(meta["processId"])==Convert.ToInt32(scene["processId"])&&
      (string)meta["startFileTime"]==(string)scene["startFileTime"]&&(string)meta["windowHandle"]==(string)scene["windowHandle"],
      "Window/process identity mismatch");
    int width=Convert.ToInt32(meta["width"]),height=Convert.ToInt32(meta["height"]);
    Need(width>0&&height>0&&width<=4096&&height<=4096&&(long)width*height<=8388608,"Frame bound");
    string parent=Path.GetDirectoryName(Path.GetFullPath(metadataPath)),rawPath=Path.Combine(parent,"frame.bgra"),pngPath=Path.Combine(parent,"frame.png");
    Need(new FileInfo(rawPath).Length==(long)width*height*4&&new FileInfo(pngPath).Length<=67108864,"File byte bound");
    Need(Hash(rawPath)==(string)Object(meta,"raw")["sha256"]&&Hash(pngPath)==(string)Object(meta,"png")["sha256"],"Capture hash mismatch");
    var raw=File.ReadAllBytes(rawPath);long zero=0,partial=0,opaque=0,nonBlack=0;
    for(int i=0;i<raw.Length;i+=4) {
      if(raw[i+3]==0)zero++;else if(raw[i+3]==255)opaque++;else partial++;
      if(raw[i]+raw[i+1]+raw[i+2]>24)nonBlack++;
    }
    bool alphaPreserved=true;
    using(var bitmap=new Bitmap(pngPath)) {
      Need(bitmap.Width==width&&bitmap.Height==height,"Decoded PNG dimensions mismatch");
      var data=bitmap.LockBits(new Rectangle(0,0,width,height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
      try {
        var row=new byte[width*4];
        for(int y=0;y<height;y++) {
          Marshal.Copy(IntPtr.Add(data.Scan0,y*data.Stride),row,0,row.Length);
          for(int x=0;x<width;x++)if(row[x*4+3]!=raw[(y*width+x)*4+3])alphaPreserved=false;
        }
      } finally {bitmap.UnlockBits(data);}
    }
    double vw=Number(viewport,"width"),vh=Number(viewport,"height"),x=Number(target,"x"),y=Number(target,"y"),radius=Number(scene,"radius");
    Need(vw>0&&vh>0&&vw<=16384&&vh<=16384&&x>=0&&y>=0&&x<vw&&y<vh&&radius>=2&&radius<=100,"Scene geometry bound");
    var region=Region(raw,width,height,x*width/vw,y*height/vh,radius*width/vw,radius*height/vh);
    bool background=(zero>0&&opaque+partial>0)||nonBlack>=(long)width*height*.8;
    bool valid=(bool)region["verified"]&&alphaPreserved&&background;
    region["verified"]=valid;
    return new {className="KelpieScriptPresentation",status=valid?"pixels-captured":"unsupported-native-pixels",
      file=pngPath,sha256=Hash(pngPath),width=width,height=height,markerRegion=region,pngAlphaPreserved=alphaPreserved,
      alphaZero=zero,alphaPartial=partial,alphaOpaque=opaque,backgroundSupported=background,
      method="Independent raw BGRA connected-component and PNG alpha verification"};
  }
  private static void SelfTest() {
    int w=160,h=120;var circle=new byte[w*h*4];
    for(int y=0;y<h;y++)for(int x=0;x<w;x++)if((x-80)*(x-80)+(y-60)*(y-60)<=400) {
      int i=(y*w+x)*4;circle[i+2]=128;circle[i+3]=128;
    }
    Need((bool)Region(circle,w,h,80,60,20,20)["verified"],"Native alpha circle fixture failed");
    Need(!(bool)Region(circle,w,h,40,20,20,20)["verified"],"Wrong marker center accepted");
    var fringe=new byte[w*h*4];
    for(int y=45;y<75;y++)for(int x=50;x<110;x++)if((x+y)%5==0){int i=(y*w+x)*4;fringe[i+2]=255;fringe[i+3]=255;}
    Need(!(bool)Region(fringe,w,h,80,60,20,20)["verified"],"ClearType-like sparse fringes accepted");
    Console.WriteLine("{\"selfTest\":true,\"fixtures\":3}");
  }
  public static int Main(string[] args) {
    try {
      if(args.Length==1&&args[0]=="self-test"){SelfTest();return 0;}
      if(args.Length!=2)throw new InvalidOperationException("Provide capture metadata and trusted numeric scene files");
      Console.WriteLine(new JavaScriptSerializer().Serialize(Validate(args[0],args[1])));return 0;
    }catch(Exception error){Console.Error.WriteLine(error.GetType().Name+": "+error.Message);return 1;}
  }
}
