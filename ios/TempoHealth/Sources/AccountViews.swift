import PhotosUI
import SwiftUI
import UIKit

struct TempoLaunchView: View {
    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 82, height: 82)
                Text("TEMPO").font(.headline.bold()).tracking(4).foregroundStyle(TempoTheme.green)
                ProgressView().tint(TempoTheme.green)
            }
        }
    }
}

struct TempoBrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.23, blue: 0.30), Color(red: 0.05, green: 0.10, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(TempoTheme.green.opacity(0.24))
                .frame(width: size * 0.70, height: size * 0.70)
                .blur(radius: size * 0.22)
                .offset(x: -size * 0.20, y: -size * 0.22)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [TempoTheme.green, Color(red: 0.47, green: 0.83, blue: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
    }
}

struct TempoAmbientBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.075, blue: 0.105),
                        TempoTheme.background,
                        Color(red: 0.025, green: 0.035, blue: 0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(TempoTheme.green.opacity(0.17))
                    .frame(width: proxy.size.width * 0.92)
                    .blur(radius: 95)
                    .offset(x: proxy.size.width * 0.48, y: -proxy.size.height * 0.40)
                Circle()
                    .fill(TempoTheme.blue.opacity(0.12))
                    .frame(width: proxy.size.width * 0.78)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.48, y: proxy.size.height * 0.38)
            }
        }
        .ignoresSafeArea()
    }
}

struct AccountWelcomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                TempoAmbientBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 27) {
                        HStack(spacing: 12) {
                            TempoBrandMark(size: 48)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Tempo")
                                    .font(.title3.bold())
                                Text("Sağlık ve spor")
                                    .font(.caption)
                                    .foregroundStyle(TempoTheme.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 13) {
                            Text("Daha iyi hisset.\nDaha güçlü hareket et.")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .tracking(-1.2)
                                .minimumScaleFactor(0.82)
                            Text("Aktivitelerini ve sağlık verilerini anlamlı, kişisel ve sakin bir deneyimde buluştur.")
                                .font(.body)
                                .foregroundStyle(TempoTheme.secondary)
                                .lineSpacing(4)
                        }

                        WellnessIntroCard()

                        VStack(spacing: 11) {
                            NavigationLink(destination: AccountFormView(mode: .signUp)) {
                                HStack {
                                    Text("Ücretsiz hesap oluştur")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountPrimaryButtonStyle())

                            NavigationLink(destination: AccountFormView(mode: .signIn)) {
                                Text("Giriş yap")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountOutlineButtonStyle())
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(TempoTheme.green)
                            Text("Verilerin senin kontrolünde.")
                        }
                        .font(.caption)
                        .foregroundStyle(TempoTheme.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct WellnessIntroCard: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: 0.82)
                        .stroke(TempoTheme.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .stroke(.white.opacity(0.055), lineWidth: 7)
                        .padding(15)
                    Circle()
                        .trim(from: 0, to: 0.64)
                        .stroke(TempoTheme.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(15)
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.pink)
                }
                .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Günün tek görünümü")
                        .font(.headline)
                    Text("Hareketin, toparlanman ve hedeflerin bir arada.")
                        .font(.subheadline)
                        .foregroundStyle(TempoTheme.secondary)
                        .lineSpacing(3)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                WellnessPill(icon: "figure.run", title: "Aktivite", color: TempoTheme.orange)
                WellnessPill(icon: "heart.fill", title: "Sağlık", color: .pink)
                WellnessPill(icon: "sparkles", title: "Koç", color: TempoTheme.blue)
            }
        }
        .padding(19)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.075))
        )
    }
}

private struct WellnessPill: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).foregroundStyle(.white.opacity(0.84))
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.045), in: Capsule())
    }
}

private enum AccountFormMode {
    case signUp, signIn

    var title: String { self == .signUp ? "Hesabını oluştur" : "Tekrar hoş geldin" }
    var subtitle: String { self == .signUp ? "Birkaç adım sonra Tempo hazır olacak." : "Kaldığın yerden devam etmek için giriş yap." }
    var actionTitle: String { self == .signUp ? "Hesap oluştur" : "Giriş yap" }
    var alternatePrompt: String { self == .signUp ? "Zaten hesabın var mı?" : "Tempo’ya yeni misin?" }
    var alternateTitle: String { self == .signUp ? "Giriş yap" : "Hesap oluştur" }
}

