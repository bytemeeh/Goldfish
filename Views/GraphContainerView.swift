import SwiftUI
import SpriteKit

// MARK: - Graph Container View
/// SwiftUI wrapper hosting the SpriteKit graph scene.
struct GraphContainerView: View {
    @ObservedObject var viewModel: GraphViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager

    @State private var scene: GoldfishGraphScene?

    var body: some View {
        ZStack {
            // MARK: - SpriteKit View
            GeometryReader { proxy in
                SpriteView(
                    scene: scene ?? createScene(size: proxy.size),
                    options: [.allowsTransparency]
                )
                .ignoresSafeArea()
            }

            // MARK: - Zoom Controls Overlay
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

            // MARK: - Loading
            if viewModel.isLoading {
                ProgressView("Building graph...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .onAppear {
            viewModel.loadGraph()
        }
        .onChange(of: viewModel.graphLevels?.count) { _ in
            scene?.didUpdateGraphLevels(viewModel.graphLevels.flatMap { $0.isEmpty ? nil : $0 } ?? [])
        }
        .sheet(item: $viewModel.selectedContactID) { id in
            if let person = try? dataManager.fetchAllPersons().first(where: { $0.id == id }) {
                NavigationView {
                    ContactDetailView(
                        viewModel: ContactDetailViewModel(person: person, dataManager: dataManager)
                    )
                }
            }
        }
    }

    private func createScene(size: CGSize) -> GoldfishGraphScene {
        let newScene = GoldfishGraphScene(size: size)
        newScene.scaleMode = .resizeFill
        newScene.graphDelegate = viewModel
        viewModel.sceneDelegate = newScene
        DispatchQueue.main.async {
            self.scene = newScene
        }
        return newScene
    }
}

// MARK: - UUID + Identifiable (needed for .sheet(item:))
// Note: On iOS 17+ UUID conforms to Identifiable via Foundation.
// This extension is only needed if targeting earlier iOS versions.
// If you get a duplicate conformance warning, remove this extension.
#if swift(<5.9)
extension UUID: Identifiable {
    public var id: UUID { self }
}
#endif
