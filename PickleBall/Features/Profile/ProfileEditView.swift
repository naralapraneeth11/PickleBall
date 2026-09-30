import SwiftUI
import CourtKit

/// Edits the device owner's profile. The display name feeds the local
/// user's player record, so history follows the ID, not the name.
struct ProfileEditView: View {
    @AppStorage("profile_firstName") private var firstName: String = ""
    @AppStorage("profile_lastName") private var lastName: String = ""
    @AppStorage("profile_gender") private var selectedGender: String = "Male"
    @AppStorage("profile_birthYear") private var birthYear: String = "2002"
    @AppStorage("profile_email") private var email: String = ""
    @AppStorage("profile_country") private var countryCode: String = "United States"

    @State private var showSettings = false
    @State private var emailValidationError = false

    @FocusState private var focusedField: Field?
    private enum Field { case firstName, lastName, email }
    let lightGrey  = DS.Palette.pageGrey
    let cardWhite  = Color.white
    let royalBlue  = DS.Palette.royalBlue
    let fieldGrey  = DS.Palette.fieldGrey
    let textMuted  = DS.Palette.textSecondary
    let stroke     = Color.black.opacity(0.08)
    let genderOptions = ["Male", "Female", "Non-binary", "Prefer not to say"]
    /// Birth years from current year back to 1940. Computed each render
    /// so the list never goes stale — the previous hardcoded "1940...2024"
    /// already excluded users born in 2025 or later.
    var years: [String] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(1940...currentYear).reversed().map { String($0) }
    }
    let countries = [
        ("🇺🇸", "United States"),
        ("🇬🇧", "United Kingdom"),
        ("🇩🇪", "Germany"),
        ("🇨🇦", "Canada"),
        ("🇨🇳", "China"),
        ("🇦🇺", "Australia"),
        ("🇮🇳", "India"),
        ("🌎", "Other")
    ]
    private var selectedCountry: (String, String) {
        countries.first { $0.1 == countryCode } ?? ("🇺🇸", "United States")
    }
    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespaces)
    }
    // MARK: - Court Strip Header

    private var courtStripHeader: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DS.Palette.courtBlue)
                    .frame(width: geo.size.width * 0.3)
                Rectangle()
                    .fill(.white)
                    .frame(width: 8)
                Rectangle()
                    .fill(DS.Palette.courtBlue)
                    .frame(width: geo.size.width * 0.69)
            }
            .frame(height: 146)
            .ignoresSafeArea(edges: .top)
            .overlay(
                HStack {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.leading, 16)
                    .accessibilityLabel("Open settings")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if trimmedFirstName.isEmpty {
                            Text("PROFILE")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundColor(.white)
                        } else {
                            Text("\(trimmedFirstName)'s")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(DS.Palette.lime)
                            Text("PROFILE")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.4)
                                .foregroundColor(.white)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(trimmedFirstName.isEmpty ? "Profile" : "\(trimmedFirstName)'s profile")
                    .padding(.trailing, 20)
                }
                .padding(.top, 20),
                alignment: .topLeading
            )
        }
        .frame(height: 146)
    }
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            lightGrey.ignoresSafeArea()

            VStack(spacing: 0) {
                courtStripHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        countrySection
                        personalDetailsSection
                        contactDetailsSection

                        // Save button removed: @AppStorage persists automatically.
                        Text("Changes save automatically")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(textMuted.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                            .padding(.bottom, 34)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        // Tap anywhere outside a field to dismiss the keyboard.
        .onTapGesture {
            focusedField = nil
        }
        .onChange(of: firstName) { _, _ in PlayerDirectory.shared.syncProfileName() }
        .onChange(of: lastName) { _, _ in PlayerDirectory.shared.syncProfileName() }
    }
    // MARK: - Country Section
    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COUNTRY")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(textMuted)
                .tracking(1.4)

            Menu {
                ForEach(countries, id: \.1) { country in
                    Button(action: { countryCode = country.1 }) {
                        HStack {
                            Text("\(country.0) \(country.1)")
                            if selectedCountry.1 == country.1 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedCountry.0)
                        .font(.system(size: 22))

                    Text(selectedCountry.1)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(royalBlue.opacity(0.8))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cardWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(stroke, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                )
            }
            .accessibilityLabel("Country: \(selectedCountry.1)")
            .accessibilityHint("Double tap to change country")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
    // MARK: - Personal Details Section
    private var personalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PERSONAL DETAILS")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(textMuted)
                .tracking(1.4)
                .padding(.horizontal, 4)

            VStack(spacing: 16) {
                // First / Last name row
                HStack(spacing: 12) {
                    nameField(
                        label: "FIRST NAME",
                        placeholder: "Pickle",
                        text: $firstName,
                        field: .firstName,
                        submitLabel: .next,
                        onSubmit: { focusedField = .lastName }
                    )
                    nameField(
                        label: "LAST NAME",
                        placeholder: "Ballers",
                        text: $lastName,
                        field: .lastName,
                        submitLabel: .next,
                        onSubmit: { focusedField = .email }
                    )
                }
                // Gender
                VStack(alignment: .leading, spacing: 7) {
                    Text("GENDER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textMuted)
                        .tracking(1.2)

                    // Use a Menu instead of a horizontal radio strip — fits
                    // 4 options without overflow and matches the country picker style.
                    Menu {
                        ForEach(genderOptions, id: \.self) { gender in
                            Button(action: { selectedGender = gender }) {
                                HStack {
                                    Text(gender)
                                    if selectedGender == gender {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedGender)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(royalBlue.opacity(0.8))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(fieldGrey)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(stroke, lineWidth: 1)
                                )
                        )
                    }
                    .accessibilityLabel("Gender: \(selectedGender)")
                    .accessibilityHint("Double tap to change")
                }
                // Birth Year
                VStack(alignment: .leading, spacing: 7) {
                    Text("BIRTH YEAR")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textMuted)
                        .tracking(1.2)

                    Menu {
                        ForEach(years, id: \.self) { year in
                            Button(year) { birthYear = year }
                        }
                    } label: {
                        HStack {
                            Text(birthYear)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(royalBlue.opacity(0.8))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(fieldGrey)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(stroke, lineWidth: 1)
                                )
                        )
                    }
                    .accessibilityLabel("Birth year: \(birthYear)")
                    .accessibilityHint("Double tap to change")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            )
        }
        .padding(.horizontal, 16)
    }
    // MARK: - Contact Details Section
    private var contactDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONTACT DETAILS")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(textMuted)
                .tracking(1.4)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 7) {
                Text("EMAIL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textMuted)
                    .tracking(1.2)
                TextField("Enter your email", text: $email)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fieldGrey)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        emailValidationError
                                            ? Color.red.opacity(0.55)
                                            : stroke,
                                        lineWidth: emailValidationError ? 1.2 : 1
                                    )
                            )
                    )
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .onChange(of: email) { _, newValue in
                        // Live validation: clear error as soon as input becomes
                        // valid (or empty), so the red border doesn't linger.
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || isValidEmail(trimmed) {
                            emailValidationError = false
                        }
                    }
                    .onSubmit {
                        let trimmed = email.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !isValidEmail(trimmed) {
                            emailValidationError = true
                        }
                    }
                    .accessibilityLabel("Email")

                if emailValidationError {
                    Text("Please enter a valid email address.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color.red.opacity(0.85))
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
            )
        }
        .padding(.horizontal, 16)
    }
    // MARK: - Helpers
    private func nameField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textMuted)
                .tracking(1.2)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .textContentType(field == .firstName ? .givenName : .familyName)
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldGrey)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(stroke, lineWidth: 1)
                        )
                )
                .accessibilityLabel(label.capitalized)
        }
    }
    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }
}
#Preview {
    ProfileEditView()
}
