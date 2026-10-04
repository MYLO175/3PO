import Foundation
@main struct Checks {
    static func main() throws {
        assert(ChatGPTRecovery.quota("subscription_sharing_usage_limit_exceeded"))
        let first = ChatGPTRecovery.blocked(after:"subscription_sharing_usage_limit_exceeded",registration:"request-account",existing:[])
        assert(first == ["request-account"] && !first.contains("new-active-account"))
        assert(ChatGPTRecovery.blocked(after:"rate_limit_exceeded",registration:"request-account",existing:[]) == [])
        assert(ChatGPTRecovery.blocked(after:"subscription_sharing_usage_limit_exceeded",registration:"",existing:[]) == [])
        assert(!ChatGPTRecovery.quota("subscription_sharing_usage_unavailable"))
        assert(!ChatGPTRecovery.quota("rate_limit_exceeded"))
        assert(ChatGPTRecovery.message(code:"rate_limit_exceeded",status:429).contains("not confirmed"))
        assert(ChatGPTRecovery.message(code:"subscription_sharing_usage_unavailable",status:503).contains("session is retained"))
        assert(ChatGPTRecovery.safe("req_test-123") == "req_test-123")
        assert(ChatGPTRecovery.safe("Bearer private token") == "unavailable")
        for code in ["invalid_grant","invalid_refresh_token","token_expired","refresh_token_expired","refresh_token_invalidated","refresh_token_reused"] {
            assert(ChatGPTRecovery.terminalRefresh(code:code,status:400,grant:"refresh_token"))
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:503,grant:"refresh_token"))
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:400,grant:"authorization_code"))
        }
        for code in ["invalid_client","subscription_sharing_usage_limit_exceeded","subscription_sharing_usage_unavailable","request_failed"] {
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:401,grant:"refresh_token"))
        }
        var quotaFailure = ChatGPTStream()
        do {
            _ = try quotaFailure.line(#"data: {"type":"response.failed","response":{"id":"resp_test123","error":{"code":"subscription_sharing_usage_limit_exceeded","param":"model"}}}"#)
            assertionFailure("Quota failure must throw")
        } catch ChatGPTStream.Failure.failed(let code) {
            assert(code == "subscription_sharing_usage_limit_exceeded")
            assert(quotaFailure.errorParam == "model")
            assert(quotaFailure.responseID == "resp_test123")
        }
        var stream = ChatGPTStream()
        let ignored = try stream.line("event: response.output_text.delta"); assert(ignored == nil)
        let delta = try stream.line(#"data: {"type":"response.output_text.delta","delta":"Hello"}"#)
        assert(delta == "Hello")
        _ = try stream.line(#"data: {"type":"response.completed"}"#)
        _ = try stream.line("data: [DONE]")
        let result = try stream.finish(); assert(result == "Hello")
        for lines in [[], [#"data: {"type":"response.output_text.delta","delta":"Partial"}"#], [#"data: {"type":"response.completed"}"#], [#"data: {"type":"response.incomplete"}"#], [#"data: {"type":"response.failed","response":{"error":{"code":"usage_limit_reached"}}}"#], ["data: malformed", ""]] {
            var failed = ChatGPTStream(); var rejected = false
            do { for line in lines { _ = try failed.line(line) }; _ = try failed.finish() } catch { rejected = true }
            assert(rejected, "Must reject interrupted, empty, incomplete, failed or malformed streams")
        }
        var multiline = ChatGPTStream()
        _ = try multiline.line(#"data: {"type":"response.output_text.delta","delta":"#)
        _ = try multiline.line(#"data: "Two lines"}"#)
        _ = try multiline.line(#"data: {"type":"response.completed"}"#)
        let multi = try multiline.finish(); assert(multi == "Two lines")
        let unicode = "A\u{2028}B\u{2029}C\u{0085}D £ 🛰️"
        let payload = String(data:try JSONSerialization.data(withJSONObject:["type":"response.output_text.delta","delta":unicode]),encoding:.utf8)!
        for separator in ["\n","\r\n","\r"] {
            var framed = ChatGPTStream()
            let wire = "data: " + payload + separator + separator + "data: {\"type\":\"response.completed\"}" + separator + separator
            var deltas = ""
            for byte in wire.utf8 { if let value = try framed.byte(byte) { deltas += value } }
            let completed = try framed.finishBytes()
            assert(deltas == unicode && completed == unicode)
        }
        var badUTF8 = ChatGPTStream(), invalidUTF8Rejected = false
        do { _ = try badUTF8.byte(255); _ = try badUTF8.byte(10) } catch { invalidUTF8Rejected = true }
        assert(invalidUTF8Rejected)
        print("PASS: SSE deltas, terminal completion, multiline events, interruption, failed/incomplete/empty/malformed rejection")
    }
}
