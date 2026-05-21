//
//  PrismMusicLiveActivityBundle.swift
//  PrismMusicLiveActivity
//
//  Widget bundle entry point for the Live Activity extension. Registers
//  the single Activity widget that powers Dynamic Island + lock-screen
//  Now Playing.
//

import SwiftUI
import WidgetKit

@main
struct PrismMusicLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PrismMusicLiveActivityWidget()
    }
}
