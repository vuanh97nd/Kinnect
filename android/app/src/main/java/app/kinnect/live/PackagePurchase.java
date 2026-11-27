package app.kinnect.live;
import android.app.*;import android.widget.*;import org.json.*;
/** One explicit source selection, one nonce and one server-confirmed grant. */
final class PackagePurchase {
 private static final java.util.Set<Activity> pending=java.util.Collections.newSetFromMap(new java.util.WeakHashMap<Activity,Boolean>());
 static void buy(Activity a,JSONObject p,JSONObject state,Runnable done,Runnable use){
  if(!pending.add(a))return;
  boolean trial=state.optBoolean("trialPackagePurchases");
  long giftedBal=state.optLong("giftedCoins",state.optLong("trialCoins")),paidBal=state.optLong("purchasedCoins");
  String[] sources=trial?new String[]{"gifted","purchased"}:new String[]{"purchased"};
  String[] labels=trial?new String[]{I18n.t("Xu tặng")+" · "+giftedBal,I18n.t("Xu mua")+" · "+paidBal}:new String[]{I18n.t("Xu mua")+" · "+paidBal};
  Dialog sourceDialog=new Sheet(a).setTitle(I18n.t("Chọn nguồn xu")).setItems(labels,(d,n)->{
   String source=sources[n];
   long balance=source.equals("gifted")?giftedBal:paidBal,cost=p.optLong("priceCoins");
   if(balance<cost){pending.remove(a);Toast.makeText(a,I18n.t("Chưa đủ xu."),Toast.LENGTH_LONG).show();return;}
   final String nonce=java.util.UUID.randomUUID().toString();
   Dialog confirmDialog=new Sheet(a).setTitle(p.optString("name")).setMessage(cost+" "+I18n.t("xu")+" · "+I18n.t(source.equals("gifted")?"Xu tặng":"Xu mua")+"\n"+p.optString("period")+"\n\n"+I18n.t("Có xác nhận trước khi trừ xu. Không tự gia hạn.")).setPositiveButton(I18n.t("Xác nhận mua"),(dialog,w)->{
    try{
     NativeApi.shared.call("POST","/api/store/packages/buy",new JSONObject().put("productId",p.optString("id")).put("priceCoins",cost).put("requestId",nonce).put("coinSource",source),null,(result,error,status)->{
      pending.remove(a);
      if(a.isFinishing()||a.isDestroyed())return;
      if(error!=null){
       String trimmed=error.trim();
       String fallback=status==402?"Chưa đủ xu.":status==403?"Thử nghiệm đã kết thúc. Gói mới cần Xu mua.":"Chưa mua được gói. Hãy tải lại cửa hàng.";
       Toast.makeText(a,I18n.t(trimmed.isEmpty()?fallback:trimmed),Toast.LENGTH_LONG).show();
       return;
      }
      if(done!=null)done.run();
      if(result==null||!result.optBoolean("duplicate"))SuccessEffects.purchase(a,p,use);
     },()->pending.remove(a));
    }catch(Exception e){pending.remove(a);Toast.makeText(a,I18n.t("Chưa mua được gói."),Toast.LENGTH_LONG).show();}
   }).setNegativeButton(I18n.t("Hủy"),(dialog,w)->pending.remove(a)).show();
   confirmDialog.setOnCancelListener(dialog->pending.remove(a));
   if(!confirmDialog.isShowing())pending.remove(a);
  }).setNegativeButton(I18n.t("Hủy"),(d,w)->pending.remove(a)).show();
  sourceDialog.setOnCancelListener(d->pending.remove(a));
  if(!sourceDialog.isShowing())pending.remove(a);
 }
}
