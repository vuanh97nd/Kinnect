package app.kinnect.live;

/** Content signatures are authoritative; Android document-provider MIME labels are hints. */
public final class MediaType {
  private MediaType() {}
  private static boolean at(byte[] b,int offset,String value){
    if(b==null || offset+value.length()>b.length)return false;
    for(int i=0;i<value.length();i++)if((b[offset+i]&255)!=value.charAt(i))return false;
    return true;
  }
  public static String sniff(byte[] b){
    if(b==null)return null;
    if(b.length>=8 && (b[0]&255)==137 && at(b,1,"PNG\r\n\032\n"))return "image/png";
    if(b.length>=3 && (b[0]&255)==255 && (b[1]&255)==216 && (b[2]&255)==255)return "image/jpeg";
    if(at(b,0,"RIFF")&&at(b,8,"WEBP"))return "image/webp";
    if(b.length>=16 && at(b,4,"ftyp")){
      for(String brand:new String[]{"heic","heix","hevc","hevx","mif1","msf1","avif","avis"})if(at(b,8,brand))return "image/heif";
      return "video/mp4";
    }
    return null;
  }
  public static boolean quickTime(byte[] b){return at(b,4,"ftyp")&&at(b,8,"qt  ");}
}
