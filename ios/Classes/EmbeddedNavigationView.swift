//
//  FlutterMapboxNavigationPlugin.swift
//  demo_plugin
//
//  Created by NhatPV on 16/06/2023.
//
import Flutter
import UIKit
import Mapbox
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation

private typealias RouteRequestSuccess = (([Route]) -> Void)
private typealias RouteRequestFailure = ((NSError) -> Void)

public class FlutterMapNavigationView : NavigationFactory, FlutterPlatformView
{
    let frame: CGRect
    let viewId: Int64

    let messenger: FlutterBinaryMessenger
    let channel: FlutterMethodChannel
    let eventChannel: FlutterEventChannel

    var navigationMapView: NavigationMapView! {
        didSet {
            oldValue?.removeFromSuperview()
            if let mapView = navigationMapView {
                configureMapView(mapView)
            }
        }
    }
    var routes: [Route]? {
        didSet {
            guard let routes = routes,
                  let current = routes.first else { navigationMapView?.removeRoutes(); return }

            navigationMapView?.showRoutes(routes)
            navigationMapView?.showWaypoints(current)
        }
    }
    
    var routeController: RouteController?
    
    var arguments: NSDictionary?
    var wayPoints = [Waypoint]()
    var routeResponse: Route?
    var selectedRouteIndex = 0
    var routeOptions: NavigationRouteOptions?
//    var navigationService: NavigationService!

    var locationManager = CLLocationManager()

//    private let passiveLocationManager = PassiveLocationManager()
//    private lazy var passiveLocationProvider = PassiveLocationProvider(locationManager: passiveLocationManager)

    init(messenger: FlutterBinaryMessenger, frame: CGRect, viewId: Int64, args: Any?)
    {
        self.frame = frame
        self.viewId = viewId
        self.arguments = args as! NSDictionary?

        self.messenger = messenger
        self.channel = FlutterMethodChannel(name: "demo_plugin/\(viewId)", binaryMessenger: messenger)
        self.eventChannel = FlutterEventChannel(name: "demo_plugin/\(viewId)/events", binaryMessenger: messenger)

        super.init()

        self.eventChannel.setStreamHandler(self)

        self.channel.setMethodCallHandler { [weak self](call, result) in

            guard let strongSelf = self else { return }

            let arguments = call.arguments as? NSDictionary

            if(call.method == "getPlatformVersion")
            {
                result("iOS " + UIDevice.current.systemVersion)
            }
            else if(call.method == "buildRoute")
            {
                strongSelf.buildRoute(arguments: arguments, flutterResult: result)
            }
            else if(call.method == "clearRoute")
            {
                strongSelf.clearRoute(arguments: arguments, result: result)
            }
            else if(call.method == "getDistanceRemaining")
            {
                result(strongSelf._distanceRemaining ?? 0.0)
            }
            else if(call.method == "getDurationRemaining")
            {
                result(strongSelf._durationRemaining ?? 0.0)
            }
            else if(call.method == "finishNavigation")
            {
                strongSelf.endNavigation(result: result)
            }
            else if(call.method == "startFreeDrive")
            {
//                strongSelf.startEmbeddedFreeDrive(arguments: arguments, result: result)
            }
            else if(call.method == "startNavigation")
            {
                strongSelf.startNavigationEmbedded(arguments: arguments, result: result)
            }
            else if(call.method == "reCenter")
            {
                //used to recenter map from user action during navigation
                strongSelf.navigationMapView.recenterMap()
            }
            else
            {
                result("method is not implemented");
            }

        }
    }

    public func view() -> UIView
    {
        setupMapView()
        return navigationMapView
    }

    private func configureMapView(_ mapView: NavigationMapView) {
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.navigationMapDelegate = self
        mapView.showsUserHeadingIndicator = true
    }
    
    private func setupMapView()
    {
        navigationMapView = NavigationMapView(frame: frame,styleURL: URL(string: _url))
        if(self.arguments != nil)
        {
            parseFlutterArguments(arguments: arguments)
            var currentLocation: CLLocation!
            locationManager.requestWhenInUseAuthorization()
            if(CLLocationManager.authorizationStatus() == .authorizedWhenInUse ||
                CLLocationManager.authorizationStatus() == .authorizedAlways) {
                currentLocation = locationManager.location

            }
            let initialLatitude = arguments?["initialLatitude"] as? Double ?? currentLocation?.coordinate.latitude
            let initialLongitude = arguments?["initialLongitude"] as? Double ?? currentLocation?.coordinate.longitude
            if(initialLatitude != nil && initialLongitude != nil)
            {
                moveCameraToCoordinates(latitude: initialLatitude!, longitude: initialLongitude!)
            }

        }

        if _longPressDestinationEnabled
        {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            gesture.delegate = self
            navigationMapView?.addGestureRecognizer(gesture)
        }

    }

