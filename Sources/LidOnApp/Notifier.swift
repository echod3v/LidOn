import Foundation
import LidOnCore
import UserNotifications

/// 로컬 알림 + 휴대폰 알림(웹훅)
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func local(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// 웹훅 전송. 완료(성공/실패/시간 초과) 시 메인 스레드에서 completion 호출.
    static func webhook(kind: WebhookKind, url: String, title: String, body: String, record: SessionRecord?,
                        completion: @escaping (Bool) -> Void) {
        guard kind != .none, let u = URL(string: url.trimmingCharacters(in: .whitespaces)),
              u.scheme == "https" || u.scheme == "http" else {
            completion(false)
            return
        }
        var req = URLRequest(url: u, timeoutInterval: 5)
        req.httpMethod = "POST"
        switch kind {
        case .ntfy:
            req.setValue(title.data(using: .utf8).map { "=?UTF-8?B?\($0.base64EncodedString())?=" }, forHTTPHeaderField: "Title")
            req.setValue("laptop", forHTTPHeaderField: "Tags")
            req.httpBody = Data(body.utf8)
        case .slack:
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": "*\(title)*\n\(body)"])
        case .discord:
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": "**\(title)**\n\(body)"])
        case .json:
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payload: [String: Any] = ["event": "session_ended", "title": title, "message": body]
            if let r = record {
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                if let d = try? enc.encode(r), let obj = try? JSONSerialization.jsonObject(with: d) { payload["session"] = obj }
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        case .none:
            break
        }
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let ok = err == nil && ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 400
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}
