//
//  ImageGeneratorView.swift
//
//  Created by Scott on 11/26/25.
//

import ComposableArchitecture
import FalClient
import Kingfisher
import SwiftUI

struct ImageGeneratorView: View {
    
    @Bindable var store: StoreOf<ImageGenerator>
    
    var body: some View {
        ZStack(alignment: .bottom) {
            imageList()
            //grid
            inputBar()
        }
        .alert($store.scope(state: \.destination?.alert,
                            action: \.destination.alert))
    }
    
    @ViewBuilder
    func imageList() -> some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let statusText = store.statusText {
                        loadingCell(label: statusText)
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ForEach(store.images) { image in
                        KFImage(image.url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipped()
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                // Animate changes when the loading cell appears/disappears and when
                // the newest image is inserted at the top of the list.
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.85, blendDuration: 0.2),
                    value: store.statusText != nil
                )
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.85, blendDuration: 0.2),
                    value: store.images.map(\.id)
                )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
    
    @ViewBuilder
    func loadingCell(label: String) -> some View {
        // Animated grayscale moving gradient background
        TimelineView(.animation) { timeline in
            let date = timeline.date.timeIntervalSinceReferenceDate
            // Animate positions between 0 and 1
            let phase = abs(sin(date * 0.5))
            let startPoint = UnitPoint(x: 0.0, y: phase)
            let endPoint = UnitPoint(x: 1.0, y: 1.0 - phase)
            
            let gradient = LinearGradient(
                colors: [
                    Color(white: 0.15),
                    Color(white: 0.4),
                    Color(white: 0.7),
                    Color(white: 0.95)
                ],
                startPoint: startPoint,
                endPoint: endPoint
            )
            
            ZStack {
                gradient
                VStack {
                    Spacer()
                    Text(label)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    let systemBackground: Color = Color(uiColor: .systemBackground)
    
    @ViewBuilder
    func inputBar() -> some View {
        HStack {
            TextField("Describe your image", text: $store.inputText)
                .padding(.leading)
                .disabled(store.inputDisabled)
            Button {
                store.send(.sendButtonTapped)
            } label: {
                if store.statusText != nil {
                    ProgressView()
                        .padding(8)
                        .background(systemBackground)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(systemBackground)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.trailing)
        }
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal)
        
    }
}

#Preview {
    ImageGeneratorView(store: Store(initialState: ImageGenerator.State()) {
        ImageGenerator()
      }
    )
}

extension QueueStatus {
    var description: String {
        switch self {
        case .inProgress:
            return "In progress"
        case .completed:
            return "Completed"
        case .inQueue:
            return "In queue"
        }
    }
}
