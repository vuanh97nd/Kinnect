package app.kinnect.live;
import android.app.*;import android.content.*;import android.graphics.Typeface;import android.graphics.drawable.*;import android.view.*;import android.widget.*;

/** Sleek Google Material 3 setup sheet over the Studio camera. */
final class LiveSetupSheet {
 private final FxEngine fx;private final Activity activity;private boolean front;private Dialog dialog;private LiveGamePicker picker;private String mode="chat",game="";private TextView startButton,gameButton;private LinearLayout gameOptions;private final boolean dark;private final int ink,muted,soft,line,purple,liveRed=0xffd93025;
 LiveSetupSheet(Activity a,boolean front,FxEngine fx){this.fx=fx;activity=a;this.front=front;dark=WebTheme.isDark(a);int v=dark?1:0;ink=WebDesign.INK[v];muted=WebDesign.MUTED[v];soft=WebDesign.WASH[v];line=WebDesign.LINE[v];purple=WebDesign.PURPLE[v];}
 private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
 private GradientDrawable box(int fill,int r,int strokeColor){GradientDrawable b=new GradientDrawable();b.setColor(fill);b.setCornerRadius(dp(r));if(strokeColor!=0)b.setStroke(Math.max(1,dp(1)),strokeColor);return b;}
 private TextView segTab(String text,String icon){
  TextView t=new KinnectText(activity);t.setText(I18n.t(text));t.setTextSize(12);t.setSingleLine(true);
  t.setGravity(Gravity.CENTER_VERTICAL);t.setMinHeight(dp(34));t.setPadding(dp(26),0,dp(12),0);
  Drawable d=WebIcons.load(activity,icon);d.setBounds(0,0,dp(16),dp(16));
  t.setCompoundDrawablesRelative(d,null,null,null);t.setCompoundDrawablePadding(dp(6));
  return t;
 }
 private TextView chipToggle(CheckBox state,String label,String icon){
  TextView t=new KinnectText(activity);t.setText(I18n.t(label));t.setTextSize(12);t.setSingleLine(true);
  t.setEnabled(state.isEnabled());t.setGravity(Gravity.CENTER_VERTICAL);t.setMinHeight(dp(36)); // M3 height
  t.setPadding(dp(12),0,dp(12),0);
  t.setEllipsize(android.text.TextUtils.TruncateAt.END);
  Drawable d=WebIcons.load(activity,icon);d.setBounds(0,0,dp(16),dp(16));
  t.setCompoundDrawablesRelative(d,null,null,null);t.setCompoundDrawablePadding(dp(6));
  Runnable update=()->{
   boolean on=state.isChecked();
   t.setAlpha(on?1f:.68f);t.setSelected(on);
   t.setTypeface(null,on?Typeface.BOLD:Typeface.NORMAL);
   t.setTextColor(on?purple:muted);
   t.setBackground(box(on?(purple&0x00ffffff)|(dark?0x28000000:0x14000000):soft,999,on?purple:line));
   d.setTint(on?purple:muted);
   t.setContentDescription(I18n.t(label)+" · "+I18n.t(on?"Bật":"Tắt"));
  };
  t.setOnClickListener(v->{state.setChecked(!state.isChecked());update.run();});
  update.run();return t;
 }
 void front(boolean value){front=value;}
 void show(){if(dialog!=null){startButton.setEnabled(true);dialog.show();return;}
  LinearLayout body=new LinearLayout(activity);body.setOrientation(1);body.setTag("live:camera-setup");
  EditText title=new KinnectInput(activity);title.setSingleLine(true);title.setHint(I18n.t("Tiêu đề buổi Live"));title.setTextColor(ink);title.setHintTextColor(muted);title.setTextSize(13);title.setPadding(dp(12),0,dp(12),0);title.setBackground(box(soft,12,line));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});body.addView(title,new LinearLayout.LayoutParams(-1,dp(42)));
  LinearLayout modes=new LinearLayout(activity);modes.setPadding(dp(3),dp(3),dp(3),dp(3));modes.setBackground(box(soft,999,line));
  LinearLayout.LayoutParams modesLp=new LinearLayout.LayoutParams(-1,dp(40));modesLp.topMargin=dp(10);modesLp.bottomMargin=dp(10);
  TextView chat=segTab("Trò chuyện","video"),games=segTab("Chơi game","gamepad");
  modes.addView(chat,new LinearLayout.LayoutParams(0,-1,1));modes.addView(games,new LinearLayout.LayoutParams(0,-1,1));body.addView(modes,modesLp);
  gameOptions=new LinearLayout(activity);gameOptions.setOrientation(1);gameOptions.setVisibility(View.GONE);
  gameButton=new KinnectText(activity);gameButton.setText(I18n.t("Chọn game"));gameButton.setTextSize(13);gameButton.setTypeface(null,Typeface.BOLD);gameButton.setTextColor(ink);gameButton.setSingleLine(true);gameButton.setGravity(Gravity.CENTER_VERTICAL);gameButton.setMinHeight(dp(48));gameButton.setPadding(dp(16),0,dp(16),0);gameButton.setBackground(box(soft,16,line));gameButton.setEllipsize(android.text.TextUtils.TruncateAt.END);
  Drawable gIcon=WebIcons.load(activity,"gamepad");gIcon.setTint(purple);gIcon.setBounds(0,0,dp(20),dp(20));
  Drawable chev=WebIcons.load(activity,"chevron_right");if(chev!=null){chev.setTint(muted);chev.setBounds(0,0,dp(18),dp(18));}
  gameButton.setCompoundDrawablesRelative(gIcon,null,chev,null);gameButton.setCompoundDrawablePadding(dp(12));
  gameButton.setOnClickListener(v->{picker=new LiveGamePicker(activity,game,value->{game=value;gameButton.setText(I18n.t(value.isEmpty()?"Chọn game":value));});picker.show();});
  gameOptions.addView(gameButton,new LinearLayout.LayoutParams(-1,dp(48)));
  CheckBox sound=new CheckBox(activity);sound.setText(I18n.t("Âm thanh game"));sound.setTextColor(ink);sound.setChecked(android.os.Build.VERSION.SDK_INT>=29);sound.setEnabled(android.os.Build.VERSION.SDK_INT>=29);
  CheckBox comments=new CheckBox(activity);comments.setText(I18n.t("Bình luận nổi"));comments.setTextColor(ink);final boolean[] chatComments={true},gameOverlay={android.provider.Settings.canDrawOverlays(activity)};comments.setChecked(chatComments[0]);comments.setOnCheckedChangeListener((b,on)->{if(mode.equals("chat"))chatComments[0]=on;else gameOverlay[0]=on;});
  TextView notice=new KinnectText(activity);notice.setText(I18n.t("Phát toàn màn hình, gồm cả thông báo. Dùng Tạm che khi cần."));notice.setTextSize(11);notice.setTextColor(muted);notice.setPadding(dp(4),dp(6),dp(4),dp(6));gameOptions.addView(notice);body.addView(gameOptions);
  CheckBox mic=new CheckBox(activity);mic.setText(I18n.t("Micro"));mic.setTextColor(ink);mic.setChecked(true);
  LinearLayout toggles=new LinearLayout(activity);toggles.setGravity(Gravity.CENTER_VERTICAL);
  TextView micToggle=chipToggle(mic,"Micro","mic"),soundToggle=chipToggle(sound,"Tiếng game","volume_2"),commentsToggle=chipToggle(comments,"Bình luận","message_circle");
  for(TextView t:new TextView[]{micToggle,soundToggle,commentsToggle}){LinearLayout.LayoutParams slot=new LinearLayout.LayoutParams(-2,dp(34));slot.setMargins(0,0,dp(8),0);toggles.addView(t,slot);}
  Runnable update=()->{
   boolean isChat=mode.equals("chat");
   int activeFill=dark?0xff2b2936:0xffffffff;
   chat.setSelected(isChat);games.setSelected(!isChat);
   chat.setTypeface(null,isChat?Typeface.BOLD:Typeface.NORMAL);
   games.setTypeface(null,!isChat?Typeface.BOLD:Typeface.NORMAL);
   chat.setTextColor(isChat?ink:muted);games.setTextColor(!isChat?ink:muted);
   chat.setBackground(isChat?box(activeFill,999,line):null);
   games.setBackground(!isChat?box(activeFill,999,line):null);
   if(chat.getCompoundDrawablesRelative()[0]!=null)chat.getCompoundDrawablesRelative()[0].setTint(isChat?purple:muted);
   if(games.getCompoundDrawablesRelative()[0]!=null)games.getCompoundDrawablesRelative()[0].setTint(!isChat?purple:muted);
   gameOptions.setVisibility(!isChat?View.VISIBLE:View.GONE);
   soundToggle.setVisibility(!isChat?View.VISIBLE:View.GONE);
   commentsToggle.setVisibility(View.VISIBLE);
   if(dialog!=null&&dialog.getWindow()!=null){
    Window w=dialog.getWindow();
    int width=Math.min(activity.getResources().getDisplayMetrics().widthPixels,dp(560));
    w.getDecorView().post(()->w.setLayout(width,ViewGroup.LayoutParams.WRAP_CONTENT));
   }
  };
  chat.setOnClickListener(v->{mode="chat";comments.setChecked(chatComments[0]);update.run();});games.setOnClickListener(v->{mode="game";comments.setChecked(gameOverlay[0]);update.run();});update.run();
  TextView start=new KinnectText(activity);start.setText(I18n.t("Bắt đầu"));start.setTextSize(14);start.setTypeface(null,Typeface.BOLD);start.setGravity(Gravity.CENTER);start.setTextColor(0xffffffff);start.setMinHeight(dp(48));start.setBackground(box(liveRed,99,0));
  startButton=start;
  start.setOnClickListener(v->{if(mode.equals("game")&&LiveGameLaunch.intent(activity,game)==null){Toast.makeText(activity,I18n.t(game.isEmpty()?"Hãy chọn game trước.":"Không tìm thấy game trên máy. Hãy cài game hoặc chọn game khác."),Toast.LENGTH_LONG).show();return;}if(mode.equals("game")){LiveGamePass.ensure(activity,()->{if(mode.equals("game")&&LiveGameLaunch.intent(activity,game)==null){Toast.makeText(activity,I18n.t(game.isEmpty()?"Hãy chọn game trước.":"Không tìm thấy game trên máy. Hãy cài game hoặc chọn game khác."),Toast.LENGTH_LONG).show();return;}start.setEnabled(false);dialog.dismiss();activity.startActivity(new Intent(activity,LiveActivity.class).putExtra(LiveActivity.EXTRA_HOST,true).putExtra("cameraSetup",true).putExtra("liveMode",mode).putExtra("gameTitle",game).putExtra("title",title.getText().toString().trim()).putExtra("front",front).putExtra("filter",fx.filter).putExtra("sticker",fx.sticker).putExtra("beauty",fx.beautyOn).putExtra("smooth",fx.smooth).putExtra("blemish",fx.blemish).putExtra("eyes",fx.eyes).putExtra("lips",fx.lips).putExtra("mic",mic.isChecked()).putExtra("sound",sound.isChecked()).putExtra("comments",comments.isChecked()));});}else{if(mode.equals("game")&&LiveGameLaunch.intent(activity,game)==null){Toast.makeText(activity,I18n.t(game.isEmpty()?"Hãy chọn game trước.":"Không tìm thấy game trên máy. Hãy cài game hoặc chọn game khác."),Toast.LENGTH_LONG).show();return;}start.setEnabled(false);dialog.dismiss();activity.startActivity(new Intent(activity,LiveActivity.class).putExtra(LiveActivity.EXTRA_HOST,true).putExtra("cameraSetup",true).putExtra("liveMode",mode).putExtra("gameTitle",game).putExtra("title",title.getText().toString().trim()).putExtra("front",front).putExtra("filter",fx.filter).putExtra("sticker",fx.sticker).putExtra("beauty",fx.beautyOn).putExtra("smooth",fx.smooth).putExtra("blemish",fx.blemish).putExtra("eyes",fx.eyes).putExtra("lips",fx.lips).putExtra("mic",mic.isChecked()).putExtra("sound",sound.isChecked()).putExtra("comments",comments.isChecked()));}});
  ScrollView scroll=new ScrollView(activity){protected void onMeasure(int w,int h){super.onMeasure(w,View.MeasureSpec.makeMeasureSpec(activity.getResources().getDisplayMetrics().heightPixels*45/100,View.MeasureSpec.AT_MOST));}};scroll.addView(body);LinearLayout container=new LinearLayout(activity);container.setOrientation(1);container.addView(scroll);toggles.setPadding(0,dp(8),0,0);container.addView(toggles);LinearLayout.LayoutParams footer=new LinearLayout.LayoutParams(-1,dp(42));footer.topMargin=dp(12);container.addView(start,footer);dialog=new Sheet(activity).setTitle(I18n.t("Live")).setView(container).show();start.setTextColor(0xffffffff);int wPx=Math.min(activity.getResources().getDisplayMetrics().widthPixels,dp(560));dialog.getWindow().setLayout(wPx,ViewGroup.LayoutParams.WRAP_CONTENT);dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
 }
 void close(){if(picker!=null)picker.close();if(dialog!=null)dialog.dismiss();}
}