    func moveCameraToCoordinates(latitude: Double, longitude: Double) {
        navigationMapView.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), zoomLevel: self._zoom, animated: true)
    }
    
    fileprivate lazy var defaultSuccess: RouteRequestSuccess = { [weak self] (routes) in
        guard let strongSelf = self else { return }
        guard let current = routes.first else { return }
        strongSelf.routeResponse = current
        strongSelf.sendEvent(eventType: MapEventType.routeBuilt, data: strongSelf.encodeRoute(route: current))
        strongSelf.routes = routes
        strongSelf._routes = routes
        strongSelf._wayPoints = current.routeOptions.waypoints
    }

    fileprivate lazy var defaultFailure: RouteRequestFailure = { [weak self] (error) in
        guard let strongSelf = self else { return }
        strongSelf._routes = nil //clear routes from the map
    }
    
    func buildRoute(arguments: NSDictionary?, flutterResult: @escaping FlutterResult)
    {
        sendEvent(eventType: MapEventType.routeBuilding)

        guard let oWayPoints = arguments?["wayPoints"] as? NSDictionary else {return}

        for item in oWayPoints as NSDictionary
        {
            let point = item.value as! NSDictionary
            guard point["Name"] is String else {return }
            guard let oLatitude = point["Latitude"] as? Double else {return}
            guard let oLongitude = point["Longitude"] as? Double else {return}
            _ = point["IsSilent"] as? Bool ?? false
            _ = point["Order"] as? Int
            let coordinate = CLLocationCoordinate2D(latitude: oLatitude, longitude: oLongitude)
            let waypoint = Waypoint(coordinate: coordinate)
            _wayPoints.append(waypoint)
        }

        parseFlutterArguments(arguments: arguments)
        
        if(_wayPoints.count > 3 && arguments?["mode"] == nil)
        {
            _navigationMode = "driving"
        }

        var mode: MBDirectionsProfileIdentifier = .automobileAvoidingTraffic

        if (_navigationMode == "cycling")
        {
            mode = .cycling
        }
        else if(_navigationMode == "driving")
        {
            mode = .automobile
        }
        else if(_navigationMode == "walking")
        {
            mode = .walking
        }

        let routeOptions = NavigationRouteOptions(waypoints: _wayPoints, profileIdentifier: mode)
        routeOptions.shapeFormat = .polyline6

        if (_allowsUTurnAtWayPoints != nil)
        {
            routeOptions.allowsUTurnAtWaypoint = _allowsUTurnAtWayPoints!
        }

        routeOptions.distanceMeasurementSystem = _voiceUnits == "imperial" ? .imperial : .metric
        routeOptions.locale = Locale(identifier: _language)
        self.routeOptions = routeOptions

        // Generate the route object and draw it on the map
        _ = Directions.shared.calculate(routeOptions) { [weak self] (session, result, error) in
            guard let strongSelf = self else { return }
            if let response = result?.first {
                // Handle success case
                strongSelf.routes = result
                strongSelf._routes = result
                strongSelf._wayPoints = response.routeOptions.waypoints
                strongSelf.routeResponse = response
                strongSelf.navigationMapView.setOverheadCameraView(from: strongSelf._wayPoints.first!.coordinate, along: response.coordinates!, for: strongSelf.overheadInsets)
                strongSelf.sendEvent(eventType: MapEventType.routeBuilt, data: strongSelf.encodeRoute(route: response))
            } else {
                // Handle failure case
                flutterResult(false)
                strongSelf.sendEvent(eventType: MapEventType.routeBuildFailed)
            }
        }
    }
    
    @objc var overheadInsets: UIEdgeInsets {
        return UIEdgeInsets(top: 20, left: 20, bottom: 70, right: 20)
    }
    
    func clearRoute(arguments: NSDictionary?, result: @escaping FlutterResult) {
        if routeResponse == nil
        {
            return
        }
        navigationMapView.removeRoutes()
        navigationMapView.removeWaypoints()
        _wayPoints.removeAll()
        sendEvent(eventType: MapEventType.navigationCancelled)
    }
    
    func endNavigationEmbedded(result: FlutterResult?) {
        if (routeController != nil) {
            routeController?.endNavigation()
            navigationMapView.recenterMap()                        
            suspendNotifications()
            sendEvent(eventType: MapEventType.navigationCancelled)
            if(result != nil)
            {
                result!(true)
            }
        }
    }
    
    func startNavigationEmbedded(arguments: NSDictionary?, result: @escaping FlutterResult) {
        isEmbeddedNavigation = true
        guard let response = self.routeResponse else { return }
        
        routeController = RouteController(along: response, locationManager: NavigationLocationManager())
        routeController?.delegate = self
        routeController?.reroutesProactively = true
        routeController?.resume()
        navigationMapView.recenterMap()
        resumeNotifications()
        result(true)
    }
    
    func resumeNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(progressDidChange(_ :)), name: .routeControllerProgressDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rerouted(_:)), name: .routeControllerDidReroute, object: nil)
    }

    func suspendNotifications() {
        NotificationCenter.default.removeObserver(self, name: .routeControllerProgressDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .routeControllerWillReroute, object: nil)
    }
    
    @objc func progressDidChange(_ notification: NSNotification) {
        let routeProgress = notification.userInfo![RouteControllerNotificationUserInfoKey.routeProgressKey] as! RouteProgress
        let location = notification.userInfo![RouteControllerNotificationUserInfoKey.locationKey] as! CLLocation
        // Update the user puck
        let camera = MGLMapCamera(lookingAtCenter: location.coordinate, fromDistance: 120, pitch: 60, heading: location.course)
        navigationMapView.updateCourseTracking(location: location, camera: camera, animated: true)
        _distanceRemaining = routeProgress.distanceRemaining
        _durationRemaining = routeProgress.durationRemaining
        sendEvent(eventType: MapEventType.navigationRunning)
    }
    
    @objc func rerouted(_ notification: NSNotification) {
        self.navigationMapView.showRoutes([(routeController?.routeProgress.route)!])
        self.navigationMapView.tracksUserCourse = true
        self.navigationMapView.recenterMap()
    }
}

