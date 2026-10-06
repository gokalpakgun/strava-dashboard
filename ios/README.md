# Tempo iPhone uygulaması

`TempoHealth/TempoHealth.xcodeproj` dosyasını macOS üzerinde Xcode ile aç. `TempoHealth` hedefinde kendi Apple Developer takımını seç ve gerçek bir iPhone'da çalıştır. Proje iOS 17 ve üstünü hedefler; HealthKit yetkisi gerektirmez.

Uygulama gömülü web sayfası kullanmaz. Profil, aktiviteler, rotalar, istatistikler, ekipman, segmentler, fotoğraflar ve yapay zekâ koçu SwiftUI ile native olarak gösterilir. Her kullanıcı kendi Strava OAuth girişiyle tanınır. Mobil erişim anahtarı iPhone Keychain'de, Strava yenileme anahtarı Cloudflare KV'de tutulur. Su miktarı kullanıcı tarafından uygulamadaki hızlı ekleme düğmeleriyle kaydedilir.

Strava OAuth callback domain'i `apitempo.com` olarak kalmalı. Strava uygulaması tek kullanıcı modundaysa Strava API ayarlarından 10 sporcu kapasitesine yükselt; bu sınıra ulaşınca daha fazla kullanıcı için Strava incelemesine başvur. iOS uygulaması bu Strava sınırını değiştirmez.

App Store'a göndermeden önce gizlilik sayfasına gerçek veri sorumlusu ve destek iletişim bilgilerini ekle; Apple Developer imzalama, mağaza metinleri ve gerçek iPhone kontrollerini tamamla.

## Ücretsiz kişisel kurulum

`.github/workflows/build-ios.yml`, GitHub Actions üzerindeki macOS makinesinde imzasız bir IPA üretir. GitHub'da Actions > Tempo iPhone IPA > Run workflow yoluyla çalıştır; işlem tamamlanınca `Tempo-iPhone-unsigned` çıktısını indir ve ZIP dosyasını aç. Windows'ta resmi Sideloadly uygulamasıyla `Tempo-unsigned.ipa` dosyasını ücretsiz Apple hesabınla imzalayıp kendi iPhone'una yükleyebilirsin. Ücretsiz imza yedi gün geçerlidir ve App Store/TestFlight dağıtımı sağlamaz.
