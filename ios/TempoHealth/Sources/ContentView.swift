import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: TempoAppModel
    @AppStorage("tempoCloudSyncConsent") private var agreesToCloudSync = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "drop.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color(red: 0.20, green: 0.43, blue: 0.32))

                VStack(spacing: 8) {
                    Text("Tempo")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Su tüketimini kaydet ve antrenman panona eşitle.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if model.isConnected {
                    connectedCard
                } else {
                    connectCard
                }

                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 36)

                Link("Gizlilik bilgisi", destination: URL(string: "https://apitempo.com/privacy")!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: agreesToCloudSync) { _, agrees in
            if !agrees { model.disableHealthSync() }
        }
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Strava hesabın bağlı", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 8) {
                Text("BUGÜN")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(model.todayWaterMl) ml")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Spacer()
                    Text("Hedef \(model.dailyGoalMl) ml")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(Double(model.todayWaterMl), Double(model.dailyGoalMl)), total: Double(model.dailyGoalMl))
                    .tint(Color(red: 0.20, green: 0.43, blue: 0.32))
            }

            Toggle("Günlük su toplamımın apitempo.com’a gönderilmesini kabul ediyorum.", isOn: $agreesToCloudSync)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 10) {
                Text("Su ekle")
                    .font(.headline)
                HStack(spacing: 8) {
                    ForEach([200, 250, 500], id: \.self) { amount in
                        Button("+\(amount) ml") {
                            model.addWater(amount)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.20, green: 0.43, blue: 0.32))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .disabled(model.isBusy || !agreesToCloudSync)

            Button {
                Task { await model.refreshWater() }
            } label: {
                Label("Toplamı yenile", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)

            Text("Eklediğin miktar yalnızca günlük toplam olarak saklanır ve web sitesindeki Su Takibi bölümünde görünür.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Strava bağlantısını kes", role: .destructive) {
                model.disconnect()
            }
            .frame(maxWidth: .infinity)
            .disabled(model.isBusy)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var connectCard: some View {
        VStack(spacing: 12) {
            Text("Su toplamını kendi antrenman panona kaydetmek için Strava hesabını bağla.")
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
}
