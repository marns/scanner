//
//  NewSession.swift
//  Stray Scanner
//
//  Created by Kenneth Blomqvist on 11/28/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import SwiftUI
import SwiftData

struct RecordSessionManager: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    func makeUIViewController(context: Context) -> RecordSessionViewController {
        let viewController = RecordSessionViewController(nibName: "RecordSessionView", bundle: nil)
        viewController.modelContext = modelContext
        viewController.setDismissFunction { [weak viewController] in
            dismiss()
            viewController?.setDismissFunction(Optional.none)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: RecordSessionViewController, context: Context) {}
}

struct NewSessionView : View {

    var body: some View {
        RecordSessionManager()
            .padding(.vertical, 0.0)
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea()
    }
}

#Preview {
    NavigationStack {
        NewSessionView()
    }
    .modelContainer(for: Recording.self, inMemory: true)
}
