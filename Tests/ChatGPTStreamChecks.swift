import Foundation
@main struct Checks {
    static func main() throws {
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
        print("PASS: SSE deltas, terminal completion, multiline events, interruption, failed/incomplete/empty/malformed rejection")
    }
}
