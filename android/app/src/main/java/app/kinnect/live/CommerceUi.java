package app.kinnect.live;
import android.app.*;import android.content.*;import android.graphics.*;import android.graphics.drawable.*;import android.view.*;import android.widget.*;

/** Compact native commerce components, sharing Kinnect typography and icons. */
final class CommerceUi {
 final Activity a;final int ink,muted,card,soft,purple,bg;
 CommerceUi(Activity a){this.a=a;int v=WebTheme.isDark(a)?1:0;ink=WebDesign.INK[v];muted=WebDesign.MUTED[v];card=WebDesign.CARD[v];soft=WebDesign.WASH[v];purple=WebDesign.PURPLE[v];bg=WebDesign.BG[v];}
 int dp(int n){return Math.round(n*a.getResources().getDisplayMetrics().density*WebDesign.UI_SCALE);}
 LinearLayout col(){LinearLayout l=new LinearLayout(a);l.setOrientation(1);return l;}
 LinearLayout row(){LinearLayout l=new LinearLayout(a);l.setGravity(Gravity.CENTER_VERTICAL);l.setBaselineAligned(false);return l;}
 GradientDrawable round(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
 GradientDrawable gradient(){GradientDrawable d=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff5d36d6,0xff9655ec,0xffd35ab6});d.setCornerRadius(dp(24));return d;}
 TextView text(String value,int size,int color,boolean bold){TextView t=new KinnectText(a);t.setText(I18n.t(value));t.setTextSize(size);t.setTextColor(color);t.setTypeface(ApprovedTypography.font(a,bold?Typeface.BOLD:Typeface.NORMAL));return t;}
 Drawable glyph(String name,int color,int size){Drawable d=WebIcons.load(a,name);d.setTint(color);d.setBounds(0,0,dp(size),dp(size));return d;}
 FrameLayout icon(String name,String title,Runnable click){FrameLayout b=new FrameLayout(a);b.setContentDescription(I18n.t(title));b.setBackground(new RippleDrawable(android.content.res.ColorStateList.valueOf(0x22415f91),round(soft,99),null));ImageView i=new ImageView(a);i.setImageDrawable(glyph(name,purple,24));b.addView(i,new FrameLayout.LayoutParams(dp(24),dp(24),Gravity.CENTER));b.setOnClickListener(v->click.run());b.setMinimumHeight(dp(48));b.setMinimumWidth(dp(48));return b;}
 Button action(String title,String icon,Runnable click){Button b=new KinnectButton(a);b.setAllCaps(false);b.setText(I18n.t(title));b.setTextSize(14);b.setTextColor(Color.WHITE);b.setTypeface(ApprovedTypography.font(a,Typeface.BOLD));b.setMinWidth(0);b.setMinimumWidth(0);b.setMinHeight(dp(48));b.setPadding(dp(16),dp(12),dp(16),dp(12));b.setBackground(new RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff),round(purple,99),null));if(icon!=null){b.setCompoundDrawablesRelative(glyph(icon,Color.WHITE,20),null,null,null);b.setCompoundDrawablePadding(dp(8));}b.setOnClickListener(v->click.run());b.setOnTouchListener((v,e)->{if(e.getActionMasked()==MotionEvent.ACTION_DOWN)v.animate().scaleX(.97f).scaleY(.97f).setDuration(WebDesign.MOTION_FAST).start();else if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL)v.animate().scaleX(1f).scaleY(1f).setDuration(WebDesign.MOTION_BASE).start();return false;});return b;}
 TextView badge(String title){TextView t=text(title,12,purple,true);t.setGravity(Gravity.CENTER);t.setPadding(dp(12),dp(6),dp(12),dp(6));t.setBackground(round(soft,99));return t;}
 LinearLayout header(String title,View...actions){LinearLayout line=row();line.setPadding(dp(16),dp(12),dp(16),dp(12));line.addView(icon("arrow_left","Quay lại",a::finish),new LinearLayout.LayoutParams(dp(48),dp(48)));TextView name=text(title,22,ink,true);name.setPadding(dp(16),0,dp(8),0);line.addView(name,new LinearLayout.LayoutParams(0,-2,1));for(View action:actions){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(dp(48),dp(48));p.leftMargin=dp(8);line.addView(action,p);}return line;}
 LinearLayout section(){LinearLayout l=col();l.setPadding(dp(20),dp(20),dp(20),dp(20));l.setBackground(round(card,24));l.setElevation(dp(2));return l;}
 void add(LinearLayout parent,View child,int margin){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=dp(margin);parent.addView(child,p);}
 View empty(String icon,String title){LinearLayout l=col();l.setPadding(dp(16),dp(24),dp(16),dp(24));l.setGravity(Gravity.CENTER);ImageView art=new ImageView(a);art.setImageDrawable(glyph(icon,purple,32));l.addView(art,new LinearLayout.LayoutParams(dp(40),dp(40)));TextView label=text(title,14,muted,false);label.setGravity(Gravity.CENTER);label.setPadding(0,dp(10),0,0);l.addView(label);return l;}
 void moneyUnavailable(String title){new Sheet(a).setTitle(I18n.t(title)).setItemIcon("clock").setMessage(I18n.t("Chưa mở thanh toán. Không phát sinh giao dịch.")).setPositiveButton(I18n.t("Đóng"),null).show();}
 void go(Class<?> target){a.startActivity(new Intent(a,target).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));}
}
