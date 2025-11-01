import SwiftUI
import MapKit

// MARK: - App Entry Point
/// The main entry point for the ParkVision app
/// This struct conforms to the App protocol and defines the app's structure
@main
struct ParkVisionApp: App {
    var body: some Scene {
        WindowGroup {
            // Set ParkingFinderView as the initial view when the app launches
            ParkingFinderView()
        }
    }
}

// MARK: - API Service
/// Service class responsible for all network communication with the backend
/// Uses ObservableObject to allow SwiftUI views to react to data changes
class ParkingAPIService: ObservableObject {
    // Singleton pattern - ensures only one instance exists throughout the app
    static let shared = ParkingAPIService()
    
    // CHANGE THIS to your backend server URL
    // This is where your Python Flask server is running
    private let baseURL = "http://your-server-ip:5000"
    // Examples:
    // Local testing: "http://192.168.1.100:5000"
    // Cloud deployment: "https://your-api.herokuapp.com"
    // ngrok tunnel: "https://abc123.ngrok.io"
    
    // @Published properties automatically notify views when they change
    @Published var parkingLots: [ParkingLot] = []  // Array of all parking lot data
    @Published var isLoading = false               // Shows loading indicator
    @Published var errorMessage: String?           // Displays error messages to user
    @Published var lastUpdated: Date?              // Timestamp of last data refresh
    
    /// Fetches all parking lots from the backend API
    /// This is called when the app first loads and during manual refreshes
    /// Returns: Array of ParkingLot objects with current availability
    func fetchParkingLots() async throws -> [ParkingLot] {
        // Construct the full API endpoint URL
        let url = URL(string: "\(baseURL)/api/parking_lots")!
        
        // Make async network request to fetch data
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Create decoder to convert JSON to Swift objects
        let decoder = JSONDecoder()
        // Converts snake_case JSON keys to camelCase Swift properties
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Decode the JSON response into our response model
        let response = try decoder.decode(ParkingLotsResponse.self, from: data)
        
        // Map the API response data to our app's ParkingLot model
        return response.lots.map { lotData in
            ParkingLot(
                id: lotData.id,
                name: lotData.name,
                address: lotData.address,
                latitude: lotData.latitude,
                longitude: lotData.longitude,
                totalSpots: lotData.totalSpots,
                availableSpots: lotData.availableSpots,
                pricePerHour: lotData.pricePerHour,
                rating: lotData.rating,
                type: ParkingType(rawValue: lotData.type) ?? .lot,
                distance: lotData.distance,
                // Map each spot's data to IndividualSpot objects
                spots: lotData.spots.map { spotData in
                    IndividualSpot(
                        id: spotData.id,
                        number: spotData.number,
                        isOccupied: spotData.isOccupied,
                        confidence: spotData.confidence,
                        // Convert ISO8601 string to Date object
                        lastUpdated: ISO8601DateFormatter().date(from: spotData.lastUpdated) ?? Date()
                    )
                }
            )
        }
    }
    
