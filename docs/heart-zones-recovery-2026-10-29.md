# Nabız bölgeleri, kas yükü ve ACWR — 29 Ekim 2026

## Kapsam

- HealthKit antrenmanlarının gerçek başlangıç/bitiş aralığında `HKQuantitySeriesSampleQuery` ile nabız zaman noktaları okunur. Son 90 günlük kayıtlı maksimum nabız referanstır; bulunamazsa 190 bpm varsayımı görünür biçimde belirtilir. Bunlar Apple'ın kişiselleştirilmiş nabız bölgeleri değildir.
- %50–60, %60–70, %70–80, %80–90 ve %90+ süreleri Edwards ağırlıkları 1–5 ile mevcut efor motoruna girer. %50 altındaki gözlenen süre ayrıca tutulur. Ölçüm eksikliği sıfır nabız/yük olarak gösterilmez.
- Duraklamalar çıkarılır; çakışan örnek zamanları iki kez sayılmaz. Örnek en fazla 30 saniye taşınır, daha uzun boşluklar doldurulmaz. En az %80 zaman kapsaması olmadan nabız temelli yük puanlanmaz.
- Başlangıç eşitlemesi son 90 günün bölgelerini toplu okur. Daha eski antrenmanların detayı açıldığında ayrı okuma yapılır. Bellek önbelleği yalnız türetilen süreleri tutar; ham nabız dizisi diske veya Koç'a gönderilmez. Zaman aşımı/kayıt sınırı kısmi veri olarak işaretlenir.
- Antrenman detayında Z1–Z5, ölçüm kapsamı ve maksimum nabız referansı gösterilir. Manuel bölge düzeltmeleri korunur.

## Kas haritası

`MuscleRecoveryCalculator` yalnız geçerli, bitmiş ve yinelenmeyen Tempo/izinli Health antrenmanlarının gerçek setlerini kullanır. Her set 4 puan, RPE≥8 veya RIR≤2 olan set ayrıca 4 puan model yükü taşır. Yük bitişten itibaren 72 saatte doğrusal sıfırlanır; gösterilen yüzde 100 eksi kalan yüktür. Bu katsayılar Tempo planlama sezgisidir, biyolojik toparlanma ölçümü değildir. %100 yoğun egzersize tıbbi onay anlamına gelmez. Bilinmeyen kas grubu bilinmeyen kalır; tüm-vücut setleri her kasa çoğaltılmaz.

Kart efor panosunda ve hareket menüsünde bulunur. Düşük tahmini hazırlık hareket menüsünde hafif alternatifi öne alır; kayıt veya antrenman başlatmayı engellemez. Koç yalnız ayrı antrenman/Health paylaşım izinleri açıksa özet alır.

## ACWR

Hesap: son 7 günün ham `combinedDose` toplamı / (son 28 günün ham toplamı / 4). Normalize 0–100 puanlar toplanmaz. Sıfır payda yok değer üretir. 28 günlük görünür geçmiş ve en az dört puanlanabilir kayıt oluşmadan oran yalnız açıklamada geçici değer olarak bulunur. Eksik puanlanamayan kayıtlar ayrıca sayılır.

Betimleyici bantlar: <0,8 düşük yük; 0,8–1,3 referans aralığı; >1,3–1,5 artan yük; >1,5 belirgin artış. Bu bantlar kişinin sakatlık riskini tahmin etmez, güvenli/optimal egzersiz garantisi vermez. Koç düşük oran nedeniyle otomatik daha fazla yük önermez.

## Kaynaklar ve sınırlar

- Apple: https://developer.apple.com/documentation/healthkit/hkquantityseriessamplequery/init(quantitytype:predicate:quantityhandler:)
- ACWR'nin nedensellik ve uygulama sınırları: https://pubmed.ncbi.nlm.nih.gov/33332011/ ve https://pubmed.ncbi.nlm.nih.gov/32125672/
- Strava kayıtları bu özel analiz/Koç bağlamına dahil edilmez. Mevcut özellikler kaldırılmamıştır.

## Doğrulama

Yerel Node kontrolleri: 35/35 geçti (Koç kapsamı, izinler, yeni özetlerin temizlenmesi ve sosyal regresyonlar). Swift 6 hesaplama kontrolleri ve iOS SDK tür denetimi için odaklı GitHub iş akışı kullanılacaktır; simülatör açılmaz, TestFlight yüklenmez. Gerçek Apple Sağlık izin/veri akışı cihazda kullanıcı tarafından denenecektir.
