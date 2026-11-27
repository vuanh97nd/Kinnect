package app.kinnect.live;
import android.app.*;import android.content.*;import android.content.res.ColorStateList;import android.graphics.*;import android.graphics.drawable.*;import android.view.*;import android.widget.*;
/** Persistent Kinnect brand and navigation around account feature content. */
final class CommerceChrome {
 private static Drawable pressable(int color,int ripple,int radius,float density){GradientDrawable bg=new GradientDrawable();bg.setColor(color);bg.setCornerRadius(dp(radius,density));GradientDrawable mask=new GradientDrawable();mask.setColor(Color.BLACK);mask.setCornerRadius(dp(radius,density));return new RippleDrawable(ColorStateList.valueOf(ripple),bg,mask);}
 static View wrap(Activity a,View content){
  return wrap(a,content,!(a instanceof WalletActivity||a instanceof StoreActivity));
 }
 static View wrap(Activity a,View content,boolean showGlobalChrome){
  final float density=a.getResources().getDisplayMetrics().density;
  boolean compact=a.getResources().getConfiguration().orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE;
  int variant=WebTheme.isDark(a)?1:0,card=WebDesign.CARD[variant],ink=WebDesign.INK[variant],muted=WebDesign.MUTED_STRICT[variant],purple=WebDesign.PURPLE[variant],purpleText=WebDesign.PURPLE_TEXT_STRICT[variant],line=WebDesign.LINE[variant],ripple=(purple&0x00ffffff)|0x22000000;
  LinearLayout root=new LinearLayout(a);root.setOrientation(1);
  if(android.os.Build.VERSION.SDK_INT>=29)root.setForceDarkAllowed(false);
  root.setBackgroundColor(WebDesign.BG[variant]);
  root.setOnApplyWindowInsetsListener((v,i)->{if(android.os.Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=i.getInsets(WindowInsets.Type.systemBars());android.graphics.Insets ime=i.getInsets(WindowInsets.Type.ime());v.setPadding(bars.left,bars.top,bars.right,Math.max(bars.bottom,ime.bottom));}else{v.setPadding(i.getSystemWindowInsetLeft(),i.getSystemWindowInsetTop(),i.getSystemWindowInsetRight(),i.getSystemWindowInsetBottom());}return i;});
  if(!showGlobalChrome){
   root.addView(content,new LinearLayout.LayoutParams(-1,0,1));
   return root;
  }
  int raw48=UiMetrics.dpRaw(a,48);
  LinearLayout header=new LinearLayout(a);header.setGravity(Gravity.CENTER_VERTICAL);
  header.setPadding(dp(14,density),0,dp(8,density),0);
  header.setBackgroundColor(card);header.setElevation(dp(2,density));
  ImageView logo=new ImageView(a);
  logo.setImageResource(a.getResources().getIdentifier("kinnect_logo","drawable",a.getPackageName()));
  logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
  GradientDrawable logoBg=new GradientDrawable();logoBg.setColor(card);logoBg.setCornerRadius(dp(12,density));
  logo.setBackground(logoBg);logo.setClipToOutline(true);
  logo.setLayoutParams(new LinearLayout.LayoutParams(dp(40,density),dp(40,density)));
  logo.setContentDescription(I18n.t("Trang chủ"));
  logo.setOnClickListener(v->go(a,"feed"));
  header.addView(UiMetrics.wrapMinTouchTarget(a,logo));
  header.addView(new View(a),new LinearLayout.LayoutParams(0,1,1));
  for(String[] item:new String[][]{{"bell","notifications","Thông báo"},{"store","store","Cửa hàng"},{"users-round","friends","Bạn bè"},{"message-square","inbox","Tin nhắn"},{"user-round","account","Tài khoản"}}){
   if(item[1].equals("account")){
    FrameLayout holder=new FrameLayout(a);holder.setBackground(pressable(card,ripple,99,density));
    ImageView face=new ImageView(a);face.setTag("commerce:account-avatar");face.setScaleType(ImageView.ScaleType.CENTER_CROP);
    bindAccount(a,face,density);
    holder.addView(face,new FrameLayout.LayoutParams(dp(26,density),dp(26,density),Gravity.CENTER));
    holder.setContentDescription(I18n.t(item[2]));holder.setOnClickListener(v->go(a,item[1]));
    LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(raw48,raw48);mp.setMargins(dp(2,density),0,0,0);
    header.addView(holder,mp);UiMetrics.enforceMinTouchTarget(holder);continue;
   }
   FrameLayout btn=new FrameLayout(a);btn.setBackground(pressable(card,ripple,99,density));
   ImageView icon=new ImageView(a);
   android.graphics.drawable.Drawable d=WebIcons.load(a,item[0]);
   d.setTint(item[1].equals("store")&&a instanceof StoreActivity?purpleText:ink);
   icon.setImageDrawable(d);icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
   btn.addView(icon,new FrameLayout.LayoutParams(dp(22,density),dp(22,density),Gravity.CENTER));
   btn.setContentDescription(I18n.t(item[2]));
   if(item[1].equals("store"))btn.setOnClickListener(v->{if(!(a instanceof StoreActivity))a.startActivity(new Intent(a,StoreActivity.class).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));});
   else btn.setOnClickListener(v->go(a,item[1]));
   header.addView(btn,new LinearLayout.LayoutParams(raw48,raw48));UiMetrics.enforceMinTouchTarget(btn);
  }
  root.addView(header,new LinearLayout.LayoutParams(-1,Math.max(raw48,dp(compact?48:WebDesign.HEADER,density))));
  View topLine=new View(a);topLine.setBackgroundColor(line);root.addView(topLine,new LinearLayout.LayoutParams(-1,1));
  root.addView(content,new LinearLayout.LayoutParams(-1,0,1));
  View bottomLine=new View(a);bottomLine.setBackgroundColor(line);root.addView(bottomLine,new LinearLayout.LayoutParams(-1,1));
  LinearLayout bottom=new LinearLayout(a);bottom.setBackgroundColor(card);bottom.setGravity(Gravity.CENTER_VERTICAL);
  int tabH=Math.max(raw48,dp(compact?48:68,density));
  for(String[] item:new String[][]{{"feed","house","Bảng tin"},{"discover","compass","Khám phá"},{"create","plus","Tạo"},{"shorts","clapperboard","Video"},{"live","radio","Live"}}){
   LinearLayout tab=new LinearLayout(a);tab.setOrientation(compact?0:1);tab.setGravity(Gravity.CENTER);tab.setBackground(pressable(card,ripple,14,density));
   ImageView icon=new ImageView(a);android.graphics.drawable.Drawable d=WebIcons.load(a,item[1]);d.setTint(item[0].equals("create")?Color.WHITE:muted);icon.setImageDrawable(d);
   if(item[0].equals("create")){GradientDrawable g=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{purple,0xffff4f9a});g.setCornerRadius(dp(16,density));icon.setBackground(g);icon.setElevation(dp(4,density));icon.setPadding(dp(11,density),dp(11,density),dp(11,density),dp(11,density));tab.addView(icon,new LinearLayout.LayoutParams(dp(46,density),dp(40,density)));}
   else{tab.addView(icon,new LinearLayout.LayoutParams(dp(24,density),dp(24,density)));TextView name=new KinnectText(a);name.setText(I18n.t(item[2]));name.setTextSize(12);name.setTextColor(muted);name.setPadding(compact?dp(4,density):0,compact?0:dp(4,density),0,0);name.setGravity(Gravity.CENTER);name.setSingleLine(true);tab.addView(name);}
   tab.setContentDescription(I18n.t(item[2]));tab.setOnClickListener(v->go(a,item[0]));bottom.addView(tab,new LinearLayout.LayoutParams(0,tabH,1));UiMetrics.enforceMinTouchTarget(tab);
  }
  root.addView(bottom);return root;
 }
 static void refreshAccount(Activity a){if(a==null||a.isFinishing()||a.isDestroyed())return;View decor=a.getWindow()==null?null:a.getWindow().getDecorView();View found=decor==null?null:decor.findViewWithTag("commerce:account-avatar");if(found instanceof ImageView)bindAccount(a,(ImageView)found,a.getResources().getDisplayMetrics().density);}
 private static void renderAccount(Activity a,ImageView face,org.json.JSONObject user){if(a.isFinishing()||a.isDestroyed()||user==null)return;boolean dark=WebTheme.isDark(a);int fill=dark?0xff483020:0xfff8e6d8,fg=dark?0xffefc39f:0xff9a562b;face.setPadding(0,0,0,0);face.setScaleType(ImageView.ScaleType.CENTER_CROP);GradientDrawable circle=new GradientDrawable();circle.setShape(GradientDrawable.OVAL);circle.setColor(fill);face.setBackground(circle);face.setClipToOutline(true);Bitmap bitmap=Bitmap.createBitmap(96,96,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(bitmap);Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);paint.setColor(fill);canvas.drawOval(0,0,96,96,paint);paint.setColor(fg);paint.setTypeface(ApprovedTypography.font(a,Typeface.BOLD));paint.setTextAlign(Paint.Align.CENTER);String name=user.optString("name",user.optString("username","?")).trim();StringBuilder letters=new StringBuilder();for(String w:name.split("\\s+"))if(!w.isEmpty())letters.append(w.substring(0,1));String initials=letters.length()==0?"?":letters.substring(Math.max(0,letters.length()-2)).toUpperCase(java.util.Locale.ROOT);paint.setTextSize(96f*(initials.length()>1?0.34f:0.4f));Paint.FontMetrics fm=paint.getFontMetrics();canvas.drawText(initials,48f,48f-(fm.ascent+fm.descent)/2f,paint);face.setImageBitmap(bitmap);String path=user.optString("avatar","");if(!path.isEmpty()&&!path.equals("null")){MediaImageLoader.displayImage(a,NativeApi.shared,path,face,192,()->!a.isFinishing()&&!a.isDestroyed());}}
 private static void bindAccount(Activity a,ImageView face,float density){org.json.JSONObject cached=NativeApi.shared.cachedGet("/api/me");if(cached!=null&&cached.optJSONObject("user")!=null)renderAccount(a,face,cached.optJSONObject("user"));NativeApi.shared.call("GET","/api/me",null,(data,error,status)->{if(error==null&&data!=null)renderAccount(a,face,data.optJSONObject("user"));});}
 private static int dp(int n,float density){return Math.round(n*density*WebDesign.UI_SCALE);}
 private static void go(Activity a,String target){a.startActivity(new Intent(a,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("commerce_destination",target));a.finish();}
}
