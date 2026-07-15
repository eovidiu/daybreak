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
        VStack(spacing: 16) {
            Spacer()
            Text("Daybreak")
                .font(.system(size: 34, weight: .heavy))
            Text("Every day starts on a fresh page.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                if signup {
                    TextField("Your name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("nameField")
                }
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("emailField")
                SecureField("Password (8+ characters)", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("passwordField")

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("authError")
                }

                Button {
                    submit()
                } label: {
                    Text(signup ? "Create account" : "Sign in")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .accessibilityIdentifier("authSubmit")
            }
            .padding(.horizontal, 28)

            Button(signup ? "Have an account? Sign in" : "New here? Create an account") {
                signup.toggle()
                error = nil
            }
            .font(.footnote)
            .accessibilityIdentifier("authToggle")
            Spacer()
            Spacer()
        }
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
