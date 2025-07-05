//
//  DeviceTypeModifier.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//


import SwiftUI

struct DeviceTypeModifier: ViewModifier {
    enum DeviceType {
        case phone
        case pad
    }
    
    let content: (DeviceType) -> AnyView
    
    func body(content: Content) -> some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                self.content(.pad)
            } else {
                self.content(.phone)
            }
        }
    }
}

extension View {
    func deviceSpecific<P: View, I: View>(phone: @escaping () -> P, iPad: @escaping () -> I) -> some View {
        modifier(DeviceTypeModifier(content: { deviceType in
            switch deviceType {
            case .phone:
                return AnyView(phone())
            case .pad:
                return AnyView(iPad())
            }
        }))
    }
}

// This comment shows how to use the device detection in MainEmployeeView.swift
/*
    // Sports Shoot with device detection
    NavigationLink(
        destination: Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                SportsShootDetailiPadView(sportsShootID: selectedSportsShootID ?? "")
            } else {
                SportsShootListView()
            }
        },
        tag: "sportsShoot",
        selection: $selectedFeatureID
    ) { EmptyView() }
*/
