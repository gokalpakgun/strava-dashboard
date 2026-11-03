# Tempo Çember: bağlı TestFlight beta sürümü

## Uygulama akışı

Sosyal → Tempo Çember. En az üç karşılıklı arkadaş gerekir. Oluşturucu iki ila beş arkadaş seçer; sunucu tüm ikili arkadaşlıkları/engelleri kontrol eder. Diğer üyeler hem Çember listesinde daveti görür hem mevcut APNs altyapısından nötr bir davet bildirimi alabilir. Herkes kendi kredi/paylaşım şartlarını ayrıca kabul eder.

Varsayılan dönem gelecek pazartesi 00:00 UTC başlayıp yedi gün sürer: üç uygun gün ve 20 grup kredisi. İlk kabulde bakiye 100'den 80'e, kilitli tutar 20'ye geçer. Aynı kabulün tekrarı ikinci kez kesmez. Yeni hafta için yeniden açık kabul gerekir; otomatik borç/gerçek para/ödül yoktur.

## Gerçek bağlantılar

- `TempoCircle.swift`: canlı sunucu snapshot'ı, grup oluşturma, açık kabul, bakiye/kilitli tutar, üye ilerlemesi, durum, hayalet sonucu, tercihler, ara verme ve ayrılma ekranları. Mevcut sosyal ekran/arkadaşlık özellikleri korunur. Açık/koyu mod mevcut TempoTheme ile çalışır.
- `TempoHealthApp` + `TempoCircleStore`: aynı Tempo hesabı geri yüklendiğinde ve Sağlık/pasif algılama güncellendiğinde otomatik eşitleme. Çember'e katılım yoksa seans yüklenmez. Eşitleme en fazla iki dakikada bir; çevrimdışı geçmiş son yedi günün kaynaklarından tekrar elde edilir. Kullanıcı spor sırasında ekrana dokunmaz.
- `TempoHealthStore`: orijinal HKWorkout'un elle girilme bayrağı korunur. Elle girilmiş veya eski/kanıtı olmayan cache kayıtları sosyal seans sayılmaz. Sağlık sinyalli günler için 15 dakika–4 saat ve en az %70 gözlenen nabız zaman kapsaması gerekir. Salon günleri yalnız CoreLocation ziyaretleridir; birbirinin yerine sayılmaz.
- `passive-social-live.js`: oturumla yetkilendirilmiş API, grup ve üye kontrolleri, kaynak/süre/tekrar sınırları, sunucu saati, istek kotası, ayrı grup izinleri. Çember ve alıcı başına SQLite Durable Object; mevcut KV para/rehin defteri olarak kullanılmaz.
- `PassiveCohort`: tek sıralı komut kapısı ve tek aggregate yazısı içinde bakiye/escrow/settlement/outbox saklanır. Dönem alarmları otomatik sonuçlandırır. Kayıtlı settlement tekrar ödeme yapmaz. Sonuç bildirimleri kalıcı outbox ve mevcut NotificationInbox kimlikleriyle tekilleşir.
- `PassiveRecipient`: alıcı başına tüm gruplarda 24 saatte bir dürtme. Sessiz saat 22:00–08:00; saat dilimi eşitlemede güncellenir. Gönderim öncesinde arkadaşlık, grup tercihi ve güncel aktiflik tekrar kontrol edilir. İzin iptalinden sonra kuyruktaki dürtme düşürülür.
- `deleteAccount`: Çember verilerini de kapatır ve ilgili grup görünürlüğünü durdurur. İzin geri çekme/ara verme, sonuçlanmamış haftada iade oluşturur. Çemberden ayrılma kapalı üyeliği sonlandırır; diğer üyeler eski grupta yarışmaya devam etmez.

## Hayalet karşılaşmasının çalışan kapsamı

