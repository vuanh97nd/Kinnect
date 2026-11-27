package app.kinnect.live;
import android.app.*;import android.content.*;import android.graphics.Typeface;import android.graphics.drawable.*;import android.view.*;import android.widget.*;

/** Sleek Google Material 3 setup sheet over the Studio camera. */
final class LiveSetupSheet {
 private static final int DARK_SURFACE=0xff14111d,DARK_ELEVATED=0xff1e1930,DARK_ACTIVE_CHIP=0xff2c2346,DARK_LINE=0xff352d52,DARK_INK=0xfff8f7fc,DARK_MUTED=0xffa9a2c6,DARK_ACCENT=WebDesign.DARK_ACCENT_TEXT;
 private final FxEngine fx;private final Activity activity;private boolean front;private Dialog dialog;private LiveGamePicker picker;private String mode="chat",game="",topic="Giao lưu kết bạn";private Button startButton;private TextView gameButton;private LinearLayout gameOptions;private final int ink=DARK_INK,muted=DARK_MUTED,soft=DARK_ELEVATED,line=DARK_LINE,purple=DARK_ACCENT,liveRed=WebDesign.LIVE_RED;
 LiveSetupSheet(Activity a,boolean front,FxEngine fx){this.fx=fx;activity=a;this.front=front;}
 private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density*WebDesign.UI_SCALE);}
 private int dpRaw(int n){return UiMetrics.dpRaw(activity,n);}
 private boolean isGameLiveSupported(){if(Distribution.PLAY)return false;try{return activity.getPackageManager().resolveService(new Intent(activity,LiveGameService.class),0)!=null;}catch(Exception e){return false;}}
 private GradientDrawable box(int fill,int r,int strokeColor){GradientDrawable b=new GradientDrawable();b.setColor(fill);b.setCornerRadius(dp(r));if(strokeColor!=0)b.setStroke(Math.max(1,dp(1)),strokeColor);return b;}
 private TextView segTab(String text,String icon){
  TextView t=new KinnectText(activity);t.setText(I18n.t(text));t.setTextSize(12);t.setSingleLine(true);
  t.setGravity(Gravity.CENTER);t.setMinWidth(dpRaw(48));t.setMinimumWidth(dpRaw(48));t.setMinHeight(dpRaw(48));t.setMinimumHeight(dpRaw(48));t.setPadding(dp(12),0,dp(12),0);
  Drawable d=WebIcons.load(activity,icon);d.setBounds(0,0,dp(16),dp(16));
  t.setCompoundDrawablesRelative(d,null,null,null);t.setCompoundDrawablePadding(dp(6));
  return t;
 }
 private TextView chipToggle(CheckBox state,String label,String icon){
  TextView t=new KinnectText(activity);t.setText(I18n.t(label));t.setTextSize(11.5f);t.setSingleLine(true);
  t.setEnabled(state.isEnabled());t.setGravity(Gravity.CENTER);t.setMinWidth(dpRaw(48));t.setMinimumWidth(dpRaw(48));t.setMinHeight(dpRaw(48));t.setMinimumHeight(dpRaw(48));
  t.setPadding(dp(12),0,dp(12),0);
  t.setEllipsize(android.text.TextUtils.TruncateAt.END);
  Drawable d=WebIcons.load(activity,icon);d.setBounds(0,0,dp(14),dp(14));
  t.setCompoundDrawablesRelative(d,null,null,null);t.setCompoundDrawablePadding(dp(4));
  Runnable update=()->{
   boolean on=state.isChecked();
   t.setAlpha(1f);t.setSelected(on);
   t.setTypeface(null,on?Typeface.BOLD:Typeface.NORMAL);
   t.setTextColor(on?ink:muted);
   t.setBackground(box(on?DARK_ACTIVE_CHIP:soft,999,on?purple:line));
   d.setTint(on?purple:muted);
   t.setContentDescription(I18n.t(label)+" · "+I18n.t(on?"Bật":"Tắt"));
  };
  t.setTag(update);
  t.setOnClickListener(v->{state.setChecked(!state.isChecked());update.run();});
  update.run();return t;
 }
 private TextView actionChip(String label,String icon,boolean highlighted,Runnable onClick){
  TextView t=new KinnectText(activity);t.setText(I18n.t(label));t.setTextSize(11.5f);t.setSingleLine(true);
  t.setGravity(Gravity.CENTER);t.setMinWidth(dpRaw(48));t.setMinimumWidth(dpRaw(48));t.setMinHeight(dpRaw(48));t.setMinimumHeight(dpRaw(48));t.setPadding(dp(12),0,dp(12),0);
  t.setEllipsize(android.text.TextUtils.TruncateAt.END);
  t.setTypeface(null,highlighted?Typeface.BOLD:Typeface.NORMAL);
  t.setTextColor(ink);
  t.setBackground(box(highlighted?DARK_ACTIVE_CHIP:soft,999,highlighted?purple:line));
  Drawable d=WebIcons.load(activity,icon);d.setBounds(0,0,dp(14),dp(14));d.setTint(highlighted?purple:muted);
  t.setCompoundDrawablesRelative(d,null,null,null);t.setCompoundDrawablePadding(dp(4));
  t.setContentDescription(I18n.t(label));
  t.setOnClickListener(v->onClick.run());
  return t;
 }
 private void syncDialogHeight(){
  if(dialog==null||dialog.getWindow()==null)return;
  Window w=dialog.getWindow();
  int rawDp560=Math.round(560*activity.getResources().getDisplayMetrics().density);
  int width=Math.min(activity.getResources().getDisplayMetrics().widthPixels,rawDp560);
  w.setLayout(width,ViewGroup.LayoutParams.WRAP_CONTENT);
  View decor=w.getDecorView();
  if(decor!=null){decor.requestLayout();decor.requestApplyInsets();}
 }
 private ViewGroup flowWrap(final int hGap,final int vGap){
  return new ViewGroup(activity){
   @Override protected void onMeasure(int widthMeasureSpec,int heightMeasureSpec){
    int rawDp560=Math.round(560*getResources().getDisplayMetrics().density);
    int fallbackW=Math.max(0,Math.min(getResources().getDisplayMetrics().widthPixels,rawDp560)-dp(44));
    int wMode=MeasureSpec.getMode(widthMeasureSpec);
    int maxW=(wMode==MeasureSpec.UNSPECIFIED||MeasureSpec.getSize(widthMeasureSpec)<=0)?fallbackW:MeasureSpec.getSize(widthMeasureSpec);
    int padL=getPaddingLeft(),padT=getPaddingTop(),padR=getPaddingRight(),padB=getPaddingBottom();
    int availW=Math.max(0,maxW-padL-padR);
    int x=0,y=padT,rowH=0;
    for(int i=0;i<getChildCount();i++){
     View c=getChildAt(i);
     if(c.getVisibility()==GONE)continue;
     ViewGroup.LayoutParams lp=c.getLayoutParams();
     int cwSpec=getChildMeasureSpec(MeasureSpec.makeMeasureSpec(availW,MeasureSpec.AT_MOST),0,lp!=null?lp.width:ViewGroup.LayoutParams.WRAP_CONTENT);
     int chSpec=getChildMeasureSpec(heightMeasureSpec,padT+padB,lp!=null?lp.height:ViewGroup.LayoutParams.WRAP_CONTENT);
     c.measure(cwSpec,chSpec);
     int cw=c.getMeasuredWidth(),ch=c.getMeasuredHeight();
     if(x>0&&x+cw>availW){y+=rowH+vGap;x=0;rowH=0;}
     x+=cw+hGap;rowH=Math.max(rowH,ch);
    }
    int totalH=y+rowH+padB;
    setMeasuredDimension(resolveSize(maxW,widthMeasureSpec),resolveSize(totalH,heightMeasureSpec));
   }
   @Override protected void onLayout(boolean changed,int l,int t,int r,int b){
    int padL=getPaddingLeft(),padT=getPaddingTop(),padR=getPaddingRight();
    int availW=Math.max(0,(r-l)-padL-padR);
    int x=0,y=padT,rowH=0;
    for(int i=0;i<getChildCount();i++){
     View c=getChildAt(i);
     if(c.getVisibility()==GONE)continue;
     int cw=c.getMeasuredWidth(),ch=c.getMeasuredHeight();
     if(x>0&&x+cw>availW){y+=rowH+vGap;x=0;rowH=0;}
     c.layout(padL+x,y,padL+x+cw,y+ch);
     x+=cw+hGap;rowH=Math.max(rowH,ch);
    }
   }
  };
 }
 void front(boolean value){front=value;}
 void show(){
  if(activity.isFinishing()||activity.isDestroyed())return;
  if(dialog!=null){startButton.setEnabled(true);dialog.show();syncDialogHeight();return;}
  final boolean gameSupported=isGameLiveSupported();
  if(!gameSupported)mode="chat";
  LinearLayout body=new LinearLayout(activity);body.setOrientation(LinearLayout.VERTICAL);body.setTag("live:camera-setup");
  EditText title=new KinnectInput(activity);title.setSingleLine(true);title.setGravity(Gravity.CENTER_VERTICAL);title.setHint(I18n.t("Tiêu đề buổi Live"));title.setTextColor(ink);title.setHintTextColor(muted);title.setTextSize(14);title.setPadding(dp(14),0,dp(14),0);title.setBackground(box(soft,14,line));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});body.addView(title,new LinearLayout.LayoutParams(-1,dpRaw(48)));UiMetrics.enforceMinTouchTarget(title,48);
  TextView topicHeading=new KinnectText(activity);topicHeading.setText(I18n.t("Chủ đề buổi Live"));topicHeading.setTextSize(12);topicHeading.setTextColor(muted);topicHeading.setTypeface(ApprovedTypography.font(activity,Typeface.BOLD));LinearLayout.LayoutParams thLp=new LinearLayout.LayoutParams(-1,-2);thLp.topMargin=dp(12);thLp.bottomMargin=dp(6);body.addView(topicHeading,thLp);
  final String[] topics={"Giao lưu kết bạn","Âm nhạc","Tâm sự","Hỏi đáp","Nghệ thuật"};
  final java.util.List<TextView> topicChips=new java.util.ArrayList<>();
  final Runnable syncTopics=()->{
   for(int i=0;i<topicChips.size();i++){
    TextView c=topicChips.get(i);
    boolean on=topics[i].equals(topic);
    c.setSelected(on);
    c.setTypeface(ApprovedTypography.font(activity,on?Typeface.BOLD:Typeface.NORMAL));
    c.setTextColor(on?0xffffffff:muted);
    c.setBackground(box(on?WebDesign.PURPLE_HERO[0]:soft,999,on?purple:line));
   }
  };
  ViewGroup topicFlow=flowWrap(dp(8),dp(8));
  for(int i=0;i<topics.length;i++){
   final String label=topics[i];
   TextView chip=new KinnectText(activity);chip.setText(I18n.t(label));chip.setTextSize(12);chip.setSingleLine(true);chip.setEllipsize(android.text.TextUtils.TruncateAt.END);chip.setGravity(Gravity.CENTER);chip.setMinWidth(dpRaw(48));chip.setMinimumWidth(dpRaw(48));chip.setMinHeight(dpRaw(48));chip.setMinimumHeight(dpRaw(48));chip.setPadding(dp(14),0,dp(14),0);chip.setContentDescription(I18n.t(label));
   chip.setOnClickListener(v->{topic=label;syncTopics.run();});
   topicFlow.addView(chip,new ViewGroup.LayoutParams(-2,dpRaw(48)));UiMetrics.enforceMinTouchTarget(chip,48);topicChips.add(chip);
  }
  syncTopics.run();
  body.addView(topicFlow,new LinearLayout.LayoutParams(-1,-2));
  LinearLayout modes=new LinearLayout(activity);modes.setPadding(dp(3),dp(3),dp(3),dp(3));modes.setBackground(box(soft,999,line));
  LinearLayout.LayoutParams modesLp=new LinearLayout.LayoutParams(-1,-2);modesLp.topMargin=dp(10);modesLp.bottomMargin=dp(2);
  TextView chat=segTab("Trò chuyện","video"),games=segTab("Chơi game","gamepad");
  modes.addView(chat,new LinearLayout.LayoutParams(0,dpRaw(48),1));UiMetrics.enforceMinTouchTarget(chat,48);
  modes.addView(games,new LinearLayout.LayoutParams(0,dpRaw(48),1));UiMetrics.enforceMinTouchTarget(games,48);
  if(!gameSupported)modes.setVisibility(View.GONE);
  body.addView(modes,modesLp);
  gameOptions=new LinearLayout(activity);gameOptions.setOrientation(LinearLayout.VERTICAL);gameOptions.setVisibility(View.GONE);
  gameButton=new KinnectText(activity);gameButton.setText(I18n.t("Chọn game"));gameButton.setTextSize(13);gameButton.setTypeface(null,Typeface.BOLD);gameButton.setTextColor(ink);gameButton.setSingleLine(true);gameButton.setGravity(Gravity.CENTER_VERTICAL);gameButton.setMinHeight(dpRaw(48));gameButton.setMinimumHeight(dpRaw(48));gameButton.setPadding(dp(14),0,dp(14),0);gameButton.setBackground(box(soft,14,line));gameButton.setEllipsize(android.text.TextUtils.TruncateAt.END);
  Drawable gIcon=WebIcons.load(activity,"gamepad");gIcon.setTint(purple);gIcon.setBounds(0,0,dp(18),dp(18));
  Drawable chev=WebIcons.load(activity,"chevron_right");if(chev!=null){chev.setTint(muted);chev.setBounds(0,0,dp(16),dp(16));}
  gameButton.setCompoundDrawablesRelative(gIcon,null,chev,null);gameButton.setCompoundDrawablePadding(dp(10));
  gameButton.setOnClickListener(v->{picker=new LiveGamePicker(activity,game,value->{game=value;gameButton.setText(I18n.t(value.isEmpty()?"Chọn game":value));});picker.show();});
  LinearLayout.LayoutParams gbLp=new LinearLayout.LayoutParams(-1,dpRaw(48));gbLp.topMargin=dp(8);
  gameOptions.addView(gameButton,gbLp);UiMetrics.enforceMinTouchTarget(gameButton,48);
  CheckBox sound=new CheckBox(activity);sound.setText(I18n.t("Âm thanh game"));sound.setTextColor(ink);sound.setChecked(android.os.Build.VERSION.SDK_INT>=29);sound.setEnabled(android.os.Build.VERSION.SDK_INT>=29);
  CheckBox comments=new CheckBox(activity);comments.setText(I18n.t("Bình luận nổi"));comments.setTextColor(ink);final boolean[] chatComments={true},gameOverlay={android.provider.Settings.canDrawOverlays(activity)};comments.setChecked(chatComments[0]);comments.setOnCheckedChangeListener((b,on)->{if(mode.equals("chat"))chatComments[0]=on;else gameOverlay[0]=on;});
  TextView notice=new KinnectText(activity);notice.setText(I18n.t("Phát toàn màn hình, gồm cả thông báo. Dùng Tạm che khi cần."));notice.setTextSize(11);notice.setTextColor(muted);notice.setPadding(dp(4),dp(6),dp(4),dp(4));gameOptions.addView(notice);body.addView(gameOptions);
  CheckBox mic=new CheckBox(activity);mic.setText(I18n.t("Micro"));mic.setTextColor(ink);mic.setChecked(true);
  ViewGroup toggles=flowWrap(dp(6),dp(8));
  TextView micToggle=chipToggle(mic,"Micro","mic"),soundToggle=chipToggle(sound,"Tiếng game","volume_2"),commentsToggle=chipToggle(comments,"Bình luận","message_circle");
  TextView flipChip=actionChip("Đổi cam","switch_camera",false,()->{if(activity instanceof StudioActivity)((StudioActivity)activity).flipCameraForLiveSetup();});
  TextView beautyChip=actionChip("Làm đẹp","sparkles",fx.beautyOn,()->{if(activity instanceof StudioActivity)((StudioActivity)activity).openBeautyForLiveSetup();});
  for(TextView t:new TextView[]{micToggle,commentsToggle,flipChip,beautyChip,soundToggle}){toggles.addView(t,new ViewGroup.LayoutParams(-2,dpRaw(48)));UiMetrics.enforceMinTouchTarget(t,48);}
  Runnable update=()->{
   if(!gameSupported)mode="chat";
   boolean isChat=mode.equals("chat");
   chat.setSelected(isChat);games.setSelected(!isChat);
   chat.setTypeface(null,isChat?Typeface.BOLD:Typeface.NORMAL);
   games.setTypeface(null,!isChat?Typeface.BOLD:Typeface.NORMAL);
   chat.setTextColor(isChat?ink:muted);games.setTextColor(!isChat?ink:muted);
   chat.setBackground(isChat?box(DARK_ACTIVE_CHIP,999,purple):null);
   games.setBackground(!isChat?box(DARK_ACTIVE_CHIP,999,purple):null);
   if(chat.getCompoundDrawablesRelative()[0]!=null)chat.getCompoundDrawablesRelative()[0].setTint(isChat?purple:muted);
   if(games.getCompoundDrawablesRelative()[0]!=null)games.getCompoundDrawablesRelative()[0].setTint(!isChat?purple:muted);
   gameOptions.setVisibility(!isChat?View.VISIBLE:View.GONE);
   soundToggle.setVisibility(!isChat?View.VISIBLE:View.GONE);
   flipChip.setVisibility(isChat?View.VISIBLE:View.GONE);
   beautyChip.setVisibility(isChat?View.VISIBLE:View.GONE);
   commentsToggle.setVisibility(View.VISIBLE);
   if(commentsToggle.getTag() instanceof Runnable)((Runnable)commentsToggle.getTag()).run();
   if(dialog!=null&&dialog.getWindow()!=null)dialog.getWindow().getDecorView().post(this::syncDialogHeight);
  };
  chat.setOnClickListener(v->{mode="chat";comments.setChecked(chatComments[0]);update.run();});
  games.setOnClickListener(v->{if(!gameSupported)return;mode="game";comments.setChecked(gameOverlay[0]);update.run();});
  update.run();
  Button start=new KinnectButton(activity);start.setAllCaps(false);start.setStateListAnimator(null);start.setText(I18n.t("Bắt đầu"));start.setTextSize(14);start.setTypeface(ApprovedTypography.font(activity,Typeface.BOLD));start.setGravity(Gravity.CENTER);start.setTextColor(0xffffffff);start.setMinHeight(dpRaw(50));start.setMinimumHeight(dpRaw(50));
  start.setBackground(new RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff),box(liveRed,999,0),null));
  startButton=start;
  Runnable launchLive=()->{
   start.setEnabled(false);
   if(dialog!=null)dialog.dismiss();
   if(activity instanceof StudioActivity)((StudioActivity)activity).releaseForLiveHandoff();
   Intent liveIntent=new Intent(activity,LiveActivity.class)
     .putExtra(LiveActivity.EXTRA_HOST,true)
     .putExtra("cameraSetup",true)
     .putExtra("liveMode",mode)
     .putExtra("gameTitle",game)
     .putExtra("topic",topic)
     .putExtra("title",title.getText().toString().trim())
     .putExtra("front",front)
     .putExtra("filter",fx.filter)
     .putExtra("sticker",fx.sticker)
     .putExtra("beauty",fx.beautyOn)
     .putExtra("smooth",fx.smooth)
     .putExtra("blemish",fx.blemish)
     .putExtra("eyes",fx.eyes)
     .putExtra("lips",fx.lips)
     .putExtra("mic",mic.isChecked())
     .putExtra("sound",sound.isChecked())
     .putExtra("comments",comments.isChecked());
   activity.startActivity(liveIntent);
   if(activity instanceof StudioActivity)activity.finish();
  };
  start.setOnClickListener(v->{
   if(mode.equals("game")){
    if(!gameSupported){mode="chat";update.run();return;}
    if(LiveGameLaunch.intent(activity,game)==null){Toast.makeText(activity,I18n.t(game.isEmpty()?"Hãy chọn game trước.":"Không tìm thấy game trên máy. Hãy cài game hoặc chọn game khác."),Toast.LENGTH_LONG).show();return;}
    LiveGamePass.ensure(activity,()->{
     if(mode.equals("game")&&LiveGameLaunch.intent(activity,game)==null){Toast.makeText(activity,I18n.t(game.isEmpty()?"Hãy chọn game trước.":"Không tìm thấy game trên máy. Hãy cài game hoặc chọn game khác."),Toast.LENGTH_LONG).show();return;}
     launchLive.run();
    });
   }else{
    launchLive.run();
   }
  });
  LinearLayout container=new LinearLayout(activity);container.setOrientation(LinearLayout.VERTICAL);
  container.addView(body,new LinearLayout.LayoutParams(-1,-2));
  toggles.setPadding(0,dp(10),0,0);
  container.addView(toggles,new LinearLayout.LayoutParams(-1,-2));
  LinearLayout.LayoutParams footer=new LinearLayout.LayoutParams(-1,dpRaw(50));footer.topMargin=dp(14);
  container.addView(start,footer);UiMetrics.enforceMinTouchTarget(start,48);

  dialog=new Dialog(activity);
  dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
  dialog.setCancelable(true);
  dialog.setCanceledOnTouchOutside(true);
  LinearLayout sheetBox=new LinearLayout(activity);
  sheetBox.setOrientation(LinearLayout.VERTICAL);
  sheetBox.setPadding(dp(22),dp(14),dp(22),dp(22));
  GradientDrawable shape=new GradientDrawable();
  shape.setColor(DARK_SURFACE);
  float r=dpRaw(28);
  shape.setCornerRadii(new float[]{r,r,r,r,0,0,0,0});
  View grip=new View(activity);
  grip.setBackground(box(line,99,0));
  LinearLayout.LayoutParams gp=new LinearLayout.LayoutParams(dpRaw(32),dpRaw(4));
  gp.gravity=Gravity.CENTER_HORIZONTAL;gp.bottomMargin=dp(16);
  sheetBox.addView(grip,gp);
  LinearLayout headerRow=new LinearLayout(activity);
  headerRow.setGravity(Gravity.CENTER_VERTICAL);
  headerRow.setPadding(0,0,0,dp(10));
  TextView sheetTitle=new KinnectText(activity);
  sheetTitle.setText(I18n.t("Phát trực tiếp"));
  sheetTitle.setTextSize(22);
  sheetTitle.setTextColor(ink);
  sheetTitle.setTag("sheet:title");
  sheetTitle.setTypeface(ApprovedTypography.font(activity,Typeface.NORMAL));
  headerRow.addView(sheetTitle,new LinearLayout.LayoutParams(0,-2,1));
  String closeGlyph=WebIcons.resolve(activity,"close")!=0?"close":"x";
  ImageView closeBtn=new ImageView(activity);
  Drawable closeDrawable=WebIcons.load(activity,closeGlyph).mutate();
  closeDrawable.setTint(ink);
  closeBtn.setImageDrawable(closeDrawable);
  closeBtn.setPadding(dp(8),dp(8),dp(8),dp(8));
  closeBtn.setBackground(box(soft,999,line));
  closeBtn.setContentDescription(I18n.t("Đóng"));
  closeBtn.setOnClickListener(v->close());
  closeBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(36),dp(36)));
  headerRow.addView(UiMetrics.wrapMinTouchTarget(activity,closeBtn,48));
  sheetBox.addView(headerRow,new LinearLayout.LayoutParams(-1,-2));
  sheetBox.addView(container,new LinearLayout.LayoutParams(-1,-2));
  ScrollView outer=new ScrollView(activity);
  outer.setFillViewport(false);
  outer.addView(sheetBox,new ViewGroup.LayoutParams(-1,-2));
  final LinearLayout surface=new LinearLayout(activity){
   @Override protected void onMeasure(int widthMeasureSpec,int heightMeasureSpec){
    int screenH=activity.getResources().getDisplayMetrics().heightPixels;
    int maxTotal=screenH*9/10;
    int hMode=MeasureSpec.getMode(heightMeasureSpec);
    int hSize=MeasureSpec.getSize(heightMeasureSpec);
    int limit=(hMode==MeasureSpec.UNSPECIFIED||hSize<=0)?maxTotal:Math.min(hSize,maxTotal);
    int wSize=MeasureSpec.getSize(widthMeasureSpec);
    int innerW=Math.max(0,wSize-getPaddingLeft()-getPaddingRight());
    int padV=getPaddingTop()+getPaddingBottom();
    View child=getChildCount()>0?getChildAt(0):null;
    int chH=0;
    if(child!=null&&child.getVisibility()!=GONE){
     child.measure(MeasureSpec.makeMeasureSpec(innerW,MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(Math.max(0,limit-padV),MeasureSpec.AT_MOST));
     chH=child.getMeasuredHeight();
    }
    setMeasuredDimension(resolveSize(wSize,widthMeasureSpec),hMode==MeasureSpec.EXACTLY?hSize:Math.min(limit,padV+chH));
   }
  };
  surface.setOrientation(LinearLayout.VERTICAL);
  surface.setBackground(shape);
  surface.addView(outer,new LinearLayout.LayoutParams(-1,-2));
  dialog.setContentView(surface);
  Window w=dialog.getWindow();
  if(w!=null){
   w.setBackgroundDrawable(new ColorDrawable(0));
   w.setGravity(Gravity.BOTTOM);
   w.setDimAmount(0.48f);
   w.setWindowAnimations(android.R.style.Animation_InputMethod);
   w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
  }
  try{dialog.show();}catch(RuntimeException badToken){return;}
  start.setTextColor(0xffffffff);
  if(w!=null){
   ApprovedTypography.sheet(w.getDecorView());
   w.getDecorView().setOnApplyWindowInsetsListener((v,insets)->{
    int leftInset,rightInset,sysBottom,imeBottom;
    if(android.os.Build.VERSION.SDK_INT>=30){
     android.graphics.Insets sys=insets.getInsets(WindowInsets.Type.systemBars());
     android.graphics.Insets ime=insets.getInsets(WindowInsets.Type.ime());
     leftInset=sys.left;rightInset=sys.right;sysBottom=sys.bottom;imeBottom=ime.bottom;
    }else{
     leftInset=insets.getSystemWindowInsetLeft();rightInset=insets.getSystemWindowInsetRight();sysBottom=insets.getSystemWindowInsetBottom();imeBottom=0;
    }
    int neededBottom=(imeBottom>sysBottom)?dp(12):Math.max(dp(12),sysBottom);
    surface.setPadding(leftInset,0,rightInset,neededBottom);
    return insets;
   });
   syncDialogHeight();
  }
 }
 void close(){if(picker!=null)picker.close();if(dialog!=null)dialog.dismiss();}
}
