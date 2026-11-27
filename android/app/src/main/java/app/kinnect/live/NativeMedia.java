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
  static final int MAX_VIDEO_BYTES = 42 * 1024 * 1024;
  private static final int MAX_OTHER_BYTES = 20 * 1024 * 1024;
  private NativeMedia() {}
  static Prepared read(Context context,Uri uri,boolean requireVideo) throws Exception {
    if(uri==null)throw new IOException(I18n.t("Chưa chọn tệp."));
    long declaredSize=-1;
    InputStream opened=null;
    try{
      android.content.res.AssetFileDescriptor afd=context.getContentResolver().openAssetFileDescriptor(uri,"r");
      if(afd!=null){
        declaredSize=afd.getLength();
        if(declaredSize>MAX_VIDEO_BYTES){
          try{afd.close();}catch(Exception ignored){}
          throw new IOException(I18n.t("Video hoặc tệp quá lớn (tối đa 42 MB cho video, 20 MB cho tệp khác)."));
        }
        try{opened=afd.createInputStream();}
        catch(IOException e){try{afd.close();}catch(Exception ignored){} throw e;}
      }
    }catch(SecurityException e){
      throw e;
    }catch(IOException e){
      if(declaredSize>MAX_VIDEO_BYTES)throw e;
    }catch(RuntimeException|LinkageError ignored){}
    if(opened==null)opened=context.getContentResolver().openInputStream(uri);
    if(opened==null)throw new IOException(I18n.t("Không mở được tệp đã chọn."));
    File original=null;
    try(BufferedInputStream input=new BufferedInputStream(opened)){
      input.mark(64);byte[] header=new byte[64];int size=0;
      while(size<header.length){int n=input.read(header,size,header.length-size);if(n<0)break;if(n==0){int b=input.read();if(b<0)break;header[size++]=(byte)b;}else size+=n;}
      if(size==0)throw new IOException(I18n.t("Tệp đã chọn rỗng."));
      input.reset();header=Arrays.copyOf(header,size);String type=MediaType.sniff(header);
      if(type!=null && type.startsWith("image/")){
        if(requireVideo)throw new IOException(I18n.t("Tệp đã chọn là ảnh. Hãy chọn video."));
        if(declaredSize>MAX_OTHER_BYTES)throw new IOException(I18n.t("Ảnh quá lớn (tối đa 20 MB)."));
        if(!type.equals("image/heif"))return new Prepared(NativeApi.read(input,MAX_OTHER_BYTES),type);
        byte[] rawHeif=NativeApi.read(input,MAX_OTHER_BYTES);
        BitmapFactory.Options bounds=new BitmapFactory.Options();
        bounds.inJustDecodeBounds=true;
        BitmapFactory.decodeByteArray(rawHeif,0,rawHeif.length,bounds);
        BitmapFactory.Options decodeOpts=new BitmapFactory.Options();
        if(bounds.outWidth>0&&bounds.outHeight>0){
          decodeOpts.inSampleSize=MediaImageLoader.calculateInSampleSize(bounds.outWidth,bounds.outHeight,2048);
        }
        Bitmap image=BitmapFactory.decodeByteArray(rawHeif,0,rawHeif.length,decodeOpts);
        if(image==null)throw new IOException(I18n.t("Thiết bị chưa đọc được ảnh HEIF/AVIF này."));
        try{
          android.graphics.Matrix m=new android.graphics.Matrix();
          try(ByteArrayInputStream exifIn=new ByteArrayInputStream(rawHeif)){
            int orientation=new ExifInterface(exifIn).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
            switch(orientation){
              case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:m.postScale(-1,1);break;
              case ExifInterface.ORIENTATION_ROTATE_180:m.postRotate(180);break;
              case ExifInterface.ORIENTATION_FLIP_VERTICAL:m.postScale(1,-1);break;
              case ExifInterface.ORIENTATION_TRANSPOSE:m.postRotate(90);m.postScale(-1,1);break;
              case ExifInterface.ORIENTATION_ROTATE_90:m.postRotate(90);break;
              case ExifInterface.ORIENTATION_TRANSVERSE:m.postRotate(270);m.postScale(-1,1);break;
              case ExifInterface.ORIENTATION_ROTATE_270:m.postRotate(270);break;
              default:break;
            }
          }catch(Exception ignored){}
          if(!m.isIdentity()){
            Bitmap rotated=Bitmap.createBitmap(image,0,0,image.getWidth(),image.getHeight(),m,true);
            if(rotated!=image){image.recycle();image=rotated;}
          }
          try(ByteArrayOutputStream out=new ByteArrayOutputStream()){
            if(!image.compress(Bitmap.CompressFormat.JPEG,92,out))throw new IOException(I18n.t("Không chuẩn bị được ảnh."));
            return new Prepared(out.toByteArray(),"image/jpeg");
          }
        }finally{if(image!=null&&!image.isRecycled())image.recycle();}
      }
      // Read a standard MP4 exactly once, unchanged, bounded to avoid OOM.
      if("video/mp4".equals(type) && !MediaType.quickTime(header)){
        if(declaredSize>MAX_VIDEO_BYTES)throw new IOException(I18n.t("Video quá lớn (tối đa 42 MB)."));
        return new Prepared(NativeApi.read(input,MAX_VIDEO_BYTES),"video/mp4");
      }
      // A local, seekable copy also supports cloud providers and one-shot URI grants.
      original=File.createTempFile("kinnect-source-",".media",context.getCacheDir());
      long copied=0;
      try(OutputStream out=new FileOutputStream(original)){
        byte[] block=new byte[65536];int n;
        while((n=input.read(block))!=-1){
          copied+=n;
          if(copied>MAX_VIDEO_BYTES)throw new IOException(I18n.t("Video quá lớn (tối đa 42 MB)."));
          out.write(block,0,n);
        }
      }
    }catch(Exception e){if(original!=null)original.delete();throw e;}
    File normalized=null;
    try{
      normalized=File.createTempFile("kinnect-upload-",".mp4",context.getCacheDir());
      remux(context,Uri.fromFile(original),normalized);
      if(normalized.length()>MAX_VIDEO_BYTES)throw new IOException(I18n.t("Video quá lớn (tối đa 42 MB)."));
      return new Prepared(NativeApi.read(new FileInputStream(normalized),MAX_VIDEO_BYTES),"video/mp4");
    }catch(Exception e){throw new IOException(I18n.t("Không chuyển được định dạng/codec của tệp này sang MP4. ")+(e.getMessage()==null?"":e.getMessage()),e);}
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
        if(mime==null)continue;
        boolean isVideo=mime.startsWith("video/");
        boolean isMp4Audio="audio/mp4a-latm".equals(mime)||"audio/mp4".equals(mime)||"audio/aac".equals(mime)||"audio/mpeg".equals(mime);
        if(!isVideo&&!isMp4Audio)continue;
        try{
          int dst=mux.addTrack(format);
          video|=isVideo;tracks.put(i,dst);input.selectTrack(i);
          if(format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))bufferSize=Math.max(bufferSize,format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE));
        }catch(IllegalArgumentException unsupported){
          if(isVideo)throw unsupported;
        }
      }
      if(!video)throw new IOException(I18n.t("Tệp không có luồng hình ảnh video."));
      MediaMetadataRetriever orientation=new MediaMetadataRetriever();
      try{orientation.setDataSource(context,uri);String r=orientation.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);if(r!=null)mux.setOrientationHint(Integer.parseInt(r));}catch(Exception ignored){}finally{try{orientation.release();}catch(Exception ignored){}}
      mux.start();started=true;ByteBuffer buffer=ByteBuffer.allocateDirect(bufferSize);MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();int videoSamples=0;
      while(input.getSampleTrackIndex()>=0){
        int track=input.getSampleTrackIndex();
        Integer dstTrack=tracks.get(track);
        if(dstTrack==null){input.advance();continue;}
        if(android.os.Build.VERSION.SDK_INT>=28){long n=input.getSampleSize();if(n>Integer.MAX_VALUE)throw new IOException(I18n.t("Khung hình quá lớn cho bộ nhớ thiết bị."));if(n>buffer.capacity())buffer=ByteBuffer.allocateDirect((int)n);}
        buffer.clear();int count;
        while(true){try{count=input.readSampleData(buffer,0);break;}catch(IllegalArgumentException e){if(buffer.capacity()>Integer.MAX_VALUE/2)throw e;buffer=ByteBuffer.allocateDirect(buffer.capacity()*2);}}
        if(count<0)break;
        if((input.getSampleFlags()&MediaExtractor.SAMPLE_FLAG_ENCRYPTED)!=0)throw new IOException(I18n.t("Video được mã hóa/bảo vệ."));
        long sampleTime=input.getSampleTime();
        if(sampleTime<0){input.advance();continue;}
        info.set(0,count,sampleTime,(input.getSampleFlags()&MediaExtractor.SAMPLE_FLAG_SYNC)!=0?MediaCodec.BUFFER_FLAG_KEY_FRAME:0);
        mux.writeSampleData(dstTrack,buffer,info);
        String mime=input.getTrackFormat(track).getString(MediaFormat.KEY_MIME);if(mime!=null&&mime.startsWith("video/"))videoSamples++;
        input.advance();
      }
      if(videoSamples==0)throw new IOException(I18n.t("Không đọc được khung hình video."));
      mux.stop();started=false;
    }finally{input.release();if(mux!=null){try{if(started)mux.stop();}catch(Exception ignored){}mux.release();}}
  }
}
