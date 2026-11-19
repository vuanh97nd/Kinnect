package app.kinnect.live;
import java.util.*;
final class RegistrationBadge {
  static boolean today(long created,long now){if(created<=0||created>now)return false;Calendar day=Calendar.getInstance(TimeZone.getTimeZone("Asia/Ho_Chi_Minh"));day.setTimeInMillis(now);day.set(Calendar.HOUR_OF_DAY,0);day.set(Calendar.MINUTE,0);day.set(Calendar.SECOND,0);day.set(Calendar.MILLISECOND,0);long start=day.getTimeInMillis();day.add(Calendar.DATE,1);return created>=start&&created<day.getTimeInMillis();}
}
