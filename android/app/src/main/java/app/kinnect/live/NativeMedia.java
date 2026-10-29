package app.kinnect.live;

import android.content.Context;
import android.net.Uri;
import android.media.*;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.*;
import java.nio.ByteBuffer;
import java.util.*;

/** Read selected documents without trusting MIME labels or requiring platform duration metadata. */
final class NativeMedia {
  static final class Prepared {
    final byte[] bytes; final String type;
    Prepared(byte[] b,String t){bytes=b;type=t;}
    boolean video(){return type.startsWith("video/");}
    String dataUrl(){return "data:"+type+";base64,"+android.util.Base64.encodeToString(bytes,android.util.Base64.NO_WRAP);}
  }
  private NativeMedia() {}
  static Prepared read(Context context,Uri uri,boolean requireVideo) throws Exception {
    if(uri==null)throw new IOException("Chưa chọn tệp.");
    InputStream opened=context.getContentResolver().openInputStream(uri);
    if(opened==null)throw new IOException("Không mở được tệp đã chọn.");
    File original=null;
    try(BufferedInputStream input=new BufferedInputStream(opened)){
      input.mark(64);byte[] header=new byte[64];int size=0;
      while(size<header.length){int n=input.read(header,size,header.length-size);if(n<0)break;if(n==0){int b=input.read();if(b<0)break;header[size++]=(byte)b;}else size+=n;}
      if(size==0)throw new IOException("Tệp đã chọn rỗng.");
      input.reset();header=Arrays.copyOf(header,size);String type=MediaType.sniff(header);
      if(type!=null && type.startsWith("image/")){
        if(requireVideo)throw new IOException("Tệp đã chọn là ảnh. Hãy chọn video.");
        if(!type.equals("image/heif"))return new Prepared(NativeApi.readAll(input),type);
        Bitmap image=BitmapFactory.decodeStream(input);
        if(image==null)throw new IOException("Thiết bị chưa đọc được ảnh HEIF/AVIF này.");
        try(ByteArrayOutputStream out=new ByteArrayOutputStream()){
          if(!image.compress(Bitmap.CompressFormat.JPEG,95,out))throw new IOException("Không chuẩn bị được ảnh.");
          return new Prepared(out.toByteArray(),"image/jpeg");
        }finally{image.recycle();}
      }
      // Read a standard MP4 exactly once, unchanged, as the web file picker does.
      if("video/mp4".equals(type) && !MediaType.quickTime(header))return new Prepared(NativeApi.readAll(input),"video/mp4");
      // A local, seekable copy also supports cloud providers and one-shot URI grants.
      original=File.createTempFile("kinnect-source-",".media",context.getCacheDir());
      try(OutputStream out=new FileOutputStream(original)){byte[] block=new byte[65536];int n;while((n=input.read(block))!=-1)out.write(block,0,n);}
    }catch(Exception e){if(original!=null)original.delete();throw e;}
    File normalized=null;
    try{
      normalized=File.createTempFile("kinnect-upload-",".mp4",context.getCacheDir());
      remux(context,Uri.fromFile(original),normalized);
      return new Prepared(NativeApi.readAll(new FileInputStream(normalized)),"video/mp4");
    }catch(Exception e){throw new IOException("Không chuyển được định dạng/codec của tệp này sang MP4. "+(e.getMessage()==null?"":e.getMessage()),e);}
    finally{if(original!=null)original.delete();if(normalized!=null)normalized.delete();}
  }
  private static void remux(Context context,Uri uri,File output) throws Exception {
    MediaExtractor input=new MediaExtractor();MediaMuxer mux=null;boolean started=false;
    try{
      input.setDataSource(context,uri,null);
      mux=new MediaMuxer(output.getAbsolutePath(),MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
      Map<Integer,Integer> tracks=new HashMap<>();boolean video=false;int bufferSize=1024*1024;
      for(int i=0;i<input.getTrackCount();i++){
        MediaFormat format=input.getTrackFormat(i);String mime=format.getString(MediaFormat.KEY_MIME);
        if(mime==null || !(mime.startsWith("video/")||mime.startsWith("audio/")))continue;
        video|=mime.startsWith("video/");tracks.put(i,mux.addTrack(format));input.selectTrack(i);
        if(format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))bufferSize=Math.max(bufferSize,format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE));
      }
      if(!video)throw new IOException("Tệp không có luồng hình ảnh video.");
      MediaMetadataRetriever orientation=new MediaMetadataRetriever();
      try{orientation.setDataSource(context,uri);String r=orientation.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);if(r!=null)mux.setOrientationHint(Integer.parseInt(r));}catch(Exception ignored){}finally{try{orientation.release();}catch(Exception ignored){}}
      mux.start();started=true;ByteBuffer buffer=ByteBuffer.allocateDirect(bufferSize);MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();int videoSamples=0;
      while(input.getSampleTrackIndex()>=0){
        int track=input.getSampleTrackIndex();
        if(android.os.Build.VERSION.SDK_INT>=28){long n=input.getSampleSize();if(n>Integer.MAX_VALUE)throw new IOException("Khung hình quá lớn cho bộ nhớ thiết bị.");if(n>buffer.capacity())buffer=ByteBuffer.allocateDirect((int)n);}
        buffer.clear();int count;
        while(true){try{count=input.readSampleData(buffer,0);break;}catch(IllegalArgumentException e){if(buffer.capacity()>Integer.MAX_VALUE/2)throw e;buffer=ByteBuffer.allocateDirect(buffer.capacity()*2);}}
        if(count<0)break;
        if((input.getSampleFlags()&MediaExtractor.SAMPLE_FLAG_ENCRYPTED)!=0)throw new IOException("Video được mã hóa/bảo vệ.");
        info.set(0,count,input.getSampleTime(),(input.getSampleFlags()&MediaExtractor.SAMPLE_FLAG_SYNC)!=0?MediaCodec.BUFFER_FLAG_KEY_FRAME:0);
        mux.writeSampleData(tracks.get(track),buffer,info);
        String mime=input.getTrackFormat(track).getString(MediaFormat.KEY_MIME);if(mime!=null&&mime.startsWith("video/"))videoSamples++;
        input.advance();
      }
      if(videoSamples==0)throw new IOException("Không đọc được khung hình video.");
      mux.stop();started=false;
    }finally{input.release();if(mux!=null){try{if(started)mux.stop();}catch(Exception ignored){}mux.release();}}
  }
}
