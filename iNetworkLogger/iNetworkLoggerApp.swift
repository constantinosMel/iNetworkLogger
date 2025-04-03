//
//  iNetworkLoggerApp.swift
//  iNetworkLogger
//

import SwiftUI

@main
struct NetworkLoggerDemoApp: App {
    init() {
        DebugNetworkLogger.setEnabled(true)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var showSettings = false
    @State private var response: String = "Make a request to see the response"
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Test Requests")) {
                    Button("GET Request") {
                        makeGetRequest()
                    }
                    
                    Button("POST Request") {
                        makePostRequest()
                    }
                    
                    Button("Error Request") {
                        makeErrorRequest()
                    }
                }
                
                Section(header: Text("Response")) {
                    Text(response)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Network Logger")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                NetworkLoggerSettingsView(onClose: {
                    showSettings = false
                })
            }
        }
    }
    
    private func makeGetRequest() {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.response = "Error: \(error.localizedDescription)"
                } else if let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.response = "Success: \(json)"
                }
            }
        }.resume()
    }
    
    private func makePostRequest() {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "title": "Test Post",
            "body": "This is a test post",
            "userId": 1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.response = "Error: \(error.localizedDescription)"
                } else if let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.response = "Success: \(json)"
                }
            }
        }.resume()
    }
    
    private func makeErrorRequest() {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/invalid") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.response = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    self.response = "HTTP Error: \(httpResponse.statusCode)"
                }
            }
        }.resume()
    }
}
