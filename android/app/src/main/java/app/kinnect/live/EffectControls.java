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
      for(String[] item:new String[][]{{"off","○","Gốc"},{"natural","✧","Tự nhiên"},{"glass","✨","Da căng"},{"peach","🌸","Đào"},{"doll","🎀","Búp bê"},{"eyes","👀","Mắt to"},{"lips","💋","Môi đầy"}}){
        TextView b=tile(c,item[1],item[2],ink,soft);b.setContentDescription(item[2]);b.setOnClickListener(v->{target.look(item[0]);changed.run();replacePanel(box,c,tab,target,changed);});choices.addView(b,new LinearLayout.LayoutParams(dp(c,76),dp(c,76)));
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
        if(i%columns==0){row=new LinearLayout(c);box.addView(row,new LinearLayout.LayoutParams(-1,dp(c,84)));}
        String[] item=catalog[i];boolean selected=(tab.equals("filter")?target.filter():target.sticker()).equals(item[0]);
        TextView b=tile(c,tab.equals("filter")?"◈":item.length>2?item[2]:"✦",item[1],selected?0xff26104d:ink,selected?0xffdcd0ff:soft);b.setContentDescription(item[1]);
        b.setOnClickListener(v->{if(tab.equals("filter"))target.filter(item[0]);else target.sticker(item[0]);changed.run();replacePanel(box,c,tab,target,changed);});row.addView(b,new LinearLayout.LayoutParams(0,-1,1));
      }
    }
    return box;
  }
  private static void replacePanel(LinearLayout old,Context c,String tab,Target target,Runnable changed){
    if(!(old.getParent() instanceof android.view.ViewGroup))return;android.view.ViewGroup parent=(android.view.ViewGroup)old.getParent();int index=parent.indexOfChild(old);android.view.ViewGroup.LayoutParams params=old.getLayoutParams();parent.removeView(old);parent.addView(panel(c,tab,target,changed),index,params);
  }
  private static TextView tile(Context c,String glyph,String name,int ink,int color){TextView t=new TextView(c);t.setText(glyph+"\n"+name);t.setTextSize(12);t.setGravity(Gravity.CENTER);t.setTextColor(ink);t.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));t.setBackground(bg(c,color));t.setPadding(dp(c,3),dp(c,6),dp(c,3),dp(c,6));return t;}
}
