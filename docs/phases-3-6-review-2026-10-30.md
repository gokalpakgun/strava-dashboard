# Faz 3–6 bağlantı kontrolü — 30 Ekim 2026

İncelenen TestFlight çalışması: [40949693373](https://github.com/gokalpakgun/strava-dashboard/actions/runs/40949693373), başarılı, kaynak `a3697262aa45f30755b3a0f2ac19c732771d25fc`. Bu build Faz 3–6 kaynaklarını içerir; 30 Ekim logo/erişim düzeltmelerini içermez.

| Faz | Kodda bulunan akış | Uygulamada erişim / koşul |
| --- | --- | --- |
| 3 | Hesaba özel yerel isimli kuvvet şablonları; aynı spor/şablonda önceki kilo/tekrar; yeni set kimlikleri ve boş RPE/RIR; önceki RPE≤7 veya RIR≥3 olduğunda isteğe bağlı artış ipucu | Aktiviteler → kuvvet kaydı → Setler ve şablonlar → Düzenle. Önceki eşleşen set yoksa artış rozeti gösterilmez. |
| 4 | Dört hazırlık bandına göre önerilen efor aralığı; yerel takvim gününe göre mevcut efor; enerji/ruh hali/yorgunluk özeti ve güçlü ölçüm + düşük enerji/yüksek yorgunluk karşılaştırması | Ana sayfa Sağlık kartı, Sporlar → efor panosu, Sağlık ayrıntısı ve Günün hareket menüsü. Ölçüm yoksa puan uydurulmaz. |
| 5 | Mesafesiz kayıtlarda geçerli efor/destekleyici ölçümle sınırlı XP bonusu; mesafe bonusuyla üst üste bindirilmez; sensör kaynak etiketi ve `verified_10` | Aktivite satırındaki kalkan, Profil → Başarılar. Health/GPS kaynağı veya sinyal puanı≥4 gerekir. |
| 6 | Sosyal avatar aktarımı; 420 dk uyku / 2.000 ml su eşikleri; eski yarışmalarda competitive varsayımı; coop hedefi ve ekip toplamı | Sosyal → mücadele oluştur → metrik/mod seçimi. Katılım ve açık veri paylaşımı şartları korunur. Eksik skor gizli/eksik kalır. |

## Bu kontrolde düzeltilenler

- Set/şablon ve diğer branş ayrıntılarına bütün Aktivite satırlarından doğrudan erişim eklendi. Önceden yalnız Sporlar/branş analizi üzerinden bulunuyordu.
- Kısa bağlantı satırları ayrıntı geçmişini yalnız hedef ekran açıldığında okur; her Aktivite satırı için tekrar büyük geçmiş yüklenmez.
- Check-in kaydı değişince aynı hesaba ait açık Sağlık, hazırlık ayrıntısı ve hareket menüsü görünümleri yenilenir. Yenileme tekrar kayıt yazmadığından bildirim döngüsü oluşmaz.
- Onaylanan açık yeşil gradyan tek vektör kaynağa işlendi. Mavi, şekil ve mevcut ölçek korunur. Dokuz opak ikon, iki aynı şeffaf uygulama görseli, build ikonu ve web SVG yeniden üretildi. Profil kartı aynı `TempoBrandMark` bileşenini kullanır.

## Kontrol sınırı

Kod bağlantıları ve odaklı regresyon kontrolleri incelendi. Logo boyutları, alfa kanalı ve kaynak eşitlikleri yerelde doğrulandı. Bu çalışma gerçek iPhone, gerçek HealthKit izni, arkadaş hesabıyla uçtan uca akış veya profil PNG ekran görüntüsü testi değildir. TestFlight yayını kullanıcı tarafından yapılır.

Son doğrulama: https://github.com/gokalpakgun/strava-dashboard/actions/runs/40988710772 — 163 Swift 6 hesaplama kontrolü, tüm iOS kaynaklarının tür denetimi ve 38 sunucu regresyon kontrolü başarılı. Web logosu HTTP 200 ile onaylanan SVG ile aynı; Cloudflare sürümü 21451a18-50c0-4f37-80fd-ebbbae016d4b.
