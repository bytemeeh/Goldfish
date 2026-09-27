import SwiftUI
import SwiftData
import PhotosUI
import os

@MainActor
struct ContactFormView: View {
    private enum FormField: Hashable, CaseIterable {
        case firstName, lastName, phone, email, street, city, state, postalCode, country, tags, notes
    }
    private let logger = Logger(subsystem: "com.goldfish.app", category: "ContactFormView")
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: ContactFormViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showMoreDetails = false
    @FocusState private var focusedField: FormField?

    // Injected for circle picking
    @EnvironmentObject var dataManager: GoldfishDataManager

    private var selectedPondBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { viewModel.selectedCircleIDs.first },
            set: { newID in
                viewModel.selectedCircleIDs.removeAll()
                if let newID { viewModel.selectedCircleIDs.insert(newID) }
            }
        )
    }

    private var identitySection: some View {
        formSection(label: "Identity") {
            Picker("Contact type", selection: Binding<ContactKind>(
                get: { viewModel.contactKind.isPet ? .pet : .human },
                set: { value in
                    if value == .human { viewModel.contactKind = .human }
                    else if !viewModel.contactKind.isPet { viewModel.contactKind = .pet }
                }
            )) {
                Text("Person").tag(ContactKind.human)
                Text("Pet").tag(ContactKind.pet)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.existingPerson?.isMe == true)
            .accessibilityLabel("Contact type")
            .padding(.vertical, GoldfishDS.Space.lg)

            if viewModel.contactKind.isPet {
                hairline
                formField(placeholder: "Species") {
                    Picker("Species", selection: $viewModel.contactKind) {
                        Text("Dog").tag(ContactKind.dog)
                        Text("Cat").tag(ContactKind.cat)
                        Text("Other").tag(ContactKind.pet)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Pet species")
                }
            }
        }
    }

    private var pondSection: some View {
        formSection(label: "Pond") {
            if viewModel.existingPerson?.isMe == true {
                Text("You stay at the center and do not belong to a group.")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
            } else if viewModel.allCircles.isEmpty {
                Text("No ponds yet")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, GoldfishDS.Space.lg)
            } else {
                formField(placeholder: "Select pond") {
                    Picker("Select Pond", selection: selectedPondBinding) {
                        Text("None").tag(UUID?(nil))
                        ForEach(viewModel.allCircles, id: \.id) { circle in
                            Text(circle.name).tag(UUID?(circle.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .tint(GoldfishDS.terracotta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    var body: some View {
        ZStack {
            GoldfishDS.warmBlack.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: - Avatar Zone
                    if viewModel.existingPerson != nil {
                        avatarSection
                            .padding(.top, GoldfishDS.Space.xl)
                            .padding(.horizontal, GoldfishDS.Space.pageMargin)

                        hairline.padding(.top, GoldfishDS.Space.xl)

                        identitySection
                    }

                    // MARK: - Basic Info
                    formSection(label: "Basic Info") {
                        formField(placeholder: "First name (required)") {
                            TextField("First name", text: $viewModel.firstName)
                                .focused($focusedField, equals: .firstName)
                                .id(FormField.firstName)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfName)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.givenName)
                        }
                        hairline
                        formField(placeholder: "Last name") {
                            TextField("Last name", text: $viewModel.lastName)
                                .focused($focusedField, equals: .lastName)
                                .id(FormField.lastName)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfName)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.familyName)
                        }
                        if viewModel.existingPerson != nil {
                            hairline
                            formField(placeholder: "Phone") {
                                TextField("Phone", text: $viewModel.phone)
                                    .focused($focusedField, equals: .phone)
                                    .id(FormField.phone)
                                    .font(.gfBody)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                            }
                        }
                    }

                    if viewModel.isDemoMode && viewModel.existingPerson == nil {
                        Text("This person will be added to the demo. Turn off Show Demo Data in Settings to add your own contacts.")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .padding(.horizontal, GoldfishDS.Space.pageMargin)
                            .padding(.top, GoldfishDS.Space.lg)
                    }

                    // MARK: - First Thread (new contacts only)
                    if viewModel.existingPerson == nil {
                        sectionDivider
                        formSection(label: "How are you connected?") {
                            formField(placeholder: "Connected to") {
                                Picker("Connected to", selection: $viewModel.selectedConnectionID) {
                                    Text("Not connected yet").tag(UUID?(nil))
                                    ForEach(viewModel.allPersons) { person in
                                        Text(person.name).tag(UUID?(person.id))
                                    }
                                }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .tint(GoldfishDS.terracotta)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if viewModel.selectedConnectionID != nil {
                                hairline
                                formField(placeholder: "Relationship") {
                                    Picker("Relationship", selection: $viewModel.selectedRelationshipType) {
                                        ForEach(RelationshipType.allCases) { type in
                                            Text(type.displayName).tag(type)
                                        }
                                    }
                                    .font(.gfBody)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                    .tint(GoldfishDS.terracotta)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if let preview = viewModel.relationshipPreview {
                                    Text(preview)
                                        .font(.gfMeta)
                                        .foregroundStyle(GoldfishDS.ink(.secondary))
                                        .padding(.bottom, GoldfishDS.Space.lg)
                                }
                            } else {
                                Text("Choose a person to see the relationship direction before saving.")
                                    .font(.gfMeta)
                                    .foregroundStyle(GoldfishDS.ink(.secondary))
                                    .padding(.bottom, GoldfishDS.Space.lg)
                            }
                        }

                        sectionDivider
                        formSection(label: "Memory (optional)") {
                            memoryEditor
                        }

                        Button {
                            withAnimation(GoldfishDS.Motion.settle) { showMoreDetails.toggle() }
                        } label: {
                            Label(showMoreDetails ? "Hide more details" : "More details",
                                  systemImage: showMoreDetails ? "chevron.up" : "chevron.down")
                                .font(.gfBody.weight(.medium))
                                .foregroundStyle(GoldfishDS.terracotta)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, GoldfishDS.Space.xl)
                        .padding(.horizontal, GoldfishDS.Space.pageMargin)

                        if showMoreDetails {
                            sectionDivider
                            avatarSection
                                .padding(.top, GoldfishDS.Space.lg)
                                .padding(.horizontal, GoldfishDS.Space.pageMargin)
                            identitySection
                        }
                    }

                    if viewModel.existingPerson != nil || showMoreDetails {
                        // MARK: - Pond
                        sectionDivider
                        pondSection

                    // MARK: - Contact
                    sectionDivider
                    formSection(label: "Contact") {
                        if viewModel.existingPerson == nil {
                            formField(placeholder: "Phone") {
                                TextField("Phone", text: $viewModel.phone)
                                    .focused($focusedField, equals: .phone)
                                    .id(FormField.phone)
                                    .font(.gfBody)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                            }
                            hairline
                        }
                        formField(placeholder: "Email") {
                            TextField("Email", text: $viewModel.email)
                                .focused($focusedField, equals: .email)
                                .id(FormField.email)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        hairline
                        // Favorite toggle row
                        HStack {
                            Text("Favorite")
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                            Spacer()
                            Toggle("Favorite", isOn: $viewModel.isFavorite)
                                .labelsHidden()
                                .tint(GoldfishDS.terracotta)
                        }
                        .padding(.vertical, GoldfishDS.Space.lg)
                    }

                    // MARK: - Birthday
                    sectionDivider
                    formSection(label: "Birthday") {
                        HStack {
                            Text("Include birthday")
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                            Spacer()
                            Toggle("Include birthday", isOn: $viewModel.includeBirthday)
                                .labelsHidden()
                                .tint(GoldfishDS.terracotta)
                        }
                        .padding(.vertical, GoldfishDS.Space.lg)

                        if viewModel.includeBirthday {
                            hairline
                            DatePicker("Date", selection: $viewModel.birthday, in: ...Date(), displayedComponents: .date)
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .tint(GoldfishDS.terracotta)
                                .padding(.vertical, GoldfishDS.Space.lg)
                        }
                    }

                    // MARK: - Location
                    sectionDivider
                    formSection(label: "Location") {
                        formField(placeholder: "Street") {
                            TextField("Street", text: $viewModel.street)
                                .focused($focusedField, equals: .street)
                                .id(FormField.street)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.streetAddressLine1)
                        }
                        hairline
                        formField(placeholder: "City") {
                            TextField("City", text: $viewModel.city)
                                .focused($focusedField, equals: .city)
                                .id(FormField.city)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.addressCity)
                        }
                        hairline
                        formField(placeholder: "State") {
                            TextField("State", text: $viewModel.state)
                                .focused($focusedField, equals: .state)
                                .id(FormField.state)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.addressState)
                        }
                        hairline
                        formField(placeholder: "ZIP / Postal") {
                            TextField("ZIP/Postal", text: $viewModel.postalCode)
                                .focused($focusedField, equals: .postalCode)
                                .id(FormField.postalCode)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.postalCode)
                        }
                        hairline
                        formField(placeholder: "Country") {
                            TextField("Country", text: $viewModel.country)
                                .focused($focusedField, equals: .country)
                                .id(FormField.country)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                                .textContentType(.countryName)
                        }
                    }

                        // MARK: - Tags
                        sectionDivider
                        formSection(label: "Tags") {
                        formField(placeholder: "Tags, separated by commas") {
                            TextField("gym, work, neighbour…", text: $viewModel.tagsString)
                                .focused($focusedField, equals: .tags)
                                .id(FormField.tags)
                                .submitLabel(.next)
                                .onSubmit { advanceFocus() }
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.primary))
                        }
                        }
                    }

                    // MARK: - Notes
                    if viewModel.existingPerson != nil {
                        sectionDivider
                        formSection(label: "Notes") {
                            memoryEditor
                        }
                    }

                    // MARK: - Primary action
                    Button {
                        if viewModel.save() {
                            dismiss()
                        }
                    } label: {
                        ctaLabel(viewModel.existingPerson == nil ? "Add Contact" : "Save Changes")
                            .background(
                                RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                    .fill(GoldfishDS.ink(viewModel.isValid ? .primary : .quaternary))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isValid || isLoadingPhoto)
                    .padding(.top, GoldfishDS.Space.xxl)
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)

                    // MARK: - Danger Zone
                    if let existing = viewModel.existingPerson, !existing.isMe {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            ctaLabel("Delete Contact")
                                .background(
                                    RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                        .fill(GoldfishDS.terracotta)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, GoldfishDS.Space.md)
                        .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    }

                    Spacer(minLength: GoldfishDS.Space.xxl)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                withAnimation(GoldfishDS.Motion.settle) {
                    scrollProxy.scrollTo(field, anchor: .center)
                }
            }
            }
        }
        .navigationTitle(viewModel.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if viewModel.hasUnsavedChanges { showDiscardConfirmation = true } else { dismiss() }
                }
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if viewModel.save() {
                        dismiss()
                    }
                }
                .font(.gfBody.weight(.medium))
                .foregroundStyle(viewModel.isValid ? GoldfishDS.terracotta : GoldfishDS.ink(.quaternary))
                .disabled(!viewModel.isValid || isLoadingPhoto)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous") { moveFocus(offset: -1) }
                    .disabled(focusedField == visibleFormFields.first || focusedField == nil)
                Spacer()
                Button("Next") { advanceFocus() }
                    .disabled(focusedField == visibleFormFields.last || focusedField == nil)
                Button("Done") { focusedField = nil }
                    .foregroundStyle(GoldfishDS.terracotta)
            }
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges || isLoadingPhoto)
        .confirmationDialog("Discard changes?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text("Your unsaved changes will be lost.") }
        .confirmationDialog("Delete contact?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Contact", role: .destructive) {
                if let person = viewModel.existingPerson {
                    do { try dataManager.deletePerson(person); dismiss() }
                    catch { viewModel.errorMessage = "Could not delete: \(error.localizedDescription)" }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This permanently deletes this contact and their connections. Other contacts are kept.") }
        .alert("Could not complete action", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            isLoadingPhoto = true
            Task {
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let photo = image.jpegData(compressionQuality: 0.85) else {
                        viewModel.errorMessage = "This image could not be opened. Choose another photo."
                        return
                    }
                    viewModel.photoData = photo
                    viewModel.emojiAvatar = ""
                } catch { viewModel.errorMessage = "Could not load photo: \(error.localizedDescription)" }
            }
        }
        .onAppear {
            if viewModel.existingPerson == nil, focusedField == nil {
                focusedField = .firstName
            }
        }
    }

    private var visibleFormFields: [FormField] {
        if viewModel.existingPerson == nil && !showMoreDetails {
            return [.firstName, .lastName, .notes]
        }
        return FormField.allCases
    }

    private func moveFocus(offset: Int) {
        guard let focusedField,
              let index = visibleFormFields.firstIndex(of: focusedField) else { return }
        let nextIndex = index + offset
        guard visibleFormFields.indices.contains(nextIndex) else {
            self.focusedField = nil
            return
        }
        self.focusedField = visibleFormFields[nextIndex]
    }

    private func advanceFocus() {
        moveFocus(offset: 1)
    }

    // MARK: - Hairline

    private var hairline: some View {
        Rectangle()
            .fill(GoldfishDS.ink(.hairline))
            .frame(height: 0.5)
    }

    /// Breathing room between sections (cards carry their own hairline rings)
    private var sectionDivider: some View {
        Color.clear
            .frame(height: GoldfishDS.Space.sm)
            .padding(.top, GoldfishDS.Space.lg)
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func formSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .gfSectionLabel()
                .padding(.top, GoldfishDS.Space.lg)
                .padding(.bottom, GoldfishDS.Space.sm)
                .padding(.horizontal, GoldfishDS.Space.pageMargin)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, GoldfishDS.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                    .fill(GoldfishDS.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                    .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
            )
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
        }
    }

    // MARK: - CTA label (full-width signage button)

    private func ctaLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.gfBody.weight(.medium))
            .kerning(1.2)
            .foregroundStyle(GoldfishDS.paper)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
    }

    // MARK: - Form field row

    @ViewBuilder
    private func formField<Content: View>(
        placeholder: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
            Text(placeholder)
                .font(.gfCaption)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            content()
                .accessibilityLabel(placeholder)
        }
        .padding(.vertical, GoldfishDS.Space.md)
    }

    private var memoryEditor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.notes.isEmpty {
                Text(viewModel.existingPerson == nil
                     ? "Something worth remembering…"
                     : "Any notes about this person…")
                    .font(.gfProse)
                    .foregroundStyle(GoldfishDS.ink(.quaternary))
                    .padding(.top, GoldfishDS.Space.lg)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.notes)
                .focused($focusedField, equals: .notes)
                .id(FormField.notes)
                .accessibilityLabel(viewModel.existingPerson == nil ? "Optional memory" : "Notes")
                .font(.gfProse)
                .foregroundStyle(GoldfishDS.ink(.primary))
                .scrollContentBackground(.hidden)
                .frame(minHeight: viewModel.existingPerson == nil ? 80 : 100)
                .padding(.vertical, GoldfishDS.Space.md)
                .tint(GoldfishDS.terracotta)
        }
    }

    // MARK: - Avatar Zone

    private var avatarSection: some View {
        let emojiAvatar = viewModel.emojiAvatar
        let photoData = viewModel.photoData
        let loadingPhoto = isLoadingPhoto
        return VStack(spacing: GoldfishDS.Space.md) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                VStack(spacing: GoldfishDS.Space.sm) {
                    if !emojiAvatar.isEmpty {
                        Text(emojiAvatar).font(.system(size: 54)).frame(width: 88, height: 88)
                    } else if let data = photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 88, height: 88).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 54)).frame(width: 88, height: 88)
                    }
                    Text(loadingPhoto ? "Loading photo…" : "Choose Photo").font(.gfBody)
                }
                .foregroundStyle(GoldfishDS.terracotta)
            }
            .disabled(isLoadingPhoto)
            .accessibilityLabel("Choose contact photo")
            .accessibilityIdentifier("choosePhotoButton")

            HStack {
                Text("Or use an emoji").font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
                TextField("Emoji", text: $viewModel.emojiAvatar)
                    .font(.title2).multilineTextAlignment(.center)
                    .frame(width: 64, height: 44)
                    .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                    .accessibilityLabel("Emoji avatar")
                    .onChange(of: viewModel.emojiAvatar) { _, value in
                        if value.count > 1 { viewModel.emojiAvatar = String(value.prefix(1)) }
                    }
            }
            if viewModel.photoData != nil || !viewModel.emojiAvatar.isEmpty {
                Button("Remove Photo or Emoji", role: .destructive) {
                    viewModel.photoData = nil
                    viewModel.emojiAvatar = ""
                    selectedPhoto = nil
                }
                .font(.gfMeta)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