// MARK: - NavigationMapViewDelegate
extension FlutterMapNavigationView : NavigationMapViewDelegate {
    public func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        guard let routes = routes else { return }
        guard let index = routes.firstIndex(where: { $0 == route }) else { return }
        self.routes!.remove(at: index)
        self.routes!.insert(route, at: 0)
        self._routes!.remove(at: index)
        self._routes!.insert(route, at: 0)
    }
}

extension FlutterMapNavigationView : MGLMapViewDelegate {
    
}

extension FlutterMapNavigationView : UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = navigationMapView.convert(gesture.location(in: navigationMapView), toCoordinateFrom: navigationMapView)
        requestRoute(destination: location)
    }

    func requestRoute(destination: CLLocationCoordinate2D) {
        sendEvent(eventType: MapEventType.routeBuilding)

        guard let userLocation = navigationMapView.userLocation?.location else { return }
        let location = CLLocation(latitude: userLocation.coordinate.latitude,
                                  longitude: userLocation.coordinate.longitude)
        let userWaypoint = Waypoint(location: location, name: "Vị trí của bạn")
        let destinationWaypoint = Waypoint(coordinate: destination, name: "Điểm đến của bạn")

        let routeOptions = NavigationRouteOptions(waypoints: [userWaypoint, destinationWaypoint])
        routeOptions.shapeFormat = .polyline6
        routeOptions.locale = Locale(identifier: "vi")
        requestRoute(with: routeOptions, success: defaultSuccess, failure: defaultFailure)
    }
    
    fileprivate func requestRoute(with options: RouteOptions, success: @escaping RouteRequestSuccess, failure: RouteRequestFailure?) {
        let handler: Directions.RouteCompletionHandler = {(waypoints, potentialRoutes, potentialError) in
            if let error = potentialError, let fail = failure { return fail(error) }
            guard let routes = potentialRoutes else { return }
            return success(routes)
        }
        let apiUrl = Directions.shared.url(forCalculating: options)
        print("API Request URL: \(apiUrl)")
        Directions.shared.calculate(options, completionHandler: handler)
    }
}

extension FlutterMapNavigationView: RouteControllerDelegate {
    public func routeController(_ routeController: RouteController, didArriveAt waypoint: Waypoint) -> Bool {
        return false
    }
}

