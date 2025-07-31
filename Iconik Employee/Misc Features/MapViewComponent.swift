//
//  MapViewComponent.swift
//  Iconik Employee
//
//  Created by administrator on 4/22/25.
//


import SwiftUI
import MapKit
import UIKit

// UIKit Map view wrapper for SwiftUI
struct MapViewComponent: UIViewRepresentable {
    @Binding var centerCoordinate: CLLocationCoordinate2D
    @Binding var pinCoordinate: CLLocationCoordinate2D
    @Binding var region: MKCoordinateRegion
    @Binding var isDragging: Bool
    var mapType: MKMapType = .standard
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewComponent
        var dragStartPosition: CLLocationCoordinate2D?
        
        init(_ parent: MapViewComponent) {
            self.parent = parent
        }
        
        // Handle annotation view drag events
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            let identifier = "DraggablePin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView!.isDraggable = true
                annotationView!.canShowCallout = true
            } else {
                annotationView!.annotation = annotation
            }
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            
            switch newState {
            case .starting:
                parent.isDragging = true
                dragStartPosition = view.annotation?.coordinate
            case .dragging:
                if let coordinate = view.annotation?.coordinate {
                    parent.pinCoordinate = coordinate
                }
            case .ending, .canceling:
                parent.isDragging = false
                if let coordinate = view.annotation?.coordinate {
                    parent.pinCoordinate = coordinate
                }
            default:
                break
            }
        }
        
        // Update region when the map is moved
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            parent.centerCoordinate = mapView.centerCoordinate
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        
        // Add the draggable pin
        let annotation = MKPointAnnotation()
        annotation.coordinate = pinCoordinate
        annotation.title = "Location"
        mapView.addAnnotation(annotation)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map type if it changed
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        
        // Update the region if it changed
        if mapView.region.center.latitude != region.center.latitude ||
           mapView.region.center.longitude != region.center.longitude ||
           mapView.region.span.latitudeDelta != region.span.latitudeDelta ||
           mapView.region.span.longitudeDelta != region.span.longitudeDelta {
            mapView.setRegion(region, animated: true)
        }
        
        // Update pin if it changed
        if let annotation = mapView.annotations.first as? MKPointAnnotation,
           (annotation.coordinate.latitude != pinCoordinate.latitude ||
            annotation.coordinate.longitude != pinCoordinate.longitude) {
            annotation.coordinate = pinCoordinate
        }
    }
}