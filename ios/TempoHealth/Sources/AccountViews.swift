import PhotosUI
import Photos
import SwiftUI
import UIKit

struct TempoLaunchView: View {
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TempoTheme.background
            if reduceMotion {
                TempoBrandMark(size: 154).accessibilityIdentifier("launch.brand")
            } else {
                TempoBrandMark(size: 154)
                    .keyframeAnimator(initialValue: TempoLaunchMotion(), trigger: hasAppeared) { logo, motion in
                        logo.opacity(motion.opacity).scaleEffect(motion.scale).offset(y: motion.offset).blur(radius: motion.blur)
                    } keyframes: { _ in
                        KeyframeTrack(\.opacity) { CubicKeyframe(1, duration: 0.32) }
                        KeyframeTrack(\.scale) { CubicKeyframe(1.012, duration: 0.56); CubicKeyframe(1, duration: 0.30) }
                        KeyframeTrack(\.offset) { CubicKeyframe(0, duration: 0.68) }
                        KeyframeTrack(\.blur) { CubicKeyframe(0, duration: 0.40) }
                    }.accessibilityIdentifier("launch.brand")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task { await Task.yield(); guard !Task.isCancelled else { return }; hasAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
    }
}

private struct TempoLaunchMotion {
    var opacity = 0.0
    var scale: CGFloat = 0.90
    var offset: CGFloat = 10
    var blur: CGFloat = 2.5
}

struct TempoBrandMark: View {
    var size: CGFloat = 76

    var body: some View {
        Image("TempoLaunchMark")
            .resizable()
            .scaledToFit()
            .scaleEffect(1.3)
            .frame(width: size, height: size)
    }
}

struct TempoAmbientBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        TempoTheme.card,
                        TempoTheme.background,
                        TempoTheme.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(TempoTheme.green.opacity(0.035))
                    .frame(width: proxy.size.width * 0.92)
                    .blur(radius: 125)
                    .offset(x: proxy.size.width * 0.48, y: -proxy.size.height * 0.40)
                Circle()
                    .fill(TempoTheme.blue.opacity(0.025))
                    .frame(width: proxy.size.width * 0.78)
                    .blur(radius: 120)
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
                    VStack(spacing: 20) {
                        HStack(spacing: 8) {
                            Circle().fill(TempoTheme.green).frame(width: 7, height: 7)
                            Text("HAREKET · SAĞLIK · GELİŞİM".tempoSentenceCased)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TempoTheme.secondary)
                        }
                        .padding(.top, 20)

