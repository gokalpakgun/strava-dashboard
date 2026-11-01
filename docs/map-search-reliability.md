# Harita ve ekran düzenlemeleri

- Tesis araması, her sağlayıcının ayrı tamamlandığı bir yaşam döngüsü kullanır. Apple Haritalar eşanlamlı sorguları artık toplu paralel başlatılmaz; en fazla iki yerel/İngilizce sorgu sırayla çalışır.
- İlk alan geldiğinde haritanın üstündeki bloklayan yükleme biter. Diğer kaynak sessizce tamamlanır. Tek sağlayıcının hatası diğerinin geçerli sonuçlarını silmez; boş ama başarılı sorgu internet hatası sayılmaz.
- Aramanın sağlayıcı aşamasında 12 saniyelik bağımsız bir sonlandırıcı vardır. Konum bekleyişi ayrı olarak 8 saniyeyle sınırlıdır. Filtre değişimi/ekrandan çıkış eski işleri iptal eder; geç gelen callback'ler arama kimliğiyle elenir.
- Güncel Private.coffee Overpass adresi ve FOSSGIS yedeği kullanılır. HTTP 429 ve servis hatalarında bekleme uygulanır; hata içeren Overpass JSON `remark` alanı başarılı boş yanıt sayılmaz. Kısmi sonuçlar korunur. Servisler yanıt vermezse Apple Haritalar'da arama seçeneği sunulur.
- Bu ortamdan, kişisel konum kullanmadan İstanbul merkezinde yapılan örnek sorguda eski Kumi adresi HTTP 429, FOSSGIS HTTP 406 ve Private.coffee zaman aşımı döndürdü. Bu kontrol servislerin tüm kullanıcılar için erişilemez olduğunu kanıtlamaz. Dış servislerin sürekli erişilebilirliği garanti edilmez.
- Aktiviteler yatay filtre şeridi açılır menüye dönüştürüldü. Ortak sayfa içerikleri görünür genişliğe bağlandı; ana sayfanın yatay taşması önlenir, dikey kaydırma korunur.
- Sağlık ana sekmesinde geri düğmesi yoktur; detay navigasyonundaki geri davranışı korunur.
- Spor detayında Program/Rehber sekmeleri yerine 7/28/90 gün seçilebilen ilerleme görünümü vardır: hareket günleri, toplam/ortanca/en uzun süre, önceki dönem ve seçilebilir son antrenmanlar. Eksik veri doldurulmaz ve bu metrikler performans artışı iddiası taşımaz.

Doğrulama: Foundation yaşam döngüsü senaryoları; geç yanıt, süresiz kaynak, kısmi sonuç, gerçek boş yanıt, iptal ve hızlı spor değişimini kapsar. iOS kaynak tür kontrolü, yerelleştirme ve Xcode proje biçimi CI'da kontrol edilir. Gerçek iPhone harita servisi teslim süresi ve görsel düzeni cihaz üzerinde ayrıca doğrulanmalıdır.

Kaynaklar: [Apple MapKit araması](https://developer.apple.com/documentation/mapkit/mklocalsearch), [OpenStreetMap servis listesi](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances).