private struct AccountFormView: View {
    @EnvironmentObject private var account: TempoAccountStore
    let mode: AccountFormMode
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showsPasswordReset = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        (mode == .signIn || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ZStack {
            TempoAmbientBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 25) {
                    TempoBrandMark(size: 66)
                        .padding(.top, 7)

                    VStack(spacing: 8) {
                        Text(mode.title)
                            .font(.system(size: 33, weight: .bold, design: .rounded))
                            .tracking(-0.7)
                        Text(mode.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(TempoTheme.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    VStack(spacing: 16) {
                        AccountFormFieldLabel(title: mode == .signUp ? "E-posta" : "E-posta veya kullanıcı adı") {
                            AccountTextField(
                                title: mode == .signUp ? "ornek@eposta.com" : "E-posta veya kullanıcı adın",
                                icon: mode == .signUp ? "envelope" : "person",
                                text: $email,
                                contentType: mode == .signUp ? .emailAddress : .username
                            )
                            .keyboardType(mode == .signUp ? .emailAddress : .default)
                        }

                        if mode == .signUp {
                            AccountFormFieldLabel(title: "Kullanıcı adı") {
                                AccountTextField(title: "kullaniciadi", icon: "at", text: $username, contentType: .username)
                            }
                        }

                        AccountFormFieldLabel(title: "Şifre") {
                            AccountSecureField(title: mode == .signUp ? "En az 8 karakter" : "Şifren", text: $password)
                        }

                        if mode == .signIn {
                            HStack {
                                Spacer()
                                Button("Şifremi unuttum") {
                                    account.errorMessage = ""
                                    showsPasswordReset = true
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TempoTheme.green)
                            }
                        }

                        if mode == .signUp {
                            Text("En az 8 karakterli bir şifre ve 3–24 karakterli bir kullanıcı adı kullan.")
                                .font(.caption)
                                .foregroundStyle(TempoTheme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !account.errorMessage.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(account.errorMessage)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.footnote)
                            .foregroundStyle(TempoTheme.orange)
                            .padding(13)
                            .background(TempoTheme.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }

                        Button {
                            Task {
                                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                if mode == .signUp {
                                    await account.signUp(email: cleanEmail, username: username, password: password)
                                } else {
                                    await account.signIn(identifier: cleanEmail, password: password)
                                }
                            }
                        } label: {
                            HStack {
                                if account.isBusy {
                                    ProgressView().tint(.black)
                                }
                                Text(account.isBusy ? "Giriş hazırlanıyor…" : mode.actionTitle)
                                Spacer()
                                if !account.isBusy {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())
                        .disabled(account.isBusy || !canSubmit)
                        .opacity(canSubmit ? 1 : 0.56)
                    }
                    .padding(18)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.07)))

                    HStack(spacing: 5) {
                        Text(mode.alternatePrompt)
                            .foregroundStyle(TempoTheme.secondary)
                        NavigationLink(destination: AccountFormView(mode: mode == .signUp ? .signIn : .signUp)) {
                            Text(mode.alternateTitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(TempoTheme.green)
                        }
                    }
                    .font(.subheadline)

                    if mode == .signUp {
                        Text("Devam ederek hesap ve gizlilik koşullarını kabul etmiş olursun.")
                            .font(.caption2)
                            .foregroundStyle(TempoTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 21)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .tempoGlassBackButton()
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetSheet()
                .environmentObject(account)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct PasswordResetSheet: View {
    @EnvironmentObject private var account: TempoAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var requestSent = false

    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    if requestSent {
                        VStack(spacing: 15) {
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(TempoTheme.green)
                            Text("E-postanı kontrol et")
                                .font(.title2.bold())
                            Text("Bu adresle eşleşen bir Tempo hesabı varsa şifre sıfırlama bağlantısını gönderdik.")
                                .font(.subheadline)
                                .foregroundStyle(TempoTheme.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                            Button("Tamam") { dismiss() }
                                .buttonStyle(AccountPrimaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Şifreni sıfırla")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("Tempo hesabına kayıtlı e-posta adresini gir. Sana tek kullanımlık bir bağlantı gönderelim.")
                                .font(.subheadline)
                                .foregroundStyle(TempoTheme.secondary)
                                .lineSpacing(3)
                        }

                        AccountFormFieldLabel(title: "E-posta") {
                            AccountTextField(title: "ornek@eposta.com", icon: "envelope", text: $email, contentType: .emailAddress)
                                .keyboardType(.emailAddress)
                        }

                        if !account.errorMessage.isEmpty {
                            Label(account.errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(TempoTheme.orange)
                        }

                        Button {
                            Task {
                                let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                if await account.requestPasswordReset(email: cleanEmail) {
                                    requestSent = true
                                }
                            }
                        } label: {
                            HStack {
                                if account.isBusy { ProgressView().tint(.black) }
                                Text(account.isBusy ? "Gönderiliyor…" : "Sıfırlama bağlantısı gönder")
                                Spacer()
                                if !account.isBusy { Image(systemName: "paperplane.fill") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())
                        .disabled(account.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Spacer()
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(TempoTheme.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { account.errorMessage = "" }
    }
}

private struct AccountFormFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            content
        }
    }
}

struct AccountOnboardingView: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @State private var step = 0
    @State private var displayName = ""
    @State private var username = ""
    @State private var selectedSports = Set<TempoSportChoice>()
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isPreparingPhoto = false
    @State private var photoError = ""
    @State private var loaded = false

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                onboardingProgress
                ScrollView {
                    Group {
                        if step == 0 { profileStep }
                        else if step == 1 { sportsStep }
                        else { connectionsStep }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .task { loadProfileOnce() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                isPreparingPhoto = true
                photoError = ""
                defer {
                    isPreparingPhoto = false
                    photoItem = nil
                }
                do {
                    avatarData = try await item.tempoProfileJPEGData()
                } catch {
                    photoError = "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar dene."
                }
            }
        }
    }

    private var onboardingProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TEMPO").font(.caption.bold()).tracking(3).foregroundStyle(TempoTheme.green)
                Spacer()
                Text("\(step + 1) / 3").font(.caption.bold()).foregroundStyle(TempoTheme.secondary)
            }
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule().fill(index <= step ? TempoTheme.green : TempoTheme.raised).frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            OnboardingTitle(title: "Profilini oluşturalım", subtitle: "İnsanların seni nasıl göreceğini seç.")
            VStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                    ZStack(alignment: .bottomTrailing) {
                        AccountAvatarView(data: avatarData ?? account.profile?.avatarData, size: 116)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(TempoTheme.green, in: Circle())
                    }
                }
                Text("Profil fotoğrafı seç").font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            AccountTextField(title: "Görünen ad", icon: "person.fill", text: $displayName, contentType: .name)
            AccountTextField(title: "Kullanıcı adı", icon: "at", text: $username, contentType: .username)

            accountError

            Button {
                Task {
                    if await account.updateProfile(displayName: displayName, username: username, avatarData: avatarData) {
                        withAnimation { step = 1 }
                    }
                }
            } label: {
                Label(
                    isPreparingPhoto ? "Fotoğraf hazırlanıyor…" : (account.isBusy ? "Kaydediliyor…" : "Devam et"),
                    systemImage: "arrow.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(account.isBusy || isPreparingPhoto || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sportsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingTitle(title: "Hangi sporlarla ilgileniyorsun?", subtitle: "Bir veya daha fazla spor seç. Ana ekranın ve menülerin buna göre hazırlanacak.")
            SportSelectionGrid(selection: $selectedSports)
            accountError
            HStack(spacing: 10) {
                Button("Geri") { withAnimation { step = 0 } }
                    .buttonStyle(AccountOutlineButtonStyle())
                Button {
                    Task {
                        if await account.updateProfile(sports: selectedSports) {
                            withAnimation { step = 2 }
                        }
                    }
                } label: {
                    Text(account.isBusy ? "Kaydediliyor…" : "Devam et").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .disabled(account.isBusy || selectedSports.isEmpty)
            }
        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingTitle(title: "Verilerini bağla", subtitle: "Bağlantıları şimdi kurabilir veya daha sonra profilinden tamamlayabilirsin.")

            ConnectionCard(
                title: "Strava",
                subtitle: model.isConnected ? "Strava hesabın bağlı." : "Aktivitelerini, rotalarını ve spor istatistiklerini getir.",
                icon: "figure.run",
                color: TempoTheme.orange,
                connected: model.isConnected,
                busy: model.isBusy,
                action: model.connectStrava
            )
            ConnectionCard(
                title: "Apple Sağlık",
                subtitle: model.healthSyncEnabled ? "Apple Sağlık bağlı." : "Uyku, su, adım, kalori, nabız ve diğer sağlık ölçülerini eşitle.",
                icon: "heart.fill",
                color: .pink,
                connected: model.healthSyncEnabled,
                busy: model.isHealthSyncing,
                action: model.connectAppleHealth
            )

            Text(model.status).font(.footnote).foregroundStyle(TempoTheme.secondary)
            accountError

            HStack(spacing: 10) {
                Button("Geri") { withAnimation { step = 1 } }
                    .buttonStyle(AccountOutlineButtonStyle())
                Button {
                    Task {
                        await account.updateProfile(onboardingComplete: true)
                    }
                } label: {
                    Text(account.isBusy ? "Hazırlanıyor…" : "Tempo’yu aç").frame(maxWidth: .infinity)
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .disabled(account.isBusy)
            }
        }
    }

    @ViewBuilder
    private var accountError: some View {
        if !photoError.isEmpty {
            Label(photoError, systemImage: "photo.badge.exclamationmark")
                .font(.footnote).foregroundStyle(TempoTheme.orange)
        }
        if !account.errorMessage.isEmpty {
            Label(account.errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.footnote).foregroundStyle(TempoTheme.orange)
        }
    }

    private func loadProfileOnce() {
        guard !loaded, let profile = account.profile else { return }
        loaded = true
        displayName = profile.displayName
        username = profile.username
        selectedSports = Set(profile.sports.compactMap(TempoSportChoice.init(rawValue:)))
    }
}

struct AccountProfileCard: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel

    private var achievement: TempoAchievement { model.dashboard?.achievement ?? .empty }

    var body: some View {
        if let profile = account.profile {
            NavigationLink(destination: AchievementsScreen()) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                            AccountAvatarView(data: profile.avatarData, size: 76)
                            Text("\(achievement.level)")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .frame(width: 27, height: 27)
                                .background(TempoTheme.green, in: Circle())
                                .overlay(Circle().stroke(TempoTheme.card, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.displayName.isEmpty ? profile.username : profile.displayName).font(.title2.bold())
                            Text("@\(profile.username)").font(.subheadline).foregroundStyle(TempoTheme.green)
                            Text(profile.sports.compactMap(TempoSportChoice.init(rawValue:)).map(\.title).prefix(3).joined(separator: " · "))
                                .font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
                    }

                    Divider().overlay(.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SEVİYE \(achievement.level) · \(achievement.title.uppercased())")
                                .font(.caption.bold()).tracking(1.1).foregroundStyle(TempoTheme.green)
                            Spacer()
                            Text(achievement.nextLevelXp > 0 ? "\(achievement.currentLevelXp) / \(achievement.nextLevelXp) XP" : "MAKSİMUM")
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                        ProgressView(value: achievement.safeProgress)
                            .tint(TempoTheme.green)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    if !achievement.unlockedBadges.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(achievement.unlockedBadges.reversed().prefix(3))) { badge in
                                HStack(spacing: 6) {
                                    Image(systemName: badge.symbol).foregroundStyle(badge.tempoColor)
                                    Text(badge.title).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(badge.tempoColor.opacity(0.12), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.055)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct AchievementsScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var achievement: TempoAchievement { model.dashboard?.achievement ?? .empty }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TEMPO BAŞARILARI").font(.caption.bold()).tracking(1.6).foregroundStyle(TempoTheme.green)
                        Text("Seviye ve rozetlerin").font(.system(size: 31, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    levelCard

                    HStack {
                        Text("ROZETLER").font(.caption.bold()).tracking(1.4).foregroundStyle(TempoTheme.green)
                        Spacer()
                        Text("\(achievement.unlockedBadgeCount) / \(achievement.totalBadgeCount) açıldı")
                            .font(.caption).foregroundStyle(TempoTheme.secondary)
                    }

                    if achievement.badges.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView().tint(TempoTheme.green)
                            Text("Strava aktivitelerin hazırlanıyor…").font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        }
                        .padding(30).frame(maxWidth: .infinity)
                        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(achievement.badges.sorted { left, right in
                                if left.unlocked != right.unlocked { return left.unlocked && !right.unlocked }
                                return left.safeProgress > right.safeProgress
                            }) { badge in
                                AchievementBadgeCard(badge: badge)
                            }
                        }
                    }

                    Text("XP ve rozetler Strava’daki erişilebilir aktivitelerinden hesaplanır. Geçmiş sınırlandırılmışsa sonuçlar eksik olabilir.")
                        .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 34)
            }
        }
        .navigationTitle("Başarılar")
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }

    private var levelCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: achievement.safeProgress)
                    .stroke(
                        LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("SEVİYE").font(.caption2.bold()).tracking(1.3).foregroundStyle(TempoTheme.secondary)
                    Text("\(achievement.level)").font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(achievement.title).font(.caption.bold()).foregroundStyle(TempoTheme.green)
                }
            }
            .frame(width: 178, height: 178)

            VStack(spacing: 8) {
                HStack {
                    Text("\(achievement.totalXp.formatted()) toplam XP").font(.subheadline.bold())
                    Spacer()
                    Text(achievement.nextLevelXp > 0 ? "Sonraki seviyeye \(max(achievement.nextLevelXp - achievement.currentLevelXp, 0)) XP" : "En yüksek seviye")
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                ProgressView(value: achievement.safeProgress).tint(TempoTheme.green)
            }
        }
        .padding(22)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(.white.opacity(0.055)))
    }
}

private struct AchievementBadgeCard: View {
    let badge: TempoBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: badge.symbol)
                    .font(.title2)
                    .foregroundStyle(badge.unlocked ? badge.tempoColor : TempoTheme.secondary)
                    .frame(width: 45, height: 45)
                    .background((badge.unlocked ? badge.tempoColor : Color.white).opacity(0.12), in: Circle())
                Spacer()
                Image(systemName: badge.unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(badge.unlocked ? TempoTheme.green : TempoTheme.secondary)
            }
            Text(badge.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Text(badge.description).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: badge.safeProgress).tint(badge.unlocked ? badge.tempoColor : TempoTheme.secondary)
                Text(badge.unlocked ? "Tamamlandı" : badge.progressText)
                    .font(.caption2).foregroundStyle(badge.unlocked ? badge.tempoColor : TempoTheme.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(badge.unlocked ? badge.tempoColor.opacity(0.28) : .white.opacity(0.045)))
        .opacity(badge.unlocked ? 1 : 0.72)
    }
}

private extension TempoBadge {
    var tempoColor: Color {
        switch tint {
        case "orange": return TempoTheme.orange
        case "blue": return TempoTheme.blue
        case "purple": return TempoTheme.purple
        case "pink": return .pink
        default: return TempoTheme.green
        }
    }

    var progressText: String {
        let currentText = current.formatted(.number.precision(.fractionLength(current.rounded() == current ? 0 : 1)))
        let targetText = target.formatted(.number.precision(.fractionLength(target.rounded() == target ? 0 : 1)))
        return "\(currentText) / \(targetText) \(unit)"
    }
}

struct AccountSettingsScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var username = ""
    @State private var selectedSports = Set<TempoSportChoice>()
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isPreparingPhoto = false
    @State private var photoError = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingTitle(title: "Tempo Hesabı", subtitle: "Profilini ve ilgilendiğin sporları düzenle.")

                    PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                        HStack(spacing: 16) {
                            AccountAvatarView(data: avatarData ?? account.profile?.avatarData, size: 82)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Profil fotoğrafı").font(.headline).foregroundStyle(.white)
                                Text("Değiştirmek için dokun").font(.caption).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(TempoTheme.secondary)
                        }
                        .padding(16).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    AccountTextField(title: "Görünen ad", icon: "person.fill", text: $displayName, contentType: .name)
                    AccountTextField(title: "Kullanıcı adı", icon: "at", text: $username, contentType: .username)

                    Text("SPORLARIM").font(.caption.bold()).tracking(1.3).foregroundStyle(TempoTheme.green)
                    SportSelectionGrid(selection: $selectedSports)

                    if !photoError.isEmpty {
                        Label(photoError, systemImage: "photo.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(TempoTheme.orange)
                    }
                    if !account.errorMessage.isEmpty {
                        Text(account.errorMessage).font(.footnote).foregroundStyle(TempoTheme.orange)
                    }

                    Button {
                        Task { await account.updateProfile(displayName: displayName, username: username, sports: selectedSports, avatarData: avatarData) }
                    } label: {
                        Text(isPreparingPhoto ? "Fotoğraf hazırlanıyor…" : (account.isBusy ? "Kaydediliyor…" : "Değişiklikleri kaydet"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccountPrimaryButtonStyle())
                    .disabled(account.isBusy || isPreparingPhoto || displayName.isEmpty || selectedSports.isEmpty)

                    Divider().overlay(.white.opacity(0.08)).padding(.vertical, 6)

                    Button(role: .destructive) {
                        model.disconnect()
                        Task { await account.signOut() }
                    } label: {
                        Label("Tempo hesabından çık", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccountDangerButtonStyle())

                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Hesabı kalıcı olarak sil", systemImage: "trash.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccountDangerButtonStyle())
                }
                .padding(18)
            }
        }
        .navigationTitle("Hesap")
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task { loadProfileOnce() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                isPreparingPhoto = true
                photoError = ""
                defer {
                    isPreparingPhoto = false
                    photoItem = nil
                }
                do {
                    avatarData = try await item.tempoProfileJPEGData()
                } catch {
                    photoError = "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar dene."
                }
            }
        }
        .confirmationDialog("Tempo hesabın kalıcı olarak silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Hesabı sil", role: .destructive) {
                model.disconnect()
                Task {
                    if await account.deleteAccount() { dismiss() }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Profilin ve spor tercihlerin silinir. Bu işlem geri alınamaz.")
        }
    }

    private func loadProfileOnce() {
        guard !loaded, let profile = account.profile else { return }
        loaded = true
        displayName = profile.displayName
        username = profile.username
        selectedSports = Set(profile.sports.compactMap(TempoSportChoice.init(rawValue:)))
    }
}

struct SportSelectionGrid: View {
    @Binding var selection: Set<TempoSportChoice>
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 11) {
            ForEach(TempoSportChoice.allCases) { sport in
                let selected = selection.contains(sport)
                Button {
                    if selected { selection.remove(sport) } else { selection.insert(sport) }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: sport.symbol).font(.title3)
                        Text(sport.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if selected { Image(systemName: "checkmark.circle.fill") }
                    }
                    .foregroundStyle(selected ? .black : .white)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selected ? TempoTheme.green : TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ConnectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let connected: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
                .frame(width: 50, height: 50).background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            }
            Spacer()
            Button(action: action) {
                if connected { Image(systemName: "checkmark.circle.fill").foregroundStyle(TempoTheme.green) }
                else if busy { ProgressView().tint(TempoTheme.green) }
                else { Text("Bağla").font(.caption.bold()).foregroundStyle(.black).padding(.horizontal, 13).padding(.vertical, 9).background(TempoTheme.green, in: Capsule()) }
            }
            .disabled(connected || busy)
        }
        .padding(17)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountTextField: View {
    let title: String
    let icon: String
    @Binding var text: String
    let contentType: UITextContentType?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(TempoTheme.green).frame(width: 22)
            TextField(title, text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(contentType == .name ? .words : .never)
                .autocorrectionDisabled(contentType != .name)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07)))
    }
}

