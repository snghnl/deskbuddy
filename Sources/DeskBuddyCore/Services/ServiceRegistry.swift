import Observation

/// Lets plugins offer typed services to each other without importing each other's code.
///
/// The service protocol lives in a small API module both sides depend on: the providing
/// plugin registers its implementation under that protocol and the others look it up by it.
/// Look a service up where it is used rather than holding on to it from `activate`, so
/// plugins do not depend on activation order. The registry is observable, so a view that
/// found nothing updates once the service is provided.
@MainActor
@Observable
public final class ServiceRegistry {
    private var services: [ObjectIdentifier: Any] = [:]

    public init() {}

    /// Registers `service` under `type`. Pass the protocol: `provide(TodoService.self, store)`
    public func provide<Service>(_ type: Service.Type, _ service: Service) {
        let key = ObjectIdentifier(type)
        assert(services[key] == nil, "\(type) is already provided")
        services[key] = service
    }

    /// The service registered under `type`, or nil when nothing provides it
    public func resolve<Service>(_ type: Service.Type) -> Service? {
        services[ObjectIdentifier(type)] as? Service
    }
}
