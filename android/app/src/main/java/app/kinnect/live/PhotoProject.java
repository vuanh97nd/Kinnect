package app.kinnect.live;

import android.graphics.Color;
import java.util.*;
import org.json.*;

/** Non-destructive photo document. History copies metadata, never full-size bitmaps. */
final class PhotoProject {
  static final int MAX_LAYERS=12, MAX_STROKES=300, MAX_POINTS=24000;
  static final class Stroke {
    boolean restore; float size=.04f,softness=.4f; final ArrayList<Float> points=new ArrayList<>();
    JSONObject json() throws JSONException {JSONArray p=new JSONArray();for(float v:points)p.put(Math.round(v*10000f)/10000d);return new JSONObject().put("restore",restore).put("size",size).put("softness",softness).put("points",p);}
    static Stroke from(JSONObject o){Stroke s=new Stroke();s.restore=o.optBoolean("restore");s.size=(float)o.optDouble("size",.04);s.softness=(float)o.optDouble("softness",.4);JSONArray p=o.optJSONArray("points");for(int i=0;p!=null&&i<Math.min(p.length(),2000);i++)s.points.add((float)p.optDouble(i,0));return s;}
  }
  static final class Layer {
    String id=UUID.randomUUID().toString(),kind="image",name="",source="",text="Kinnect";
    float x=.5f,y=.5f,scale=1,angle=0,opacity=1,textSize=.09f;int color=Color.WHITE;
    boolean visible=true,locked=false;final ArrayList<Stroke> strokes=new ArrayList<>();
    JSONObject json() throws JSONException {JSONArray a=new JSONArray();for(Stroke s:strokes)a.put(s.json());return new JSONObject().put("id",id).put("kind",kind).put("name",name).put("source",source).put("text",text).put("x",x).put("y",y).put("scale",scale).put("angle",angle).put("opacity",opacity).put("textSize",textSize).put("color",color).put("visible",visible).put("locked",locked).put("strokes",a);}
    static Layer from(JSONObject o){Layer l=new Layer();l.id=o.optString("id",l.id);l.kind=o.optString("kind","image");l.name=o.optString("name");l.source=o.optString("source");l.text=o.optString("text","Kinnect");l.x=(float)o.optDouble("x",.5);l.y=(float)o.optDouble("y",.5);l.scale=(float)o.optDouble("scale",1);l.angle=(float)o.optDouble("angle",0);l.opacity=(float)o.optDouble("opacity",1);l.textSize=(float)o.optDouble("textSize",.09);l.color=o.optInt("color",Color.WHITE);l.visible=o.optBoolean("visible",true);l.locked=o.optBoolean("locked");JSONArray a=o.optJSONArray("strokes");for(int i=0;a!=null&&i<Math.min(a.length(),MAX_STROKES);i++)l.strokes.add(Stroke.from(a.optJSONObject(i)));return l;}
  }
  int width=1,height=1,rotation=0,background=Color.TRANSPARENT;
  float left=0,top=0,right=1,bottom=1,brightness=0,contrast=0,saturation=0,warmth=0,curves=0,smooth=0;
  final float[] hue=new float[6],hslSaturation=new float[6],lightness=new float[6];
  boolean flip=false;String selected="",originalSource="";final ArrayList<Layer> layers=new ArrayList<>();
  int pointCount(){int n=0;for(Layer l:layers)for(Stroke s:l.strokes)n+=s.points.size();return n;}
  Layer selected(){for(Layer l:layers)if(l.id.equals(selected))return l;return layers.isEmpty()?null:layers.get(0);}
  String encode(){try{JSONArray h=new JSONArray(),s=new JSONArray(),v=new JSONArray();for(int i=0;i<6;i++){h.put(hue[i]);s.put(hslSaturation[i]);v.put(lightness[i]);}JSONArray a=new JSONArray();for(Layer l:layers)a.put(l.json());return new JSONObject().put("schema",1).put("hue",h).put("hslSaturation",s).put("lightness",v).put("originalSource",originalSource).put("width",width).put("height",height).put("rotation",rotation).put("background",background).put("left",left).put("top",top).put("right",right).put("bottom",bottom).put("brightness",brightness).put("contrast",contrast).put("saturation",saturation).put("warmth",warmth).put("curves",curves).put("smooth",smooth).put("flip",flip).put("selected",selected).put("layers",a).toString();}catch(JSONException e){throw new IllegalStateException(e);}}
  static PhotoProject decode(String value)throws JSONException {JSONObject o=new JSONObject(value);if(o.optInt("schema")!=1)throw new JSONException("Unsupported photo project");PhotoProject p=new PhotoProject();p.width=o.getInt("width");p.height=o.getInt("height");if(p.width<1||p.height<1||p.width>50000||p.height>50000)throw new JSONException("Invalid dimensions");p.rotation=o.optInt("rotation");p.background=o.optInt("background");p.left=(float)o.optDouble("left",0);p.top=(float)o.optDouble("top",0);p.right=(float)o.optDouble("right",1);p.bottom=(float)o.optDouble("bottom",1);if(p.left<0||p.top<0||p.right>1||p.bottom>1||p.right-p.left<.01||p.bottom-p.top<.01)throw new JSONException("Invalid crop");p.brightness=(float)o.optDouble("brightness",0);p.contrast=(float)o.optDouble("contrast",0);p.saturation=(float)o.optDouble("saturation",0);p.warmth=(float)o.optDouble("warmth",0);p.curves=(float)o.optDouble("curves",0);p.smooth=(float)o.optDouble("smooth",0);p.flip=o.optBoolean("flip");p.selected=o.optString("selected");p.originalSource=o.optString("originalSource");for(int i=0;i<6;i++){p.hue[i]=(float)(o.optJSONArray("hue")==null?0:o.optJSONArray("hue").optDouble(i,0));p.hslSaturation[i]=(float)(o.optJSONArray("hslSaturation")==null?0:o.optJSONArray("hslSaturation").optDouble(i,0));p.lightness[i]=(float)(o.optJSONArray("lightness")==null?0:o.optJSONArray("lightness").optDouble(i,0));}JSONArray a=o.getJSONArray("layers");if(a.length()<1||a.length()>MAX_LAYERS)throw new JSONException("Too many layers");for(int i=0;i<a.length();i++)p.layers.add(Layer.from(a.getJSONObject(i)));if(p.pointCount()>MAX_POINTS)throw new JSONException("Too many mask points");return p;}
  PhotoProject copy(){try{return decode(encode());}catch(JSONException e){throw new IllegalStateException(e);}}
}
