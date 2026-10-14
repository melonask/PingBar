import CoreGraphics
import Foundation
@testable import PingBarKit
import Testing

@MainActor
struct PanelPlacementTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1_512, height: 944)
    private let external = CGRect(x: 1_512, y: -200, width: 2_560, height: 1_415)
    private let size = CGSize(width: 420, height: 520)

    @Test func offsetRoundTripsOnTheSameDisplay() {
        let frame = CGRect(x: 300, y: 200, width: size.width, height: size.height)
        let offset = PanelGeometry.offset(of: frame, in: laptop)

        #expect(offset == PanelOffset(left: 300, top: 224))
        #expect(PanelGeometry.frame(size: size, offset: offset, in: laptop) == frame)
    }

    @Test func offsetIsRelativeToEachDisplay() {
        let offset = PanelOffset(left: 40, top: 30)
        let frame = PanelGeometry.frame(size: size, offset: offset, in: external)

        #expect(frame.minX == external.minX + 40)
        #expect(frame.maxY == external.maxY - 30)
    }

    @Test func placementOnASmallerDisplayStaysFullyVisible() {
        // Saved near the bottom-right of a large display.
        let offset = PanelOffset(left: 2_100, top: 880)
        let frame = PanelGeometry.frame(size: size, offset: offset, in: laptop)

        #expect(laptop.contains(frame))
        #expect(frame.maxX == laptop.maxX)
        #expect(frame.minY == laptop.minY)
    }

    @Test func panelTallerThanTheDisplayKeepsItsTopVisible() {
        let short = CGRect(x: 0, y: 0, width: 800, height: 400)
        let frame = PanelGeometry.clamped(CGRect(x: 10, y: -300, width: 420, height: 520), to: short)

        #expect(frame.maxY == short.maxY)
    }

    @Test func defaultFrameSitsBelowTheStatusItem() {
        let item = CGRect(x: 1_200, y: 944, width: 60, height: 24)
        let frame = PanelGeometry.defaultFrame(size: size, below: item, in: laptop)

        #expect(frame.midX == item.midX)
        #expect(frame.maxY == laptop.maxY - PanelGeometry.menuBarGap)

        let nearEdge = CGRect(x: 1_480, y: 944, width: 30, height: 24)
        #expect(PanelGeometry.defaultFrame(size: size, below: nearEdge, in: laptop).maxX == laptop.maxX)
    }

    @Test func bestDisplayPrefersLargestOverlapThenNearest() {
        let displays = [laptop, external]
        let mostlyExternal = CGRect(x: 1_400, y: 100, width: 420, height: 300)
        let offscreen = CGRect(x: 5_000, y: 100, width: 420, height: 300)

        #expect(PanelGeometry.bestDisplayIndex(for: mostlyExternal, among: displays) == 1)
        #expect(PanelGeometry.bestDisplayIndex(for: offscreen, among: displays) == 1)
        #expect(PanelGeometry.bestDisplayIndex(for: .zero, among: []) == nil)
    }

    @Test func storeRemembersEachDisplaySeparately() throws {
        let store = try PanelPlacementStore(defaults: makeDefaults())

        store.save(PanelOffset(left: 10, top: 20), forDisplay: "laptop")
        store.save(PanelOffset(left: 900, top: 50), forDisplay: "external")

        #expect(store.offset(forDisplay: "laptop") == PanelOffset(left: 10, top: 20))
        #expect(store.offset(forDisplay: "external") == PanelOffset(left: 900, top: 50))
    }

    @Test func newDisplayUsesTheMostRecentPlacement() throws {
        let store = try PanelPlacementStore(defaults: makeDefaults())
        #expect(store.offset(forDisplay: "anything") == nil)

        store.save(PanelOffset(left: 10, top: 20), forDisplay: "laptop")
        store.save(PanelOffset(left: 900, top: 50), forDisplay: "external")

        #expect(store.offset(forDisplay: "projector") == PanelOffset(left: 900, top: 50))
    }

    @Test func placementPersistsAcrossLaunches() throws {
        let defaults = try makeDefaults()
        PanelPlacementStore(defaults: defaults).save(PanelOffset(left: 33, top: 44), forDisplay: "laptop")

        #expect(PanelPlacementStore(defaults: defaults).offset(forDisplay: "laptop") == PanelOffset(left: 33, top: 44))
    }

    @Test func positionFromEarlierVersionsIsMigrated() throws {
        let defaults = try makeDefaults()
        defaults.set("1", forKey: "panelScreenID")
        defaults.set(120.0, forKey: "panelScreenX")
        defaults.set(80.0, forKey: "panelScreenTop")
        defaults.set(500.0, forKey: "panelPositionX")
        defaults.set(700.0, forKey: "panelPositionTop")
        let store = PanelPlacementStore(defaults: defaults)

        #expect(store.offset(forDisplay: "laptop") == PanelOffset(left: 120, top: 80))

        store.save(PanelOffset(left: 1, top: 2), forDisplay: "laptop")
        for key in PanelPlacementStore.Keys.legacy {
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
