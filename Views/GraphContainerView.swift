import SwiftUI
import SpriteKit
import SwiftData

// MARK: - Graph Container View
/// SwiftUI wrapper hosting the SpriteKit graph scene.
struct GraphContainerView: View {
    @ObservedObject var viewModel: GraphViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager


    @State private var scene: GoldfishGraphScene?
    @State private var connectRelType: RelationshipType = .friend
    @State private var connectPondName: String = "None"
    @State private var isAddContactPresented = false
    @Query private var circles: [GoldfishCircle]

    var body: some View {
        ZStack {
            // MARK: - SpriteKit View (only when we have data)
            if viewModel.graphLevels != nil {
                GeometryReader { proxy in
                    SpriteView(
                        scene: getOrCreateScene(size: CGSize(width: max(proxy.size.width, 100), height: max(proxy.size.height, 100))),
                        options: [.allowsTransparency]
                    )
                    .ignoresSafeArea(edges: .bottom)
                    .onChange(of: proxy.size) { _, newSize in
                        // Ensure scene sticks to the view size if it changes, avoiding zero sizes
                        scene?.size = CGSize(width: max(newSize.width, 100), height: max(newSize.height, 100))
                    }
                }
                
                // Pond Shortcut Bar removed in favor of bottom carousel
            }

            // MARK: - Zoom Controls Overlay
            if viewModel.graphLevels != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Button(action: viewModel.zoomIn) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            Button(action: viewModel.zoomOut) {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            Button(action: viewModel.resetCamera) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding()
                    }
                }
                
                // MARK: - Floating Pond Carousel
                VStack {
                    Spacer()
                    floatingPondCarousel
                        .padding(.bottom, 24)
                }
            }

