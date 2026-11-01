# Akıllı antrenman önerileri

- Varsayılan kapalıdır. Aktiviteler → Akıllı algılama üzerinden kullanıcı etkinleştirir; hareket ve bildirim izinleri ayrı istenir.
- Telefon tarafı son 24 saatlik Core Motion yürüme/koşma geçmişini adım sayısı ve tempo ile birleştirir. Araç sınıfı, düşük güven, kısa hareket ve uzun boşluklar elenir. Algılama için GPS veya sürekli ham ivme kaydı kullanılmaz.
- Sağlık tarafı son 24 saati 5 dakikalık pencerelerle değerlendirir. En az 15 dakika boyunca tekrarlayan yüksek nabız ve enerji/hareket desteği gerekir. Bunlar ürün heuristikleridir; klinik olarak doğrulanmış spor sınıflandırıcısı değildir. Sabit ağırlık çalışması yalnız yeterli saat sinyali varsa önerilebilir; set, tonaj, branş veya kalori uydurulmaz.
- Telefon ve Sağlık önerileri zaman çakışmasına göre birleştirilir. Kayıtlı antrenmanlar ve reddedilmiş zaman aralıkları yeniden önerilmez. Onay öncesi çakışma tekrar kontrol edilir. Sonradan gelen gerçek HealthKit antrenmanı, örtüşen algılanmış kayıttan önce toplam hesabına girer.
- Sonuç bir öneridir. Kullanıcı branşı seçip onaylamadıkça antrenman oluşturulmaz. Bildirimde sağlık sayıları bulunmaz. Bildirim sıklığı en fazla altı saatte birdir.
- Hesap başına ayrı, yedeklenmeyen ve ilk kilit açılışına kadar korunan yerel dosyada en fazla 100 öneri / 7 gün saklanır. Hesap değişimi sorgu sonuçlarını geçersiz kılar; hesap silme dosyayı kaldırır. Ham sensör verisi sunucuya gönderilmez.
- HealthKit observer, uygulama açıkken hareket değişimleri ve periyodik kontroller, ayrıca BGAppRefresh kullanılır. iOS arka plan zamanlamasını belirler; kapatılmış uygulamada anında bildirim garanti edilmez. Veri yokken başarı/aktivite varsayılmaz.
- Geriye dönük manuel ekleme ve elle metrik düzenleme arayüzleri kaldırılmıştır. Eski kayıtlar/ölçümler korunur. Sensörü olmayan sabit egzersizler için kullanıcı tarafından başlatılan canlı süre kaydı vardır.

## Doğrulama sınırı

Foundation senaryoları araç yolculuğu, kısa hareket, düşük adım, tekrarlayan nabız/enerji, eksik veri, duraklamalar, tekrar önerme ve yinelenen toplamları kapsar. Tam iOS kaynak tür denetimi ve plist kontrolleri CI üzerinde çalıştırılır. Bunlar gerçek iPhone/Watch algılama doğruluğunu veya arka plan bildirim teslim süresini ölçmez; gerçek cihaz geri bildirimiyle eşikler kalibre edilmelidir.
