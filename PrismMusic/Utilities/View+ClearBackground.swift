//
//  View+ClearBackground.swift
//  PrismMusic
//
//  Utility to clear the background of containing UIHostingController
//  and UINavigationController so that parent backgrounds (like the
//  immersive cover background) are visible.
//

import SwiftUI
import UIKit

struct TransparentBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            var parentResponder: UIResponder? = view
            while let nextResponder = parentResponder?.next {
                parentResponder = nextResponder
                if let viewController = parentResponder as? UIViewController {
                    viewController.view.backgroundColor = .clear
                    viewController.view.isOpaque = false
                    
                    // Also clear all parent view controllers in the hierarchy (e.g. UINavigationController, UITabBarController)
                    var parentVC = viewController.parent
                    while let parent = parentVC {
                        parent.view.backgroundColor = .clear
                        parent.view.isOpaque = false
                        parentVC = parent.parent
                    }
                }
            }
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ClearBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TransparentBackground())
    }
}

extension View {
    /// Clears the background of containing hosting controllers and navigation controllers.
    func clearHostingBackground() -> some View {
        self.modifier(ClearBackgroundModifier())
    }
}
