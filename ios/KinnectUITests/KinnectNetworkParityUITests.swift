import XCTest

final class KinnectNetworkParityUITests: XCTestCase {
    private var ctrlURL: String { ProcessInfo.processInfo.environment["QA_CTRL_URL"] ?? "" }
    private var primaryOrigin: String { ProcessInfo.processInfo.environment["QA_PRIMARY_ORIGIN"] ?? "" }
    private var fallbackOrigin: String { ProcessInfo.processInfo.environment["QA_FALLBACK_ORIGIN"] ?? "" }
    private var username: String { ProcessInfo.processInfo.environment["QA_USERNAME"] ?? "qa_parity_minh" }
    private var password: String { ProcessInfo.processInfo.environment["QA_PASSWORD"] ?? "" }
    private var outDir: String { ProcessInfo.processInfo.environment["QA_OUT_DIR"] ?? "/tmp/qa-ios-out" }
    private var leafSha256: String { ProcessInfo.processInfo.environment["QA_LEAF_SHA256"] ?? "" }
    private var deviceName: String { ProcessInfo.processInfo.environment["QA_DEVICE_NAME"] ?? "iPhone Simulator" }
    private var gitSha: String { ProcessInfo.processInfo.environment["QA_GIT_SHA"] ?? "unknown" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCTAssertFalse(ctrlURL.isEmpty, "QA_CTRL_URL must be set")
        XCTAssertFalse(primaryOrigin.isEmpty, "QA_PRIMARY_ORIGIN must be set")
        XCTAssertFalse(fallbackOrigin.isEmpty, "QA_FALLBACK_ORIGIN must be set")
        XCTAssertFalse(password.isEmpty, "QA_PASSWORD must be set")
        try FileManager.default.createDirectory(
            atPath: "\(outDir)/captures",
            withIntermediateDirectories: true
        )
    }

    // MARK: - HTTP Control Helpers (never logs credentials)

