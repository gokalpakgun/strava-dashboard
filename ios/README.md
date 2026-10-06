# Tempo iPhone uygulaması

`TempoHealth/TempoHealth.xcodeproj` dosyasını macOS üzerinde Xcode ile aç. `TempoHealth` hedefinde kendi Apple Developer takımını seç, HealthKit ve HealthKit Background Delivery yeteneklerini imzalama ayarlarında etkinleştir ve gerçek bir iPhone'da çalıştır. Proje iOS 17 ve üstünü hedefler.

Uygulama her kullanıcıyı kendi Strava OAuth girişiyle tanır. Apple Sağlık izni ve ayrıca günlük su toplamlarını apitempo.com'a gönderme onayı alınmadan eşitleme başlamaz. iPhone'da günlük toplamlar hesaplanır; ayrı su kayıtları sunucuya gönderilmez. Sunucu mobil belirtecin yalnızca özetini saklar. Kullanıcı eşitleme iznini kapatabilir veya bağlantıyı kaldırabilir.

Strava OAuth callback domain'i `apitempo.com` olarak kalmalı. Strava uygulaması tek kullanıcı modundaysa Strava API ayarlarından 10 sporcu kapasitesine yükselt; bu sınıra ulaşınca daha fazla kullanıcı için Strava incelemesine başvur. iOS uygulaması bu Strava sınırını değiştirmez.

App Store'a göndermeden önce gizlilik sayfasına gerçek veri sorumlusu ve destek iletişim bilgilerini ekle; Apple Developer imzalama, uygulama simgesi, mağaza metinleri ve gerçek iPhone'da HealthKit arka plan teslimatı kontrollerini tamamla. iOS arka plan bildirimlerinin zamanını sistem belirler; eşitleme uygulama açıkken de çalışır.

## Ücretsiz kişisel kurulum

`.github/workflows/build-ios.yml`, GitHub Actions üzerindeki macOS makinesinde imzasız bir IPA üretir. GitHub'da Actions > Tempo iPhone IPA > Run workflow yoluyla çalıştır; işlem tamamlanınca `Tempo-iPhone-unsigned` çıktısını indir ve ZIP dosyasını aç. Windows'ta resmi Sideloadly uygulamasıyla `Tempo-unsigned.ipa` dosyasını ücretsiz Apple hesabınla imzalayıp kendi iPhone'una yükleyebilirsin. Ücretsiz imza yedi gün geçerlidir ve App Store/TestFlight dağıtımı sağlamaz.
