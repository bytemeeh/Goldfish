import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject var dataManager: GoldfishDataManager
    @StateObject private var viewModel: OnboardingViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    init() {
        // Initialize with temporary placeholder, will receive enviroment object via middleware if needed
        // but here we can just use the environment object if we pass it 
        // Logic: Main View (GoldfishApp) creates this.
        // We need to inject datamanager to VM.
        // Best to use the same logic as HomeView or just default init and use onAppear?
        // Actually, since this is a top level view in a fullScreenCover, we can use the same pattern.
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(dataManager: .preview())) // Placeholder
    }
    
    var body: some View {
        DataManagerInjector()
    }
    
    struct DataManagerInjector: View {
        @EnvironmentObject var dataManager: GoldfishDataManager
        var body: some View {
            Content(dataManager: dataManager)
        }
    }
    
    struct Content: View {
        @StateObject var viewModel: OnboardingViewModel
        @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
        
        init(dataManager: GoldfishDataManager) {
            _viewModel = StateObject(wrappedValue: OnboardingViewModel(dataManager: dataManager))
        }
        
        var body: some View {
            TabView(selection: $viewModel.currentTab) {
                // MARK: Screen 1: Welcome
                VStack(spacing: 32) {
                    Spacer()
                    Image(systemName: "network") // Placeholder for Goldfish logo
                        .font(.system(size: 100))
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(.bottom, 20)
                    
                    Text("Goldfish")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your personal relationship map")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { viewModel.currentTab = 1 }) {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
                .tag(0)
                
                // MARK: Screen 2: Create Your Card
                VStack(spacing: 24) {
                    Text("About You")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 48)
                    
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .padding(.vertical)
                    
                    VStack(spacing: 16) {
                        TextField("Name", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                        
                        TextField("Phone (Optional)", text: $viewModel.phone)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.phonePad)
                        
                        TextField("Email (Optional)", text: $viewModel.email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    Button(action: { 
                        viewModel.createMeCardAndContinue {
                            withAnimation { viewModel.currentTab = 2 }
                        }
                    }) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.name.isEmpty ? Color.gray : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.name.isEmpty)
                    .padding(.horizontal, 32)
                    
                    Button("I'll set this up later") {
                        // Skip logic
                        viewModel.createMeCardAndContinue {
                             withAnimation { viewModel.currentTab = 2 }
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.bottom, 48)
                }
                .tag(1)
                
                // MARK: Screen 3: Quick Tour
                VStack(spacing: 32) {
                    Spacer()
                    Image(systemName: "map.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    
                    Text("Visual Graph")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("See your network at a glance. Pinch to zoom, drag to pan.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    Button(action: { 
                        withAnimation { viewModel.currentTab = 3 }
                    }) {
                        Text("Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
                .tag(2)
                
                // MARK: Screen 4: Permissions
                VStack(spacing: 32) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                    
                    Text("Import from Contacts")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Goldfish can import names and contact info from your address book. Your data stays on your device.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundStyle(.secondary)
                    
                    if viewModel.isImporting {
                        ProgressView("Importing contacts...")
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.requestContactsAccess { success in
                            hasCompletedOnboarding = true
                        }
                    }) {
                        Text("Allow Access")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .disabled(viewModel.isImporting)
                    
                    Button("Not now") {
                        hasCompletedOnboarding = true
                    }
                    .foregroundColor(.secondary)
                    .disabled(viewModel.isImporting)
                    .padding(.bottom, 48)
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .ignoresSafeArea()
        }
    }
}