                        VStack(spacing: 10) {
                            Text("Kendi ritmini\nbul.")
                                .font(.system(size: 39, weight: .bold, design: .rounded))
                                .tracking(-1.2)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.84)
                            Text("Sporlarını, sağlığını ve gelişimini sade bir kişisel alanda takip et.")
                                .font(.subheadline)
                                .foregroundStyle(TempoTheme.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 8)
                        }

                        WellnessIntroCard()

                        VStack(spacing: 11) {
                            NavigationLink(destination: AccountFormView(mode: .signUp)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Ücretsiz hesap oluştur")
                                            .font(.headline)
                                        Text("Kişisel alanını birkaç adımda hazırla")
                                            .font(.caption2)
                                            .opacity(0.68)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .frame(width: 32, height: 32)
                                        .background(.black.opacity(0.08), in: Circle())
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountPrimaryButtonStyle())
                            .accessibilityIdentifier("auth.createAccount")

                            NavigationLink(destination: AccountFormView(mode: .signIn)) {
                                HStack {
                                    Text("Zaten hesabım var")
                                    Spacer()
                                    Image(systemName: "person.crop.circle")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountOutlineButtonStyle())
                            .accessibilityIdentifier("auth.signIn")
                        }

                        Text("Tempo, hareketini günlük bir ritme dönüştürür.")
                            .font(.caption)
                            .foregroundStyle(TempoTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 21)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
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
                        .stroke(TempoTheme.primary.opacity(0.07), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: 0.82)
                        .stroke(TempoTheme.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .stroke(TempoTheme.primary.opacity(0.055), lineWidth: 7)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .background(
            LinearGradient(colors: [TempoTheme.green.opacity(0.055), TempoTheme.blue.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(LinearGradient(colors: [TempoTheme.primary.opacity(0.16), TempoTheme.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }
}

private struct WellnessPill: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title.tempoLocalized).foregroundStyle(TempoTheme.primary.opacity(0.84))
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TempoTheme.primary.opacity(0.045), in: Capsule())
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
                    HStack(spacing: 8) {
                        Circle().fill(TempoTheme.green).frame(width: 7, height: 7)
                        Text((mode == .signUp ? "YENİ HESAP" : "HESABINA DÖN").tempoSentenceCased)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        Spacer()
                    }
                    .padding(.top, 18)

                    VStack(spacing: 8) {
                        Text(mode.title.tempoLocalized)
                            .font(.system(size: 33, weight: .bold, design: .rounded))
                            .tracking(-0.7)
                            .accessibilityIdentifier("auth.form.title")
                        Text(mode.subtitle.tempoLocalized)
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
                            .accessibilityIdentifier("auth.email")
                            .keyboardType(mode == .signUp ? .emailAddress : .default)
                        }

                        if mode == .signUp {
                            AccountFormFieldLabel(title: "Kullanıcı adı") {
                                AccountTextField(title: "kullaniciadi", icon: "at", text: $username, contentType: .username)
                                        .accessibilityIdentifier("auth.username")
                            }
                        }

                        AccountFormFieldLabel(title: "Şifre") {
                            AccountSecureField(title: mode == .signUp ? "En az 8 karakter" : "Şifren", text: $password)
                                .accessibilityIdentifier("auth.password")
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
                                .accessibilityIdentifier("auth.forgotPassword")
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
                                Text(account.errorMessage.tempoLocalized)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("auth.error")
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
                                    ProgressView().tint(TempoTheme.onAccent)
                                }
                                Text((account.isBusy ? "Giriş hazırlanıyor…" : mode.actionTitle).tempoLocalized)
                                Spacer()
                                if !account.isBusy {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())
                        .accessibilityIdentifier("auth.submit")
                        .disabled(account.isBusy || !canSubmit)
                        .opacity(canSubmit ? 1 : 0.56)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .background(
                        LinearGradient(colors: [TempoTheme.primary.opacity(0.035), TempoTheme.green.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(LinearGradient(colors: [TempoTheme.primary.opacity(0.16), TempoTheme.primary.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 9)

                    HStack(spacing: 5) {
                        Text(mode.alternatePrompt.tempoLocalized)
                            .foregroundStyle(TempoTheme.secondary)
                        NavigationLink(destination: AccountFormView(mode: mode == .signUp ? .signIn : .signUp)) {
                            Text(mode.alternateTitle.tempoLocalized)
                                .fontWeight(.semibold)
                                .foregroundStyle(TempoTheme.green)
                        }
                        .accessibilityIdentifier("auth.switchMode")
                    }
                    .font(.subheadline)

                    if mode == .signUp {
                        VStack(spacing: 6) {
                            Text("Hesap oluşturarak bu belgeleri kabul edersin.")
                                .font(.caption2)
                                .foregroundStyle(TempoTheme.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Link(destination: URL(string: "https://apitempo.com/privacy")!) {
                                    Text("Gizlilik Politikası".tempoLocalized)
                                }
                                Link(destination: URL(string: "https://apitempo.com/terms")!) {
                                    Text("Kullanım Koşulları".tempoLocalized)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .tint(TempoTheme.green)
                        }
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
                                .accessibilityIdentifier("auth.passwordReset.done")
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
                                .accessibilityIdentifier("auth.passwordReset.email")
                        }

                        if !account.errorMessage.isEmpty {
                            Label(account.errorMessage.tempoLocalized, systemImage: "exclamationmark.circle.fill")
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
                                if account.isBusy { ProgressView().tint(TempoTheme.onAccent) }
                                Text(account.isBusy ? "Gönderiliyor…" : "Sıfırlama bağlantısı gönder")
                                Spacer()
                                if !account.isBusy { Image(systemName: "paperplane.fill") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())
                        .accessibilityIdentifier("auth.passwordReset.submit")
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
                        .accessibilityIdentifier("auth.passwordReset.close")
                }
            }
        }
        .onAppear { account.errorMessage = "" }
    }
}

private struct AccountFormFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.tempoLocalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TempoTheme.primary.opacity(0.78))
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
        .task(id: photoItem) {
            guard let item = photoItem else { isPreparingPhoto = false; return }
            isPreparingPhoto = true
            photoError = ""
            defer {
                if photoItem == item {
                    isPreparingPhoto = false
                    photoItem = nil
                }
            }
            do {
                let data = try await item.tempoProfileJPEGData()
                guard !Task.isCancelled, photoItem == item else { return }
                avatarData = data
            } catch {
                guard !Task.isCancelled, photoItem == item else { return }
                photoError = "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar dene."
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
                .accessibilityIdentifier("onboarding.profile.title")
            VStack(spacing: 12) {
                let currentAvatarData = avatarData ?? account.profile?.avatarData
                PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                    ZStack(alignment: .bottomTrailing) {
                        AccountAvatarView(data: currentAvatarData, size: 116)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(TempoTheme.onAccent)
                            .frame(width: 36, height: 36)
                            .background(TempoTheme.green, in: Circle())
                    }
                }
                Text("Profil fotoğrafı seç").font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            AccountTextField(title: "Görünen ad", icon: "person.fill", text: $displayName, contentType: .name)
                .accessibilityIdentifier("onboarding.displayName")
            AccountTextField(title: "Kullanıcı adı", icon: "at", text: $username, contentType: .username)
                .accessibilityIdentifier("onboarding.username")

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
            .accessibilityIdentifier("onboarding.profile.continue")
            .disabled(account.isBusy || isPreparingPhoto || photoItem != nil || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text((account.isBusy ? "Kaydediliyor…" : "Devam et").tempoLocalized).frame(maxWidth: .infinity)
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.sports.continue")
                .disabled(account.isBusy || selectedSports.isEmpty)
            }
        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingTitle(title: "Sağlık verilerini bağla", subtitle: "Apple Sağlık Tempo’nun ana sağlık kaynağıdır. Strava isteğe bağlıdır ve daha sonra bağlanabilir.")

            ConnectionCard(
                title: "Apple Sağlık · Önerilen",
                subtitle: model.healthSyncEnabled ? "Apple Sağlık bağlı." : "Uyku, su, adım, kalori, nabız ve diğer sağlık ölçülerini eşitle.",
                icon: "heart.fill",
                color: .pink,
                connected: model.healthSyncEnabled,
                busy: model.isHealthSyncing,
                action: model.connectAppleHealth
            )
            ConnectionCard(
                title: "Strava · İsteğe bağlı",
                subtitle: model.isConnected ? "Strava hesabın bağlı." : "Strava aktivitelerini ve rotalarını isteğe bağlı görüntüle.",
                icon: "figure.run",
                color: TempoTheme.orange,
                connected: model.isConnected,
                busy: model.isBusy,
                action: model.connectStrava
            )

            Text(model.status.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
            accountError

            HStack(spacing: 10) {
                Button("Geri") { withAnimation { step = 1 } }
                    .buttonStyle(AccountOutlineButtonStyle())
                Button {
                    Task {
                        if await account.updateProfile(onboardingComplete: true) {
                            model.skipStravaForNow()
                        }
                    }
                } label: {
                    Text((account.isBusy ? "Hazırlanıyor…" : "Tempo’yu aç").tempoLocalized).frame(maxWidth: .infinity)
                }
                .buttonStyle(AccountPrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.finish")
                .disabled(account.isBusy)
            }
        }
    }

    @ViewBuilder
    private var accountError: some View {
        if !photoError.isEmpty {
            Label(photoError.tempoLocalized, systemImage: "photo.badge.exclamationmark")
                .font(.footnote).foregroundStyle(TempoTheme.orange)
        }
        if !account.errorMessage.isEmpty {
            Label(account.errorMessage.tempoLocalized, systemImage: "exclamationmark.circle.fill")
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

struct ProfileProgressSummary: View {
    @EnvironmentObject private var model: TempoAppModel
    private var workouts: [TempoManualWorkout] { model.weekActivityWorkouts }
    private var activeDays: Int { Set(workouts.map { Calendar.autoupdatingCurrent.startOfDay(for: $0.startedAt) }).count }
    private var nextBadge: TempoBadge? {
        model.tempoAchievement.badges.filter { !$0.unlocked && $0.progress > 0 && $0.progress.isFinite }.sorted {
            $0.progress == $1.progress ? $0.id < $1.id : $0.progress > $1.progress
        }.first
    }
    var body: some View {
        TempoCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("profile.extra.progress".tempoLocalized, systemImage: "chart.bar.xaxis").font(.headline)
                TempoMetricGrid(columns: 2) {
                    metric("profile.extra.weekSessions", value: workouts.count.formatted(), symbol: "figure.mixed.cardio")
                    metric("profile.extra.activeDays", value: activeDays.formatted(), symbol: "calendar")
                }
                Text("profile.extra.restNote".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                if let badge = nextBadge {
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: badge.symbol).font(.title2).foregroundStyle(badge.tempoColor)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("profile.extra.nextBadge".tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                            Text(badge.title.tempoLocalized).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            ProgressView(value: badge.safeProgress).tint(TempoTheme.green)
                            Text(badge.current.formatted(.number.precision(.fractionLength(0...1))) + " / " + badge.target.formatted(.number.precision(.fractionLength(0...1))) + " " + badge.unit.tempoLocalized).font(.caption.monospacedDigit()).foregroundStyle(TempoTheme.secondary)
                        }
                    }
                }
                NavigationLink(destination: AchievementsScreen()) {
                    Label("profile.extra.allBadges".tempoLocalized, systemImage: "arrow.up.right").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(TempoTheme.green)
            }
        }
    }
    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(TempoTheme.green)
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(title.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
    }
}

struct AccountProfileCard: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel

    private var achievement: TempoAchievement { model.tempoAchievement }

    var body: some View {
        if let profile = account.profile {
            NavigationLink(destination: AccountSettingsScreen()) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                            AccountAvatarView(data: profile.avatarData, size: 76)
                            Text("\(achievement.level)")
                                .font(.caption2.bold())
                                .foregroundStyle(TempoTheme.onAccent)
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

                    Divider().overlay(TempoTheme.primary.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Seviye %d · %@".tempoFormatted(achievement.level, achievement.title.tempoLocalized))
                                .font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            Spacer()
                            Text(achievement.nextLevelXp > 0 ? "\(achievement.currentLevelXp) / \(achievement.nextLevelXp) XP" : "MAKSİMUM".tempoSentenceCased)
                                .font(.caption2).foregroundStyle(TempoTheme.secondary)
                        }
                        ProgressView(value: achievement.safeProgress)
                            .tint(TempoTheme.green)
                            .background(TempoTheme.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    if !achievement.unlockedBadges.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(achievement.unlockedBadges.reversed().prefix(3))) { badge in
                                HStack(spacing: 6) {
                                    Image(systemName: badge.symbol).foregroundStyle(badge.tempoColor)
                                    Text(badge.title.tempoLocalized).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(badge.tempoColor.opacity(0.12), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .foregroundStyle(TempoTheme.primary)
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [TempoTheme.green.opacity(0.10), TempoTheme.card, TempoTheme.blue.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(TempoTheme.primary.opacity(0.085), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 18, y: 9)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Hesap ayarlarını aç".tempoLocalized)
        }
    }
}

struct TempoProfileShareScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveID: UUID?
    @State private var photoPermissionDenied = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var notice = ""

    private var profileCard: some View {
        Group {
            if let profile = account.profile {
                TempoProfileShareArtwork(profile: profile)
            } else {
                EmptyCard(icon: "person.crop.rectangle", text: "Profil bilgisi yüklenemedi.")
            }
        }
    }

    var body: some View {
        TempoPage {
            PageTitle(title: "Profil kartın", subtitle: "Hareketini paylaş")
            Text("Kartında profil adın, kullanıcı adın, fotoğrafın ve seçtiğin sporlar yer alır. E-posta, sağlık verileri ve Strava istatistikleri paylaşılmaz.")
                .font(.caption).foregroundStyle(TempoTheme.secondary).fixedSize(horizontal: false, vertical: true)

            profileCard
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Button(action: saveToPhotos) {
                    if isSaving {
                        ProgressView().tint(TempoTheme.onAccent).frame(maxWidth: .infinity)
                    } else {
                        Label("PNG’yi Fotoğraflar’a kaydet", systemImage: "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(TempoPrimaryButtonStyle())
                .disabled(isSaving || account.profile == nil)

                Button(action: prepareShare) {
                    Label("Başkalarıyla paylaş", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TempoSecondaryButtonStyle())
                .disabled(isSaving || showShareSheet || account.profile == nil)
            }

            if photoPermissionDenied {
                Button("iPhone Ayarları’nı aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(TempoSecondaryButtonStyle())
            }
            if !notice.isEmpty {
                Text(notice.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Profil kartı").navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .sheet(isPresented: $showShareSheet, onDismiss: removeTemporaryShareFile) {
            if let shareURL { TempoProfileActivitySheet(items: [shareURL]) }
        }
        .onChange(of: account.profile?.id) { _, _ in
            cancelSave()
            showShareSheet = false
            removeTemporaryShareFile()
        }
        .onDisappear {
            cancelSave()
            if !showShareSheet { removeTemporaryShareFile() }
        }
    }

    @MainActor
    private func renderedPNG() -> Data? {
        guard let profile = account.profile else { return nil }
        let renderer = ImageRenderer(content: TempoProfileShareArtwork(profile: profile).frame(width: 360, height: 450))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }

    @MainActor
    private func saveToPhotos() {
        guard !isSaving else { return }
        guard let owner = account.profile?.id, let imageData = renderedPNG() else {
            notice = "Profil kartı oluşturulamadı. Tekrar deneyebilirsin."
            return
        }
        let operation = UUID()
        saveID = operation
        isSaving = true
        photoPermissionDenied = false
        notice = ""
        saveTask = Task { @MainActor in
            defer {
                if saveID == operation { isSaving = false; saveTask = nil; saveID = nil }
            }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard !Task.isCancelled, saveID == operation, account.profile?.id == owner else { return }
            guard permission == .authorized || permission == .limited else {
                photoPermissionDenied = permission == .denied || permission == .restricted
                notice = photoPermissionDenied
                    ? "Fotoğraflar’a ekleme izni kapalı. iPhone Ayarları’ndan izin verebilirsin."
                    : "Fotoğraflar izni alınamadı."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = "Tempo-Profil.png"
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: options)
                }
                guard !Task.isCancelled, saveID == operation, account.profile?.id == owner else { return }
                notice = "Profil kartı PNG olarak Fotoğraflar’a kaydedildi."
            } catch {
                guard !Task.isCancelled, saveID == operation, account.profile?.id == owner else { return }
                notice = "Fotoğraf kaydedilemedi: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
            }
        }
    }

    private func cancelSave() {
        saveID = nil
        saveTask?.cancel()
        saveTask = nil
        isSaving = false
    }

    @MainActor
    private func prepareShare() {
        guard !isSaving, !showShareSheet else { return }
        removeTemporaryShareFile()
        guard let data = renderedPNG() else {
            notice = "Profil kartı oluşturulamadı. Tekrar deneyebilirsin."
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tempo-Profil-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            shareURL = url
            notice = ""
            showShareSheet = true
        } catch {
            notice = "Paylaşım dosyası oluşturulamadı: %@".tempoFormatted(error.localizedDescription.tempoLocalized)
        }
    }

    private func removeTemporaryShareFile() {
        guard let shareURL else { return }
        try? FileManager.default.removeItem(at: shareURL)
        self.shareURL = nil
    }
}

private struct TempoProfileShareArtwork: View {
    let profile: TempoUserProfile

    private var name: String { profile.displayName.isEmpty ? profile.username : profile.displayName }
    private var sports: [TempoSportChoice] { profile.sports.compactMap(TempoSportChoice.init(rawValue:)) }
    private var displaySports: [TempoSportChoice] { Array(sports.prefix(4)) }
    private let ink = Color(red: 0.08, green: 0.14, blue: 0.12)
    private let paper = Color(red: 0.95, green: 0.95, blue: 0.90)
    private let mutedInk = Color(red: 0.36, green: 0.42, blue: 0.38)
    private let accent = Color(red: 0.73, green: 0.91, blue: 0.36)
    private var heroSymbol: String { sports.first?.symbol ?? "figure.run" }

    var body: some View {
        VStack(spacing: 0) {
            heroPanel
                .frame(height: 160)

            VStack(alignment: .leading, spacing: 0) {
                identityRow
                    .padding(.bottom, 15)

                Rectangle().fill(ink.opacity(0.10)).frame(height: 1)

                HStack(alignment: .firstTextBaseline) {
                    Text("SPORLARIM")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.6).foregroundStyle(mutedInk)
                    Spacer()
                    Text("%d spor".tempoFormatted(sports.count))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                }
                .padding(.top, 15)
                .padding(.bottom, 10)

                if displaySports.isEmpty {
                    Text("Spor tercihlerini Tempo profilinden ekleyebilirsin.")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(mutedInk)
                } else {
                    VStack(spacing: 7) {
                        ForEach(Array(stride(from: 0, to: displaySports.count, by: 2)), id: \.self) { start in
                            HStack(spacing: 7) {
                                sportPill(displaySports[start])
                                if start + 1 < displaySports.count {
                                    sportPill(displaySports[start + 1])
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 10)

                HStack(alignment: .center, spacing: 8) {
                    Rectangle().fill(ink).frame(width: 22, height: 3)
                    Text("KENDİ TEMPO’NDA. KENDİ YOLUNDA.")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.8).foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text("APITEMPO.COM")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.6).foregroundStyle(mutedInk)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 17)
            .frame(maxHeight: .infinity)
            .background(paper)
        }
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(ink.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var heroPanel: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.18, blue: 0.15), ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 1)
                .frame(width: 150, height: 150)
                .offset(x: 245, y: -67)
            Circle()
                .stroke(accent.opacity(0.10), lineWidth: 1)
                .frame(width: 108, height: 108)
                .offset(x: 265, y: -45)

            Image(systemName: heroSymbol)
                .font(.system(size: 78, weight: .light))
                .foregroundStyle(.white.opacity(0.075))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: -20, y: 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TempoBrandMark(size: 25)
                    Text("TEMPO")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(3).foregroundStyle(.white)
                    Spacer()
                    Text("SPORCU KARTI")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(1.1).foregroundStyle(ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(accent, in: Capsule())
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("HAREKETİNİ")
                    Text("KENDİ RİTMİNDE YAŞA")
                }
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .tracking(0.3).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 21)
            .padding(.top, 18)
            .padding(.bottom, 17)
        }
        .clipped()
    }

    private var identityRow: some View {
        HStack(spacing: 13) {
            AccountAvatarView(data: profile.avatarData, size: 62)
                .overlay(Circle().stroke(paper, lineWidth: 4))
                .overlay(Circle().stroke(ink.opacity(0.10), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.72)
                Text("@\(profile.username)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(mutedInk).lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "figure.run")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 34, height: 34)
                .background(accent, in: Circle())
        }
    }

    private func sportPill(_ sport: TempoSportChoice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: sport.symbol).foregroundStyle(ink.opacity(0.72))
            Text(sport.title).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
        .background(.white.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(ink.opacity(0.08), lineWidth: 1))
    }
}

private struct TempoProfileActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AchievementsScreen: View {
    @EnvironmentObject private var model: TempoAppModel
    @State private var selectedCategory = "all"
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var achievement: TempoAchievement { model.tempoAchievement }

    private let categories: [AchievementCategory] = [
        .init(id: "all", title: "Tümü", symbol: "square.grid.2x2.fill"),
        .init(id: "general", title: "Genel", symbol: "sparkles"),
        .init(id: "run", title: "Koşu", symbol: "figure.run"),
        .init(id: "ride", title: "Bisiklet", symbol: "bicycle"),
        .init(id: "walk", title: "Yürüyüş", symbol: "figure.walk"),
        .init(id: "hike", title: "Doğa", symbol: "figure.hiking"),
        .init(id: "swim", title: "Yüzme", symbol: "figure.pool.swim"),
        .init(id: "fitness", title: "Fitness", symbol: "dumbbell.fill"),
        .init(id: "tennis", title: "Tenis", symbol: "tennis.racket"),
        .init(id: "basketball", title: "Basketbol", symbol: "basketball.fill"),
        .init(id: "football", title: "Futbol", symbol: "soccerball"),
        .init(id: "volleyball", title: "Voleybol", symbol: "volleyball.fill"),
        .init(id: "padel", title: "Padel", symbol: "figure.racquetball"),
        .init(id: "badminton", title: "Badminton", symbol: "figure.badminton"),
        .init(id: "yoga", title: "Yoga", symbol: "figure.yoga")
    ]

    private var sportCategoryIDs: Set<String> {
        Set(categories.map(\.id).filter { $0 != "all" && $0 != "general" })
    }

    private var filteredBadges: [TempoBadge] {
        let values: [TempoBadge]
        if selectedCategory == "all" {
            values = achievement.badges
        } else if selectedCategory == "general" {
            values = achievement.badges.filter { badge in
                !sportCategoryIDs.contains { badge.id.hasPrefix("\($0)_") }
            }
        } else {
            values = achievement.badges.filter { $0.id.hasPrefix("\(selectedCategory)_") }
        }
        return values.sorted { left, right in
            if left.unlocked != right.unlocked { return left.unlocked && !right.unlocked }
            return left.safeProgress > right.safeProgress
        }
    }

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TEMPO BAŞARILARI".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        Text("Seviye ve rozetlerin").font(.system(size: 31, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    levelCard

                    HStack {
                        Text("ROZETLER".tempoSentenceCased).font(.caption.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                        Spacer()
                        Text("%d / %d açıldı".tempoFormatted(achievement.unlockedBadgeCount, achievement.totalBadgeCount))
                            .font(.caption).foregroundStyle(TempoTheme.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(categories) { category in
                                let selected = selectedCategory == category.id
                                Button {
                                    withAnimation(.snappy) { selectedCategory = category.id }
                                } label: {
                                    Label(category.title.tempoLocalized, systemImage: category.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? TempoTheme.onAccent : TempoTheme.primary.opacity(0.82))
                                        .padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(selected ? TempoTheme.green : TempoTheme.raised, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if model.isLoadingDashboard && model.manualWorkouts.isEmpty && model.healthDays.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView().tint(TempoTheme.green)
                            Text("Tempo ilerlemen hazırlanıyor…".tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary)
                        }
                        .padding(30).frame(maxWidth: .infinity)
                        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredBadges) { badge in
                                AchievementBadgeCard(badge: badge)
                            }
                        }
                    }

                    Text("XP ve rozetler yalnızca Tempo’da kaydettiğin antrenmanlar ve Apple Sağlık’taki hareket günlerinden hesaplanır. Strava aktiviteleri bu puana katılmaz.")
                        .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, TempoTheme.scrollBottomClearance)
            }
        }
        .navigationTitle("Başarılar")
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
    }

    private var levelCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: achievement.safeProgress)
                    .stroke(
                        LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("SEVİYE".tempoSentenceCased).font(.caption.weight(.medium)).foregroundStyle(TempoTheme.secondary)
                    Text("\(achievement.level)").font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(achievement.title.tempoLocalized).font(.caption.bold()).foregroundStyle(TempoTheme.green)
                }
            }
            .frame(width: 178, height: 178)

            VStack(spacing: 8) {
                HStack {
                    Text("%@ toplam XP".tempoFormatted(achievement.totalXp.formatted())).font(.subheadline.bold())
                    Spacer()
                    Text(achievement.nextLevelXp > 0 ? "Sonraki seviyeye %d XP".tempoFormatted(max(achievement.nextLevelXp - achievement.currentLevelXp, 0)) : "En yüksek seviye".tempoLocalized)
                        .font(.caption).foregroundStyle(TempoTheme.secondary)
                }
                ProgressView(value: achievement.safeProgress).tint(TempoTheme.green)
            }
        }
        .padding(22)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(TempoTheme.primary.opacity(0.055)))
    }
}

private struct AchievementCategory: Identifiable {
    let id: String
    let title: String
    let symbol: String
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
                    .background((badge.unlocked ? badge.tempoColor : TempoTheme.primary).opacity(0.12), in: Circle())
                Spacer()
                Image(systemName: badge.unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(badge.unlocked ? TempoTheme.green : TempoTheme.secondary)
            }
            Text(badge.localizedTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Text(badge.localizedDescription).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: badge.safeProgress).tint(badge.unlocked ? badge.tempoColor : TempoTheme.secondary)
                Text((badge.unlocked ? "Tamamlandı" : badge.progressText).tempoLocalized)
                    .font(.caption2).foregroundStyle(badge.unlocked ? badge.tempoColor : TempoTheme.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(badge.unlocked ? badge.tempoColor.opacity(0.28) : TempoTheme.primary.opacity(0.045)))
        .opacity(badge.unlocked ? 1 : 0.72)
    }
}

private extension TempoBadge {
    var localizedTitle: String {
        guard Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true else { return title }
        let fixed: [String: String] = [
            "first_activity": "First Step", "activity_10": "Find Your Rhythm", "activity_25": "Consistency",
            "activity_50": "Active 50", "activity_100": "Century Club", "activity_250": "Tempo Master",
            "active_10_hours": "10 Active Hours", "active_50_hours": "50 Active Hours", "active_100_hours": "100 Hours",
            "active_250_hours": "Endurance", "elevation_1000": "First Summit", "elevation_5000": "Mountaineer",
            "elevation_10000": "High Altitude", "elevation_25000": "Summit Seeker", "streak_3": "3-Day Streak",
            "streak_7": "7-Day Streak", "streak_14": "Two-Week Streak", "streak_30": "Monthly Streak",
            "multi_sport_3": "Well-Rounded", "multi_sport_5": "Sports Explorer", "multi_sport_8": "All-Rounder",
            "century": "Long Route", "early_bird": "Early Bird", "early_bird_20": "Chase the Sunrise",
            "movement_days_10": "10 Movement Days"
        ]
        if let fixed = fixed[id] { return fixed }
        guard let (sportKey, kind, targetText) = generatedBadgeParts else { return title.tempoLocalized }
        let sport = localizedSportName(sportKey)
        switch kind {
        case "count": return targetText == "1" ? "First \(sport)" : "\(sport) · \(targetText) Activities"
        case "hours": return "\(sport) · \(targetText) Hours"
        case "streak": return "\(sport) · \(targetText)-Day Streak"
        case "distance": return "\(sport) · \(targetText) km"
        case "longest": return "\(sport) · \(targetText) km in One Session"
        case "single": return "\(sport) · \(targetText)-Min Session"
        default: return title.tempoLocalized
        }
    }

    var localizedDescription: String {
        guard Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true else { return description }
        let fixed: [String: String] = [
            "first_activity": "Complete your first Tempo workout.", "activity_10": "Complete 10 Tempo workouts.",
            "activity_25": "Complete 25 Tempo workouts.", "activity_50": "Complete 50 Tempo workouts.",
            "activity_100": "Complete 100 Tempo workouts.", "activity_250": "Complete 250 Tempo workouts.",
            "active_10_hours": "Accumulate 10 hours of movement.", "active_50_hours": "Accumulate 50 hours of movement.",
            "active_100_hours": "Accumulate 100 hours of movement.", "active_250_hours": "Accumulate 250 hours of movement.",
            "elevation_1000": "Climb 1,000 m in total.", "elevation_5000": "Climb 5,000 m in total.",
            "elevation_10000": "Climb 10,000 m in total.", "elevation_25000": "Climb 25,000 m in total.",
            "streak_3": "Record activities on 3 consecutive days.", "streak_7": "Record activities on 7 consecutive days.",
            "streak_14": "Record activities on 14 consecutive days.", "streak_30": "Record activities on 30 consecutive days.",
            "multi_sport_3": "Try at least 3 different sports.", "multi_sport_5": "Try at least 5 different sports.",
            "multi_sport_8": "Try at least 8 different sports.", "century": "Complete 100 km in one activity.",
            "early_bird": "Start 5 Tempo workouts before 8:00 AM.", "early_bird_20": "Start 20 Tempo workouts before 8:00 AM.",
            "movement_days_10": "Reach 10 movement days using Apple Health or Tempo records."
        ]
        if let fixed = fixed[id] { return fixed }
        guard let (sportKey, kind, targetText) = generatedBadgeParts else { return description.tempoLocalized }
        let sport = localizedSportName(sportKey).lowercased()
        switch kind {
        case "count": return targetText == "1" ? "Complete your first \(sport) activity." : "Complete \(targetText) \(sport) activities."
        case "hours": return "Accumulate \(targetText) hours of \(sport)."
        case "streak": return "Log \(targetText) consecutive days of \(sport)."
        case "distance": return "Cover \(targetText) km through \(sport)."
        case "longest": return "Cover \(targetText) km in a single activity."
        case "single": return "Complete a single \(sport) session lasting \(targetText) minutes."
        default: return description.tempoLocalized
        }
    }

    private var generatedBadgeParts: (String, String, String)? {
        let sports = ["run", "ride", "walk", "hike", "swim", "fitness", "tennis", "basketball", "football", "volleyball", "padel", "badminton", "yoga"]
        guard let sport = sports.first(where: { id.hasPrefix($0 + "_") }) else { return nil }
        let remainder = String(id.dropFirst(sport.count + 1))
        guard let separator = remainder.firstIndex(of: "_") else { return nil }
        let kind = String(remainder[..<separator])
        var target = String(remainder[remainder.index(after: separator)...])
        if kind == "distance" || kind == "longest" { target = target.replacingOccurrences(of: "_", with: ".") }
        return (sport, kind, target)
    }

    private func localizedSportName(_ key: String) -> String {
        ["run": "Running", "ride": "Cycling", "walk": "Walking", "hike": "Hiking", "swim": "Swimming", "fitness": "Fitness", "tennis": "Tennis", "basketball": "Basketball", "football": "Football", "volleyball": "Volleyball", "padel": "Padel", "badminton": "Badminton", "yoga": "Yoga"][key] ?? key.capitalized
    }

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
        return "%@ / %@ %@".tempoFormatted(currentText, targetText, unit.tempoLocalized)
    }
}

struct AccountSettingsScreen: View {
    @EnvironmentObject private var account: TempoAccountStore
    @EnvironmentObject private var model: TempoAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var displayName = ""
    @State private var username = ""
    @State private var selectedSports = Set<TempoSportChoice>()
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isPreparingPhoto = false
    @State private var photoError = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var showStravaRevocationNotice = false
    @State private var isEditingProfile = false
    @State private var isEditingSports = false
    @State private var showAccountActions = false

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingTitle(title: "Tempo Hesabı", subtitle: "Profilin, sporların ve hesap ayarların.")

                    HStack(spacing: 15) {
                        AccountAvatarView(data: avatarData ?? account.profile?.avatarData, size: 70)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? username : displayName)
                                .font(.title3.bold()).foregroundStyle(TempoTheme.primary)
                            Text("@\(username)").font(.subheadline).foregroundStyle(TempoTheme.green)
                            if let email = account.profile?.email {
                                Text(email).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Button(isEditingProfile ? "Bitti" : "Düzenle") {
                            withAnimation(.snappy) { isEditingProfile.toggle() }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(isEditingProfile ? TempoTheme.onAccent : TempoTheme.green)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isEditingProfile ? TempoTheme.green : TempoTheme.green.opacity(0.11), in: Capsule())
                    }
                    .padding(16)
                    .background(TempoTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TempoTheme.primary.opacity(0.075), lineWidth: 1))

                    if isEditingProfile {
                        let currentAvatarData = avatarData ?? account.profile?.avatarData
                        PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                            HStack(spacing: 16) {
                                AccountAvatarView(data: currentAvatarData, size: 62)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Profil fotoğrafı").font(.headline).foregroundStyle(TempoTheme.primary)
                                    Text("Fotoğrafı değiştir").font(.caption).foregroundStyle(TempoTheme.green)
                                }
                                Spacer()
                                Image(systemName: "photo.badge.plus").foregroundStyle(TempoTheme.secondary)
                            }
                            .padding(14).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        HStack(spacing: 16) {
                            Image(systemName: "info.circle.fill").foregroundStyle(TempoTheme.blue)
                            Text("Görünen adını, kullanıcı adını ve profil fotoğrafını buradan değiştirebilirsin.")
                                .font(.caption).foregroundStyle(TempoTheme.secondary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("PROFİL BİLGİLERİ".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                            AccountTextField(title: "Görünen ad", icon: "person.fill", text: $displayName, contentType: .name)
                            AccountTextField(title: "Kullanıcı adı", icon: "at", text: $username, contentType: .username)
                            if let email = account.profile?.email {
                                Label(email, systemImage: "envelope.fill")
                                    .font(.subheadline).foregroundStyle(TempoTheme.secondary)
                                    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                    .background(TempoTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SPORLARIM".tempoSentenceCased).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.secondary)
                                Text("%d spor seçili".tempoFormatted(selectedSports.count)).font(.caption).foregroundStyle(TempoTheme.secondary)
                            }
                            Spacer()
                            Button(isEditingSports ? "Bitti" : "Düzenle") {
                                withAnimation(.snappy) { isEditingSports.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isEditingSports ? TempoTheme.onAccent : TempoTheme.green)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(isEditingSports ? TempoTheme.green : TempoTheme.green.opacity(0.11), in: Capsule())
                        }

                        if !selectedSports.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(TempoSportChoice.allCases.filter { selectedSports.contains($0) }) { sport in
                                    Label(sport.title, systemImage: sport.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(TempoTheme.primary.opacity(0.86))
                                        .padding(.horizontal, 11).padding(.vertical, 9)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(TempoTheme.raised, in: Capsule())
                                        .lineLimit(1)
                                }
                            }
                        }

                        if isEditingSports {
                            Divider().overlay(TempoTheme.primary.opacity(0.08))
                            SportSelectionGrid(selection: $selectedSports)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(16)
                    .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TempoTheme.primary.opacity(0.055)))

                    if !photoError.isEmpty {
                        Label(photoError, systemImage: "photo.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(TempoTheme.orange)
                    }
                    if !account.errorMessage.isEmpty {
                        Text(account.errorMessage.tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.orange)
                    }

                    if isEditingProfile || isEditingSports || avatarData != nil {
                        Button {
                            Task {
                                if await account.updateProfile(displayName: displayName, username: username, sports: selectedSports, avatarData: avatarData) {
                                    withAnimation(.snappy) {
                                        isEditingProfile = false
                                        isEditingSports = false
                                    }
                                }
                            }
                        } label: {
                            Text((isPreparingPhoto ? "Fotoğraf hazırlanıyor…" : (account.isBusy ? "Kaydediliyor…" : "Değişiklikleri kaydet")).tempoLocalized)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())
                        .disabled(account.isBusy || isPreparingPhoto || photoItem != nil || displayName.isEmpty || username.isEmpty || selectedSports.isEmpty)
                    }

                    NavigationLink(destination: TempoAppearanceSettingsScreen()) {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.lefthalf.filled").foregroundStyle(TempoTheme.green)
                            Text("appearance.title".tempoLocalized).font(.subheadline.weight(.semibold)).foregroundStyle(TempoTheme.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(TempoTheme.secondary)
                        }.padding(16).frame(minHeight: 54).background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }.buttonStyle(.plain).accessibilityIdentifier("account.appearance")

                    DisclosureGroup(isExpanded: $showAccountActions) {
                        VStack(spacing: 10) {
                            Button(role: .destructive) {
                                Task {
                                    await account.signOut()
                                    model.clearLocalStateForTempoSignOut()
                                }
                            } label: {
                                Label("Tempo hesabından çık", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountDangerButtonStyle())

                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Hesabı kalıcı olarak sil", systemImage: "trash.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AccountDangerButtonStyle())
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("Hesap ve güvenlik", systemImage: "lock.shield.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(TempoTheme.secondary)
                    .padding(16)
                    .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, TempoTheme.scrollBottomClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Hesap")
        .navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
        .task { loadProfileOnce() }
        .task(id: photoItem) {
            guard let item = photoItem else { isPreparingPhoto = false; return }
            isPreparingPhoto = true
            photoError = ""
            defer {
                if photoItem == item {
                    isPreparingPhoto = false
                    photoItem = nil
                }
            }
            do {
                let data = try await item.tempoProfileJPEGData()
                guard !Task.isCancelled, photoItem == item else { return }
                avatarData = data
            } catch {
                guard !Task.isCancelled, photoItem == item else { return }
                photoError = "Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar dene."
            }
        }
        .confirmationDialog("Tempo hesabın kalıcı olarak silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Hesabı sil", role: .destructive) {
                Task {
                    if await account.deleteAccount() {
                        model.clearLocalStateAfterAccountDeletion()
                        if account.stravaRevocationFailed {
                            showStravaRevocationNotice = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Profilin, sağlık özetlerin, arkadaşlıkların, yarışmaların ve cihazındaki antrenman kayıtların silinir. Bu işlem geri alınamaz.")
        }
        .alert("Strava iznini ayrıca kaldır", isPresented: $showStravaRevocationNotice) {
            Button("Strava ayarlarını aç") {
                openURL(URL(string: "https://www.strava.com/settings/apps")!)
                dismiss()
            }
            Button("Kapat", role: .cancel) { dismiss() }
        } message: {
            Text("Tempo hesabın ve Tempo’da saklanan verilerin silindi. Strava yetkisi otomatik iptal edilemedi; Strava’nın bağlı uygulamalar ayarından Tempo erişimini kaldır.")
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

struct TempoAppearanceSettingsScreen: View {
    @AppStorage(TempoAppearance.storageKey) private var appearance = TempoAppearance.system.rawValue
    private var selected: TempoAppearance { TempoAppearance(rawValue: appearance) ?? .system }

    var body: some View {
        TempoPage {
            PageTitle(title: "appearance.title", subtitle: "appearance.subtitle")
            TempoCard {
                VStack(spacing: 0) {
                    ForEach(TempoAppearance.allCases) { option in
                        Button { appearance = option.rawValue } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.symbol).font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(TempoTheme.green).frame(width: 32)
                                Text(option.title).font(.body).foregroundStyle(TempoTheme.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 12)
                                Image(systemName: selected == option ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(selected == option ? TempoTheme.green : TempoTheme.secondary.opacity(0.4))
                                    .accessibilityHidden(true)
                            }.padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("appearance.\(option.rawValue)")
                            .accessibilityAddTraits(selected == option ? .isSelected : [])
                        if option != TempoAppearance.allCases.last { Divider() }
                    }
                }
            }
            Text("appearance.detail".tempoLocalized).font(.footnote).foregroundStyle(TempoTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("appearance.title".tempoLocalized).navigationBarTitleDisplayMode(.inline).tempoGlassBackButton()
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
                    .foregroundStyle(selected ? TempoTheme.onAccent : TempoTheme.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(selected ? TempoTheme.green : TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sport.selection.\(sport.rawValue)")
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
                Text(title.tempoLocalized).font(.headline)
                Text(subtitle.tempoLocalized).font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(2)
            }
            Spacer()
            Button(action: action) {
                if connected { Image(systemName: "checkmark.circle.fill").foregroundStyle(TempoTheme.green) }
                else if busy { ProgressView().tint(TempoTheme.green) }
                else { Text("Bağla").font(.caption.bold()).foregroundStyle(TempoTheme.onAccent).padding(.horizontal, 13).padding(.vertical, 9).background(TempoTheme.green, in: Capsule()) }
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
            Text(title.tempoLocalized).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle.tempoLocalized).font(.subheadline).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
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
            TextField(title.tempoLocalized, text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(contentType == .name ? .words : .never)
                .autocorrectionDisabled(contentType != .name)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(TempoTheme.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TempoTheme.primary.opacity(0.07)))
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
                    SecureField(title.tempoLocalized, text: $text)
                } else {
                    TextField(title.tempoLocalized, text: $text)
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
            .accessibilityLabel((hidesPassword ? "Şifreyi göster" : "Şifreyi gizle").tempoLocalized)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(TempoTheme.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TempoTheme.primary.opacity(0.07)))
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
        .overlay(Circle().stroke(TempoTheme.primary.opacity(0.08), lineWidth: 1))
    }
}

private struct AccountPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(TempoTheme.onAccent).padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(TempoTheme.green.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AccountOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(TempoTheme.primary).padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(TempoTheme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(TempoTheme.primary.opacity(0.08)))
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
        guard let data = try await loadTransferable(type: Data.self) else {
            throw ProfilePhotoError.unreadable
        }
        try Task.checkCancellation()
        guard let image = UIImage(data: data),
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .global)
                    .onEnded { value in
                        let beganAtLeadingEdge = value.startLocation.x <= 28
                        let wasPrimarilyHorizontal = abs(value.translation.height) < 64
                        guard beganAtLeadingEdge,
                              wasPrimarilyHorizontal,
                              value.translation.width >= 88 else { return }
                        dismiss()
                    }
            )
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(TempoTheme.primary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(TempoTheme.primary.opacity(0.20), lineWidth: 1))
                            .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Geri".tempoLocalized)
                }
            }
    }
}

extension View {
    func tempoGlassBackButton() -> some View {
        modifier(TempoGlassBackButtonModifier())
    }
}
