import SwiftUI
import SpriteKit
import SwiftData

// MARK: - Graph Container View
/// SwiftUI wrapper hosting the SpriteKit graph scene.
struct GraphContainerView: View {
    private struct HiddenPondOption: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    @ObservedObject var viewModel: GraphViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMapHelp = false
    @State private var branchShare: IdentifiableWrapper<[UUID]>?
    @AppStorage("pondTipExploreSeen") private var exploreTipSeen = false
    @AppStorage("pondTipArrangeSeen") private var arrangeTipSeen = false
    @State private var batchConnectionPerson: Person?


    @State private var scene = GoldfishGraphScene(size: CGSize(width: 390, height: 844))
    @State private var connectRelType: RelationshipType = .friend
    @State private var connectGroupID: String = ""
    @State private var isAddContactPresented = false
    @State private var isImportSettingsPresented = false
    @Query private var circles: [GoldfishCircle]

    private func updateObscuredInsets() {
        let insets = walkthroughManager.graphObscuredInsets
        scene.topObscuredInset = insets.top
        scene.bottomObscuredInset = insets.bottom
    }

    private var tourCardCoversBottomControls: Bool {
        walkthroughManager.isActive && walkthroughManager.currentStep.hintPlacement == .bottom
    }

    private var graphAccessibility: some View {
        VStack {
            ForEach(visiblePondPeople) { person in
                Button(person.isMe ? "You, \(person.name)" : person.name) {
                    viewModel.activatePondContact(id: person.id)
                }
                .accessibilityHint(pondContactHint(person))
                .accessibilityActions {
                    pondConnectionAccessibilityActions(for: person)
                }
                .accessibilityLabel(pondContactLabel(person))
                .accessibilityIdentifier("pondContact-\(person.name)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visible people and connections in the pond")
    }

    var body: some View {
        ZStack {
            // Adaptive paper canvas behind the transparent map and every
            // empty/loading state.
            GoldfishDS.warmBlack.ignoresSafeArea()
                .sheet(item: $batchConnectionPerson) { person in
                    BatchConnectionsView(person: person, dataManager: dataManager) { _ in
                        viewModel.refreshGraph()
                        viewModel.activatePondContact(id: person.id)
                    }
                }

            // MARK: - Map and footer
            // Give the footer a real row below the map so the measured SpriteView
            // frame stays aligned with the area SpriteKit actually renders.
            VStack(spacing: 0) {
                if viewModel.graphLevels != nil && !viewModel.hasNoData && !dynamicTypeSize.isAccessibilitySize {
                    GeometryReader { proxy in
                        ZStack {
                            PondCanvasBackground()
                                .allowsHitTesting(false)
                            SpriteView(scene: scene, options: [.allowsTransparency])
                            .onAppear {
                                scene.scaleMode = .resizeFill
                                updateViewport(size: proxy.size, frame: proxy.frame(in: .global))
                            }
                            .onChange(of: proxy.size) { _, size in
                                updateViewport(size: size, frame: proxy.frame(in: .global))
                            }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in
                                updateViewport(size: proxy.size, frame: frame)
                            }
                            // Keep SpriteKit in the actual host viewport. Without an
                            // explicit frame, SpriteView can retain its intrinsic scene
                            // size and render a small island inside the full-width card.
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .accessibilityRepresentation { graphAccessibility }
                            // At accessibility text sizes the inspector supplies native,
                            // scrolling rows. Hiding this representation avoids announcing
                            // the same people twice.
                            .accessibilityHidden(dynamicTypeSize.isAccessibilitySize)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if viewModel.graphLevels != nil && !viewModel.hasNoData && !tourCardCoversBottomControls {
                    if dynamicTypeSize.isAccessibilitySize {
                        // A map cannot remain legible in the sliver left by very
                        // large controls. Give the native exploration controls
                        // and contact rows one continuous scrolling surface.
                        ScrollView {
                            graphFooter
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        graphFooter
                    }
                }
            }

            // MARK: - Loading
            if viewModel.isLoading {
                ProgressView("Composing your pond…")
                    .font(.gfMeta)
                    .tint(GoldfishDS.ink(.secondary))
                    .padding()
                    .background(GoldfishDS.surface)
                    .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                            .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                    )
            }

            // MARK: - Empty State
            if viewModel.hasNoData && !viewModel.isLoading && viewModel.rippleFocus == nil {
                EmptyStateView(
                    systemImage: "circle.hexagongrid",
                    headline: "Your pond starts here.",
                    subtext: "Add or import people to begin mapping your connections.",
                    actionLabel: "Add a contact",
                    editorial: true,
                    action: {
                        isAddContactPresented = true
                    },
                    secondaryActionLabel: viewModel.isDemoMode ? nil : "Import contacts",
                    secondaryAction: viewModel.isDemoMode ? nil : { isImportSettingsPresented = true }
                )
            }
            
            // MARK: - Inline Connect Popup
            if viewModel.pendingConnectionFrom != nil && viewModel.pendingConnectionTo != nil {
                connectPopupOverlay
                    .onAppear {
                        // Suppress the already-connected dialog during the walkthrough tour:
                        // if both IDs exist but the pair is already connected and the tour
                        // is active, clear the pending state and fire a light haptic instead.
                        if walkthroughManager.isActive,
                           let fromID = viewModel.pendingConnectionFrom,
                           let toID   = viewModel.pendingConnectionTo,
                           let all    = try? dataManager.fetchAllPersons(),
                           let from   = all.first(where: { $0.id == fromID }),
                           from.allRelationships.contains(where: { $0.fromContact.id == toID || $0.toContact.id == toID }) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo   = nil
                        }
                    }
            }
            
            // MARK: - Inline Line Move Popup
            if viewModel.pendingPondMovePerson != nil && viewModel.pendingPondMoveTarget != nil {
                pondMovePopupOverlay
            }
        }
        .overlay(alignment: .top) {
            if let feedback = viewModel.latestPondReveal, !dynamicTypeSize.isAccessibilitySize,
               viewModel.disclosureCurrentPerson == nil {
                revealFeedback(feedback)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .confirmationDialog("Which contact?", isPresented: Binding(
            get: { !viewModel.pendingContactChoiceIDs.isEmpty },
            set: { if !$0 { viewModel.cancelPendingContactChoice() } }
        ), titleVisibility: .visible) {
            ForEach(viewModel.pendingContactChoiceIDs, id: \.self) { id in
                if let person = pondPerson(id) {
                    Button(contactChoiceLabel(person)) {
                        viewModel.choosePendingContact(id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPendingContactChoice() }
        } message: {
            Text("These contacts are close together. Choose the one you meant.")
        }
        .sheet(item: $branchShare) { share in
            NavigationStack {
                ContactExportSelectionView(selectedContactIDs: Set(share.value))
                    .environmentObject(dataManager)
                    .environmentObject(demoModeManager)
            }
        }
        .sheet(isPresented: $showsMapHelp) {
            MapHelpView()
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .onAppear {
            scene.graphDelegate = viewModel
            viewModel.sceneDelegate = scene
            scene.opensRipplesOnTap = true
            scene.showsMeDuringGuidedTour = walkthroughManager.isActive
            viewModel.loadGraph()
            scene.didUpdateGroups(viewModel.groups)
            pushLevelsToScene()
            scene.didUpdatePondFilter(viewModel.selectedPondFilter)
            scene.didUpdateSearchMatches(viewModel.searchMatchedIDs)
            scene.didSelectContact(viewModel.selectedContactID)
            scene.didUpdateRipple(focus: viewModel.rippleFocus, neighbors: viewModel.visibleRippleNeighbors)
            scene.didUpdateDisclosure(viewModel.pondDisclosureSnapshot)
            // The footer now occupies its own row below the map, so it does not
            // overlap the map viewport. Tour insets only describe the tour card.
            walkthroughManager.graphFooterHeight = 0
            updateObscuredInsets()
        }
        .onChange(of: viewModel.levelsLoaded) { _, loaded in
            // When graph data changes and finishes loading, push it to the scene
            if loaded {
                pushLevelsToScene()
            }
        }
        .onChange(of: viewModel.pondDisclosureSnapshot) { previous, snapshot in
            scene.didUpdateDisclosure(snapshot)
            if snapshot.selectedID != nil { exploreTipSeen = true }
            if let target = walkthroughManager.branchPersonID,
               !previous.expandedIDs.contains(target), snapshot.expandedIDs.contains(target) {
                walkthroughManager.report(.expandedConnections)
            }
        }
        .onChange(of: walkthroughManager.isActive) { _, isActive in
            scene.opensRipplesOnTap = true
            scene.showsMeDuringGuidedTour = isActive
            updateObscuredInsets()
        }
        .onChange(of: walkthroughManager.currentStep) { _, _ in updateObscuredInsets() }
        .onChange(of: walkthroughManager.overlayFrame) { _, _ in updateObscuredInsets() }
        .onChange(of: walkthroughManager.graphViewportFrame) { _, _ in updateObscuredInsets() }
        .onDisappear { walkthroughManager.graphViewportFrame = .zero }
        .sheet(item: Binding<IdentifiableWrapper<UUID>?>(
            get: { viewModel.selectedContactID.map { IdentifiableWrapper($0, id: $0) } },
            set: { viewModel.selectedContactID = $0?.value }
        ), onDismiss: {
            // The locator is transient: once the contact sheet closes, remove
            // its ring and restore ordinary first-name labels.
            viewModel.selectedContactID = nil
            viewModel.refreshGraph()
        }) { wrapper in
            if let person = try? dataManager.fetchAllPersons().first(where: { $0.id == wrapper.value }) {
                NavigationStack {
                    ContactDetailView(
                        viewModel: ContactDetailViewModel(person: person, dataManager: dataManager),
                        showsCloseButton: true,
                        onExploreRipples: { contactID in
                            viewModel.selectedContactID = nil
                            viewModel.openRipple(contactID)
                        }
                    )
                }
            }
        }
        .confirmationDialog(
            "Contact Actions",
            isPresented: Binding(
                get: { viewModel.pendingActionContactID != nil },
                set: { if !$0 { viewModel.pendingActionContactID = nil } }
            ),
            presenting: viewModel.pendingActionContactID
        ) { contactID in
            Button("Open Contact") {
                viewModel.selectContact(contactID)
                viewModel.pendingActionContactID = nil
            }
            Button("Show in Pond") {
                viewModel.pendingActionContactID = nil
                viewModel.openRipple(contactID)
            }
            
            // Generate a button for each existing line (only for non-Me contacts)
            if let person = try? dataManager.fetchAllPersons().first(where: { $0.id == contactID }),
               !person.isMe {
                ForEach(circles.sorted(by: { $0.sortOrder < $1.sortOrder })) { circle in
                    Button("Assign to \(circle.name)") {
                        assignContact(contactID, to: circle)
                        viewModel.pendingActionContactID = nil
                    }
                }
            }
            
            Button("Cancel", role: .cancel) {
                viewModel.pendingActionContactID = nil
            }
        } message: { contactID in
            if let person = try? dataManager.fetchAllPersons().first(where: { $0.id == contactID }) {
                Text("Actions for \(person.name)")
            } else {
                Text("Contact Actions")
            }
        }
        .alert("Could not complete action", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        .sheet(isPresented: $isAddContactPresented, onDismiss: {
            viewModel.refreshGraph()
        }) {
            NavigationStack {
                ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager, isDemoMode: viewModel.isDemoMode, initialCircleID: viewModel.selectedPondFilter.flatMap(UUID.init(uuidString:))))
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $isImportSettingsPresented) {
            NavigationStack {
                SettingsView(startWithImport: true)
                    .environmentObject(dataManager)
                    .environmentObject(walkthroughManager)
                    .environmentObject(demoModeManager)
            }
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
    }

    /// Helper to assign a contact to a line from the shortcut menu
    private func assignContact(_ contactID: UUID, to circle: GoldfishCircle) {
        guard let allPersons = try? dataManager.fetchAllPersons(),
              let person = allPersons.first(where: { $0.id == contactID }) else { return }

        // Already in this exact circle? No-op.
        if person.circleContacts.contains(where: { $0.circle.id == circle.id && !$0.manuallyExcluded }) {
            ToastManager.shared.showToast(message: "\(person.name) is already on the \(circle.name) pond")
            return
        }

        do {
            let undo = try dataManager.changePondMembership(of: person, to: circle)
            showPondMoveUndo(undo, message: "Moved \(person.name) to \(circle.name)")
        } catch { viewModel.errorMessage = error.localizedDescription; return }
        viewModel.refreshGraph()
    }

    /// Keep the viewport frame in SwiftUI's global coordinate space, matching
    /// the walkthrough card measurement. The fixed SpriteView frame below is
    /// the same rectangle SpriteKit renders into.
    private func updateViewport(size: CGSize, frame: CGRect) {
#if DEBUG
        let layoutTraceEnabled = ProcessInfo.processInfo.arguments.contains("--ui-layout-trace")
        if layoutTraceEnabled {
            print("[GoldfishLayout] proxy size=\(size) frame=\(frame) sceneBefore=\(scene.size) footerRow=separate insets=(\(scene.topObscuredInset),\(scene.bottomObscuredInset))")
        }
#endif
        guard size.width.isFinite, size.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              size.width >= 240, size.height >= 100,
              frame.minX >= -1, frame.minY >= -1,
              abs(frame.width - size.width) <= 1,
              abs(frame.height - size.height) <= 1 else { return }

        if scene.size != size { scene.size = size }
        let measuredFrame = frame.integral
        if walkthroughManager.graphViewportFrame != measuredFrame {
            walkthroughManager.graphViewportFrame = measuredFrame
        }
        updateObscuredInsets()
#if DEBUG
        if layoutTraceEnabled {
            let overlay = walkthroughManager.overlayFrame
            let insets = walkthroughManager.graphObscuredInsets
            print("[GoldfishLayout] global viewport=\(measuredFrame) overlay=\(overlay) insets=(\(insets.top),\(insets.bottom)) scene=\(scene.size) zoom=\(scene.currentZoomForDebug)")
        }
#endif
    }

    /// Pushes current graph levels to the persistent scene.
    private func pushLevelsToScene() {
        guard let levels = viewModel.graphLevels else { return }
        scene.didUpdateGraphLevels(levels)
        scene.didUpdateRipple(focus: viewModel.rippleFocus, neighbors: viewModel.visibleRippleNeighbors)
    }
    
    @ViewBuilder
    private var connectPopupOverlay: some View {
        if let fromID = viewModel.pendingConnectionFrom,
           let toID = viewModel.pendingConnectionTo,
           let allPersons = try? dataManager.fetchAllPersons(),
           let fromPerson = allPersons.first(where: { $0.id == fromID }),
           let toPerson = allPersons.first(where: { $0.id == toID }) {
            
            let existingRelationship = fromPerson.allRelationships.first(where: {
                ($0.fromContact.id == toID || $0.toContact.id == toID)
            })
            
            popupCard {
            VStack(spacing: 16) {
                if let existing = existingRelationship {
                    // ── Already Connected: Edit/Remove ──
                    Text("Already Connected")
                        .font(.gfName)
                        .foregroundStyle(GoldfishDS.ink(.primary))

                    HStack(spacing: 20) {
                        ContactPhotoView(person: fromPerson, size: .medium)
                            .overlay(Circle().stroke(GoldfishDS.ink(.hairline), lineWidth: 1))

                        VStack(spacing: 2) {
                            Image(systemName: "link")
                                .font(.title2)
                                .foregroundStyle(GoldfishDS.terracotta)
                            Text(existing.type.displayName)
                                .font(.gfMeta)
                                .foregroundStyle(GoldfishDS.ink(.tertiary))
                        }

                        ContactPhotoView(person: toPerson, size: .medium)
                            .overlay(Circle().stroke(GoldfishDS.ink(.hairline), lineWidth: 1))
                    }

                    Text("\(fromPerson.name) and \(toPerson.name) are already connected.")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .multilineTextAlignment(.center)

                    // Destructive action — marker-red outline, severity by colour.
                    Button {
                        do {
                            let undo = try dataManager.removeRelationshipWithUndo(existing)
                            ToastManager.shared.showToast(message: "Connection removed", actionTitle: "Undo") {
                                do {
                                    _ = try dataManager.restoreRemovedRelationship(using: undo)
                                    viewModel.refreshGraph()
                                    ToastManager.shared.showToast(message: "Connection restored")
                                } catch { viewModel.errorMessage = error.localizedDescription }
                            }
                        } catch { viewModel.errorMessage = error.localizedDescription; return }

                        withAnimation(GoldfishDS.Motion.snappy) {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                        viewModel.refreshGraph()
                    } label: {
                        Text("REMOVE CONNECTION")
                            .font(.gfLabel)
                            .kerning(1.2)
                            .foregroundStyle(GoldfishDS.terracotta)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                    .strokeBorder(GoldfishDS.terracotta.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        withAnimation {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                    }
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .buttonStyle(.plain)
                } else {
                    // ── New Connection ──
                    Text("Connect \(fromPerson.name) → \(toPerson.name)")
                        .font(.gfName)
                        .foregroundStyle(GoldfishDS.ink(.primary))

                    HStack(spacing: 20) {
                        ContactPhotoView(person: fromPerson, size: .medium)
                            .overlay(Circle().stroke(GoldfishDS.ink(.hairline), lineWidth: 1))

                        Image(systemName: "arrow.left.and.right")
                            .font(.title2)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))

                        ContactPhotoView(person: toPerson, size: .medium)
                            .overlay(Circle().stroke(GoldfishDS.ink(.hairline), lineWidth: 1))
                    }

                    VStack(spacing: 12) {
                        Text(connectRelType == .other
                             ? "Record a connection from \(fromPerson.name) to \(toPerson.name)."
                             : "\(fromPerson.name) is a \(connectRelType.displayName.lowercased()) of \(toPerson.name).")
                            .font(.gfBody.weight(.medium))
                            .foregroundStyle(GoldfishDS.ink(.primary))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        HStack {
                            Text("Relationship type")
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.secondary))
                            Spacer()
                            Picker("Relationship type", selection: $connectRelType) {
                                ForEach(RelationshipType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                        }

                        HStack {
                            Text("Add to pond")
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.secondary))
                            Spacer()
                            Picker("Add to pond", selection: $connectGroupID) {
                                Text("None").tag("")
                                if let circles = try? dataManager.fetchAllCircles() {
                                    ForEach(circles) { circle in
                                        Text(circle.name).tag(circle.id.uuidString)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    
                    Button {
                        var createdRelationshipID: UUID?
                        let relationshipIDsBeforeSave = Set(fromPerson.allRelationships.map(\.id))
                        do {
                            try dataManager.performAtomicEdit {
                                let relationship = try dataManager.createRelationship(from: fromPerson, to: toPerson, type: connectRelType,
                                                                                      skipAutoAssign: true)
                                if !relationshipIDsBeforeSave.contains(relationship.id) {
                                    createdRelationshipID = relationship.id
                                }
                                if !connectGroupID.isEmpty {
                                    guard let group = circles.first(where: { $0.id.uuidString == connectGroupID }) else {
                                        throw GoldfishError.circleNotFound
                                    }
                                    if !fromPerson.isMe { try dataManager.addToCircle(fromPerson, circle: group) }
                                    if !toPerson.isMe { try dataManager.addToCircle(toPerson, circle: group) }
                                }
                            }
                        } catch { viewModel.errorMessage = error.localizedDescription; return }

                        if let createdRelationshipID {
                            ToastManager.shared.showToast(
                                message: "Connected \(fromPerson.name) & \(toPerson.name)",
                                actionTitle: "Undo"
                            ) { [dataManager] in
                                do {
                                    if try dataManager.undoCreatedRelationship(id: createdRelationshipID) {
                                        ToastManager.shared.showToast(message: "Connection undone")
                                    }
                                } catch {
                                    ToastManager.shared.showToast(message: "Could not undo connection")
                                }
                            }
                        }

                        viewModel.confirmConnection()

                        withAnimation(GoldfishDS.Motion.snappy) {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                        viewModel.refreshGraph()

                        connectRelType = .friend
                        connectGroupID = ""
                    } label: {
                        Text("CONFIRM CONNECTION")
                            .font(.gfLabel)
                            .kerning(1.2)
                            .foregroundStyle(GoldfishDS.paper)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(GoldfishDS.ink(.primary))
                            .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                    }
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        withAnimation(GoldfishDS.Motion.snappy) {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                    }
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .buttonStyle(.plain)
                }
            }
            }
        }
    }

    @ViewBuilder
    private var pondMovePopupOverlay: some View {
        if let personID = viewModel.pendingPondMovePerson,
           let groupID = viewModel.pendingPondMoveTarget,
           (groupID == "unassigned" || circles.contains(where: { $0.id.uuidString == groupID })),
           let allPersons = try? dataManager.fetchAllPersons(),
           let person = allPersons.first(where: { $0.id == personID }),
           !person.isMe {
            let group = circles.first { $0.id.uuidString == groupID }
            let pondName = group?.name ?? "Unassigned"
            popupCard {
            VStack(spacing: 16) {
                Text("Change ponds?")
                    .font(.gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))

                HStack(spacing: 20) {
                    ContactPhotoView(person: person, size: .medium)
                        .overlay(Circle().stroke(GoldfishDS.ink(.hairline), lineWidth: 1))

                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))

                    // The destination line's roundel.
                    ZStack {
                        Circle()
                            .fill(GoldfishDS.graphTone(group))
                            .frame(width: 50, height: 50)
                        Text(String(pondName.prefix(1).uppercased()))
                            .font(.gfName)
                            .foregroundStyle(.white)
                    }
                }

                Text("Move **\(person.name)** to the **\(pondName)** pond.")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    do {
                        let undo = try dataManager.changePondMembership(of: person, to: group)
                        showPondMoveUndo(undo, message: "Moved \(person.name) to \(pondName)")
                    } catch { viewModel.errorMessage = error.localizedDescription; return }

                    withAnimation(GoldfishDS.Motion.snappy) {
                        viewModel.pendingPondMovePerson = nil
                        viewModel.pendingPondMoveTarget = nil
                    }
                    viewModel.refreshGraph()
                } label: {
                    Text("MOVE")
                        .font(.gfLabel)
                        .kerning(1.2)
                        .foregroundStyle(GoldfishDS.paper)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(GoldfishDS.ink(.primary))
                        .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                }
                .buttonStyle(.plain)

                Button("Cancel") {
                    withAnimation(GoldfishDS.Motion.snappy) {
                        viewModel.pendingPondMovePerson = nil
                        viewModel.pendingPondMoveTarget = nil
                    }
                }
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .buttonStyle(.plain)
            }
            }
        }
    }
    
    private func popupCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { area in
            ScrollView {
                content().padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: min(max(area.size.height - 24, 100), 560))
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .frame(maxHeight: .infinity)
        }
        .transition(.opacity)
        .zIndex(100)
    }

    private var allGraphPeople: [Person] {
        var seen = Set<UUID>()
        return (viewModel.graphLevels ?? []).flatMap(\.allContacts).filter { seen.insert($0.id).inserted }
    }

    private var visiblePondPeople: [Person] {
        let visible = viewModel.pondDisclosureSnapshot.visibleIDs
        let disclosed = visible.isEmpty ? allGraphPeople : allGraphPeople.filter { visible.contains($0.id) }
        let people = disclosed.filter { person in
            if person.isMe {
                return walkthroughManager.isActive || viewModel.pondDisclosureSnapshot.pathHighlightIDs.contains(person.id)
            }
            return viewModel.selectedPondFilter == nil ||
                (person.primaryCircle?.id.uuidString ?? "unassigned") == viewModel.selectedPondFilter
        }
        return people.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    private func pondPerson(_ id: UUID) -> Person? {
        allGraphPeople.first { $0.id == id }
    }

    private var pondGraph: RippleGraph {
        RippleGraph(people: allGraphPeople)
    }

    /// Describe the actual incoming relationship, independently of pond membership.
    private func explorationRelationshipSummary(for person: Person) -> String {
        let trail = viewModel.pondDisclosureSnapshot.trail
        if trail.last == person.id, let anchorID = trail.dropLast().last,
           let anchor = pondPerson(anchorID), !anchor.isMe,
           let role = pondGraph.role(of: person.id, relativeTo: anchorID) {
            return "\(anchor.name)’s \(role.roleLabel.lowercased())"
        }
        return RelationshipContextService(people: allGraphPeople).summary(for: person) ?? "No saved path from you"
    }

    private func roleAndPath(for person: Person) -> String {
        if person.isMe { return "You · Pond starting point" }
        let context = RelationshipContextService(people: allGraphPeople)
        let path = viewModel.pondDisclosureSnapshot.trail.compactMap { pondPerson($0)?.name }.joined(separator: " → ")
        return [context.summary(for: person) ?? "No saved path from you",
                "Pond: \(person.primaryCircle?.name ?? "Unassigned")", path]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func contactChoiceLabel(_ person: Person) -> String {
        let candidates = viewModel.pendingContactChoiceIDs.compactMap(pondPerson)
        let base = "\(person.name) · \(person.primaryCircle?.name ?? "Unassigned")"
        guard candidates.filter({ $0.name == person.name && $0.primaryCircle?.id == person.primaryCircle?.id }).count > 1 else { return base }
        let context = RelationshipContextService(people: allGraphPeople).compactSummary(for: person)
        let detail = [context, person.city, person.email, person.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        let position = (viewModel.pendingContactChoiceIDs.firstIndex(of: person.id) ?? 0) + 1
        return [base, detail, position == 1 ? "Closest to your tap" : "Match \(position) by distance"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func pondContactLabel(_ person: Person) -> String {
        let identity = person.isMe ? "You" : person.name
        let snapshot = viewModel.pondDisclosureSnapshot
        if snapshot.selectedID == person.id {
            return "\(identity), selected, \(roleAndPath(for: person))"
        }
        let hiddenCount = snapshot.hiddenNeighborCounts[person.id] ?? 0
        let state: String
        if snapshot.expandedIDs.contains(person.id) {
            state = hiddenCount > 0
                ? "connections showing, \(hiddenCount) additional connections available"
                : "connections showing"
        } else {
            state = hiddenCount > 0 ? "\(hiddenCount) additional connections available" : "No hidden connections"
        }
        let pond = person.isMe ? "Pond starting point" : (person.primaryCircle?.name ?? "Unassigned")
        return "\(identity), \(pond), \(state)"
    }

    private func pondContactHint(_ person: Person) -> String {
        if viewModel.isPondConnectionsExpanded(person.id) { return "Opens this person's connections" }
        if viewModel.canShowPondConnections(person.id) {
            return viewModel.hiddenPondNeighborCount(for: person.id) > 0
                ? "Opens this person and reveals saved connections"
                : "Keeps shared connections visible if another branch is closed"
        }
        return "Opens this person in the pond"
    }

    @ViewBuilder
    private func pondConnectionAccessibilityActions(for person: Person) -> some View {
        Button("Open contact") { viewModel.selectContact(person.id) }
        if !walkthroughManager.isActive {
            let hiddenCount = viewModel.hiddenPondNeighborCount(for: person.id)
            if viewModel.isPondConnectionsExpanded(person.id) {
                if hiddenCount > 0 {
                    Button("Show more") { viewModel.showMorePondConnections(person.id) }
                }
                Button("Hide connections") { viewModel.togglePondConnections(person.id) }
            } else if viewModel.canShowPondConnections(person.id) {
                Button(hiddenCount > 0 ? "Show connections" : "Keep connections open") {
                    viewModel.activatePondContact(id: person.id)
                }
            }
        }
    }

    private var hasOpenPondBranches: Bool {
        let snapshot = viewModel.pondDisclosureSnapshot
        var baseline = snapshot.directIDs
        if let me = allGraphPeople.first(where: \.isMe) { baseline.insert(me.id) }
        return !snapshot.expandedIDs.isEmpty || !snapshot.visibleIDs.subtracting(baseline).isEmpty
    }

    private var hasAdditionalDisclosure: Bool {
        hasOpenPondBranches || viewModel.disclosureCurrentPerson != nil
    }

    private var pondInspector: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorSummary
                    inspectorActions
                    accessibleVisiblePeople
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.disclosureCurrentPerson != nil {
                        inspectorSummary
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    inspectorActions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tint(GoldfishDS.terracotta)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var inspectorSummary: some View {
        if let person = viewModel.disclosureCurrentPerson {
            VStack(alignment: .leading, spacing: 3) {
                let headingLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 6))
                headingLayout {
                    Text(person.isMe ? "You" : person.name)
                        .font(dynamicTypeSize.isAccessibilitySize ? .headline : .gfName)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if viewModel.pondDisclosureSnapshot.focusRootID != nil {
                        Button {
                            returnToPreviousPondTrailPosition()
                        } label: {
                            Label("Back", systemImage: "arrow.uturn.backward")
                                .font(.gfCaption.weight(.medium))
                                .lineLimit(1)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 8)
                                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(focusReturnButtonTitle)
                        .accessibilityHint(focusReturnButtonHint)
                        .accessibilityIdentifier("pondTrailBackButton")
                    }
                }
                Text(explorationRelationshipSummary(for: person))
                    .font(.gfCaption)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: 8) {
                    if !person.isMe {
                        Text("Pond: \(person.primaryCircle?.name ?? "Unassigned")")
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.gfCaption)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                trailNavigation.font(.gfCaption)
            }
            .accessibilityIdentifier("pondSelectionSummary")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your connections")
                    .font(dynamicTypeSize.isAccessibilitySize ? .headline : .gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                Text("Tap someone to explore their connections.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var trailNavigation: some View {
        let trail = viewModel.pondDisclosureSnapshot.trail
        if trail.count > 1 {
            Menu {
                ForEach(trail, id: \.self) { id in
                    if let person = pondPerson(id) {
                        Button(person.isMe ? "You" : person.name) {
                            _ = viewModel.selectDisclosureTrailAncestor(id)
                        }
                        .disabled(id == trail.last)
                    }
                }
            } label: {
                Label(trail.compactMap { pondPerson($0).map { $0.isMe ? "You" : $0.name.components(separatedBy: " ").first ?? $0.name } }.joined(separator: " → "), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Connection path")
            .accessibilityValue(trail.compactMap { pondPerson($0).map { $0.isMe ? "You" : $0.name } }.joined(separator: " to "))
            .accessibilityHint("Choose a person on this path without closing connections")
            .accessibilityIdentifier("pondPathMenu")
        }
    }

    private var inspectorActions: some View {
        Group {
            if let person = viewModel.disclosureCurrentPerson {
                contactInspectorActions(for: person)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(GoldfishDS.ink(.secondary))
    }

    private var mePerson: Person? { allGraphPeople.first(where: { $0.isMe }) }

    private func contactInspectorActions(for person: Person) -> some View {
        let openContact = inspectorButton("Open contact", systemImage: "person.crop.circle") {
            viewModel.selectContact(person.id)
        }
        .accessibilityIdentifier("pondOpenContact")
        .layoutPriority(1)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                openContact
                connectionToggleButton(for: person)
                inspectorMoreMenu
                    .accessibilityIdentifier("pondMoreMenu")
            }
            VStack(alignment: .leading, spacing: 8) {
                openContact
                HStack(spacing: 8) {
                    connectionToggleButton(for: person)
                    inspectorMoreMenu
                        .accessibilityIdentifier("pondMoreMenu")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                openContact
                connectionToggleButton(for: person)
                inspectorMoreMenu
                    .accessibilityIdentifier("pondMoreMenu")
            }
        }
    }

    @ViewBuilder
    private func connectionToggleButton(for person: Person) -> some View {
        let hiddenCount = viewModel.hiddenPondNeighborCount(for: person.id)
        if viewModel.isPondConnectionsExpanded(person.id) {
            if hiddenCount > 0 {
                inspectorButton("Show \(min(hiddenCount, 4)) more", systemImage: "point.3.connected.trianglepath.dotted") {
                    viewModel.showMorePondConnections(person.id)
                }
                .accessibilityLabel("Show \(min(hiddenCount, 4)) more connections")
            }
            inspectorButton("Hide", systemImage: "eye.slash") {
                viewModel.togglePondConnections(person.id)
            }
            .accessibilityLabel("Hide connections")
            .accessibilityHint("Hides this person's disclosed connections")
            .accessibilityIdentifier("hidePondConnections")
        } else if viewModel.canShowPondConnections(person.id) {
            inspectorButton(hiddenCount > 0 ? "Show \(min(hiddenCount, 4)) connections" : "Show connections", systemImage: "point.3.connected.trianglepath.dotted") {
                viewModel.activatePondContact(id: person.id)
            }
            .accessibilityLabel("Show connections")
            .accessibilityValue(hiddenCount > 0 ? "\(hiddenCount) hidden" : "")
            .accessibilityHint("Opens this person and reveals saved connections")
            .accessibilityIdentifier("showPondConnections")
        }
    }

    private var focusReturnTargetPerson: Person? {
        let trail = viewModel.pondDisclosureSnapshot.trail
        guard let previous = trail.dropLast().last,
              let person = pondPerson(previous), !person.isMe else { return nil }
        return person
    }

    private var focusReturnButtonTitle: String {
        if let person = focusReturnTargetPerson { return "Back to \(person.name)" }
        return viewModel.selectedPondFilter == nil ? "Back to overview" : "Back to selected pond"
    }

    private var focusReturnButtonHint: String {
        if let person = focusReturnTargetPerson {
            return "Returns to \(person.name) on the connection path and keeps opened branches"
        }
        return viewModel.selectedPondFilter == nil
            ? "Returns to all ponds and keeps opened branches"
            : "Returns to the selected pond overview and keeps opened branches"
    }

    private func returnToPreviousPondTrailPosition() {
        if let person = focusReturnTargetPerson {
            _ = viewModel.selectDisclosureTrailAncestor(person.id)
        } else {
            viewModel.clearPondFocus()
        }
    }

    private var inspectorMoreMenu: some View {
        let snapshot = viewModel.pondDisclosureSnapshot
        let currentPersonID = viewModel.disclosureCurrentPerson?.id
        return Menu {
            if let person = viewModel.disclosureCurrentPerson {
                Button("Share this branch", systemImage: "square.and.arrow.up") {
                    let ids = snapshot.focusedIDs.union([person.id]).filter { pondPerson($0)?.isMe == false }
                    branchShare = IdentifiableWrapper(Array(ids).sorted { $0.uuidString < $1.uuidString })
                }
                .accessibilityIdentifier("sharePondBranch")
                Button("Add connections", systemImage: "person.badge.plus") {
                    viewModel.activatePondContact(id: person.id)
                    batchConnectionPerson = person
                }
            }
            if let currentPersonID,
               viewModel.isPondConnectionsExpanded(currentPersonID),
               viewModel.hiddenPondNeighborCount(for: currentPersonID) > 0 {
                Button("Show more connections", systemImage: "plus.circle") {
                    viewModel.showMorePondConnections(currentPersonID)
                }
                .accessibilityIdentifier("showMorePondConnections")
            }
            if currentPersonID == nil, let mePerson {
                Button("Your profile", systemImage: "person.crop.circle") {
                    viewModel.selectContact(mePerson.id)
                }
            }
            if currentPersonID == nil {
                Button("Map help", systemImage: "questionmark.circle") { showsMapHelp = true }
            }
            if snapshot.pathHighlightIDs.isEmpty, !snapshot.trail.isEmpty {
                Button("Show connection path", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    viewModel.showConnectionPath()
                }
                .accessibilityIdentifier("pondPathMenu")
            } else if !snapshot.pathHighlightIDs.isEmpty {
                Button("Clear connection path", systemImage: "xmark") {
                    viewModel.clearConnectionPath()
                }
                .accessibilityIdentifier("pondPathMenu")
            }
            if snapshot.trail.count > 1 {
                Menu("Choose a person on path") {
                    ForEach(snapshot.trail, id: \.self) { id in
                        if let person = pondPerson(id) {
                            Button(person.isMe ? "You" : person.name) {
                                _ = viewModel.selectDisclosureTrailAncestor(id)
                            }
                            .disabled(id == snapshot.trail.last)
                        }
                    }
                }
            }
            if snapshot.focusRootID != nil {
                Button(focusReturnButtonTitle, systemImage: "arrow.uturn.backward") {
                    returnToPreviousPondTrailPosition()
                }
                .accessibilityHint(focusReturnButtonHint)
                .accessibilityIdentifier("pondTrailBackMenuItem")
            }
            if hasOpenPondBranches {
                Button("Collapse all", systemImage: "arrow.down.right.and.arrow.up.left") {
                    viewModel.collapseAllPondConnections()
                }
                .accessibilityIdentifier("collapseAllPondConnections")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(.gfCaption.weight(.medium))
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More map actions")
        .accessibilityHint("Path and branch controls for the current pond view")
    }

    private var mapOptionsMenu: some View {
        Menu {
            if let mePerson {
                Button("Your profile", systemImage: "person.crop.circle") {
                    viewModel.selectContact(mePerson.id)
                }
                .accessibilityIdentifier("mapYourProfile")
            }

            Button("Zoom in", systemImage: "plus.magnifyingglass") {
                viewModel.zoomIn()
            }
            .accessibilityIdentifier("mapZoomIn")

            Button("Zoom out", systemImage: "minus.magnifyingglass") {
                viewModel.zoomOut()
            }
            .accessibilityIdentifier("mapZoomOut")

            Button("Fit visible contacts", systemImage: "arrow.up.left.and.arrow.down.right") {
                scene.fitToGraph()
            }
            .accessibilityIdentifier("mapFitAllPonds")

            Button("Restore automatic layout", systemImage: "arrow.counterclockwise") {
                viewModel.restoreAutomaticPondLayout()
            }
            .accessibilityHint("Returns ponds to their original arrangement without changing contacts or connections")
            .accessibilityIdentifier("mapRestorePondLayout")

            Button("Map help", systemImage: "questionmark.circle") {
                showsMapHelp = true
            }
            .accessibilityIdentifier("mapHelp")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Map options")
        .accessibilityHint("Open your profile, adjust the map, restore the pond arrangement, or open map help")
        .accessibilityIdentifier("mapOptionsMenu")
    }

    private var collapseAllButton: some View {
        Button { viewModel.collapseAllPondConnections() } label: {
            VStack(spacing: 0) {
                Image(systemName: hasOpenPondBranches ? "arrow.down.right.and.arrow.up.left" : "xmark")
                    .font(.system(size: 15, weight: .medium))
                Text(hasOpenPondBranches ? "Collapse all" : "Clear")
                    .font(.caption2.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .lineLimit(1)
            }
            .frame(width: hasOpenPondBranches ? 82 : 44)
            .frame(minHeight: 44)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasOpenPondBranches ? "Collapse all" : "Clear selection")
        .accessibilityHint(hasOpenPondBranches ? "Closes opened connections while keeping the map in place" : "Clears the selected contact and keeps the map in place")
        .accessibilityIdentifier("collapseAllPondConnections")
    }

    private func inspectorButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.gfCaption.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        }
        .buttonStyle(.plain)
    }

    private var accessibleVisiblePeople: some View {
        // Keep this modest contact set in the accessibility tree even while
        // individual rows are outside the inspector's scroll viewport.
        VStack(spacing: 0) {
            ForEach(visiblePondPeople) { person in
                Button {
                    viewModel.activatePondContact(id: person.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ContactPhotoView(person: person, size: .small)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.isMe ? "You" : person.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(GoldfishDS.ink(.primary))
                            Text(person.primaryCircle?.name ?? (person.isMe ? "Pond starting point" : "Unassigned"))
                                .font(.caption)
                                .foregroundStyle(GoldfishDS.ink(.secondary))
                        }
                        Spacer(minLength: 0)
                        if viewModel.pondDisclosureSnapshot.selectedID == person.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GoldfishDS.terracotta)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pondContactLabel(person))
                .accessibilityIdentifier("pondAccessibleContact-\(person.name)")
                .accessibilityHint(pondContactHint(person))
                .accessibilityActions {
                    pondConnectionAccessibilityActions(for: person)
                }
                Divider().overlay(GoldfishDS.ink(.hairline))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contextualPondTip: some View {
        let selected = viewModel.disclosureCurrentPerson != nil
        let tip: String? = !selected && !exploreTipSeen
            ? "Peek circles mean there is more to discover. Tap a person to follow their connections."
            : !selected && exploreTipSeen && !arrangeTipSeen
                    ? "Make this pond yours: hold a pond title, then drag to rearrange it."
                    : nil
        if let tip {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkle").accessibilityHidden(true)
                Text(tip).font(.gfCaption).fixedSize(horizontal: false, vertical: true)
                Button {
                    if !exploreTipSeen { exploreTipSeen = true }
                    else { arrangeTipSeen = true }
                } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Dismiss pond tip")
            }
            .foregroundStyle(GoldfishDS.ink(.secondary))
            .padding(.leading, 4)
        }
    }

    private var graphFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            graphControlsRow
            if !walkthroughManager.isActive && viewModel.disclosureCurrentPerson == nil { contextualPondTip }
            if !walkthroughManager.isActive &&
                (viewModel.disclosureCurrentPerson != nil || dynamicTypeSize.isAccessibilitySize) {
                Divider().overlay(GoldfishDS.ink(.hairline))
                pondInspector
            } else if !walkthroughManager.isActive {
                Text("Tap someone to explore their connections.")
                    .font(.gfCaption)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
            .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var graphControlsRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                myPondsButton
                HStack(spacing: 8) {
                    compactPondPicker.walkthroughAnchor(step: .ponds)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    compactRevealMenu
                    if viewModel.disclosureCurrentPerson == nil { inspectorMoreMenu }
                    mapOptionsMenu
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    myPondsButton
                    Spacer(minLength: 0)
                    compactRevealMenu
                    if viewModel.disclosureCurrentPerson == nil { inspectorMoreMenu }
                    mapOptionsMenu
                }
                if viewModel.disclosureCurrentPerson == nil || walkthroughManager.isActive {
                    compactPondPicker
                        .walkthroughAnchor(step: .ponds)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var myPondsButton: some View {
        Button {
            viewModel.showMyPonds()
        } label: {
            HStack(spacing: 6) {
                Image("WatercolorKoi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                Text("My ponds")
                    .font(.gfMeta.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(GoldfishDS.ink(.primary))
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("My ponds")
        .accessibilityHint("Shows all ponds and clears the current map search and focus while keeping opened connections")
        .accessibilityIdentifier("myPondsHome")
    }

    private var compactPondPicker: some View {
        let focusID = viewModel.selectedPondFilter
        let contacts = allGraphPeople.filter { !$0.isMe }
        let scoped = contacts.filter { focusID == nil || ($0.primaryCircle?.id.uuidString ?? "unassigned") == focusID }
        let shown = scoped.filter { viewModel.pondDisclosureSnapshot.visibleIDs.contains($0.id) }.count
        let title = focusID == "unassigned" ? "Unassigned" : circles.first { $0.id.uuidString == focusID }?.name ?? "All ponds"
        return Menu {
            Button("All ponds") { viewModel.selectedPondFilter = nil; scene.fitToGraph() }
            ForEach(circles.sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }) { pond in
                Button(pond.name) { viewModel.selectedPondFilter = pond.id.uuidString }
            }
            if contacts.contains(where: { $0.primaryCircle == nil }) {
                Button("Unassigned") { viewModel.selectedPondFilter = "unassigned" }
            }
            if let emptyGroupName {
                Button("Add someone to \(emptyGroupName)") { isAddContactPresented = true }
            }
        } label: {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.gfPondTitle).lineLimit(1)
                    Text("\(shown) of \(scoped.count) shown").font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(GoldfishDS.ink(.primary))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Choose pond")
        .accessibilityValue("\(title), \(shown) of \(scoped.count) contacts shown")
        .accessibilityIdentifier("pondScopeMenu")
    }

    @ViewBuilder
    private var compactRevealMenu: some View {
        let options = hiddenPondOptions.filter { viewModel.selectedPondFilter == nil || $0.id == viewModel.selectedPondFilter }
        if !options.isEmpty {
            Menu {
                ForEach(options) { option in
                    Button("\(option.name) · \(option.count) more") {
                        viewModel.revealHiddenPeople(in: option.id)
                    }
                }
            } label: {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Show more contacts")
            .accessibilityValue("\(options.reduce(0) { $0 + $1.count }) not shown")
            .accessibilityHint("Choose a pond to reveal up to four contacts; membership does not change")
            .accessibilityIdentifier("showPeopleInPond")
        }
    }

    private func revealFeedback(_ feedback: PondRevealFeedback) -> some View {
        HStack(spacing: 10) {
            Text("\(feedback.count) \(feedback.count == 1 ? "contact" : "contacts") revealed")
                .font(.gfMeta)
            Spacer(minLength: 0)
            if feedback.hasOffscreenContacts {
                Button("Locate") { viewModel.locateLatestPondReveal() }
                    .font(.gfMeta.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("locateRevealedContacts")
            }
            Button { viewModel.dismissPondRevealFeedback() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss reveal notice")
        }
        .padding(.leading, 12)
        .foregroundStyle(GoldfishDS.ink(.primary))
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
            .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
        .task(id: feedback.id) {
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement,
                    argument: "\(feedback.count) contacts revealed." + (feedback.hasOffscreenContacts ? " Some are offscreen. Use Locate to find them." : ""))
            }
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 10))
            guard !Task.isCancelled, viewModel.latestPondReveal?.id == feedback.id else { return }
            viewModel.dismissPondRevealFeedback()
        }
    }

    private func showPondMoveUndo(_ token: PondMembershipUndoToken, message: String) {
        ToastManager.shared.showToast(message: message, actionTitle: "Undo") {
            do {
                try dataManager.restorePondMembership(using: token)
                viewModel.refreshGraph()
                ToastManager.shared.showToast(message: "Pond move undone")
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
    }

    private var hiddenPondOptions: [HiddenPondOption] {
        viewModel.pondDisclosureSnapshot.hiddenByPond.compactMap { id, people in
            guard !people.isEmpty else { return nil }
            let name = id == "unassigned" ? "Unassigned" : circles.first { $0.id.uuidString == id }?.name
            return HiddenPondOption(id: id, name: name ?? "Pond", count: people.count)
        }
        .sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    private var emptyGroupName: String? {
        guard let selected = viewModel.selectedPondFilter else { return nil }
        let members = allGraphPeople.filter {
            !$0.isMe && ($0.primaryCircle?.id.uuidString ?? "unassigned") == selected
        }
        guard members.isEmpty else { return nil }
        return selected == "unassigned" ? "Unassigned" : circles.first { $0.id.uuidString == selected }?.name
    }


}

private struct MapHelpView: View {
    private struct HelpRow: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let accessibility: String
    }

    private let rows = [
        HelpRow(icon: "hand.tap", title: "Follow", detail: "Tap a person to see their role and reveal up to four of their saved connections. Their place in the pond stays put while the camera frames the focused cluster.", accessibility: "Tap a person to see their role, focus the map, and show up to four saved connections."),
        HelpRow(icon: "circle.dashed", title: "Reading ponds", detail: "Ponds group people by the contexts you choose, such as Family or Daycare. Visible lines between people show saved relationships.", accessibility: "Ponds group people by contexts you choose, such as Family or Daycare. Visible lines between people show saved relationships."),
        HelpRow(icon: "point.3.connected.trianglepath.dotted", title: "Connections", detail: "Use Show more for the next small group or Hide connections for one branch. Collapse all closes expanded connections. Show connection path highlights the selected person's saved route; clearing it keeps branches open. My ponds clears map search and pond focus, frames all ponds, and keeps opened branches. Open contact shows the full profile.", accessibility: "Show more reveals the next group. Hide connections closes one branch. Collapse all closes expanded connections. My ponds clears search and pond focus, frames all ponds, and keeps opened branches."),
        HelpRow(icon: "person.2.badge.plus", title: "People in ponds", detail: "Pond totals include everyone. Show people in a pond reveals hidden members in small groups, including people without a saved path from you. It never changes membership.", accessibility: "Pond totals include hidden members. Show people reveals up to four members without changing membership."),
        HelpRow(icon: "link", title: "Connect or move", detail: "Open a contact and choose Add relationship to connect people. Choose Edit, then Pond to move them. Collapse expanded connections before dragging people together or across a pond boundary. Long-press for contact actions.", accessibility: "Open a contact and choose Add relationship to connect people. Choose Edit, then Pond to move them."),
        HelpRow(icon: "hand.draw", title: "Arrange ponds", detail: "Hold a pond title or an empty area inside it, then drag. Its people move with it, and your arrangement is saved on this device. Hold a person for contact actions. Choose Restore automatic layout in Map options to start over.", accessibility: "Hold a pond title or empty area inside it, then drag to move the pond and its people. Map options includes Restore automatic layout."),
        HelpRow(icon: "arrow.up.left.and.arrow.down.right", title: "Navigate", detail: "Drag empty space to pan, or use two fingers. Pinch to zoom. The map controls also offer Zoom in, Zoom out, and Fit visible contacts. Switch to List to read every name.", accessibility: "Use Zoom in, Zoom out, and Fit visible contacts below the map. Switch to List to read every name.")
    ]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.lg) {
                    Text("A quiet map of the people you remember.")
                        .font(.gfProse)
                        .foregroundStyle(GoldfishDS.ink(.secondary))

                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: GoldfishDS.Space.md) {
                            Image(systemName: row.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(GoldfishDS.terracotta)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                                Text(row.title)
                                    .font(.gfName)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                Text(row.detail)
                                    .font(.gfBody)
                                    .foregroundStyle(GoldfishDS.ink(.secondary))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.title). \(row.accessibility)")
                    }
                }
                .padding(.horizontal, GoldfishDS.Space.pageMargin)
                .padding(.vertical, GoldfishDS.Space.xl)
            }
            .navigationTitle("Using the map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
