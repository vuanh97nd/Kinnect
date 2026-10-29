package app.kinnect.live;
import android.app.Activity;import com.android.billingclient.api.*;import java.util.*;

/** One-time non-consumable products. All grants and acknowledgements happen on the server. */
public final class PlayStoreBilling implements StoreBilling, PurchasesUpdatedListener {
 private final Activity activity;private BillingClient client;private Events events;private String account;private List<String> ids;private final Map<String,ProductDetails> details=new HashMap<>();private boolean closed;
 public PlayStoreBilling(Activity activity){this.activity=activity;}
 public void connect(List<String> products,String user,Events events){
  this.ids=new ArrayList<>(products);this.account=user;this.events=events;
  client=BillingClient.newBuilder(activity).setListener(this).enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()).enableAutoServiceReconnection().build();
  client.startConnection(new BillingClientStateListener(){public void onBillingSetupFinished(BillingResult result){if(closed)return;if(result.getResponseCode()==BillingClient.BillingResponseCode.OK){query();restore();}else unavailable();}public void onBillingServiceDisconnected(){if(!closed)unavailable();}});
 }
 private void unavailable(){events.message(I18n.t("Google Play chưa sẵn sàng. Bạn vẫn có thể xem thử sản phẩm."));events.prices(Collections.emptyMap());}
 private void query(){List<QueryProductDetailsParams.Product> products=new ArrayList<>();for(String id:ids)products.add(QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(BillingClient.ProductType.INAPP).build());client.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(products).build(),(result,answer)->{if(closed)return;Map<String,String> prices=new HashMap<>();details.clear();if(result.getResponseCode()==BillingClient.BillingResponseCode.OK)for(ProductDetails product:answer.getProductDetailsList()){if(product.getOneTimePurchaseOfferDetails()==null)continue;details.put(product.getProductId(),product);prices.put(product.getProductId(),product.getOneTimePurchaseOfferDetails().getFormattedPrice());}events.prices(prices);});}
 public void buy(String id){
  if(closed||client==null||!client.isReady()||!details.containsKey(id)){unavailable();return;}
  ProductDetails p=details.get(id);BillingFlowParams.ProductDetailsParams.Builder item=BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(p);
  String token=p.getOneTimePurchaseOfferDetails().getOfferToken();if(token!=null&&!token.isEmpty())item.setOfferToken(token);
  BillingResult result=client.launchBillingFlow(activity,BillingFlowParams.newBuilder().setObfuscatedAccountId(account).setProductDetailsParamsList(Collections.singletonList(item.build())).build());
  if(result.getResponseCode()==BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED)restore();else if(result.getResponseCode()!=BillingClient.BillingResponseCode.OK)events.message(I18n.t("Chưa mở được thanh toán Google Play."));
 }
 public void restore(){if(closed||client==null||!client.isReady())return;client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),(result,purchases)->{if(closed)return;if(result.getResponseCode()==BillingClient.BillingResponseCode.OK)accept(purchases);else events.message(I18n.t("Chưa khôi phục được giao dịch. Hãy thử lại."));});}
 private void accept(List<Purchase> purchases){if(purchases==null)return;for(Purchase purchase:purchases){if(purchase.getPurchaseState()==Purchase.PurchaseState.PENDING){events.message(I18n.t("Giao dịch đang chờ xử lý; chưa cấp quyền lợi."));continue;}if(purchase.getPurchaseState()!=Purchase.PurchaseState.PURCHASED)continue;for(String id:purchase.getProducts())if(ids.contains(id))events.receipt(id,purchase.getPurchaseToken());}}
 public void onPurchasesUpdated(BillingResult result,List<Purchase> purchases){if(closed)return;int code=result.getResponseCode();if(code==BillingClient.BillingResponseCode.OK)accept(purchases);else if(code==BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED)restore();else if(code!=BillingClient.BillingResponseCode.USER_CANCELED)events.message(I18n.t("Giao dịch chưa hoàn tất. Hãy kiểm tra Google Play trước khi thử lại."));}
 public void close(){closed=true;if(client!=null)client.endConnection();}
}