    @discardableResult
    private func ctrlRequest(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> [String: Any] {
        guard let url = URL(string: ctrlURL + path) else {
            throw NSError(domain: "QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid ctrlURL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let sem = DispatchSemaphore(value: 0)
        var outData: Data?
        var outErr: Error?
        URLSession.shared.dataTask(with: req) { d, _, e in
            outData = d
            outErr = e
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        if let outErr { throw outErr }
        guard let outData,
              let json = try JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func writeJSON(_ relativePath: String, _ obj: Any) {
        let full = "\(outDir)/\(relativePath)"
        let dir = (full as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: full))
        }
    }

    private func saveScreenshot(_ filename: String) {
        let shot = XCUIScreen.main.screenshot()
        let path = "\(outDir)/captures/\(filename)"
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        let att = XCTAttachment(screenshot: shot)
        att.name = filename
        att.lifetime = .keepAlways
        add(att)
    }

    private func launchApp(
        theme: String = "dark",
        lang: String = "vi",
        resetSession: Bool = true,
        requestTimeout: Int? = nil,
        largeText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "--qa-primary-origin", primaryOrigin,
            "--qa-fallback-origin", fallbackOrigin,
            "--qa-appearance", theme,
            "--qa-lang", lang
        ]
        if !leafSha256.isEmpty {
            args.append(contentsOf: ["--qa-leaf-sha256", leafSha256])
        }
        if resetSession {
            args.append("--qa-reset-session")
        }
        if let requestTimeout {
            args.append(contentsOf: ["--qa-request-timeout", "\(requestTimeout)"])
        }
        if largeText {
            args.append(contentsOf: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"])
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func loginViaUI(_ app: XCUIApplication) {
        let welcomeLogin = app.buttons["qa.welcome.login"]
        XCTAssertTrue(welcomeLogin.waitForExistence(timeout: 20), "Welcome login button should appear")
        welcomeLogin.tap()

        let userField = app.textFields["qa.login.username"]
        XCTAssertTrue(userField.waitForExistence(timeout: 12), "Login username field should appear")
        userField.tap()
        userField.typeText(username)

        let passField = app.secureTextFields["qa.login.password"]
        XCTAssertTrue(passField.waitForExistence(timeout: 6), "Login password field should appear")
        passField.tap()
        passField.typeText(password)

        let submit = app.buttons["qa.login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6), "Login submit button should exist")
        submit.tap()

        let topMessages = app.buttons["qa.topbar.messages"]
        XCTAssertTrue(topMessages.waitForExistence(timeout: 20), "Authenticated top bar should appear after real login")
    }

    private func waitForBadgeValue(_ button: XCUIElement, expected: String, timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let v = button.value as? String, v == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return (button.value as? String) == expected
    }

    private func findDMInput(_ app: XCUIApplication) -> XCUIElement {
        let tv = app.textViews["qa.dm.input"]
        if tv.exists { return tv }
        let tf = app.textFields["qa.dm.input"]
        if tf.exists { return tf }
        _ = tv.waitForExistence(timeout: 5)
        return tv.exists ? tv : tf
    }

    private func clearAndType(_ element: XCUIElement, text: String) {
        element.tap()
        if let existing = element.value as? String, !existing.isEmpty, existing != "Tin nhắn…" {
            let deleteSeq = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4)
            element.typeText(deleteSeq)
        }
        element.typeText(text)
    }

    // MARK: - IOS-N1 (C-001) + IOS-N2 (C-002): Real unread total 2+3=5 & UI mark-read without loop

    func testIOS_N1_N2_UnreadTotalAndMarkReadNoLoop() throws {
        let resetResp = try ctrlRequest("/_qa/reset", method: "POST")
        let seedInfo = resetResp["seed"] as? [String: Any] ?? [:]
        let peerId = seedInfo["peerId"] as? String ?? ""
        let groupId = seedInfo["groupId"] as? String ?? ""
        let dbBefore = resetResp["db"] as? [String: Any] ?? [:]

        let app = launchApp(theme: "dark", lang: "vi", resetSession: true)
        loginViaUI(app)

        let topMessages = app.buttons["qa.topbar.messages"]
        XCTAssertTrue(app.staticTexts["P1 parity post"].waitForExistence(timeout: 12), "Feed should render seeded post")

        // IOS-N1: Expect total unread = 2 (direct) + 3 (group) = 5
        let reached5 = waitForBadgeValue(topMessages, expected: "5", timeout: 12)
        let observedInitialBadge = (topMessages.value as? String) ?? "nil"
        saveScreenshot("n1-feed-unread-5.png")
        XCTAssertTrue(reached5, "Expected initial unread total 5, got \(observedInitialBadge)")

        // Open Inbox and check direct unread = 2 & Unread filter
        topMessages.tap()
        XCTAssertTrue(app.staticTexts["QA Lan"].waitForExistence(timeout: 10), "Direct conversation QA Lan should appear")
        XCTAssertTrue(app.staticTexts["2"].waitForExistence(timeout: 5), "Direct unread badge 2 should appear")
        saveScreenshot("n1-inbox-before-read.png")

        let unreadFilter = app.buttons["qa.messages.filter.unread"]
        XCTAssertTrue(unreadFilter.waitForExistence(timeout: 5))
        unreadFilter.tap()
        XCTAssertTrue(app.staticTexts["QA Lan"].waitForExistence(timeout: 5), "QA Lan must appear under Chưa đọc filter")

        // IOS-N2 (Direct): Open DM via UI -> backend marks seen -> back updates list/badge without loop
        app.staticTexts["QA Lan"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello parity"].waitForExistence(timeout: 10), "Direct chat messages should load")
        saveScreenshot("n2-dm-opened.png")

        // Observe 3s stability window to verify no reload loop
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))
        let metricsAfterDM = try ctrlRequest("/_qa/metrics")

        app.buttons["Quay lại"].firstMatch.tap()
        XCTAssertTrue(waitForBadgeValue(topMessages, expected: "3", timeout: 10), "Unread total should drop from 5 to 3 after reading DM")
        let emptyUnreadAfterDM = app.staticTexts["Không có tin nhắn chưa đọc."].waitForExistence(timeout: 8)
        saveScreenshot("n2-inbox-after-dm-read.png")
        XCTAssertTrue(emptyUnreadAfterDM, "Unread filter should show empty after DM read")

        // Switch to Group scope -> verify unread 3 -> open group -> back -> total 0
        let groupSegment = app.buttons["Nhóm chat"].firstMatch
        XCTAssertTrue(groupSegment.waitForExistence(timeout: 8), "Group scope segment should exist")
        groupSegment.tap()
        XCTAssertTrue(app.staticTexts["QA Parity Group"].waitForExistence(timeout: 10), "Group row should appear")
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 5), "Group unread badge 3 should appear")
        saveScreenshot("n2-group-list-before-read.png")

        app.staticTexts["QA Parity Group"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello parity group 1"].waitForExistence(timeout: 10), "Group messages should load")
        saveScreenshot("n2-group-opened.png")

        // Observe 3s stability window to verify no reload loop
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))

        app.buttons["Quay lại"].firstMatch.tap()
        let reached0 = waitForBadgeValue(topMessages, expected: "0", timeout: 10)
        let observedFinalBadge = (topMessages.value as? String) ?? "nil"
        saveScreenshot("n2-inbox-after-group-read.png")
        XCTAssertTrue(reached0, "Unread total should drop from 3 to 0 after reading group, got \(observedFinalBadge)")

        let metricsFinal = try ctrlRequest("/_qa/metrics")
        let counts = metricsFinal["countsByEndpoint"] as? [String: Any] ?? [:]
        let dmGetCount = counts["primary GET /api/users/\(peerId)/messages"] as? Int ?? 0
        let groupGetCount = counts["primary GET /api/groups/\(groupId)/messages"] as? Int ?? 0
        let convGetCount = counts["primary GET /api/conversations"] as? Int ?? 0
        let groupsGetCount = counts["primary GET /api/groups"] as? Int ?? 0
        let dbAfter = metricsFinal["db"] as? [String: Any] ?? [:]

        let reqCounts: [String: Any] = [
            "directMessagesGet": dmGetCount,
            "groupMessagesGet": groupGetCount,
            "conversationsGet": convGetCount,
            "groupsGet": groupsGetCount
        ]
        let n1n2Payload: [String: Any] = [
            "fixtureEnabled": false,
            "primaryOrigin": primaryOrigin,
            "fallbackOrigin": fallbackOrigin,
            "initialBadge": observedInitialBadge,
            "afterDMBadge": "3",
            "finalBadge": observedFinalBadge,
            "emptyUnreadFilterAfterDM": emptyUnreadAfterDM,
            "dbBefore": dbBefore,
            "dbAfterDM": metricsAfterDM["db"] ?? [:],
            "dbAfterFinal": dbAfter,
            "requestCounts": reqCounts,
            "countsByEndpoint": counts
        ]
        writeJSON("ios-n1-n2-evidence.json", n1n2Payload)

        XCTAssertEqual(dbAfter["directUnread"] as? Int, 0, "Backend directUnread must be 0")
        XCTAssertEqual(dbAfter["groupUnread"] as? Int, 0, "Backend groupUnread must be 0")
        XCTAssertGreaterThanOrEqual(dmGetCount, 1)
        XCTAssertLessThanOrEqual(dmGetCount, 2, "Direct messages GET must not loop (got \(dmGetCount))")
        XCTAssertGreaterThanOrEqual(groupGetCount, 1)
        XCTAssertLessThanOrEqual(groupGetCount, 2, "Group messages GET must not loop (got \(groupGetCount))")
    }

    // MARK: - IOS-N3 (C-003): POST commit + socket drop / timeout, no replay, 401/500 no failover, GET failover bounded

    func testIOS_N3_PostCommitDropAndFallbackBounds() throws {
        let resetResp = try ctrlRequest("/_qa/reset", method: "POST")
        let seedInfo = resetResp["seed"] as? [String: Any] ?? [:]
        let peerId = seedInfo["peerId"] as? String ?? ""
        let dbInitial = resetResp["db"] as? [String: Any] ?? [:]

        let app = launchApp(theme: "dark", lang: "vi", resetSession: true, requestTimeout: 3)
        loginViaUI(app)

        app.buttons["qa.topbar.messages"].tap()
        XCTAssertTrue(app.staticTexts["QA Lan"].waitForExistence(timeout: 10))
        app.staticTexts["QA Lan"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello parity"].waitForExistence(timeout: 10))

        // Subcase A: POST commits in createApp DB, then real TLS socket drops before response
        _ = try ctrlRequest("/_qa/fault", method: "POST", body: ["dropNextDirectPost": true])
        let inputA = findDMInput(app)
        XCTAssertTrue(inputA.exists, "DM input should exist")
        let draftA = "N3 drop after commit"
        clearAndType(inputA, text: draftA)
        let sendBtn = app.buttons["qa.dm.send"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "DM send button should appear")
        sendBtn.tap()

        let toast = app.staticTexts["qa.toast"]
        let toastShownA = toast.waitForExistence(timeout: 10)
        let toastTextA = toastShownA ? toast.label : ""
        saveScreenshot("n3-post-drop-error-draft.png")

        // Wait 2.5s to ensure client does NOT auto-retry
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let restoredDraftA = (findDMInput(app).value as? String) ?? ""
        let metricsA = try ctrlRequest("/_qa/metrics")
        let countsA = metricsA["countsByEndpoint"] as? [String: Any] ?? [:]
        let postCountA = countsA["primary POST /api/users/\(peerId)/messages"] as? Int ?? 0
        let fallbackA = metricsA["fallbackRequests"] as? [[String: Any]] ?? []
        let dbA = metricsA["db"] as? [String: Any] ?? [:]

        // Subcase B: POST commits in createApp DB, then response hangs > 3s client timeout
        _ = try ctrlRequest("/_qa/fault", method: "POST", body: ["hangNextDirectPostMs": 5500])
        let draftB = "N3 timeout after commit"
        clearAndType(findDMInput(app), text: draftB)
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5))
        sendBtn.tap()

        let toastShownB = toast.waitForExistence(timeout: 10)
        let toastTextB = toastShownB ? toast.label : ""
        saveScreenshot("n3-post-timeout-error-draft.png")
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let restoredDraftB = (findDMInput(app).value as? String) ?? ""
        let metricsB = try ctrlRequest("/_qa/metrics")
        let countsB = metricsB["countsByEndpoint"] as? [String: Any] ?? [:]
        let postCountB = countsB["primary POST /api/users/\(peerId)/messages"] as? Int ?? 0
        let fallbackB = metricsB["fallbackRequests"] as? [[String: Any]] ?? []
        let dbB = metricsB["db"] as? [String: Any] ?? [:]

        // Subcase C: HTTP 500 on POST must NOT fail over
        _ = try ctrlRequest("/_qa/fault", method: "POST", body: ["return500NextDirectPost": true])
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5))
        sendBtn.tap()
        let toastShown500 = toast.waitForExistence(timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let metrics500 = try ctrlRequest("/_qa/metrics")
        let fallback500 = metrics500["fallbackRequests"] as? [[String: Any]] ?? []

        // Return to Feed for 401 non-failover & GET transport failover checks
        app.buttons["Quay lại"].firstMatch.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.buttons["Về đầu Bảng tin Kinnect"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["P1 parity post"].waitForExistence(timeout: 8))

        // Subcase D: HTTP 401 on GET /api/posts must NOT fail over
        _ = try ctrlRequest("/_qa/fault", method: "POST", body: ["return401NextFeedGet": true])
        let feedScroll = app.scrollViews.firstMatch
        let startCoord = feedScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let endCoord = feedScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        startCoord.press(forDuration: 0.1, thenDragTo: endCoord)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let metrics401 = try ctrlRequest("/_qa/metrics")
        let fallback401 = metrics401["fallbackRequests"] as? [[String: Any]] ?? []

        // Subcase E: GET transport failure on primary CAN fail over to fallback (bounded)
        _ = try ctrlRequest("/_qa/fault", method: "POST", body: ["dropPrimaryFeedGet": 5])
        startCoord.press(forDuration: 0.1, thenDragTo: endCoord)
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        saveScreenshot("n3-get-failover.png")
        let metricsGetFailover = try ctrlRequest("/_qa/metrics")
        let fallbackGet = metricsGetFailover["fallbackRequests"] as? [[String: Any]] ?? []

        let subA: [String: Any] = [
            "toastShown": toastShownA,
            "toastText": toastTextA,
            "restoredDraft": restoredDraftA,
            "committedBeforeDrop": metricsA["committedBeforeDrop"] ?? 0,
            "directPostCount": postCountA,
            "directSentByMinh": dbA["directSentByMinh"] ?? -1,
            "fallbackCount": fallbackA.count
        ]
        let subB: [String: Any] = [
            "toastShown": toastShownB,
            "toastText": toastTextB,
            "restoredDraft": restoredDraftB,
            "committedBeforeTimeout": metricsB["committedBeforeTimeout"] ?? 0,
            "directPostCount": postCountB,
            "directSentByMinh": dbB["directSentByMinh"] ?? -1,
            "fallbackCount": fallbackB.count
        ]
        let subC: [String: Any] = [
            "toastShown": toastShown500,
            "fallbackCount": fallback500.count
        ]
        let subD: [String: Any] = [
            "fallbackCount": fallback401.count
        ]
        let subE: [String: Any] = [
            "fallbackCount": fallbackGet.count,
            "fallbackRequests": fallbackGet
        ]
        let n3Payload: [String: Any] = [
            "fixtureEnabled": false,
            "primaryOrigin": primaryOrigin,
            "fallbackOrigin": fallbackOrigin,
            "dbInitial": dbInitial,
            "subcaseA_dropAfterCommit": subA,
            "subcaseB_timeoutAfterCommit": subB,
            "subcaseC_http500NoFailover": subC,
            "subcaseD_http401NoFailover": subD,
            "subcaseE_getTransportFailover": subE,
            "countsByEndpoint": metricsGetFailover["countsByEndpoint"] ?? [:]
        ]
        writeJSON("ios-n3-evidence.json", n3Payload)

        // Hard assertions for IOS-N3
        XCTAssertTrue(toastShownA, "Socket drop POST must surface error toast")
        XCTAssertTrue(restoredDraftA.contains(draftA), "Socket drop POST must restore user draft, got '\(restoredDraftA)'")
        XCTAssertEqual(metricsA["committedBeforeDrop"] as? Int, 1, "Backend must have committed 1 POST before socket drop")
        XCTAssertEqual(postCountA, 1, "Client must send exactly 1 POST on socket drop (no retry)")
        XCTAssertEqual(dbA["directSentByMinh"] as? Int, 1, "DB must hold exactly 1 sent message (no duplicate)")
        XCTAssertEqual(fallbackA.count, 0, "POST socket drop must NEVER replay to fallbackOrigin")

        XCTAssertTrue(toastShownB, "Timeout POST must surface error toast")
        XCTAssertTrue(restoredDraftB.contains(draftB), "Timeout POST must restore user draft, got '\(restoredDraftB)'")
        XCTAssertEqual(metricsB["committedBeforeTimeout"] as? Int, 1, "Backend must have committed 1 POST before timeout")
        XCTAssertEqual(postCountB, 2, "Client must send exactly 1 additional POST on timeout (no retry)")
        XCTAssertEqual(dbB["directSentByMinh"] as? Int, 2, "DB must hold exactly 2 sent messages total (no duplicate)")
        XCTAssertEqual(fallbackB.count, 0, "POST timeout must NEVER replay to fallbackOrigin")

        XCTAssertEqual(fallback500.count, 0, "HTTP 500 must NEVER fail over")
        XCTAssertEqual(fallback401.count, 0, "HTTP 401 must NEVER fail over")
        XCTAssertGreaterThanOrEqual(fallbackGet.count, 1, "GET transport failure should fail over to fallbackOrigin")
        XCTAssertLessThanOrEqual(fallbackGet.count, 3, "GET failover must be bounded")
    }

    // MARK: - Parity Captures (Real createApp Backend, UIReviewFixture = false)

    func testParityCapturesRealBackend() throws {
        var records: [[String: Any]] = []
        let combos: [(String, String, Bool)] = [
            ("vi", "dark", false),
            ("vi", "light", false),
            ("en", "dark", false),
            ("en", "light", false),
            ("vi", "dark", true)
        ]

        func record(
            slug: String,
            screen: String,
            state: String,
            locale: String,
            theme: String,
            largeText: Bool,
            logicalWidth: Int
        ) {
            let file = "\(slug).png"
            saveScreenshot(file)
            let seedDict: [String: Any] = [
                "user": "QA Minh",
                "peer": "QA Lan",
                "post": "P1 parity post",
                "message": "Hello parity",
                "unreadDirect": 2,
                "unreadGroup": 3
            ]
            let entry: [String: Any] = [
                "platform": "ios",
                "file": "captures/\(file)",
                "slug": slug,
                "screen": screen,
                "state": state,
                "locale": locale,
                "theme": theme,
                "textScale": largeText ? "accessibilityLarge" : "default",
                "device": deviceName,
                "logicalWidth": logicalWidth,
                "gitSha": gitSha,
                "seed": seedDict,
                "fixtureEnabled": false
            ]
            records.append(entry)
        }

        for (locale, theme, largeText) in combos {
            _ = try ctrlRequest("/_qa/reset", method: "POST")
            let app = launchApp(theme: theme, lang: locale, resetSession: true, largeText: largeText)
            let logicalWidth = Int(round(app.frame.width))
            let suffix = "\(locale)-\(theme)" + (largeText ? "-large" : "-default")

            // 1. Auth screen
            XCTAssertTrue(app.buttons["qa.welcome.login"].waitForExistence(timeout: 20))
            if !largeText {
                record(slug: "parity-auth-welcome-\(suffix)", screen: "auth", state: "welcome", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)
            }
            app.buttons["qa.welcome.login"].tap()
            XCTAssertTrue(app.textFields["qa.login.username"].waitForExistence(timeout: 12))
            if !largeText {
                record(slug: "parity-auth-login-\(suffix)", screen: "auth", state: "login", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)
            }

            // Login
            app.textFields["qa.login.username"].tap()
            app.textFields["qa.login.username"].typeText(username)
            app.secureTextFields["qa.login.password"].tap()
            app.secureTextFields["qa.login.password"].typeText(password)
            app.buttons["qa.login.submit"].tap()
            XCTAssertTrue(app.buttons["qa.topbar.messages"].waitForExistence(timeout: 20))
            XCTAssertTrue(app.staticTexts["P1 parity post"].waitForExistence(timeout: 12))
            _ = waitForBadgeValue(app.buttons["qa.topbar.messages"], expected: "5", timeout: 8)

            // 2. Feed screen
            record(slug: "parity-feed-\(suffix)", screen: "feed", state: "seeded-unread-5", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)

            // 3. Inbox screen (direct unread = 2)
            app.buttons["qa.topbar.messages"].tap()
            XCTAssertTrue(app.staticTexts["QA Lan"].waitForExistence(timeout: 10))
            record(slug: "parity-inbox-\(suffix)", screen: "inbox", state: "direct-unread-2", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)

            if largeText {
                app.terminate()
                continue
            }

            // 4. Direct Chat screen
            app.staticTexts["QA Lan"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Hello parity"].waitForExistence(timeout: 10))
            record(slug: "parity-direct-chat-\(suffix)", screen: "direct-chat", state: "opened-hello-parity", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)

            // 5. Group Chat screen
            app.buttons["Quay lại"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Nhóm chat"].firstMatch.waitForExistence(timeout: 8))
            app.buttons["Nhóm chat"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["QA Parity Group"].waitForExistence(timeout: 10))
            app.staticTexts["QA Parity Group"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Hello parity group 1"].waitForExistence(timeout: 10))
            record(slug: "parity-group-chat-\(suffix)", screen: "group-chat", state: "opened-qa-parity-group", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)

            // 6. Profile screen
            app.buttons["Quay lại"].firstMatch.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            app.buttons["qa.topbar.profile"].tap()
            let profileCard = app.buttons["Trang cá nhân"].firstMatch
            XCTAssertTrue(profileCard.waitForExistence(timeout: 8))
            profileCard.tap()
            XCTAssertTrue(app.staticTexts["QA Minh"].waitForExistence(timeout: 10))
            record(slug: "parity-profile-\(suffix)", screen: "profile", state: "self-qa-minh", locale: locale, theme: theme, largeText: largeText, logicalWidth: logicalWidth)

            app.terminate()
        }

        writeJSON("captures/manifest.json", [
            "platform": "ios",
            "gitSha": gitSha,
            "device": deviceName,
            "fixtureEnabled": false,
            "capturesCount": records.count,
            "captures": records
        ])
    }
}
