import Foundation
import Testing
@testable import AgryCore

private let now = Date(timeIntervalSince1970: 1_000_000)

@Suite struct ManualHoldTests {
    @Test func unlimitedIsOfferedOnlyOnAC() {
        #expect(ManualHold.stops(onAC: true).last! == nil)
        #expect(!ManualHold.stops(onAC: false).contains { $0 == nil })
    }

    @Test func unlimitedOnBatteryIsCapped() {
        #expect(ManualHold.expiry(.distantFuture, onAC: false, now: now) == now.addingTimeInterval(2 * 3600))
    }

    @Test func unlimitedOnACStaysUnlimited() {
        #expect(ManualHold.expiry(.distantFuture, onAC: true, now: now) == .distantFuture)
    }

    @Test func timedHoldIsUntouchedOnBattery() {
        let expiry = now.addingTimeInterval(600)
        #expect(ManualHold.expiry(expiry, onAC: false, now: now) == expiry)
    }

    @Test func extendAddsToRemainingTime() {
        #expect(ManualHold.extended(now.addingTimeInterval(600), by: 1800, now: now) == now.addingTimeInterval(2400))
    }

    @Test func extendLapsedHoldCountsFromNow() {
        #expect(ManualHold.extended(now.addingTimeInterval(-60), by: 1800, now: now) == now.addingTimeInterval(1800))
    }
}
