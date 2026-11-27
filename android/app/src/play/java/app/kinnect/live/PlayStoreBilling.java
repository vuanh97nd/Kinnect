package app.kinnect.live;
import android.app.Activity;import com.android.billingclient.api.*;import java.util.*;import java.util.concurrent.ConcurrentHashMap;

/** One-time non-consumable products. All grants and acknowledgements happen on the server. */
public final class PlayStoreBilling implements StoreBilling, PurchasesUpdatedListener {
 private final Activity activity;private BillingClient client;private Events events;private String account;private List<String> ids;private final Map<String,ProductDetails> details=new ConcurrentHashMap<>();private volatile boolean closed;
 public PlayStoreBilling(Activity activity){this.activity=activity;}
 public void connect(List<String> products,String user,Events events){
  this.ids=products==null?new ArrayList<>():new ArrayList<>(products);this.account=user;this.events=events;
  if(client!=null){try{client.endConnection();}catch(Exception ignored){}client=null;}
  client=BillingClient.newBuilder(activity).setListener(this).enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()).enableAutoServiceReconnection().build();
  client.startConnection(new BillingClientStateListener(){public void onBillingSetupFinished(BillingResult result){if(closed)return;if(result.getResponseCode()==BillingClient.BillingResponseCode.OK){query();queryPurchases(true);}else unavailable();}public void onBillingServiceDisconnected(){}});
 }
 private static ProductDetails.OneTimePurchaseOfferDetails primaryOffer(ProductDetails product){
  if(product==null)return null;
  List<ProductDetails.OneTimePurchaseOfferDetails> offers=product.getOneTimePurchaseOfferDetailsList();
  if(offers!=null&&!offers.isEmpty())for(ProductDetails.OneTimePurchaseOfferDetails offer:offers)if(offer!=null)return offer;
  return product.getOneTimePurchaseOfferDetails();
 }
 private void unavailable(){if(events!=null){events.message(I18n.t("Google Play chưa sẵn sàng. Bạn vẫn có thể xem thử sản phẩm."));events.prices(Collections.emptyMap());}}
 private void query(){if(ids==null||ids.isEmpty()){if(events!=null)events.prices(Collections.emptyMap());return;}List<QueryProductDetailsParams.Product> products=new ArrayList<>();for(String id:ids)products.add(QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(BillingClient.ProductType.INAPP).build());client.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder().setProductList(products).build(),(result,answer)->{if(closed)return;Map<String,String> prices=new HashMap<>();Map<String,ProductDetails> fresh=new HashMap<>();if(result.getResponseCode()==BillingClient.BillingResponseCode.OK&&answer!=null&&answer.getProductDetailsList()!=null)for(ProductDetails product:answer.getProductDetailsList()){ProductDetails.OneTimePurchaseOfferDetails offer=primaryOffer(product);if(offer==null)continue;fresh.put(product.getProductId(),product);prices.put(product.getProductId(),offer.getFormattedPrice());}details.putAll(fresh);details.keySet().retainAll(fresh.keySet());if(events!=null)events.prices(prices);});}
 public void buy(String id){
  if(closed||client==null){unavailable();return;}
  ProductDetails p=details.get(id);if(p==null){if(events!=null)events.message(I18n.t("Google Play chưa sẵn sàng. Bạn vẫn có thể xem thử sản phẩm."));return;}
  ProductDetails.OneTimePurchaseOfferDetails offer=primaryOffer(p);if(offer==null){if(events!=null)events.message(I18n.t("Google Play chưa sẵn sàng. Bạn vẫn có thể xem thử sản phẩm."));return;}
  BillingFlowParams.ProductDetailsParams.Builder item=BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(p);
  String token=offer.getOfferToken();if(token!=null&&!token.isEmpty())item.setOfferToken(token);
  BillingFlowParams.Builder flow=BillingFlowParams.newBuilder().setProductDetailsParamsList(Collections.singletonList(item.build()));
  if(account!=null&&!account.isEmpty()&&account.length()<=64)flow.setObfuscatedAccountId(account);
  try{
   BillingResult result=client.launchBillingFlow(activity,flow.build());
   if(result.getResponseCode()==BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED)restore();else if(result.getResponseCode()!=BillingClient.BillingResponseCode.OK&&events!=null)events.message(I18n.t("Chưa mở được thanh toán Google Play."));
  }catch(Exception ignored){
   if(events!=null)events.message(I18n.t("Chưa mở được thanh toán Google Play."));
  }
 }
 public void restore(){queryPurchases(false);}
 private void queryPurchases(final boolean unacknowledgedOnly){if(closed||client==null)return;try{client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),(result,purchases)->{if(closed)return;if(result.getResponseCode()==BillingClient.BillingResponseCode.OK)accept(purchases,unacknowledgedOnly);else if(!unacknowledgedOnly&&events!=null)events.message(I18n.t("Chưa khôi phục được giao dịch. Hãy thử lại."));});}catch(Exception ignored){if(!unacknowledgedOnly&&events!=null)events.message(I18n.t("Chưa khôi phục được giao dịch. Hãy thử lại."));}}
 private void accept(List<Purchase> purchases,boolean unacknowledgedOnly){if(purchases==null)return;for(Purchase purchase:purchases){if(purchase.getPurchaseState()==Purchase.PurchaseState.PENDING){if(!unacknowledgedOnly&&events!=null)events.message(I18n.t("Giao dịch đang chờ xử lý; chưa cấp quyền lợi."));continue;}if(purchase.getPurchaseState()!=Purchase.PurchaseState.PURCHASED)continue;if(unacknowledgedOnly&&purchase.isAcknowledged())continue;for(String id:purchase.getProducts())if(ids!=null&&ids.contains(id)&&events!=null)events.receipt(id,purchase.getPurchaseToken());}}
 public void onPurchasesUpdated(BillingResult result,List<Purchase> purchases){if(closed)return;int code=result.getResponseCode();if(code==BillingClient.BillingResponseCode.OK)accept(purchases,false);else if(code==BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED)restore();else if(code!=BillingClient.BillingResponseCode.USER_CANCELED&&events!=null)events.message(I18n.t("Giao dịch chưa hoàn tất. Hãy kiểm tra Google Play trước khi thử lại."));}
 public void close(){closed=true;if(client!=null)client.endConnection();}
}
