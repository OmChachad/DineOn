//
//  SafariSheet.swift
//  DineOn
//
//  Created by Om Chachad on 12/05/26.
//


import SwiftUI
import SafariServices

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
