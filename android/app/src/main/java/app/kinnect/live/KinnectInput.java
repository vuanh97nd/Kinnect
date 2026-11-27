package app.kinnect.live;
import android.content.Context;import android.graphics.Typeface;import android.widget.EditText;
/** The same bundled family as labels, including password and numeric fields. */
final class KinnectInput extends EditText {
 KinnectInput(Context c){
  super(c);
  setTypeface(ApprovedTypography.font(c,Typeface.NORMAL));
  int p = UiMetrics.dpRaw(c, 16);
  int pt = UiMetrics.dpRaw(c, 14);
  setPadding(p, pt, p, pt);
  int min = UiMetrics.dpRaw(c, 48);
  setMinHeight(min);
  setMinimumHeight(min);
 }
 @Override public void setTypeface(Typeface face,int style){super.setTypeface(ApprovedTypography.font(getContext(),style));}
 @Override public void setTypeface(Typeface face){setTypeface(face,face==null?Typeface.NORMAL:face.getStyle());}
 @Override public void setInputType(int type){super.setInputType(type);setTypeface(ApprovedTypography.font(getContext(),Typeface.NORMAL));}
}
