import SwiftUI
import UIKit

public final class NetworkLoggerSettingsViewController: UIViewController {
    
    public var onClose: (() -> Void)?
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let networkLoggerSettingsView = NetworkLoggerSettingsView(onClose: { [weak self] in
            self?.onClose?()
        })
        let hostingController = UIHostingController(rootView: networkLoggerSettingsView)
        view.addSubview(hostingController.view)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

struct NetworkLoggerSettingsView: View {
    @AppStorage(DebugNetworkLogger.logLevelKey)            private var logLevel = "minimal"
    @AppStorage(DebugNetworkLogger.logOnlyToConsoleKey)    private var logOnlyToConsole = false
    @AppStorage(DebugNetworkLogger.deteleOnStartupKey)     private var deleteFileOnStartup = false
    @AppStorage(DebugNetworkLogger.filteredEndpointsKey)   private var filteredEndpoints = ""
    
    var onClose: (() -> Void)?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Console Logging Level")) {
                    Picker("Log Level", selection: $logLevel) {
                        Text("Minimal").tag("minimal")
                        Text("Verbose").tag("verbose")
                        Text("Only to Log File").tag("onlyToLogFile")
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Logging Options")) {
                    Toggle("Log Only to Console", isOn: $logOnlyToConsole)
                    
                    Toggle("Delete Log File on Startup", isOn: $deleteFileOnStartup)
                }
                
                Section(header: Text("Endpoint Filtering")) {
                    TextField("Comma-separated Endpoints", text: $filteredEndpoints)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section {
                    Button("Apply Settings") {
                        applySettings()
                        onClose?()
                    }
                }
                
                Section {
                    Button("Close") {
                        onClose?()
                    }
                }
            }
            .navigationTitle("Network Logger")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func applySettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(logLevel,             forKey: DebugNetworkLogger.logLevelKey)
        userDefaults.set(logOnlyToConsole,     forKey: DebugNetworkLogger.logOnlyToConsoleKey)
        userDefaults.set(deleteFileOnStartup,  forKey: DebugNetworkLogger.deteleOnStartupKey)
        userDefaults.set(filteredEndpoints,    forKey: DebugNetworkLogger.filteredEndpointsKey)
        
        DebugNetworkLogger.reloadSettings()
    }
}
