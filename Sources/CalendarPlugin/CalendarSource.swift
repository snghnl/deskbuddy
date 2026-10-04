import Foundation

// `package` is for CalendarMac, which reads events from EventKit and draws them

/// An event as the calendar shows it, whatever calendar it came from
package struct CalendarEvent: Identifiable {
    package let id: String
    package let title: String
    package let start: Date
    package let end: Date
    package let isAllDay: Bool
    /// Its calendar's color; nil for the platform's accent color
    package let color: EventColor?

    package init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, color: EventColor?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
    }
}

/// A color as plain components, so the model needs no UI framework
package struct EventColor: Equatable {
    package let red: Double
    package let green: Double
    package let blue: Double

    package init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

package enum CalendarAccess {
    case notDetermined   // Never asked yet — show the connect button
    case denied          // Denied — point to System Settings
    case authorized
}

/// Where events come from: on macOS, the system calendar through EventKit
@MainActor
package protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }

    /// Events on a specific day: all-day events first, the rest in time order
    func events(on day: Date) -> [CalendarEvent]
}
