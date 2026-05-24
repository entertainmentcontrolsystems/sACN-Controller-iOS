import SwiftUI

/// Main screen for sACN Controller iOS.
struct MainScreen: View {
    @EnvironmentObject var model: SACNViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FixturesTab()
                .tabItem { Label("Fixtures", systemImage: "light.beacon.max") }
                .tag(0)

            CueListsTab()
                .tabItem { Label("Cues", systemImage: "list.number") }
                .tag(1)

            ConverterTab()
                .tabItem { Label("Convert", systemImage: "arrow.triangle.swap") }
                .tag(2)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .overlay(alignment: .bottom) {
            if let msg = model.statusMessage {
                StatusBar(message: msg)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

// ─── Fixtures Tab ───────────────────────────────────────────────────────────

struct FixturesTab: View {
    @EnvironmentObject var model: SACNViewModel
    @State private var showAddFixture = false
    @State private var showAddProfile = false
    @State private var newFixtureName = ""
    @State private var newFixtureProfileId = ""
    @State private var newFixtureUniverse = 1
    @State private var newFixtureAddress = 1

    var body: some View {
        NavigationStack {
            List {
                if model.fixtures.isEmpty {
                    Text("No fixtures patched")
                        .foregroundColor(.secondary)
                }
                ForEach(model.fixtures) { fixture in
                    FixtureRow(fixture: fixture)
                }
            }
            .navigationTitle("Fixtures")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Add Fixture") { showAddFixture = true }
                        Button("Import GDTF") { showAddProfile = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { model.toggleBlackout() }) {
                        Image(systemName: model.blackoutActive ? "moon.fill" : "moon")
                            .foregroundColor(model.blackoutActive ? .red : .primary)
                    }
                }
            }
            .sheet(isPresented: $showAddFixture) {
                Form {
                    TextField("Name", text: $newFixtureName)
                    TextField("Profile ID", text: $newFixtureProfileId)
                    Stepper("Universe: \(newFixtureUniverse)", value: $newFixtureUniverse, in: 1...64)
                    Stepper("Address: \(newFixtureAddress)", value: $newFixtureAddress, in: 1...512)
                    Button("Add") {
                        model.addFixture(
                            name: newFixtureName,
                            profileId: newFixtureProfileId,
                            universe: newFixtureUniverse,
                            address: newFixtureAddress
                        )
                        showAddFixture = false
                        newFixtureName = ""
                    }
                }
                .padding()
            }
        }
    }
}

struct FixtureRow: View {
    let fixture: FixtureInstance

    var body: some View {
        VStack(alignment: .leading) {
            Text(fixture.name).font(.headline)
            Text("Universe \(fixture.universe) · Address \(fixture.startAddress)")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// ─── Cue Lists Tab ──────────────────────────────────────────────────────────

struct CueListsTab: View {
    @EnvironmentObject var model: SACNViewModel
    @State private var showNewCueList = false
    @State private var newCueListName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.cueLists) { list in
                    CueListRow(list: list)
                }
            }
            .navigationTitle("Cue Lists")
            .toolbar {
                ToolbarItem {
                    Button { showNewCueList = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Cue List", isPresented: $showNewCueList) {
                TextField("Name", text: $newCueListName)
                Button("Create") {
                    model.createCueList(newCueListName)
                    newCueListName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct CueListRow: View {
    @EnvironmentObject var model: SACNViewModel
    let list: CueList

    var body: some View {
        VStack(alignment: .leading) {
            Text(list.name).font(.headline)
            Text("\(list.steps.count) cues").font(.caption).foregroundColor(.secondary)
            HStack {
                Button("Play") { model.playCueList(list.id) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Go") { model.goNext() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Back") { model.goBack() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Stop") { model.stopPlayback() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Snap") { model.saveCurrentAsCue(cueListId: list.id) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// ─── Converter Tab ──────────────────────────────────────────────────────────

struct ConverterTab: View {
    @EnvironmentObject var model: SACNViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if model.converterRunning {
                    Text("Listening on Universe \(model.converterConfig.inputUniverse)")
                        .font(.headline).foregroundColor(.green)
                }

                Picker("Input Universe", selection: Binding(
                    get: { model.converterConfig.inputUniverse },
                    set: { model.converterConfig.inputUniverse = $0 }
                )) {
                    ForEach(1...64, id: \.self) { uni in
                        Text("Universe \(uni)").tag(uni)
                    }
                }

                Button(model.converterRunning ? "Stop" : "Start") {
                    // Converter start/stop via SACN Receiver
                    model.converterRunning.toggle()
                    model.statusMessage = model.converterRunning
                        ? "Converter listening" : "Converter stopped"
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("D16xy Converter")
        }
    }
}

// ─── Settings Tab ───────────────────────────────────────────────────────────

struct SettingsTab: View {
    @EnvironmentObject var model: SACNViewModel
    @State private var sourceName = ""
    @State private var priority = 100

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("Name", text: $sourceName)
                        .onSubmit { model.settings.sourceName = sourceName }
                    Stepper("Priority: \(priority)", value: $priority, in: 0...200)
                        .onChange(of: priority) { _, new in
                            model.settings.sacnPriority = new
                        }
                }

                Section("Network") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Image(systemName: model.networkStatus.wifiConnected
                            ? "wifi" : "wifi.slash")
                        Text(model.networkStatus.wifiConnected ? "Connected" : "Disconnected")
                            .foregroundColor(.secondary)
                    }
                    if model.networkStatus.sendErrors > 0 {
                        Text("Send errors: \(model.networkStatus.sendErrors)")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                sourceName = model.settings.sourceName
                priority = model.settings.sacnPriority
            }
        }
    }
}

// ─── Status Bar ─────────────────────────────────────────────────────────────

struct StatusBar: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.bottom, 8)
    }
}

#Preview {
    MainScreen()
        .environmentObject(SACNViewModel())
}
