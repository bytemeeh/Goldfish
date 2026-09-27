import SwiftUI

/// Ponds remain groups; this view follows only saved relationships within the active data scope.
@MainActor
struct RippleExplorerView: View {
    let startID: UUID
    let dataManager: GoldfishDataManager
    let isDemoMode: Bool
    var initialTrail: [UUID]? = nil
    var searchRouteSummary: String? = nil
    /// Set when this explorer occupies the Pond tab. The callback returns to
    /// the intact pond camera instead of dismissing the surrounding Home view.
    var onReturnToPonds: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var graph: RippleGraph?
    @State private var trail: [UUID] = []
    @State private var selectedID: UUID?
    @State private var profilePerson: Person?
    @State private var showsAll = false
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var didLoad = false

    private var currentID: UUID { trail.last ?? startID }
    private var current: Person? { graph?.peopleByID[currentID] }
    private var neighbors: [RippleNeighbor] { graph?.neighbors(of: currentID, excluding: Set(trail)) ?? [] }
    private var visible: [RippleNeighbor] { Array(neighbors.prefix(4)) }
    private var selected: Person? { graph?.peopleByID[selectedID ?? currentID] }
    private var selectedTrail: [UUID] {
        guard let selectedID, selectedID != currentID else { return trail }
        return trail + [selectedID]
    }
    private var ancestorsConnectedHere: [RippleNeighbor] {
        trail.dropLast().compactMap { graph?.role(of: $0, relativeTo: currentID) }
    }