    /// Fetches detailed information for a specific parking lot
    /// Used when user taps on a lot to see all individual spot statuses
    /// Parameters:
    ///   - lotId: The unique identifier of the parking lot
    /// Returns: Single ParkingLot object with full details
    func fetchParkingLotDetails(lotId: Int) async throws -> ParkingLot {
        // Construct URL with the specific lot ID
        let url = URL(string: "\(baseURL)/api/parking_lots/\(lotId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Decode the detailed lot data
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let lotData = try decoder.decode(ParkingLotData.self, from: data)
        
        // Convert to our app's ParkingLot model
        return ParkingLot(
            id: lotData.id,
            name: lotData.name,
            address: lotData.address,
            latitude: lotData.latitude,
            longitude: lotData.longitude,
            totalSpots: lotData.totalSpots,
            availableSpots: lotData.availableSpots,
            pricePerHour: lotData.pricePerHour,
            rating: lotData.rating,
            type: ParkingType(rawValue: lotData.type) ?? .lot,
            distance: lotData.distance,
            spots: lotData.spots.map { spotData in
                IndividualSpot(
                    id: spotData.id,
                    number: spotData.number,
                    isOccupied: spotData.isOccupied,
                    confidence: spotData.confidence,
                    lastUpdated: ISO8601DateFormatter().date(from: spotData.lastUpdated) ?? Date()
                )
            }
        )
    }
    
    /// Starts automatic refresh of parking data at regular intervals
    /// This keeps the app's data synchronized with the camera system
    /// Parameters:
    ///   - interval: Time in seconds between refreshes (default: 10 seconds)
    func startAutoRefresh(interval: TimeInterval = 10.0) {
        // Create a repeating timer that fires every 'interval' seconds
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            // Create async task to fetch data without blocking UI
            Task {
                do {
                    // Fetch latest parking data
                    let lots = try await self.fetchParkingLots()
                    // Update UI on main thread
                    await MainActor.run {
                        self.parkingLots = lots
                        self.lastUpdated = Date()
                    }
                } catch {
                    // Handle errors by updating error message
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - API Response Models
/// Models that match the JSON structure returned by the backend API
/// These are used for decoding the API responses

/// Response wrapper for the list of parking lots
struct ParkingLotsResponse: Codable {
    let lots: [ParkingLotData]
}

/// Detailed data for a single parking lot from the API
struct ParkingLotData: Codable {
    let id: Int
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let totalSpots: Int
    let availableSpots: Int
    let pricePerHour: Double
    let rating: Double
    let type: String
    let distance: Double
    let spots: [SpotDetailData]
}

/// Individual parking spot data from the API
struct SpotDetailData: Codable {
    let id: Int
    let number: Int
    let isOccupied: Bool
    let confidence: Double      // CNN model's confidence level (0.0 to 1.0)
    let lastUpdated: String     // ISO8601 timestamp string
}

// MARK: - App Models
/// Models used throughout the app for displaying parking data

/// Represents a parking lot with all its details and computed properties
struct ParkingLot: Identifiable {
    let id: Int
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let totalSpots: Int
    let availableSpots: Int
    let pricePerHour: Double
    let rating: Double
    let type: ParkingType
    let distance: Double
    let spots: [IndividualSpot]
    
    /// Computed property that converts lat/long to MapKit coordinate
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Calculates what percentage of spots are available (0.0 to 1.0)
    var availabilityRatio: Double {
        Double(availableSpots) / Double(totalSpots)
    }
    
    /// Returns color based on availability: green (plenty), yellow (limited), red (few)
    var availabilityColor: Color {
        if availabilityRatio > 0.5 { return .green }
        if availabilityRatio > 0.2 { return .yellow }
        return .red
    }
}

/// Represents a single parking spot within a parking lot
struct IndividualSpot: Identifiable {
    let id: Int
    let number: Int              // Spot number displayed to user
    let isOccupied: Bool         // True if car detected, false if empty
    let confidence: Double       // CNN model's confidence (0.0 to 1.0)
    let lastUpdated: Date        // When this spot was last checked by camera
}

/// Enum for different types of parking locations
enum ParkingType: String, CaseIterable, Codable {
    case garage = "Garage"  // Multi-level parking structure
    case street = "Street"  // On-street parking
    case lot = "Lot"        // Open parking lot
}

// MARK: - Main View
/// The main screen of the app - full screen map with search overlay
struct ParkingFinderView: View {
    // Access the shared API service
    @StateObject private var apiService = ParkingAPIService.shared
    
    // State variables track UI state and user interactions
    @State private var selectedLot: ParkingLot?              // Currently selected lot for detail view
    @State private var searchText = ""                       // User's search query
    @State private var showFilters = false                   // Show/hide filter options
    @State private var selectedFilters: Set<ParkingType> = [] // Active parking type filters
    
    // Map region controls what area of the map is displayed
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    /// Filters the parking lots based on search text and selected type filters
    var filteredLots: [ParkingLot] {
        apiService.parkingLots.filter { lot in
            // Check if lot matches search query
            let matchesSearch = searchText.isEmpty ||
                lot.name.localizedCaseInsensitiveContains(searchText) ||
                lot.address.localizedCaseInsensitiveContains(searchText)
            
            // Check if lot matches selected type filters (or no filters active)
            let matchesFilter = selectedFilters.isEmpty || selectedFilters.contains(lot.type)
            
            return matchesSearch && matchesFilter
        }
    }
    
    var body: some View {
        ZStack {
            // MARK: Full Screen Map Background
            // Map takes up the entire screen
            Map(coordinateRegion: $region, annotationItems: filteredLots) { lot in
                MapAnnotation(coordinate: lot.coordinate) {
                    // Custom pin view for each parking lot
                    MapPinView(lot: lot, isSelected: selectedLot?.id == lot.id)
                        .onTapGesture {
                            // Select lot when pin is tapped
                            withAnimation {
                                selectedLot = lot
                            }
                        }
                }
            }
            .ignoresSafeArea()
            
            // MARK: Top Overlay - Search Bar & Filters
            VStack {
                VStack(spacing: 12) {
                    // Search bar with rounded corners and shadow
                    HStack(spacing: 12) {
                        // Search input field
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search parking lots...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        // Filter toggle button
                        Button(action: {
                            withAnimation {
                                showFilters.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.indigo)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Filter buttons (shown only when showFilters is true)
                    if showFilters {
                        HStack(spacing: 8) {
                            // Create a button for each parking type
                            ForEach(ParkingType.allCases, id: \.self) { type in
                                FilterButton(
                                    title: type.rawValue,
                                    isSelected: selectedFilters.contains(type)
                                ) {
                                    withAnimation {
                                        // Toggle filter on/off when tapped
                                        if selectedFilters.contains(type) {
                                            selectedFilters.remove(type)
                                        } else {
                                            selectedFilters.insert(type)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Display last update time with semi-transparent background
                    if let lastUpdated = apiService.lastUpdated {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text("Updated \(timeAgo(lastUpdated))")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // MARK: Bottom Info Card - Selected Lot Quick View
                // Shows brief info when a lot is selected, tap to see full details
                if let lot = selectedLot {
                    VStack(spacing: 0) {
                        // Quick info card
                        Button(action: {
                            // Tapping card opens full detail view
                        }) {
                            HStack(spacing: 16) {
                                // Availability indicator circle
                                Circle()
                                    .fill(lot.availabilityColor)
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        VStack(spacing: 2) {
                                            Text("\(lot.availableSpots)")
                                                .font(.headline)
                                                .fontWeight(.bold)
                                            Text("spots")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.white)
                                    )
                                
                                // Lot information
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lot.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(lot.address)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 12) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.caption)
                                            Text("\(String(format: "%.1f", lot.distance)) mi")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "dollarsign.circle.fill")
                                                .font(.caption)
                                            Text("$\(String(format: "%.0f", lot.pricePerHour))/hr")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Chevron to indicate tappable
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            // Directions button
                            Button(action: {
                                let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: lot.coordinate))
                                mapItem.name = lot.name
                                mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                            }) {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("Directions")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            // View details button
                            Button(action: {
                                // Opens detail sheet
                            }) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                    Text("Details")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.indigo)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.indigo, lineWidth: 2)
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // MARK: Refresh Button - Top Right Corner
            VStack {
                HStack {
                    Spacer()
                    Button(action: { Task { await refreshData() } }) {
                        Image(systemName: apiService.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.indigo)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                    .padding(.trailing)
                    .padding(.top, showFilters ? 180 : 80)
                    .rotationEffect(.degrees(apiService.isLoading ? 360 : 0))
                    .animation(apiService.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: apiService.isLoading)
                }
                Spacer()
            }
        }
        .sheet(item: $selectedLot) { lot in
            ParkingLotDetailView(lot: lot)
        }
        .task {
            await loadInitialData()
            apiService.startAutoRefresh(interval: 10.0) // Refresh every 10 seconds
        }
    }
    
    /// Loads parking data when the app first opens
    func loadInitialData() async {
        apiService.isLoading = true
        do {
            let lots = try await apiService.fetchParkingLots()
            await MainActor.run {
                apiService.parkingLots = lots
                apiService.lastUpdated = Date()
                apiService.isLoading = false
                
                // Center map on first parking lot location
                if let firstLot = lots.first {
                    region.center = firstLot.coordinate
                }
            }
        } catch {
            await MainActor.run {
                apiService.errorMessage = error.localizedDescription
                apiService.isLoading = false
            }
        }
    }
    
    /// Manually refreshes parking data when user taps refresh button
    func refreshData() async {
        do {
            let lots = try await apiService.fetchParkingLots()
            await MainActor.run {
                apiService.parkingLots = lots
                apiService.lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                apiService.errorMessage = error.localizedDescription
            }
        }
    }
    
    /// Converts a Date to a human-readable "time ago" string
    /// Examples: "5s ago", "3m ago", "2h ago"
    func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Parking Lot Detail View
/// Full-screen detail view showing all spots in a parking lot
struct ParkingLotDetailView: View {
    let lot: ParkingLot
    @Environment(\.dismiss) var dismiss
    
    // Grid layout configuration - spots will adapt to screen width
    let columns = [
        GridItem(.adaptive(minimum: 60))
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: Header Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lot.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(lot.address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    
                    // MARK: Statistics Cards
                    HStack(spacing: 40) {
                        // Available spots count
                        VStack {
                            Text("\(lot.availableSpots)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(lot.availabilityColor)
                            Text("Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Total spots count
                        VStack {
                            Text("\(lot.totalSpots)")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Total Spots")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Hourly rate
                        VStack {
                            Text("$\(String(format: "%.0f", lot.pricePerHour))")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Per Hour")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.indigo.opacity(0.1))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // MARK: Individual Spots Grid
                    // Shows visual representation of each parking spot
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Individual Spots")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Grid of spot items
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(lot.spots) { spot in
                                SpotGridItem(spot: spot)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // MARK: Navigation Button
                    // Opens Apple Maps with directions to this parking lot
                    Button(action: {
                        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: lot.coordinate))
                        mapItem.name = lot.name
                        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    }) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Get Directions")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .padding()
                }
            }
            .navigationTitle("Parking Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Spot Grid Item
/// Visual representation of a single parking spot in the grid
struct SpotGridItem: View {
    let spot: IndividualSpot
    
    var body: some View {
        VStack(spacing: 4) {
            // Icon: car if occupied, parking sign if free
            Image(systemName: spot.isOccupied ? "car.fill" : "parkingsign")
                .font(.title2)
                .foregroundColor(spot.isOccupied ? .red : .green)
            
            // Spot number
            Text("#\(spot.number)")
                .font(.caption)
                .fontWeight(.semibold)
            
            // Status text
            Text(spot.isOccupied ? "Occupied" : "Free")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 60, height: 80)
        // Background color based on occupancy
        .background(spot.isOccupied ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        .cornerRadius(8)
        // Border color based on occupancy
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(spot.isOccupied ? Color.red : Color.green, lineWidth: 2)
        )
    }
}

// MARK: - Supporting Views
/// Filter button that can be toggled on/off with enhanced shadow for map overlay
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // Change appearance based on selection state
                .background(isSelected ? Color.indigo : Color.white)
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}

/// Custom map pin view with color coding based on availability
struct MapPinView: View {
    let lot: ParkingLot
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // Pin with availability info
            VStack(spacing: 2) {
                // Top: Available spots count
                Text("\(lot.availableSpots)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(8)
            .background(isSelected ? Color.indigo : lot.availabilityColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            
            // Pin pointer
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption)
                .foregroundColor(isSelected ? Color.indigo : lot.availabilityColor)
                .offset(y: -4)
        }
    }
}
