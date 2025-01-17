const Scanner = @import("./main.zig").Scanner;
const Token = Scanner.Token;
const State = Scanner.State;
const Error = Scanner.Error;

pub fn scan(s: *Scanner) Error!Token {
    try s.skipSpacesAndNewLines();
    while (try s.source_accessor.current()) |c| {
        switch (c) {
            '#' => {
                try s.skipUntilNewLine();
                try s.skipSpacesAndNewLines();
            },
            '[' => {
                s.state = State.key;
                if (try s.mnext() == '[') {
                    _ = try s.mnext();
                    return Token.array_of_tables_begin;
                } else {
                    return Token.table_begin;
                }
            },
            '"', '\'' => {
                s.source_accessor.undoLastNext();
                // TODO: implement me
                unreachable;
            },
            'a'...'z', 'A'...'Z' => {
                s.source_accessor.undoLastNext();
                // TODO: implement me
                unreachable;
            },
        }
    }
}