    var body: some View {
        Group {
            if onReturnToPonds == nil {
                explorerContent
                    .navigationTitle("Ripples")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                                .accessibilityIdentifier("closeRippleExplorer")
                        }
                    }
            } else {
                explorerContent
            }
        }
    }

    private var explorerContent: some View {
        GeometryReader { viewport in
            VStack(spacing: 0) {
                if onReturnToPonds != nil {
                    inlineHeader
                }
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            breadcrumbs
                            if let searchRouteSummary {
                                Text("Search route: \(searchRouteSummary)")
                                    .font(.gfCaption)
                                    .foregroundStyle(GoldfishDS.ink(.secondary))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let error = loadError {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(error).font(.gfBody)
                                    Button("Try again") { reload() }.frame(minHeight: 44)
                                }
                            }
                            if let current {
                                Text(current.isMe ? "Your connections" : "Through \(current.name)")
                                    .font(.gfName)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                    .fixedSize(horizontal: false, vertical: true)
                                if dynamicTypeSize >= .xxLarge || viewport.size.width < 360 || (onReturnToPonds != nil && viewport.size.height < 500) {
                                    readableConnections
                                } else if neighbors.isEmpty {
                                    emptyConnections
                                } else {
                                    fan
                                }
                                if neighbors.count > 4 {
                                    Button {
                                        searchText = ""
                                        showsAll = true
                                    } label: {
                                        Label("See all \(neighbors.count) connections", systemImage: "list.bullet")
                                            .font(.gfBody)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .padding(8)
                                            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                                    }
                                    .accessibilityIdentifier("rippleSeeAll")
                                }
                                selectedDetail
                                    .id("rippleSelection")
                                if !ancestorsConnectedHere.isEmpty { ancestorConnections }
                            } else if didLoad && loadError == nil {
                                unavailableRippleState
                            } else if !didLoad {
                                ProgressView("Opening ripple…")
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .id("rippleTop")
                    }
                    .background(GoldfishDS.warmBlack)
                    .onChange(of: currentID) { _, _ in scrollProxy.scrollTo("rippleTop", anchor: .top) }
                    .onChange(of: selectedID) { _, selected in
                        if let selected, selected != currentID {
                            scrollProxy.scrollTo("rippleSelection", anchor: .top)
                        }
                    }
                }
            }
        }
        .tint(GoldfishDS.terracotta)
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .onAppear { if !didLoad { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .goldfishDataDidChange)) { _ in reload() }
        .sheet(isPresented: $showsAll) { allConnections }
        .sheet(item: $profilePerson, onDismiss: { reload() }) { person in
            NavigationStack {
                ContactDetailView(viewModel: ContactDetailViewModel(person: person, dataManager: dataManager),
                                  showsCloseButton: true, allowsRippleExploration: false)
            }
        }
    }

    private var inlineHeader: some View {
        HStack(spacing: 10) {
            Button {
                onReturnToPonds?()
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "chevron.left")
                    } else {
                        Label("Ponds", systemImage: "chevron.left")
                    }
                }
                .font(.gfBody.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Back to ponds")
            .accessibilityIdentifier("returnToPondsButton")

            Text("Ripples")
                .font(.gfMeta.weight(.medium))
                .foregroundStyle(GoldfishDS.ink(.tertiary))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(GoldfishDS.warmBlack)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GoldfishDS.ink(.hairline))
                .frame(height: GoldfishDS.Rule.hairline)
        }
    }

    private var breadcrumbs: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(trail.enumerated()), id: \.element) { index, id in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true) }
                    trailButton(id, index: index)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
                Menu {
                    ForEach(Array(trail.enumerated()), id: \.element) { index, id in
                        Button(name(id)) { goBack(to: index) }
                    }
                } label: {
                    Label("Trail", systemImage: "ellipsis.circle").frame(minHeight: 44)
                }
                Text(name(currentID))
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(GoldfishDS.ink(.secondary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exploration trail")
    }

    private var unavailableRippleState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView("Contact unavailable", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("It may have been removed."))
            Button(onReturnToPonds == nil ? "Close" : "Back to ponds") {
                if let onReturnToPonds {
                    onReturnToPonds()
                } else {
                    dismiss()
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier(onReturnToPonds == nil ? "closeRippleExplorer" : "returnToPondsButton")
        }
    }

    private func trailButton(_ id: UUID, index: Int) -> some View {
        Button { goBack(to: index) } label: {
            Text(name(id)).font(.gfCaption)
                .foregroundStyle(id == currentID ? GoldfishDS.ink(.primary) : GoldfishDS.terracotta)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(id == currentID ? "\(name(id)), current ripple" : "Back to \(name(id))")
        .accessibilityIdentifier("rippleTrail-\(id.uuidString)")
    }

    private var fan: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let compact = onReturnToPonds != nil
            // Keep the full 116-point touch targets separate in the four-node fan.
            let verticalScale: CGFloat = compact ? 0.88 : 1
            let anchor = CGPoint(x: size.width / 2, y: compact ? 310 : 358)
            ZStack(alignment: .topLeading) {
                RipplePond()
                    .fill(GoldfishDS.terracotta.opacity(0.055))
                    .scaleEffect(y: verticalScale, anchor: .top)
                RipplePondContour()
                    .stroke(GoldfishDS.ink(.hairline), lineWidth: 1)
                    .scaleEffect(y: verticalScale, anchor: .top)
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, neighbor in
                    let point = RippleFanGeometry.point(index: index, count: visible.count, width: size.width, verticalScale: verticalScale)
                    RippleConnection(anchor: anchor, target: point)
                        .stroke(selectedID == neighbor.id ? GoldfishDS.terracotta : GoldfishDS.ink(.quaternary),
                                style: StrokeStyle(lineWidth: selectedID == neighbor.id ? 2 : 1, lineCap: .round))
                        .accessibilityHidden(true)
                }
                ForEach(fanPeople, id: \.id) { person in
                    let isFocus = person.id == currentID
                    let index = visible.firstIndex(where: { $0.id == person.id }) ?? 0
                    let point = isFocus ? anchor : RippleFanGeometry.point(index: index, count: visible.count, width: size.width, verticalScale: verticalScale)
                    Button {
                        if let neighbor = visible.first(where: { $0.id == person.id }) { activate(neighbor) }
                        else { selectedID = currentID }
                    } label: {
                        token(person, isFocus: isFocus)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 94, height: 116, alignment: .top)
                    .position(x: point.x, y: point.y - 24 + 58)
                    .accessibilityLabel(contactLabel(person, isFocus: isFocus))
                    .accessibilityHint(furtherCount(person.id) > 0 && !isFocus ? "Opens this person's ripple" : "Shows the relationship and contact actions")
                    .accessibilityIdentifier("rippleContact-\(person.name)")
                    .accessibilityAddTraits((selectedID ?? currentID) == person.id ? .isSelected : [])
                    .transition(reduceMotion ? .identity : .scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .frame(height: onReturnToPonds == nil ? 454 : 404)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connections through \(name(currentID))")
    }

    private var fanPeople: [Person] { current.map { [$0] + visible.map(\.person) } ?? [] }

    private func token(_ person: Person, isFocus: Bool) -> some View {
        VStack(spacing: 5) {
            ContactPhotoView(person: person, size: .medium)
                .overlay(Circle().stroke((selectedID ?? currentID) == person.id ? GoldfishDS.terracotta : .clear, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    let count = isFocus ? 0 : furtherCount(person.id)
                    if count > 0 {
                        Text("+\(count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(GoldfishDS.terracotta)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(GoldfishDS.warmBlack, in: Capsule())
                            .overlay(Capsule().stroke(GoldfishDS.terracotta, lineWidth: 0.75))
                            .offset(x: 12, y: -6)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHidden(true)
            Text(person.name).font(.gfCaption.weight(.medium)).foregroundStyle(GoldfishDS.ink(.primary))
                .lineLimit(2).multilineTextAlignment(.center)
            if let role = displayedRole(person.id) {
                Label(role.roleLabel, systemImage: role.symbolName)
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                    .lineLimit(1)
            } else if person.isMe {
                Text("You").font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
            }
            if let age = age(person) {
                Text("Age \(age)").font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
            }
        }
        .frame(width: 94, alignment: .top)
        .contentShape(Rectangle())
    }

    private var readableConnections: some View {
        LazyVStack(spacing: 8) {
            ForEach(visible) { neighbor in
                Button { activate(neighbor) } label: { connectionRow(neighbor) }.buttonStyle(.plain)
                    .accessibilityIdentifier("rippleContact-\(neighbor.person.name)")
            }
            if neighbors.isEmpty { emptyConnections }
        }
    }

    private func connectionRow(_ neighbor: RippleNeighbor) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ContactPhotoView(person: neighbor.person, size: .small).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(neighbor.person.name).font(.gfBody).foregroundStyle(GoldfishDS.ink(.primary))
                Label(neighbor.roleLabel, systemImage: neighbor.symbolName).font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                if let age = age(neighbor.person) { Text("Age \(age)").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)) }
                let count = furtherCount(neighbor.id)
                if count > 0 { Text("\(count) further \(count == 1 ? "connection" : "connections")").font(.gfMeta).foregroundStyle(GoldfishDS.terracotta) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(contactLabel(neighbor.person, isFocus: false))
        .accessibilityHint(furtherCount(neighbor.id) > 0 ? "Opens this person's ripple" : "Shows the relationship and contact actions")
    }

    private var selectedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if let person = selected {
                Text(person.name).font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                Text(relationshipDescription(person)).font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(selectedTrail.map(name).joined(separator: " → "))
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let meID = graph?.meID {
                    if let path = graph?.shortestPath(from: meID, to: person.id) {
                        if path.count < selectedTrail.count {
                            Text(path.count == 2 ? "Also directly connected to you" : "Shortest connection from you: \(path.count - 1) links")
                                .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                        }
                    } else { Text("No saved path from you").font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary)) }
                }
                Button { profilePerson = person } label: {
                    Label("Open contact", systemImage: "person.crop.circle")
                        .font(.gfBody).frame(minHeight: 44)
                }
                .accessibilityIdentifier("rippleOpenContact")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var ancestorConnections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also on your trail").gfSectionLabel()
            ForEach(ancestorsConnectedHere) { neighbor in
                Button {
                    if let index = trail.firstIndex(of: neighbor.id) { goBack(to: index) }
                } label: {
                    Label("\(name(neighbor.id)) · \(neighbor.roleLabel)", systemImage: neighbor.symbolName)
                        .font(.gfMeta).frame(minHeight: 44, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyConnections: some View {
        Text(ancestorsConnectedHere.isEmpty ? "No saved connections yet. Open this contact to add one." : "Their other connections are already on your trail.")
            .font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
    }

    private var allConnections: some View {
        NavigationStack {
            List {
                let matches = neighbors.filter { searchText.isEmpty || $0.person.name.localizedCaseInsensitiveContains(searchText) || $0.roleLabel.localizedCaseInsensitiveContains(searchText) }
                if matches.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(matches) { neighbor in
                        Button {
                            showsAll = false
                            activate(neighbor)
                        } label: { connectionRow(neighbor) }.buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search connections")
            .navigationTitle("All connections")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showsAll = false } } }
            .scrollContentBackground(.hidden).background(GoldfishDS.warmBlack)
        }
        .presentationDetents([.large])
    }

    private func name(_ id: UUID) -> String { graph?.peopleByID[id].map { $0.isMe ? "You" : $0.name } ?? "Unavailable contact" }
    private func furtherCount(_ id: UUID) -> Int { graph?.neighbors(of: id, excluding: Set(trail + [id])).count ?? 0 }
    private func displayedRole(_ id: UUID) -> RippleNeighbor? {
        let anchor = id == currentID ? trail.dropLast().last : currentID
        return anchor.flatMap { graph?.role(of: id, relativeTo: $0) }
    }
    private func age(_ person: Person) -> Int? {
        guard let birthday = person.birthday, birthday <= Date(),
              let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year else { return nil }
        return years
    }
    private func relationshipDescription(_ person: Person) -> String {
        guard let role = displayedRole(person.id) else { return person.isMe ? "Your starting point" : "Starting from this contact" }
        let anchor = person.id == currentID ? trail.dropLast().last : currentID
        let prefix = anchor.flatMap { graph?.peopleByID[$0] }?.isMe == true ? "Your" : "\(anchor.map(name) ?? "Contact")’s"
        let result = role.roleLabel == "Connection" ? "Connected through \(anchor.map(name) ?? "this contact")" : "\(prefix) \(role.roleLabel.lowercased())"
        return age(person).map { "\(result) · \($0) years old" } ?? result
    }
    private func contactLabel(_ person: Person, isFocus: Bool) -> String {
        let count = isFocus ? 0 : furtherCount(person.id)
        let pet = person.petSpeciesLabel.map { ", \($0)" } ?? ""
        return "\(person.name)\(pet), \(relationshipDescription(person))" + (count > 0 ? ", \(count) further \(count == 1 ? "connection" : "connections")" : "")
    }
    private func activate(_ neighbor: RippleNeighbor) {
        guard furtherCount(neighbor.id) > 0 else { selectedID = neighbor.id; return }
        let next = graph?.validatedTrail(trail + [neighbor.id]) ?? []
        guard next.last == neighbor.id else { return }
        changeFocus(next)
    }
    private func goBack(to index: Int) { changeFocus(Array(trail.prefix(index + 1))) }
    private func changeFocus(_ next: [UUID]) {
        if reduceMotion { trail = next; selectedID = next.last }
        else { withAnimation(.easeInOut(duration: 0.28)) { trail = next; selectedID = next.last } }
        UIAccessibility.post(notification: .layoutChanged, argument: "Through \(next.last.map(name) ?? name(currentID))")
    }
    private func reload() {
        do {
            let people = try dataManager.fetchAllPersons().filter { !$0.isDeleted && ($0.isMe || $0.isDemo == isDemoMode) }
            let updated = RippleGraph(people: people)
            let valid = updated.validatedTrail(trail)
            graph = updated
            if didLoad {
                trail = valid
            } else if let initialTrail {
                // The result retains its complete evidence route above. A
                // repeated ancestor returns to that ripple instead of drawing
                // a duplicate person on the exploration trail.
                var simpleTrail: [UUID] = []
                for id in initialTrail {
                    if let index = simpleTrail.firstIndex(of: id) { simpleTrail = Array(simpleTrail.prefix(index + 1)) }
                    else { simpleTrail.append(id) }
                }
                let saved = updated.validatedTrail(simpleTrail)
                trail = saved.last == startID ? saved : updated.initialTrail(to: startID)
            } else {
                trail = updated.initialTrail(to: startID)
            }
            if trail.isEmpty, updated.peopleByID[startID] != nil { trail = [startID] }
            if selectedID == nil || updated.peopleByID[selectedID!] == nil || !(neighbors.map(\.id) + [currentID]).contains(selectedID!) {
                selectedID = currentID
            }
            didLoad = true
            loadError = nil
        } catch {
            didLoad = true
            loadError = "Could not load connections. Your saved contacts are unchanged."
        }
    }
}

/// Coin centres are kept separate from token frames so names never scale with the canvas.
enum RippleFanGeometry {
    static func point(index: Int, count: Int, width: CGFloat, verticalScale: CGFloat = 1) -> CGPoint {
        let layouts: [[CGPoint]] = [
            [CGPoint(x: 0.5, y: 132)],
            [CGPoint(x: 0.25, y: 166), CGPoint(x: 0.75, y: 166)],
            [CGPoint(x: 0.17, y: 200), CGPoint(x: 0.5, y: 66), CGPoint(x: 0.84, y: 207)],
            [CGPoint(x: 0.16, y: 202), CGPoint(x: 0.37, y: 66), CGPoint(x: 0.71, y: 95), CGPoint(x: 0.84, y: 234)]
        ]
        let points = layouts[max(0, min(3, count - 1))]
        let point = points[min(max(0, index), points.count - 1)]
        return CGPoint(x: point.x * width, y: point.y * verticalScale)
    }
}

private struct RippleConnection: Shape {
    let anchor: CGPoint
    let target: CGPoint
    func path(in rect: CGRect) -> Path {
        let left = target.x < anchor.x
        let side: CGFloat = left ? 1 : -1
        var path = Path()
        path.move(to: CGPoint(x: anchor.x + (left ? -12 : 12), y: anchor.y - 21))
        path.addCurve(to: CGPoint(x: target.x + side * 25, y: target.y),
                      control1: CGPoint(x: anchor.x + (left ? -4 : 4), y: anchor.y - 95),
                      control2: CGPoint(x: target.x + side * 54, y: target.y))
        return path
    }
}
private struct RipplePond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.055, y: 186))
        p.addCurve(to: CGPoint(x: r.width * 0.44, y: 30), control1: CGPoint(x: 0, y: 86), control2: CGPoint(x: r.width * 0.24, y: 24))
        p.addCurve(to: CGPoint(x: r.width * 0.95, y: 229), control1: CGPoint(x: r.width * 0.72, y: 8), control2: CGPoint(x: r.width * 0.94, y: 106))
        p.addCurve(to: CGPoint(x: r.width * 0.55, y: 379), control1: CGPoint(x: r.width, y: 312), control2: CGPoint(x: r.width * 0.81, y: 365))
        p.addCurve(to: CGPoint(x: r.width * 0.055, y: 186), control1: CGPoint(x: r.width * 0.25, y: 400), control2: CGPoint(x: r.width * 0.06, y: 292))
        p.closeSubpath()
        return p
    }
}
private struct RipplePondContour: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.08, y: 178))
        p.addCurve(to: CGPoint(x: r.width * 0.44, y: 42), control1: CGPoint(x: r.width * 0.08, y: 82), control2: CGPoint(x: r.width * 0.27, y: 36))
        p.addCurve(to: CGPoint(x: r.width * 0.91, y: 214), control1: CGPoint(x: r.width * 0.71, y: 21), control2: CGPoint(x: r.width * 0.88, y: 113))
        return p
    }
}
