const Scanner = @import("./main.zig").Scanner;
const Error = Scanner.Error;
const Token = Scanner.Token;

pub fn scan(s: *Scanner) Error!Token {
    try s.skipSpaces();
    s.source_accessor.startValueCapture();
    while(true) {
        switch()
    }
}
