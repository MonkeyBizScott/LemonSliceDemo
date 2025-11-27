//
//  ImageGeneratorReducer.swift
//
//  Created by Scott on 11/27/25.
//

import ComposableArchitecture

@Reducer
struct ImageGenerator: Sendable {
    
    @Dependency(\.falDependency) var fal
    
    @Reducer
    enum Destination: Equatable, Sendable {
        case alert(AlertState<Alert>)
        @CasePathable
        public enum Alert: Sendable, Equatable {
            case noop
            case tryAgain
        }
    }

    @ObservableState
    struct State: Sendable {
        public init() {}
        @Presents var destination: Destination.State?
        var inputText: String = ""
        var inputDisabled: Bool {
            statusText != nil
        }
        var statusText: String?
        var images: IdentifiedArrayOf<FalImageResult.FalImage> = []
        var previousSearchText: String?
    }

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case destination(PresentationAction<Destination.Action>)
        case sendButtonTapped
        case handleStreamUpdate(JobStream)
        case errorGeneratingImage(Error)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .sendButtonTapped:
                if state.inputText.isEmpty {
                    //cancel request
                    return cancelGeneration(state: &state)
                } else {
                    return generateImage(state: &state)
                }
            case .binding:
                return .none
            case let .destination(.presented(.alert(alertAction))):
                return handleAlertActions(state: &state, alertAction: alertAction)
            case .destination:
                return .none
            case let .handleStreamUpdate(update):
                return handleStreamUpdate(state: &state, update: update)
            case let .errorGeneratingImage(error):
                print("Error: \(error)")
                state.destination = .alert(.imageGenerationFailure)
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
    
    func handleAlertActions(state: inout ImageGenerator.State,
                            alertAction: ImageGenerator.Destination.Alert) -> EffectOf<ImageGenerator> {
        state.statusText = nil
        switch alertAction {
        case .noop:
            return .none
        case .tryAgain:
            guard let previous = state.previousSearchText else {
                return .none
            }
            state.inputText = previous
        }
        return .none
    }
    
    func handleStreamUpdate(state: inout ImageGenerator.State, update: JobStream) -> EffectOf<ImageGenerator> {
        switch update.status {
        case .inProgress:
            state.statusText = "In progress..."
        case .inQueue:
            state.statusText = "Queued..."
        case .completed:
            guard let imageResult = update.result,
                  let image = imageResult.images.first else {
                return .none
            }
            state.statusText = nil
            state.previousSearchText = nil
            state.images.insert(image, at: 0)
        }
        return .none
    }
    
    func cancelGeneration(state: inout ImageGenerator.State) -> EffectOf<ImageGenerator> {
        state.statusText = nil
        return .run { _ in
            await fal.cancelCurrentJob()
        }
    }
    
    func generateImage(state: inout ImageGenerator.State) -> EffectOf<ImageGenerator> {
        let prompt = state.inputText
        state.previousSearchText = prompt
        state.inputText = ""
        return .run { send in
            do {
                for try await stream in try await fal.generateImage(prompt) {
                    await send(.handleStreamUpdate(stream))
                }
            } catch {
                await send(.errorGeneratingImage(error))
            }
        }
    }
}

extension AlertState where Action == ImageGenerator.Destination.Alert {
    static var imageGenerationFailure: Self {
        Self {
            TextState("Failed to generate image.")
        } actions: {
            ButtonState(role: .none, action: .tryAgain) {
                TextState("Try again")
            }
            ButtonState(role: .cancel, action: .noop) {
                TextState("Okay")
            }
        }
    }
}

