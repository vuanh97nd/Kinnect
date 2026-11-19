package app.kinnect.live;
import android.app.Activity;import java.util.*;
/** The website APK has no checkout. Only the Play variant provides a billing implementation. */
interface StoreBilling {
 interface Events {void prices(Map<String,String> prices);void receipt(String product,String token);void message(String message);}
 void connect(List<String> products,String account,Events events);void buy(String product);void restore();void close();
 static StoreBilling create(Activity activity){
  if(Distribution.PLAY)try{return (StoreBilling)Class.forName("app.kinnect.live.PlayStoreBilling").getConstructor(Activity.class).newInstance(activity);}catch(Exception ignored){}
  return new StoreBilling(){Events events;public void connect(List<String> ids,String account,Events e){events=e;e.prices(Collections.emptyMap());}public void buy(String id){events.message(I18n.t("Thanh toán chưa khả dụng trên bản này."));}public void restore(){events.message(I18n.t("Quyền lợi đã mua được đồng bộ theo tài khoản Kinnect."));}public void close(){}};
 }
}
