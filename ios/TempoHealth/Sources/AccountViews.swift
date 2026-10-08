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

struct AccountWelcomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                TempoTheme.background.ignoresSafeArea()
                Circle()
                    .fill(TempoTheme.green.opacity(0.15))
                    .frame(width: 370, height: 370)
                    .blur(radius: 80)
                    .offset(x: 160, y: -320)

                VStack(alignment: .leading, spacing: 26) {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(LinearGradient(colors: [TempoTheme.green, TempoTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 43, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TEMPO").font(.caption.bold()).tracking(4).foregroundStyle(TempoTheme.green)
                        Text("Spor hayatını\nkendine göre kur.")
                            .font(.system(size: 41, weight: .bold, design: .rounded))
                            .tracking(-1)
                        Text("Sporlarını seç, Strava ve Apple Sağlık verilerini bağla, yakınındaki sahaları keşfet.")
                            .foregroundStyle(TempoTheme.secondary)
                            .lineSpacing(4)
                    }

                    VStack(spacing: 10) {
                        NavigationLink(destination: AccountFormView(mode: .signUp)) {
                            Label("Hesap oluştur", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountPrimaryButtonStyle())

                        NavigationLink(destination: AccountFormView(mode: .signIn)) {
                            Text("Zaten hesabım var")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccountOutlineButtonStyle())
                    }
                    Spacer().frame(height: 18)
                }
                .padding(.horizontal, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private enum AccountFormMode {
    case signUp, signIn

    var title: String { self == .signUp ? "Hesap oluştur" : "Tekrar hoş geldin" }
    var subtitle: String { self == .signUp ? "Tempo profilini birkaç adımda hazırlayalım." : "Profiline ve spor verilerine devam et." }
}

private struct AccountFormView: View {
    @EnvironmentObject private var account: TempoAccountStore
    let mode: AccountFormMode
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            TempoTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(mode.title).font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(mode.subtitle).foregroundStyle(TempoTheme.secondary)
                    }

                    VStack(spacing: 13) {
                        AccountTextField(title: "E-posta", icon: "envelope.fill", text: $email, contentType: .emailAddress)
                            .keyboardType(.emailAddress)
                        if mode == .signUp {
                            AccountTextField(title: "Kullanıcı adı", icon: "at", text: $username, contentType: .username)
                        }
                        AccountSecureField(title: "Şifre", text: $password)
                    }

                    if mode == .signUp {
                        Text("Şifre en az 8 karakter olmalı. Kullanıcı adı 3–24 karakter ve yalnızca harf, rakam veya alt çizgi içerebilir.")
                            .font(.caption).foregroundStyle(TempoTheme.secondary).lineSpacing(3)
                    }

                    if !account.errorMessage.isEmpty {
                        Label(account.errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(TempoTheme.orange)
                    }

                    Button {
                        Task {
                            if mode == .signUp {
                                await account.signUp(email: email, username: username, password: password)
                            } else {
                                await account.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        HStack {
                            if account.isBusy { ProgressView().tint(.black) }
                            Text(account.isBusy ? "İşlem yapılıyor…" : mode.title)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccountPrimaryButtonStyle())
                    .disabled(account.isBusy || email.isEmpty || password.isEmpty || (mode == .signUp && username.isEmpty))
                }
                .padding(22)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        if let profile = account.profile {
            HStack(spacing: 16) {
                AccountAvatarView(data: profile.avatarData, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.displayName.isEmpty ? profile.username : profile.displayName).font(.title2.bold())
                    Text("@\(profile.username)").font(.subheadline).foregroundStyle(TempoTheme.green)
                    Text(profile.sports.compactMap(TempoSportChoice.init(rawValue:)).map(\.title).prefix(3).joined(separator: " · "))
                        .font(.caption).foregroundStyle(TempoTheme.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill").foregroundStyle(TempoTheme.green)
            }
            .padding(18)
            .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
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
        .navigationBarTitleDisplayMode(.inline)
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
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AccountSecureField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(TempoTheme.green).frame(width: 22)
            SecureField(title, text: $text)
                .textContentType(.password)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(TempoTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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