Hayalet eğrisi paylaşımı üyeye ayrı ve varsayılan kapalı bir tercihtir. Açılırsa yeterli orijinal nabız örnekleri dakikalık normalize efor eğrisine çevrilir; ham bpm veya rota arkadaşlara verilmez. Referans maksimum nabız mevcut zon analizinden gelir ve tahmin içerebilir. Bu bir bilimsel performans üstünlüğü skoru değildir.

A'nın uygun ve izinli eğrisi eşitlendiğinde B için sonraki antrenmana ait eşleşme dondurulur. B'nin eşleşmeden sonra başlayan, aynı branştaki uygun seansı eşitlenince sonuç hesaplanır. Her iki kişiye tek sonuç olayı hazırlanır. Seyrek/uyumsuz veride “veri yetersiz” sonucu vardır. Eforu yüksek olana kazanan veya ek rehin ödülü verilmez. Profil 7 gün, bekleyen eşleşme en fazla 24 saat saklanır; sonuç 30 gün tutulur.

**Bu sürüm gerçek zamanlı Watch ses/haptik/Live Activity içermez.** Mevcut tamamlanmış HKWorkout okuması anlık workout mirroring olarak sunulmaz. Çember ekranında bu sınır açıkça yazılıdır. Bunun için ayrıca watchOS target/gerçek workout session sağlayıcısı ve Activity extension/signing kurulumu gerekir.

## Güven seviyesi: cihaz bildirimi

API yalnız giriş yapılmış ve açık izin vermiş üyeden veri alır; manuel/Strava kaynakları, desteklenmeyen süreler, yetersiz kapsam ve tekrarlar reddedilir. Ancak sunucu fiziksel egzersizi veya HealthKit örneklerini bağımsız doğrulayamaz. App Attest doğrulayıcısı bu sürümde yoktur. Uygulama ve API `device-reported-v1` olarak açık etiketlidir; “hile yapılamaz”, “kesin doğrulanmış biyometri” veya tıbbi anlam taşıyan etiket kullanılmaz.

Tamamlanan Sağlık sorgusu veya açık Always-konum bölge takibi cihazdan kapsama bildirimi verir. Sunucu ancak o haftada üyeye ait en az bir uygun kaynak kaydı da varsa bu bildirimi kapsama işareti olarak kullanır; tamamen boş okuma izin/başarısızlık kanıtı sayılmaz. Bunlar bağımsız ispat değildir. Hafta sonundan sonra 48 saatlik eşitleme payında her üyeden desteklenen kapsama bildirimi gelmezse hafta cezasız iade ile kapanır. Bu nedenle hiç veri üretmeyen bir üyeye otomatik kayıp kesilmez. Bu beta, parasal değeri olmayan arkadaşlar arası krediler içindir.

## Kontroller

- Node entegrasyon senaryoları gerçek HTTP handler'ları ve sıralı DO test adapterlerini kullanır: üç hesapta davet/kabul, aynı anda tekrarlı rehin, kayıt tekrarı, manuel kaynak reddi, hafta sonu alarmı, payout tekrar koruması, kapsama eksikliğinde iade, alıcı kotası, otomatik hayalet sonucu, izin iptali ve hesap silme.
- Mevcut hesap/arkadaşlık/koç/push/inbox regresyonları korunur.
- iOS kaynak tür kontrolü ve proje/yerelleştirme lint'i GitHub macOS kontrolünde çalışır. Bu fiziksel cihazdaki HealthKit/konum/APNs teslim testi anlamına gelmez.
- Canlı dağıtımda yeni SQLite namespace migration'ı mevcut NotificationInbox migration'ına eklenir; eskisi değiştirilmez. Apple imzalama yetkileri ve profil bu sürümde değişmez.

TestFlight'ta ilk deneme: üç karşılıklı arkadaşla Çember oluştur → her hesapta ayrı kabul → Sağlık/ziyaret kaynağını bağla → isteyen iki üyede hayalet paylaşımını aç → farklı saatlerde uygun antrenmanları eşitle. Dönem başlamadan eski seanslar haftalık hedefe yazılmaz; yalnız izinli aktiflik ve sonraki seans hayaleti için kullanılabilir.
