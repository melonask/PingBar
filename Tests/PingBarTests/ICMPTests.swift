import Foundation
@testable import PingBarKit
import Testing

struct ICMPTests {
    @Test func echoRequestHasAValidChecksum() {
        let packet = ICMPEcho.request(identifier: 0xbeef, sequence: 1)

        #expect(packet[0] == 8)
        #expect(packet[4] == 0xbe && packet[5] == 0xef)
        // A correct ICMP checksum makes the whole message sum to zero.
        #expect(ICMPEcho.checksum(of: packet) == 0)
    }

    @Test func replyIsRecognisedWithAndWithoutTheIPv4Header() {
        let reply: [UInt8] = [0, 0, 0, 0, 0xbe, 0xef, 0, 1]
        let ipv4Header: [UInt8] = [0x45] + Array(repeating: 0, count: 19)

        #expect(ICMPEcho.isReply(to: 0xbeef, sequence: 1, in: reply[...]))
        #expect(ICMPEcho.isReply(to: 0xbeef, sequence: 1, in: (ipv4Header + reply)[...]))
    }

    @Test func otherICMPTrafficIsNotMistakenForTheReply() {
        let otherIdentifier: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0, 1]
        let echoRequest: [UInt8] = [8, 0, 0, 0, 0xbe, 0xef, 0, 1]
        let truncated: [UInt8] = [0x45, 0, 0]

        #expect(!ICMPEcho.isReply(to: 0xbeef, sequence: 1, in: otherIdentifier[...]))
        #expect(!ICMPEcho.isReply(to: 0xbeef, sequence: 1, in: echoRequest[...]))
        #expect(!ICMPEcho.isReply(to: 0xbeef, sequence: 1, in: truncated[...]))
    }

    #if os(macOS)
        @Test func ipv6AddressesUsePing6() {
            let ipv6 = ICMPPingClient.invocation(for: "fe80::1%en0", timeout: 2)
            let ipv4 = ICMPPingClient.invocation(for: "192.168.1.1", timeout: 2)

            #expect(ipv6.executable.path == "/sbin/ping6")
            #expect(ipv6.arguments == ["-n", "-c", "1", "fe80::1%en0"])
            #expect(ipv4.executable.path == "/sbin/ping")
            #expect(ipv4.arguments == ["-n", "-c", "1", "-t", "2", "192.168.1.1"])
        }

        @Test func ping6ReachesIPv6LoopbackEndToEnd() async throws {
            let response = try await ICMPPingClient().ping(target: PingTarget(type: .icmp, address: "::1"), timeout: 3)

            #expect(response.duration > 0)
            #expect(response.duration < 3)
        }

        @Test func processIsStoppedAtTheTimeout() async throws {
            let invocation = PingProcess.Invocation(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
            let start = ContinuousClock.now

            let result = try await PingProcess.run(invocation, timeout: 0.2)

            #expect(result.timedOut)
            #expect(ContinuousClock.now - start < .seconds(3))
        }

        @Test func processIsStoppedWhenTheCheckIsCancelled() async throws {
            let invocation = PingProcess.Invocation(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
            let start = ContinuousClock.now
            let task = Task { try await PingProcess.run(invocation, timeout: 30) }

            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            let result = try await task.value

            #expect(!result.timedOut)
            #expect(result.status != 0)
            #expect(ContinuousClock.now - start < .seconds(3))
        }
    #endif
}
