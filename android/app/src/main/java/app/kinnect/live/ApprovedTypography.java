package app.kinnect.live;
import android.content.Context;import android.graphics.Typeface;
final class ApprovedTypography {static Typeface normal,bold;static Typeface font(Context c,int style){if(normal==null)normal=c.getResources().getFont(c.getResources().getIdentifier("kinnect_regular","font",c.getPackageName()));if(bold==null)bold=c.getResources().getFont(c.getResources().getIdentifier("kinnect_semibold","font",c.getPackageName()));return Typeface.create((style&Typeface.BOLD)!=0?bold:normal,style);}}
