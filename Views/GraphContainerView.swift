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
    @Query private var circles: [GoldfishCircle]

    var body: some View {
        ZStack {
            // MARK: - SpriteKit View (only when we have data)
            if viewModel.graphLevels != nil {
                GeometryReader { proxy in
                    SpriteView(
                        scene: getOrCreateScene(size: proxy.size),
                        options: [.allowsTransparency]
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
                
                // MARK: - Pond Shortcut Bar
                VStack {
                    pondShortcutBar
                    Spacer()
                }
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
                    actionLabel: nil,
                    action: nil
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
        .onChange(of: viewModel.graphLevels?.flatMap(\.allContacts).count) { _, _ in
            // When graph data changes, push it to the scene
            pushLevelsToScene()
        }
        .sheet(item: Binding<IdentifiableWrapper<UUID>?>(
            get: { viewModel.selectedContactID.map { IdentifiableWrapper($0) } },
            set: { viewModel.selectedContactID = $0?.value }
        )) { wrapper in
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
            
            // Generate a button for each existing pond
            ForEach(circles.sorted(by: { $0.sortOrder < $1.sortOrder })) { circle in
                Button("Assign to \(circle.name)") {
                    assignContact(contactID, to: circle)
                    viewModel.pendingActionContactID = nil
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
    }

    /// Helper to assign a contact to a pond from the shortcut menu
    private func assignContact(_ contactID: UUID, to circle: GoldfishCircle) {
        guard let allPersons = try? dataManager.fetchAllPersons(),
              let person = allPersons.first(where: { $0.id == contactID }) else { return }
        
        // Don't add if already in this circle
        if !person.circleContacts.contains(where: { $0.circle.id == circle.id }) {
            let cc = CircleContact(circle: circle, contact: person)
            dataManager.context.insert(cc)
            _ = try? dataManager.context.save()
            ToastManager.shared.showToast(message: "Added \(person.name) to \(circle.name)")
            viewModel.refreshGraph()
        } else {
            ToastManager.shared.showToast(message: "\(person.name) is already in \(circle.name)")
        }
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
                        ContactPhotoView(photoData: fromPerson.photoData, name: fromPerson.name, colorHex: fromPerson.color, size: 50)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        
                        VStack(spacing: 2) {
                            Image(systemName: "link")
                                .font(.title2)
                                .foregroundColor(.goldfishAccent)
                            Text(existing.type.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ContactPhotoView(photoData: toPerson.photoData, name: toPerson.name, colorHex: toPerson.color, size: 50)
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
                        ContactPhotoView(photoData: fromPerson.photoData, name: fromPerson.name, colorHex: fromPerson.color, size: 50)
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        
                        Image(systemName: "arrow.left.and.right")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        ContactPhotoView(photoData: toPerson.photoData, name: toPerson.name, colorHex: toPerson.color, size: 50)
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
                            let _ = try? dataManager.addToCircle(fromPerson, circle: circle)
                            let _ = try? dataManager.addToCircle(toPerson, circle: circle)
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
           let person = allPersons.first(where: { $0.id == personID }) {
            
            VStack(spacing: 16) {
                Text("Move to Pond?")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    ContactPhotoView(photoData: person.photoData, name: person.name, colorHex: person.color, size: 50)
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
                    // Remove from all current ponds first
                    for cc in person.circleContacts {
                        dataManager.context.delete(cc)
                    }
                    try? dataManager.context.save()
                    
                    // Add to the target pond
                    if let circle = try? dataManager.fetchAllCircles().first(where: { $0.name == pondName }) {
                        let cc = CircleContact(circle: circle, contact: person)
                        dataManager.context.insert(cc)
                        _ = try? dataManager.context.save()
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
    
    private var pondShortcutBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Reset Button
                Button(action: viewModel.resetCamera) {
                    HStack(spacing: 6) {
                        Text("Center")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
                .foregroundColor(.primary)
                
                // Pond Buttons
                ForEach(circles.sorted(by: { $0.sortOrder < $1.sortOrder })) { circle in
                    Button(action: {
                        viewModel.centerOnPond(name: circle.name)

                    }) {
                        HStack(spacing: 6) {
                            Text(circle.name)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(hex: circle.color).opacity(0.2))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: circle.color).opacity(0.3), lineWidth: 1)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }
}

