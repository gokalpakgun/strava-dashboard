# Tempo — Strava antrenman panosu

Türkçe, mobil uyumlu Strava istatistik paneli. Şu an tasarımda örnek aktiviteler kullanılıyor; bu sayfa Strava hesabınıza bağlanmıyor.

## GitHub Pages'te yayımlama

1. GitHub'da boş bir repository oluşturun ve bu klasördeki dosyaları repository'ye gönderin.
2. Repository ayarlarında **Pages** bölümünü açın.
3. **Build and deployment → Source** alanında **GitHub Actions** seçin.
4. `main` dalına gönderilen değişiklikler siteyi otomatik yayımlar. Adres, repository'nin Pages ayarlarında görünür.

İş akışı `.github/workflows/pages.yml` üzerinden yapılandırılmıştır.

## Canlı Strava panosu

Canlı OAuth bağlantılı sürüm `worker/` dizinindedir. Cloudflare Worker, aynı origin üzerinde panoyu sunar ve `/auth/*` ile `/api/*` isteklerini işler. GitHub kaynak kodunu tutar ve Cloudflare Workers Builds ile `worker/` dizini dağıtılabilir. Canlı bağlantı kurulduktan sonra kullanıcılar `https://tempo-strava-api.gokalpakgun11.workers.dev/` adresini kullanır.

Cloudflare dağıtımı için ayrıntılı hazırlık adımları [`worker/README.md`](worker/README.md) içindedir. Strava erişim bilgilerini repository'ye eklemeyin.

## Canlı Strava verisi

GitHub Pages statik dosyaları sunar; Strava `client_secret` veya yenileme belirteci (refresh token) gibi gizli bilgileri güvenle saklayan bir sunucu çalıştırmaz. Bu yüzden canlı bağlantı için iki parça gerekir:

- Bu repository'deki web arayüzü (GitHub Pages).
- OAuth girişini, Strava tokenlarını ve API isteklerini yöneten küçük bir arka uç / serverless fonksiyon. Örneğin Cloudflare Workers veya benzeri bir servis.

Gizli anahtarları `app.js`, `index.html` veya repository'ye gönderilen başka bir dosyaya koymayın. Arka uçta OAuth callback, token yenileme ve yalnızca gereken aktivite alanlarını döndüren bir API endpoint'i kurulmalı. Ardından `app.js` bu endpoint'ten veriyi alacak şekilde güncellenebilir. Gerçek Strava bağlantısı için önce Strava API uygulama bilgileri ve arka uç dağıtımı gerekir.

## Dosyalar

- `index.html`: Panelin yapısı ve örnek aktivite satırları
- `style.css`: Görsel tasarım ve mobil düzen
- `app.js`: Ufak arayüz etkileşimleri
- `.github/workflows/pages.yml`: GitHub Pages dağıtımı
