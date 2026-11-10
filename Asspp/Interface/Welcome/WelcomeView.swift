//
//  WelcomeView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

struct WelcomeView: View {
    @State var openInstruction: Bool = false

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(width: 80, height: 80)

                Text("Welcome to Velo")
                    .font(.system(.headline, design: .rounded))

                Spacer().frame(height: 0)
            }

            VStack(spacing: 16) {
                Spacer()
                HStack(spacing: 8) {
                    Text(version)
                    Button {
                        openInstruction = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $openInstruction) {
                        SimpleInstruction()
                            .padding(32)
                    }
                }
                Text("The App Store API can be unstable. Retry if an error occurs.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AssppTheme.background)
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }
}
