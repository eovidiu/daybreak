import SwiftUI

struct AuthView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var signup = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFF4E4), Theme.paper],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            content
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Daybreak")
                .font(.serif(38, .semibold))
                .foregroundStyle(Theme.ink)
            Text("Every day starts on a fresh page.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)

            VStack(spacing: 14) {
                if signup {
                    field(TextField("Your name", text: $name), id: "nameField")
                }
                field(TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(), id: "emailField")
                field(SecureField("Password (8+ characters)", text: $password),
                      id: "passwordField")

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.urgent)
                        .accessibilityIdentifier("authError")
                }

                Button(action: submit) {
                    Text(signup ? "Create account" : "Sign in")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.paper)
                }
                .disabled(busy)
                .accessibilityIdentifier("authSubmit")
            }
            .padding(28)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
            .shadow(color: Theme.ink.opacity(0.10), radius: 30, y: 16)
            .padding(.horizontal, 24)

            Button(signup ? "Have an account? Sign in" : "New here? Create an account") {
                signup.toggle()
                error = nil
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .accessibilityIdentifier("authToggle")
            Spacer()
            Spacer()
        }
    }

    private func field(_ input: some View, id: String) -> some View {
        input
            .font(.system(size: 16, design: .serif))
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .accessibilityIdentifier(id)
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                if signup {
                    try await store.api.signUp(email: email, password: password, name: name)
                } else {
                    try await store.api.signIn(email: email, password: password)
                }
                await store.bootstrap()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
