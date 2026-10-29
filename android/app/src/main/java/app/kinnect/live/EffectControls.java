package app.kinnect.live;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;

/** Compact shared effect controls for the media editor and Live. */
final class EffectControls {
  interface Target {
    String filter();String sticker();boolean beauty();float value(String key);
    void filter(String id);void sticker(String id);void value(String key,float value);void look(String id);
    String[][] filters();default void beginEdit(){}
  }
  static Target forEditor(final FxEngine fx){return new Target(){
    public String filter(){return fx.filter;}public String sticker(){return fx.sticker;}public boolean beauty(){return fx.beautyOn;}public float value(String k){return fx.get(k);}
    public void filter(String id){fx.filter=id;}public void sticker(String id){fx.sticker=id;}public void value(String k,float v){fx.beautyOn=true;fx.set(k,v);}public void look(String id){fx.applyLook(id);}public String[][] filters(){return FxEngine.FILTERS;}
  };}
  static Target forLive(final LiveEffects fx){return new Target(){
    public String filter(){return fx.filter;}public String sticker(){return fx.sticker;}public boolean beauty(){return fx.beautyOn;}
    public float value(String k){return k.equals("smooth")?fx.smooth:k.equals("blemish")?fx.blemish:k.equals("eyes")?fx.eyes:fx.lips;}
    public void filter(String id){fx.filter=id;}public void sticker(String id){fx.sticker=id;}
    public void value(String k,float v){fx.beautyOn=true;if(k.equals("smooth"))fx.smooth=v;else if(k.equals("blemish"))fx.blemish=v;else if(k.equals("eyes"))fx.eyes=v;else fx.lips=v;}
    public void look(String id){fx.beautyOn=!id.equals("off");fx.smooth=id.equals("glass")?.78f:.55f;fx.blemish=id.equals("glass")?.85f:.5f;fx.eyes=id.equals("doll")?.72f:id.equals("eyes")?.9f:id.equals("peach")?.14f:.08f;fx.lips=id.equals("doll")?.27f:id.equals("lips")?.78f:id.equals("peach")?.13f:.05f;if(id.equals("peach")){fx.smooth=.62f;fx.blemish=.65f;}}
    public String[][] filters(){return LiveEffects.FILTERS;}
  };}
  private static int dp(Context c,float n){return Math.round(n*c.getResources().getDisplayMetrics().density);}
  private static GradientDrawable bg(Context c,int color){GradientDrawable g=new GradientDrawable();g.setColor(color);g.setCornerRadius(dp(c,14));return g;}
  static View panel(Context c,String tab,Target target,Runnable changed){
    boolean dark=c instanceof MediaEditActivity || WebTheme.isDark(c);int ink=dark?0xfff6f1ff:0xff201b2e,soft=dark?0xff302b3d:0xfff2eff8;
    LinearLayout box=new LinearLayout(c);box.setOrientation(LinearLayout.VERTICAL);box.setPadding(dp(c,8),dp(c,8),dp(c,8),dp(c,10));
    if(tab.equals("beauty")){
      HorizontalScrollView scroll=new HorizontalScrollView(c);scroll.setHorizontalScrollBarEnabled(false);LinearLayout choices=new LinearLayout(c);
      for(String[] item:new String[][]{{"off","none","Gốc"},{"natural","look_natural","Tự nhiên"},{"glass","look_glass","Da căng"},{"peach","look_peach","Đào"},{"doll","fx_bow","Búp bê"},{"eyes","eyes","Mắt to"},{"lips","lips","Môi đầy"}}){
        View b=tile(c,item[1],null,item[2],ink,soft,false);b.setOnClickListener(v->{target.look(item[0]);changed.run();replacePanel(box,c,tab,target,changed);});choices.addView(b,new LinearLayout.LayoutParams(dp(c,66),-2));
      }
      scroll.addView(choices);box.addView(scroll);
      for(String[] item:new String[][]{{"smooth","Mịn da"},{"blemish","Giảm đốm"},{"eyes","Mắt to"},{"lips","Môi đầy"}}){
        LinearLayout line=new LinearLayout(c);line.setGravity(Gravity.CENTER_VERTICAL);line.setPadding(dp(c,4),dp(c,5),0,0);TextView name=new TextView(c);name.setText(item[1]);name.setTextColor(ink);name.setTextSize(12);line.addView(name,new LinearLayout.LayoutParams(dp(c,82),-2));
        SeekBar slider=new SeekBar(c);slider.setMax(100);slider.setProgress(Math.round(target.value(item[0])*100));slider.setContentDescription(item[1]);slider.setThumbTintList(android.content.res.ColorStateList.valueOf(0xff8b5cf6));slider.setProgressTintList(android.content.res.ColorStateList.valueOf(0xff8b5cf6));
        slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onProgressChanged(SeekBar s,int p,boolean user){if(user){target.value(item[0],p/100f);changed.run();}}public void onStartTrackingTouch(SeekBar s){target.beginEdit();}public void onStopTrackingTouch(SeekBar s){}});
        line.addView(slider,new LinearLayout.LayoutParams(0,dp(c,38),1));box.addView(line);
      }
    }else{
      String[][] catalog=tab.equals("filter")?target.filters():FxEngine.STICKERS;int columns=4;LinearLayout row=null;
      for(int i=0;i<catalog.length;i++){
        if(i%columns==0){row=new LinearLayout(c);box.addView(row,new LinearLayout.LayoutParams(-1,-2));}
        String[] item=catalog[i];boolean selected=(tab.equals("filter")?target.filter():target.sticker()).equals(item[0]);
        View b=tile(c,tab.equals("filter")?null:item[0].equals("none")?"none":"fx_"+item[0],tab.equals("filter")?item[0]:null,item[1],ink,soft,selected);
        b.setOnClickListener(v->{if(tab.equals("filter"))target.filter(item[0]);else target.sticker(item[0]);changed.run();replacePanel(box,c,tab,target,changed);});row.addView(b,new LinearLayout.LayoutParams(0,-2,1));
      }
    }
    return box;
  }
  private static void replacePanel(LinearLayout old,Context c,String tab,Target target,Runnable changed){
    if(!(old.getParent() instanceof android.view.ViewGroup))return;android.view.ViewGroup parent=(android.view.ViewGroup)old.getParent();int index=parent.indexOfChild(old);android.view.ViewGroup.LayoutParams params=old.getLayoutParams();parent.removeView(old);parent.addView(panel(c,tab,target,changed),index,params);
  }
  /** Square swatch (vector icon centred, or a real filter preview) with a centred one-line label. */
  private static View tile(Context c,String icon,String filter,String name,int ink,int soft,boolean selected){
    LinearLayout t=new LinearLayout(c);t.setOrientation(LinearLayout.VERTICAL);t.setGravity(Gravity.CENTER_HORIZONTAL);t.setPadding(dp(c,3),dp(c,6),dp(c,3),dp(c,6));t.setContentDescription(name);
    FrameLayout frame=new FrameLayout(c);GradientDrawable g=new GradientDrawable();g.setColor(filter!=null?soft:Color.TRANSPARENT);if(filter==null&&!selected)g.setStroke(dp(c,1),(ink&0x00ffffff)|0x33000000);g.setCornerRadius(dp(c,14));if(selected)g.setStroke(dp(c,2),0xff8b5cf6);frame.setBackground(g);frame.setClipToOutline(true);frame.setPadding(selected?dp(c,2):0,selected?dp(c,2):0,selected?dp(c,2):0,selected?dp(c,2):0);
    ImageView image=new ImageView(c);
    if(filter!=null){image.setImageBitmap(filterPreview(c,filter));image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setClipToOutline(true);GradientDrawable clip=new GradientDrawable();clip.setCornerRadius(dp(c,12));image.setBackground(clip);frame.addView(image,new FrameLayout.LayoutParams(-1,-1));}
    else{image.setImageDrawable(EditorIcons.drawable(c,icon,selected?0xff8b5cf6:ink));frame.addView(image,new FrameLayout.LayoutParams(dp(c,20),dp(c,20),Gravity.CENTER));}
    int side=filter!=null?52:38;t.addView(frame,new LinearLayout.LayoutParams(dp(c,side),dp(c,side)));
    TextView label=new TextView(c);label.setText(name);label.setTextSize(10.5f);label.setTextColor(selected?0xff8b5cf6:ink);label.setGravity(Gravity.CENTER);label.setSingleLine(true);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));label.setPadding(0,dp(c,5),0,0);
    t.addView(label,new LinearLayout.LayoutParams(-1,-2));return t;}
  private static android.graphics.Bitmap scene;
  private static final java.util.Map<String,android.graphics.Bitmap> previews=new java.util.HashMap<>();
  /** The same small scene (sky, sun, skin tone, foliage) with each filter's real colour matrix applied. */
  static android.graphics.Bitmap filterPreview(Context c,String id){
    android.graphics.Bitmap cached=previews.get(id);if(cached!=null)return cached;int s=dp(c,52);
    if(scene==null){scene=android.graphics.Bitmap.createBitmap(s,s,android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Canvas k=new android.graphics.Canvas(scene);android.graphics.Paint p=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
      p.setShader(new android.graphics.LinearGradient(0,0,0,s,0xff6fb3f2,0xfff7c9a0,android.graphics.Shader.TileMode.CLAMP));k.drawRect(0,0,s,s,p);p.setShader(null);
      p.setColor(0xfffff1b8);k.drawCircle(s*.74f,s*.28f,s*.13f,p);p.setColor(0xff3f8f5a);k.drawCircle(s*.15f,s*1.02f,s*.42f,p);p.setColor(0xff5aa86b);k.drawCircle(s*.95f,s*1.05f,s*.38f,p);
      p.setColor(0xffe8b394);k.drawOval(s*.36f,s*.38f,s*.64f,s*.72f,p);p.setColor(0xff3b2a24);k.drawArc(s*.33f,s*.32f,s*.67f,s*.62f,180,180,true,p);p.setColor(0xffc0504d);k.drawRect(s*.3f,s*.74f,s*.7f,s,p);}
    android.graphics.Bitmap out=android.graphics.Bitmap.createBitmap(s,s,android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Paint p=new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG);
    p.setColorFilter(new android.graphics.ColorMatrixColorFilter(FxEngine.filterMatrix(id)));new android.graphics.Canvas(out).drawBitmap(scene,0,0,p);previews.put(id,out);return out;}
}
