import XCTest
@testable import LedgerCore

/// The cases of app/src/test/.../logic/LinksTest.kt.
final class LinksTests: XCTestCase {
    private func uris(_ text: String) -> [String] { Links.find(text).map(\.uri) }

    func testWebAddresses() {
        XCTAssertEqual(["https://tabelog.com/kr/a/1"], uris("訂位 https://tabelog.com/kr/a/1 很難訂"))
        XCTAssertEqual(["https://www.visitkorea.or.kr"], uris("官網 www.visitkorea.or.kr。"))
        XCTAssertEqual(["https://maps.app.goo.gl/abc123"], uris("https://maps.app.goo.gl/abc123"))
        XCTAssertEqual(["https://a.com/x"], uris("看這裡https://a.com/x,很好吃"))
        XCTAssertEqual(["http://a.com/b"], uris("(http://a.com/b)"))
    }

    func testPhoneNumbers() {
        XCTAssertEqual(["tel:0227760000"], uris("電話 02-2776-0000"))
        XCTAssertEqual(["tel:0912345678"], uris("0912 345 678 找小美"))
        XCTAssertEqual(["tel:+8227765348"], uris("+82 2-776-5348"))
        XCTAssertEqual(["tel:0312345678"], uris("03-1234-5678"))
    }

    func testNotPhoneNumbers() {
        XCTAssertEqual([], uris("2026-10-22 19:00 4 位 確認碼 AB123456"))
        XCTAssertEqual([], uris("NT$ 1,234,567"))
        XCTAssertEqual([], uris("0800")) // too short
    }

    func testBothInOrder() {
        let found = Links.find("www.a.com 或 02-2776-0000")
        XCTAssertEqual([false, true], found.map(\.isPhone))
        XCTAssertEqual(["www.a.com", "02-2776-0000"], found.map(\.text))
    }

    func testLabels() {
        XCTAssertEqual("撥打 02-2776-0000", Links.label(Links.find("02-2776-0000")[0]))
        XCTAssertEqual("開啟地圖", Links.label(Links.find("https://maps.app.goo.gl/abc")[0]))
        XCTAssertEqual("開啟 tabelog.com", Links.label(Links.find("https://www.tabelog.com/a")[0]))
    }

    func testMapLinks() {
        XCTAssertEqual("首爾站", MapLinks.query(title: "景福宮", location: "首爾站"))
        XCTAssertEqual("景福宮", MapLinks.query(title: "景福宮", location: "https://maps.app.goo.gl/x"))
        XCTAssertEqual("https://maps.app.goo.gl/x", MapLinks.url(.google, title: "景福宮", location: "https://maps.app.goo.gl/x", bundleId: "b"))
        XCTAssertEqual("nmap://search?query=%E6%99%AF%E7%A6%8F%E5%AE%AE&appname=b", MapLinks.url(.naver, title: "景福宮", location: "", bundleId: "b"))
        XCTAssertEqual("kakaomap://search?q=a%20b", MapLinks.url(.kakao, title: "x", location: "a b", bundleId: "b"))
        XCTAssertEqual("http://maps.apple.com/?q=x%20a%20b", MapLinks.url(nil, title: "x", location: "a b", bundleId: "b"))
    }
}
