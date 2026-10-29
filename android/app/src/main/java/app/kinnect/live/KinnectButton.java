package app.kinnect.live;
import android.content.Context;import android.graphics.Typeface;import android.widget.Button;
final class KinnectButton extends Button {
 KinnectButton(Context c){super(c);setTypeface(ApprovedTypography.font(c,Typeface.BOLD));}
 @Override public void setTypeface(Typeface face,int style){super.setTypeface(ApprovedTypography.font(getContext(),style));}
 @Override public void setTypeface(Typeface face){setTypeface(face,face==null?Typeface.NORMAL:face.getStyle());}
}
