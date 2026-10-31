package app.kinnect.live;
import android.content.Context;import android.graphics.Typeface;
final class ApprovedTypography {
  static Typeface font(Context c, int style) {
    if ((style & Typeface.BOLD) != 0) return Typeface.create("sans-serif-medium", style);
    return Typeface.create("sans-serif", style);
  }
  static void sheet(android.view.View view){if(view instanceof android.widget.TextView){android.widget.TextView text=(android.widget.TextView)view;String value=text.getText().toString();if(value.codePoints().anyMatch(Character::isLetterOrDigit)||text instanceof android.widget.EditText){int style=text.getTypeface()==null?Typeface.NORMAL:text.getTypeface().getStyle();text.setTypeface(font(view.getContext(),style));float size=text.getTextSize()/view.getResources().getDisplayMetrics().scaledDensity;Object tag=text.getTag();float max="sheet:title".equals(tag)?22:"sheet:display".equals(tag)?28:"sheet:heading".equals(tag)?20:text instanceof android.widget.Button?15:text instanceof android.widget.EditText?16:15;if(size>max)text.setTextSize(max);}}if(view instanceof android.view.ViewGroup){android.view.ViewGroup group=(android.view.ViewGroup)view;for(int i=0;i<group.getChildCount();i++)sheet(group.getChildAt(i));}}
}