private struct AccountSecureField: View {
    let title: String
    @Binding var text: String
    @State private var hidesPassword = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .foregroundStyle(TempoTheme.green)
                .frame(width: 22)
            Group {
                if hidesPassword {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textContentType(.password)
            Button {
                hidesPassword.toggle()
            } label: {
                Image(systemName: hidesPassword ? "eye" : "eye.slash")
                    .foregroundStyle(TempoTheme.secondary)
                    .frame(width: 28, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hidesPassword ? "Şifreyi göster" : "Şifreyi gizle")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07)))
    }
}

private struct AccountAvatarView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                ZStack {
                    TempoTheme.raised
                    Image(systemName: "person.fill").font(.system(size: size * 0.38)).foregroundStyle(TempoTheme.green)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct AccountPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black).padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(TempoTheme.green.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AccountOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

private struct AccountDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.red).padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension TempoUserProfile {
    var avatarData: Data? {
        guard let avatarBase64,
              let comma = avatarBase64.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(avatarBase64[avatarBase64.index(after: comma)...]))
    }
}

private enum ProfilePhotoError: Error {
    case unreadable
}

private extension PhotosPickerItem {
    func tempoProfileJPEGData() async throws -> Data {
        guard let data = try await loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.tempoProfileJPEG() else {
            throw ProfilePhotoError.unreadable
        }
        return jpeg
    }
}

private extension UIImage {
    func tempoProfileJPEG() -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }

        let outputSide: CGFloat = 384
        let outputSize = CGSize(width: outputSide, height: outputSide)
        let scaleToFill = max(outputSide / size.width, outputSide / size.height)
        let drawSize = CGSize(width: size.width * scaleToFill, height: size.height * scaleToFill)
        let drawOrigin = CGPoint(
            x: (outputSide - drawSize.width) / 2,
            y: (outputSide - drawSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let square = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
        return square.jpegData(compressionQuality: 0.68)
    }
}

struct TempoGlassBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                            .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Geri")
                }
            }
    }
}

extension View {
    func tempoGlassBackButton() -> some View {
        modifier(TempoGlassBackButtonModifier())
    }
}
