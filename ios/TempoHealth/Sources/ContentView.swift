import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @AppStorage("tempoCloudSyncConsent") private var agreesToCloudSync = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "drop.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color(red: 0.20, green: 0.43, blue: 0.32))

            VStack(spacing: 8) {
                Text("Tempo")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Apple Sağlık su verini antrenman panona eşitle.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.isConnected {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Strava hesabın bağlı", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Tempo, Sağlık uygulamasından yalnızca günlük su toplamlarını okur ve apitempo.com’a gönderir.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Toplamlar HTTPS ile iletilir ve en fazla 100 gün saklanır. Bu izni kapatınca sunucudaki toplamlar silinir; tek tek su kayıtları gönderilmez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Günlük su toplamımın apitempo.com’a gönderilmesini kabul ediyorum.", isOn: $agreesToCloudSync)
                        .font(.subheadline)
                    Button {
                        if model.healthSyncEnabled {
                            model.syncWhenActive()
                        } else {
                            model.enableHealthSync()
                        }
                    } label: {
                        Label(model.healthSyncEnabled ? "Şimdi eşitle" : "Apple Sağlık’a bağlan", systemImage: "drop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.20, green: 0.43, blue: 0.32))
                    .disabled(model.isBusy || !agreesToCloudSync)

                    Button("Strava bağlantısını kes", role: .destructive) {
                        model.disconnect()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(model.isBusy)
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 12) {
                    Text("Devam etmek için önce Strava hesabını bağla. Her kullanıcı kendi hesabıyla giriş yapar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        model.connectStrava()
                    } label: {
                        Label("Strava ile devam et", systemImage: "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.20, green: 0.43, blue: 0.32))
                    .disabled(model.isBusy)
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }

            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
                .accessibilityLiveRegion(.polite)

            Spacer()

            Link("Gizlilik bilgisi", destination: URL(string: "https://apitempo.com/privacy")!)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: agreesToCloudSync) { _, agrees in
            if !agrees { model.disableHealthSync() }
        }
    }
}
