import Dispatch

public struct LatencyMeasurement: Equatable, Sendable {
    public var id: Int
    public var keyReceived: UInt64
    public var ptyWritten: UInt64?
    public var modelMutated: UInt64?
    public var framePresented: UInt64?

    public init(
        id: Int,
        keyReceived: UInt64,
        ptyWritten: UInt64? = nil,
        modelMutated: UInt64? = nil,
        framePresented: UInt64? = nil
    ) {
        self.id = id
        self.keyReceived = keyReceived
        self.ptyWritten = ptyWritten
        self.modelMutated = modelMutated
        self.framePresented = framePresented
    }

    public var keystrokeToPresentNanoseconds: UInt64? {
        guard let framePresented, framePresented >= keyReceived else {
            return nil
        }
        return framePresented - keyReceived
    }
}

public struct LatencySummary: Equatable, Sendable {
    public var count: Int
    public var p95Nanoseconds: UInt64?

    public init(count: Int, p95Nanoseconds: UInt64?) {
        self.count = count
        self.p95Nanoseconds = p95Nanoseconds
    }
}

public struct LatencyProbe: Sendable {
    private var nextID = 0
    private var active: [Int: LatencyMeasurement] = [:]
    public private(set) var completedMeasurements: [LatencyMeasurement] = []
    var activeMeasurementCount: Int {
        active.count
    }

    public init() {}

    public mutating func recordKeyReceived(
        at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Int {
        let id = nextID
        nextID += 1
        active[id] = LatencyMeasurement(id: id, keyReceived: timestamp)
        return id
    }

    mutating func cancel(_ id: Int) {
        active.removeValue(forKey: id)
    }

    public mutating func recordPTYWrite(
        for id: Int,
        at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        guard var measurement = active[id] else {
            return
        }
        measurement.ptyWritten = timestamp
        active[id] = measurement
    }

    public mutating func recordModelMutation(
        for id: Int,
        at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        guard var measurement = active[id] else {
            return
        }
        measurement.modelMutated = timestamp
        active[id] = measurement
    }

    public mutating func recordFramePresented(
        for id: Int,
        at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        guard var measurement = active.removeValue(forKey: id) else {
            return
        }
        measurement.framePresented = timestamp
        completedMeasurements.append(measurement)
    }

    public func summary() -> LatencySummary {
        let values = completedMeasurements
            .compactMap(\.keystrokeToPresentNanoseconds)
            .sorted()

        guard let p95Index = Self.p95Index(forCount: values.count) else {
            return LatencySummary(count: completedMeasurements.count, p95Nanoseconds: nil)
        }

        return LatencySummary(
            count: completedMeasurements.count,
            p95Nanoseconds: values[p95Index]
        )
    }

    private static func p95Index(forCount count: Int) -> Int? {
        guard count > 0 else {
            return nil
        }
        return Int(ceil(Double(count) * 0.95)) - 1
    }
}
