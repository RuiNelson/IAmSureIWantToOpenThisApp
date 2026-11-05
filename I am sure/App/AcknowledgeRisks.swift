//
//  AcknowledgeRisks.swift
//  I am sure I want to open this App
//
//  Created by Rui Nelson on 05/11/2026.
//

import SwiftUI

struct AcknowledgeRisks: View {
    @AppStorage("ackRisks") private var acknowledged = false
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Before you continue", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())

            Text("macOS marks files downloaded from the internet with the `com.apple.quarantine` attribute. Gatekeeper uses it to check that apps are signed and notarized before they open.")

            Text("Removing it skips that check. Only do this for apps and files you trust, from a source you know.")
                .bold()

            Toggle("I understand the risks", isOn: $understood)

            HStack {
                Spacer()
                Button("Continue") { acknowledged = true }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!understood)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(28)
        .frame(width: 480)
        .glassEffect(in: .rect(cornerRadius: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mainToolbar(title: "I am sure", subtitle: "Before you continue")
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    NavigationStack {
        AcknowledgeRisks()
    }
    .frame(width: 640, height: 480)
    .environment(RemovalModel())
}
