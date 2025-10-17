//
//  IndentedDisclosureGroup.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import SwiftUI

struct IndentedDisclosureGroup<Label: View, Content: View>: View {
    var indentAmount: CGFloat = 20.0
    var expandedByDefault: Bool = false
    
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    
    @State private var isExpanded: Bool = false
    
    init(indentAmount: CGFloat = 20.0,
         expandedByDefault: Bool = false,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> Label) {
        self.indentAmount = indentAmount
        self.expandedByDefault = expandedByDefault
        self.content = content
        self.label = label
        _isExpanded = State(initialValue: expandedByDefault)
    }
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.leading, indentAmount)
        } label: {
            label()
        }
    }
}
