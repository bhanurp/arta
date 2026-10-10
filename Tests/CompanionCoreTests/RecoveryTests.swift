import XCTest
@testable import CompanionCore
final class RecoveryTests:XCTestCase {
 func testDiscoveryRequiresLiveProcessAndNeverInventsState() throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
 try Data(#"{"sessionId":"alive","pid":42,"cwd":"/tmp/one"}"#.utf8).write(to:root.appendingPathComponent("42.json"))
 try Data(#"{"sessionId":"dead","pid":43,"cwd":"/tmp/two"}"#.utf8).write(to:root.appendingPathComponent("43.json"))
 let found=SessionDiscovery.discover(directory:root,isAlive:{$0 == 42})
 XCTAssertEqual(found.map(\.id),["alive"]);XCTAssertEqual(found.first?.state,.unknown)
 }
 func testCorruptStorePreserved() throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
 let url=root.appendingPathComponent("state.json");try Data("invalid".utf8).write(to:url);XCTAssertThrowsError(try Persistence.load(url));XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.contains("corrupt")})
 }
}
