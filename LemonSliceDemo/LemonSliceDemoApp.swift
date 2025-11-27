//
//  LemonSliceDemoApp.swift
//
//  Created by Scott on 11/26/25.
//

import ComposableArchitecture
import SwiftUI

@main
struct LemonSliceDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ImageGeneratorView(store: Store(initialState: ImageGenerator.State()) {
                ImageGenerator()
              })
        }
    }
}
