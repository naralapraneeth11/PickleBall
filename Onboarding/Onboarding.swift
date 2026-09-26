import SwiftUI
struct OnboardingView: View {
    @AppStorage("profile_firstName") private var firstName: String = ""
    @AppStorage("profile_lastName")  private var lastName: String = ""
    @AppStorage("profile_email")     private var email: String = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var currentPage: Int = 0
    @State private var firstNameInput  = ""
    @State private var lastNameInput   = ""
    @State private var emailInput      = ""
    @State private var showNameError   = false
    @State private var emailValidationError = false

    @FocusState private var focusedField: Field?
    private enum Field { case firstName, lastName, email }

    private let darkBg = Color(red: 0.02, green: 0.03, blue: 0.12)
    private let navy   = Color(red: 0.04, green: 0.07, blue: 0.30)

    private let screenshotNames = ["Screenshot1", "Screenshot2", "Screenshot3"]

    private let tutorialTitles = [
        "The easiest way to play,\ntrack, and improve your\npickleball game using stats.",
        "See accurate stats after\neach game. Track points, win\nrate, longest rallies,\nand many more.",
        "Compare your performance\nover time and level up\nyour skills."
    ]

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(0..<3, id: \.self) { page in
                    tutorialPage(
                        imageName: screenshotNames[page],
                        title: tutorialTitles[page],
                        page: page
                    )
                    .tag(page)
                }

                profilePage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        // Dismiss the keyboard when the user taps outside any text field.
        // Without this, the keyboard can sit over the "Get started" button
        // and the user has no way to dismiss it from a tutorial page.
        .onTapGesture {
            focusedField = nil
        }
    }

    // MARK: Tutorial Page ─────────────────────────────────────

    private func tutorialPage(imageName: String, title: String, page: Int) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer().frame(height: geo.safeAreaInsets.top + 16)

                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geo.size.width * 0.44,
                        height: geo.size.height * 0.44
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 35, x: 0, y: 18)
                    .accessibilityHidden(true)

                Spacer().frame(height: 22)

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.white : Color.white.opacity(0.22))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .accessibilityHidden(true)

                Spacer().frame(height: 18)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                HStack(alignment: .center, spacing: 0) {
                    if page > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentPage = page - 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Previous")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                        }
                        .accessibilityLabel("Previous page")
                    } else {
                        Color.clear
                            .frame(width: 88, height: 44)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentPage = page + 1
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 58, height: 58)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(navy)
                            }
                            .shadow(color: .white.opacity(0.12), radius: 14, x: 0, y: 0)
                            Text(page == 2 ? "Next" : "Continue")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .accessibilityLabel(page == 2 ? "Continue to profile" : "Next page")
                    .accessibilityHint("Page \(page + 1) of 4")

                    Spacer()

                    Color.clear
                        .frame(width: 88, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 20) + 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Profile Page ──────────────────────────────────────

    private var profilePage: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: geo.safeAreaInsets.top + 32)

                    // Honest copy: removed "You're world-class pickleball player".
                    // Was both ungrammatical and an awkward thing to tell a brand-new
                    // user before they've played a single match.
                    Text("ALMOST THERE")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .tracking(1.2)

                    Text("Add your name")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your name appears on stats and matches you play. Email is optional.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 10)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 14) {
                        profileField(
                            label: "First name",
                            placeholder: "Neymar",
                            text: $firstNameInput,
                            isRequired: true,
                            showError: showNameError && firstNameInput.trimmingCharacters(in: .whitespaces).isEmpty,
                            keyboard: .default,
                            field: .firstName,
                            submitLabel: .next,
                            onSubmit: { focusedField = .lastName }
                        )

                        profileField(
                            label: "Last name",
                            placeholder: "Junior",
                            text: $lastNameInput,
                            isRequired: true,
                            showError: showNameError && lastNameInput.trimmingCharacters(in: .whitespaces).isEmpty,
                            keyboard: .default,
                            field: .lastName,
                            submitLabel: .next,
                            onSubmit: { focusedField = .email }
                        )

                        profileField(
                            label: "Email",
                            placeholder: "you@email.com",
                            text: $emailInput,
                            isRequired: false,
                            showError: emailValidationError,
                            keyboard: .emailAddress,
                            field: .email,
                            submitLabel: .done,
                            onSubmit: {
                                focusedField = nil
                                completeOnboarding()
                            }
                        )
                    }
                    .padding(.top, 28)

                    if showNameError {
                        Text("First and last name are required.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            .padding(.top, 6)
                    }

                    if emailValidationError {
                        Text("Please enter a valid email address.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            .padding(.top, 6)
                    }

                    Button(action: completeOnboarding) {
                        Text("Get started")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(navy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .padding(.top, 28)
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
                    .accessibilityLabel("Get started")
                    .accessibilityHint("Saves your name and opens the app")

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentPage = 2
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }
                    .accessibilityLabel("Back to tutorial")
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 32)
                }
                .padding(.horizontal, 28)
            }
            // Allow tap-outside on the scroll content to dismiss the keyboard.
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func profileField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isRequired: Bool,
        showError: Bool,
        keyboard: UIKeyboardType,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.4))
                if isRequired {
                    Text("*")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial.opacity(0.35))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            showError
                                ? Color.red.opacity(0.55)
                                : Color.white.opacity(0.14),
                            lineWidth: showError ? 1.2 : 0.8
                        )
                )
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .accessibilityLabel("\(label)\(isRequired ? ", required" : "")")
                .accessibilityValue(text.wrappedValue.isEmpty ? "Empty" : text.wrappedValue)
        }
    }

    private func completeOnboarding() {
        let fn = firstNameInput.trimmingCharacters(in: .whitespaces)
        let ln = lastNameInput.trimmingCharacters(in: .whitespaces)
        let em = emailInput.trimmingCharacters(in: .whitespaces)

        // Validate names — required
        guard !fn.isEmpty, !ln.isEmpty else {
            showNameError = true
            // Move focus to the first empty field so VoiceOver users land on it
            if fn.isEmpty {
                focusedField = .firstName
            } else {
                focusedField = .lastName
            }
            return
        }

        // Validate email if provided. Only block if it's non-empty AND invalid.
        // Empty email is fine — it's optional.
        if !em.isEmpty, !isValidEmail(em) {
            emailValidationError = true
            focusedField = .email
            return
        }

        // All validation passed — clear error states, persist, gate flips.
        // ORDER MATTERS: write profile fields BEFORE flipping hasCompletedOnboarding,
        // so by the time RootView re-renders ContentView, the profile is already there.
        showNameError = false
        emailValidationError = false
        firstName = fn
        lastName = ln
        email = em
        hasCompletedOnboarding = true
    }

    /// Lightweight email validator. Not RFC-compliant — just catches the
    /// obvious "no @, no domain" mistakes. Email is optional anyway.
    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }
}

// MARK: - Preview ─────────────────────────────────────────────

#Preview {
    OnboardingView()
}
