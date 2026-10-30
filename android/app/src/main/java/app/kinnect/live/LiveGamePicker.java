package app.kinnect.live;
import android.app.*;import android.graphics.*;import android.graphics.drawable.*;import android.text.*;import android.view.*;import android.widget.*;import java.text.Normalizer;import java.util.*;

/** Curated game labels, not a live ranking or a scan of installed applications. */
final class LiveGamePicker {
 interface Selected{void choose(String title);}
 static final String[][] GAMES={
  {"Liên Quân Mobile","MOBA","lien quan aov arena of valor lq"},
  {"Free Fire","Sinh tồn","ff garena freefire"},
  {"PUBG MOBILE VN","Sinh tồn","pubg pubgmobile vng"},
  {"Roblox VN","Sáng tạo","roblox robloxvn"},
  {"Mobile Legends: Bang Bang","MOBA","mlbb mobile legends lien quan ml"},
  {"Liên Minh Huyền Thoại: Tốc Chiến","MOBA","toc chien wild rift lol lien minh"},
  {"Đấu Trường Chân Lý","Chiến thuật","dtcl tft teamfight tactics"},
  {"Play Together VNG","Giao lưu","playtogether haegin"},
  {"Genshin Impact","Nhập vai","genshin nguyen than hoyoverse"},
  {"Honkai: Star Rail","Nhập vai","honkai starrail hsr hoyoverse"},
  {"Delta Force","Bắn súng","deltaforce delta force garena"},
  {"Minecraft","Sáng tạo","minecraft mojang"}
 };
 static String normalized(String value){return Normalizer.normalize(value,Normalizer.Form.NFD).replaceAll("\\p{M}+","").replace('đ','d').replace('Đ','D').toLowerCase(Locale.ROOT).trim();}
 static boolean matches(String[] game,String query){String q=normalized(query);if(q.isEmpty())return true;String text=normalized(game[0]+" "+game[1]+" "+game[2]);for(String word:q.split("\\s+"))if(!text.contains(word))return false;return true;}
 private final Activity activity;private final Selected chosen;private final int ink,muted,soft,purple;private String selected;private Dialog dialog;private LinearLayout results;
 LiveGamePicker(Activity activity,String current,Selected chosen){this.activity=activity;this.selected=current;this.chosen=chosen;int v=WebTheme.isDark(activity)?1:0;ink=WebDesign.INK[v];muted=WebDesign.MUTED[v];soft=WebDesign.WASH[v];purple=WebDesign.PURPLE[v];}
 private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
 private TextView text(String value,int size,int color){TextView t=new KinnectText(activity);t.setText(I18n.t(value));t.setTextSize(size);t.setTextColor(color);return t;}
 private GradientDrawable bg(int color){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(14));return d;}
 void show(){if(dialog!=null&&dialog.isShowing())return;LinearLayout body=new LinearLayout(activity);body.setOrientation(1);body.setTag("game:picker");EditText search=new KinnectInput(activity);search.setSingleLine(true);search.setHint(I18n.t("Tìm game"));search.setContentDescription(I18n.t("Tìm game"));search.setTextSize(14);search.setTextColor(ink);search.setHintTextColor(muted);search.setPadding(dp(12),dp(10),dp(12),dp(10));search.setBackground(bg(soft));body.addView(search,new LinearLayout.LayoutParams(-1,-2));ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(false);results=new LinearLayout(activity);results.setOrientation(1);scroll.addView(results);LinearLayout.LayoutParams list=new LinearLayout.LayoutParams(-1,Math.min(dp(330),activity.getResources().getDisplayMetrics().heightPixels*42/100));list.topMargin=dp(8);body.addView(scroll,list);TextView other=text("Game khác",13,purple);other.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("pencil"),null,null,null);other.setCompoundDrawablePadding(dp(10));other.setMinHeight(dp(48));other.setGravity(Gravity.CENTER_VERTICAL);other.setPadding(dp(12),dp(8),dp(12),dp(8));other.setOnClickListener(v->{dialog.dismiss();custom();});body.addView(other);search.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int n){}public void onTextChanged(CharSequence s,int a,int b,int c){render(s.toString());}public void afterTextChanged(Editable e){}});render("");dialog=new Sheet(activity).setTitle(I18n.t("Chọn game")).setView(body).setNeutralButton(I18n.t("Không chọn"),(d,w)->chosen.choose("")).setNegativeButton(I18n.t("Quay lại"),null).show();}
 private android.graphics.drawable.Drawable tinted(String name){android.graphics.drawable.Drawable d=WebIcons.load(activity,name);d.setTint(purple);d.setBounds(0,0,dp(20),dp(20));return d;}
 private void render(String query){results.removeAllViews();int count=0;for(String[] game:GAMES){if(!matches(game,query))continue;count++;LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(dp(10),dp(10),dp(10),dp(10));row.setMinimumHeight(dp(62));row.setTag("game:option:"+game[0]);ImageView art=new ImageView(activity);art.setImageDrawable(tinted("gamepad"));art.setPadding(dp(9),dp(9),dp(9),dp(9));art.setBackground(bg(soft));row.addView(art,new LinearLayout.LayoutParams(dp(40),dp(40)));LinearLayout copy=new LinearLayout(activity);copy.setOrientation(1);copy.setPadding(dp(12),0,dp(6),0);TextView name=text(game[0],13,ink);name.setMaxLines(2);copy.addView(name);copy.addView(text(game[1],11,muted));row.addView(copy,new LinearLayout.LayoutParams(0,-2,1));if(game[0].equals(selected)){ImageView tick=new ImageView(activity);tick.setImageDrawable(tinted("check"));row.addView(tick,new LinearLayout.LayoutParams(dp(22),dp(22)));}row.setContentDescription(game[0]);row.setOnClickListener(v->{selected=game[0];chosen.choose(selected);dialog.dismiss();});results.addView(row,new LinearLayout.LayoutParams(-1,-2));}if(count==0){TextView empty=text("Không tìm thấy game. Chọn Game khác để nhập tên.",13,muted);empty.setPadding(dp(12),dp(18),dp(12),dp(18));results.addView(empty);}}
 private void custom(){EditText name=new KinnectInput(activity);name.setText(selected);name.setSingleLine(true);name.setFilters(new InputFilter[]{new InputFilter.LengthFilter(60)});dialog=new Sheet(activity).setTitle(I18n.t("Game khác")).setView(name).setPositiveButton(I18n.t("Chọn"),(d,w)->{String value=name.getText().toString().trim();if(value.isEmpty()){show();return;}selected=value;chosen.choose(value);}).setNegativeButton(I18n.t("Quay lại"),(d,w)->show()).show();}
 void close(){if(dialog!=null)dialog.dismiss();}
}
