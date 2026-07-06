//
//  SessionDetailView.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 12/30/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import SwiftUI
import AVKit
import SwiftData

struct SessionDetailView: View {
    var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var tempPackageURL: URL?
    @State private var isCreatingPackage = false
    @State private var player: AVPlayer?
    @State private var shareError: String?

    let defaultUrl = URL(fileURLWithPath: "")

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 0.75
            ZStack {
                Color("BackgroundColor")
                    .ignoresSafeArea()
                VStack {
                    VideoPlayer(player: player ?? AVPlayer(url: defaultUrl))
                        .frame(width: width, height: height)
                        .padding(.horizontal, 0.0)
                        .onAppear {
                            if player == nil {
                                player = AVPlayer(url: recording.absoluteRgbPath() ?? defaultUrl)
                            }
                        }

                    HStack(spacing: 20) {
                        Button(action: shareItem) {
                            HStack {
                                if isCreatingPackage {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text(isCreatingPackage ? "Preparing..." : "Share")
                                    .fixedSize()
                            }
                            .foregroundColor(isCreatingPackage ? .gray : .blue)
                            .frame(minWidth: 100)
                        }
                        .disabled(isCreatingPackage)

                        Button(action: deleteItem) {
                            Text("Delete").foregroundColor(Color("DangerColor"))
                        }
                    }
                    .padding(.top, 20)
                }
                .navigationTitle(title)
                .background(Color("BackgroundColor"))
                .sheet(isPresented: $showingShareSheet) {
                    if let packageURL = tempPackageURL {
                        ShareSheet(activityItems: [packageURL]) { _, _, _, _ in
                            // Clean up temporary package after sharing
                            try? FileManager.default.removeItem(at: packageURL)
                            tempPackageURL = nil
                            showingShareSheet = false
                        }
                    }
                }
                .alert("Export Failed", isPresented: Binding(
                    get: { shareError != nil },
                    set: { if !$0 { shareError = nil } }
                )) {
                    Button("OK", role: .cancel) { shareError = nil }
                } message: {
                    Text(shareError ?? "")
                }
            }
        }
    }

    private var title: String {
        recording.createdAt.formatted(date: .long, time: .shortened)
    }

    func deleteItem() {
        // Dismiss before deleting so SwiftUI tears this view down before `body`
        // can re-evaluate against a deleted PersistentModel.
        dismiss()
        recording.deleteFiles()
        modelContext.delete(recording)
        try? modelContext.save()
    }

    func shareItem() {
        guard let sourceDirectory = recording.directoryPath() else {
            shareError = "Unable to locate the recording's dataset folder."
            return
        }
        isCreatingPackage = true

        Task {
            do {
                let packageURL = try await ShareUtility.createShareableArchive(from: sourceDirectory)
                tempPackageURL = packageURL
                isCreatingPackage = false
                showingShareSheet = true
            } catch {
                isCreatingPackage = false
                shareError = error.localizedDescription
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?

    init(activityItems: [Any], completionHandler: UIActivityViewController.CompletionWithItemsHandler? = nil) {
        self.activityItems = activityItems
        self.completionWithItemsHandler = completionHandler
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheet>) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = completionWithItemsHandler
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheet>) {
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(recording: Recording(
            id: UUID(),
            name: "Placeholder name",
            createdAt: Date(),
            duration: 30.0))
    }
    .modelContainer(for: Recording.self, inMemory: true)
}