            // MARK: - Loading
            if viewModel.isLoading {
                ProgressView("Building graph...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }

            // MARK: - Empty State
            if viewModel.hasNoData && !viewModel.isLoading {
                EmptyStateView(
                    systemImage: "network",
                    headline: "No connections yet",
                    subtext: "Add contacts and relationships to see your network graph.",
                    actionLabel: "Add Contact",
                    action: {
                        isAddContactPresented = true
                    }
                )
            }
            
            // MARK: - Inline Connect Popup
            if viewModel.pendingConnectionFrom != nil && viewModel.pendingConnectionTo != nil {
                connectPopupOverlay
            }
            
            // MARK: - Inline Pond Move Popup
            if viewModel.pendingPondMovePerson != nil && viewModel.pendingPondMoveTarget != nil {
                pondMovePopupOverlay
            }
        }
        .onAppear {
            viewModel.loadGraph()
        }
        .onChange(of: viewModel.levelsLoaded) { _, loaded in
            // When graph data changes and finishes loading, push it to the scene
            if loaded {
                pushLevelsToScene()
            }
        }
        .sheet(item: Binding<IdentifiableWrapper<UUID>?>(
            get: { viewModel.selectedContactID.map { IdentifiableWrapper($0) } },
            set: { viewModel.selectedContactID = $0?.value }
        ), onDismiss: {
            viewModel.refreshGraph()
        }) { wrapper in
            if let person = try? dataManager.fetchAllPersons().first(where: { $0.id == wrapper.value }) {
                NavigationStack {
                    ContactDetailView(
                        viewModel: ContactDetailViewModel(person: person, dataManager: dataManager)
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
            Button("Edit Contact") {
                viewModel.selectContact(contactID)
                viewModel.pendingActionContactID = nil
            }
            
            // Generate a button for each existing pond (only for non-Me contacts)
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
        .sheet(isPresented: $isAddContactPresented, onDismiss: {
            viewModel.refreshGraph()
        }) {
            NavigationStack {
                ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager))
                    .environmentObject(dataManager)
            }
        }
    }

    /// Helper to assign a contact to a pond from the shortcut menu
    private func assignContact(_ contactID: UUID, to circle: GoldfishCircle) {
        guard let allPersons = try? dataManager.fetchAllPersons(),
              let person = allPersons.first(where: { $0.id == contactID }) else { return }
        
        // Already in this exact circle? No-op.
        if person.circleContacts.contains(where: { $0.circle.id == circle.id && !$0.manuallyExcluded }) {
            ToastManager.shared.showToast(message: "\(person.name) is already in \(circle.name)")
            return
        }
        
        // addToCircle enforces single-pond constraint (removes old memberships)
        let _ = try? dataManager.addToCircle(person, circle: circle)
        ToastManager.shared.showToast(message: "Moved \(person.name) to \(circle.name)")
        viewModel.refreshGraph()
    }

    /// Gets the existing scene or creates a new one, immediately feeding it graph data.
    private func getOrCreateScene(size: CGSize) -> GoldfishGraphScene {
        if let existing = scene {
            return existing
        }
        
        let newScene = GoldfishGraphScene(size: size)
        newScene.scaleMode = .resizeFill
        newScene.graphDelegate = viewModel
        viewModel.sceneDelegate = newScene
        
        // Immediately feed levels to the new scene so it renders nodes
        if let levels = viewModel.graphLevels, !levels.isEmpty {
            newScene.didUpdateGraphLevels(levels)
        }
        
        DispatchQueue.main.async {
            self.scene = newScene
        }
        return newScene
    }
    
    /// Pushes current graph levels to the scene (if it exists).
    private func pushLevelsToScene() {
        guard let levels = viewModel.graphLevels, !levels.isEmpty else { return }
        scene?.didUpdateGraphLevels(levels)
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
            
            VStack(spacing: 16) {
                if let existing = existingRelationship {
                    // ── Already Connected: Edit/Remove ──
                    Text("Already Connected")
                        .font(.headline)
                    
                    HStack(spacing: 20) {
                        ContactPhotoView(photoData: fromPerson.photoData, name: fromPerson.name, colorHex: fromPerson.color, size: .medium)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        
                        VStack(spacing: 2) {
                            Image(systemName: "link")
                                .font(.title2)
                                .foregroundColor(.goldfishAccent)
                            Text(existing.type.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ContactPhotoView(photoData: toPerson.photoData, name: toPerson.name, colorHex: toPerson.color, size: .medium)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    
                    Text("\(fromPerson.name) and \(toPerson.name) are already connected.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Remove Connection", role: .destructive) {
                        dataManager.context.delete(existing)
                        try? dataManager.context.save()
                        
                        ToastManager.shared.showToast(message: "Removed connection")
                        
                        withAnimation {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                        viewModel.refreshGraph()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    Button("Cancel") {
                        withAnimation {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                } else {
                    // ── New Connection ──
                    Text("Connect \(fromPerson.name) → \(toPerson.name)")
                        .font(.headline)
                    
                    HStack(spacing: 20) {
                        ContactPhotoView(photoData: fromPerson.photoData, name: fromPerson.name, colorHex: fromPerson.color, size: .medium)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        
                        Image(systemName: "arrow.left.and.right")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        ContactPhotoView(photoData: toPerson.photoData, name: toPerson.name, colorHex: toPerson.color, size: .medium)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    }
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Relationship type")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Relationship type", selection: $connectRelType) {
                                ForEach(RelationshipType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                        }
                        
                        HStack {
                            Text("Move to pond")
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Move to pond", selection: $connectPondName) {
                                Text("None").tag("None")
                                if let circles = try? dataManager.fetchAllCircles() {
                                    ForEach(circles) { circle in
                                        Text(circle.name).tag(circle.name)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    
                    Button("Confirm Connection") {
                        let rel = Relationship(from: fromPerson, to: toPerson, type: connectRelType)
                        dataManager.context.insert(rel)
                        fromPerson.outgoingRelationships.append(rel)
                        toPerson.incomingRelationships.append(rel)
                        
                        if connectPondName != "None",
                           let circle = try? dataManager.fetchAllCircles().first(where: { $0.name == connectPondName }) {
                            // Skip ME contact — it must never belong to a pond
                            if !fromPerson.isMe {
                                let _ = try? dataManager.addToCircle(fromPerson, circle: circle)
                            }
                            if !toPerson.isMe {
                                let _ = try? dataManager.addToCircle(toPerson, circle: circle)
                            }
                        }
                        
                        try? dataManager.context.save()
                        
                        ToastManager.shared.showToast(message: "Connected \(fromPerson.name) & \(toPerson.name)")
                        
                        viewModel.confirmConnection()
                        
                        withAnimation {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                        viewModel.refreshGraph()
                        
                        connectRelType = .friend
                        connectPondName = "None"
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.goldfishAccent)
                    
                    Button("Cancel") {
                        withAnimation {
                            viewModel.pendingConnectionFrom = nil
                            viewModel.pendingConnectionTo = nil
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
            .transition(.scale.combined(with: .opacity))
            .zIndex(100)
        }
    }
    
    @ViewBuilder
    private var pondMovePopupOverlay: some View {
        if let personID = viewModel.pendingPondMovePerson,
           let pondName = viewModel.pendingPondMoveTarget,
           let allPersons = try? dataManager.fetchAllPersons(),
           let person = allPersons.first(where: { $0.id == personID }),
           !person.isMe {
            
            VStack(spacing: 16) {
                Text("Move to Pond?")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    ContactPhotoView(photoData: person.photoData, name: person.name, colorHex: person.color, size: .medium)
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)
                        Text(String(pondName.prefix(1).uppercased()))
                            .font(.title3.bold())
                    }
                }
                
                Text("Move **\(person.name)** to the **\(pondName)** circle.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Move") {
                    // Update via DataManager which ensures invariants like !isMe and single-pond
                    if let circle = try? dataManager.fetchAllCircles().first(where: { $0.name == pondName }) {
                        let _ = try? dataManager.addToCircle(person, circle: circle)
                    }
                    
                    ToastManager.shared.showToast(message: "Moved \(person.name) to \(pondName)")
                    
                    withAnimation {
                        viewModel.pendingPondMovePerson = nil
                        viewModel.pendingPondMoveTarget = nil
                    }
                    viewModel.refreshGraph()
                }
                .buttonStyle(.borderedProminent)
                .tint(.goldfishAccent)
                
                Button("Cancel") {
                    withAnimation {
                        viewModel.pendingPondMovePerson = nil
                        viewModel.pendingPondMoveTarget = nil
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
            .transition(.scale.combined(with: .opacity))
            .zIndex(100)
        }
    }
    
    private var floatingPondCarousel: some View {
        let sortedCircles = circles.sorted(by: { $0.sortOrder < $1.sortOrder })
        let currentIndex = sortedCircles.firstIndex(where: { $0.name == viewModel.selectedPondFilter })
        
        let displayName = viewModel.selectedPondFilter ?? "All Ponds"
        let displayColor = currentIndex != nil ? Color(hex: sortedCircles[currentIndex!].color) : Color.primary
        
        return HStack(spacing: 8) {
            Button(action: {
                withAnimation { cyclePond(direction: -1, sortedCircles: sortedCircles) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(sortedCircles.isEmpty ? .secondary.opacity(0.3) : .primary)
                    .frame(width: 30, height: 40)
            }
            .disabled(sortedCircles.isEmpty)
            
            Text(displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: 100)
                .animation(.easeInOut, value: displayName)
            
            Button(action: {
                withAnimation { cyclePond(direction: 1, sortedCircles: sortedCircles) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(sortedCircles.isEmpty ? .secondary.opacity(0.3) : .primary)
                    .frame(width: 30, height: 40)
            }
            .disabled(sortedCircles.isEmpty)
        }
        .padding(.horizontal, 4)
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
        .layoutPriority(1)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -30 {
                        // Swiped left = next pond
                        withAnimation { cyclePond(direction: 1, sortedCircles: sortedCircles) }
                    } else if value.translation.width > 30 {
                        // Swiped right = previous pond
                        withAnimation { cyclePond(direction: -1, sortedCircles: sortedCircles) }
                    }
                }
        )
    }
    
    private func cyclePond(direction: Int, sortedCircles: [GoldfishCircle]) {
        if sortedCircles.isEmpty { return }
        
        let currentIndex: Int
        if let currentName = viewModel.selectedPondFilter,
           let idx = sortedCircles.firstIndex(where: { $0.name == currentName }) {
            currentIndex = idx
        } else {
            currentIndex = -1 // All Ponds
        }
        
        let totalCount = sortedCircles.count
        var nextIndex = currentIndex + direction
        
        // Wrap around logic
        if nextIndex > totalCount - 1 {
            nextIndex = -1 // Wrap to "All Ponds"
        } else if nextIndex < -1 {
            nextIndex = totalCount - 1 // Wrap to last pond
        }
        
        // Apply selection
        if nextIndex == -1 {
            if viewModel.selectedPondFilter != nil {
                viewModel.selectedPondFilter = nil
                viewModel.resetCamera()
            }
        } else {
            let nextPond = sortedCircles[nextIndex]
            if viewModel.selectedPondFilter != nextPond.name {
                viewModel.centerOnPond(name: nextPond.name)
            }
        }
    }
}

