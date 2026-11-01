/// GBNF for REPLY_SCHEMA in src/textToMermaid.ts (keep in sync), the same constraint Ollama
/// builds from its `format` schema: fixed key order, optional whitespace between tokens.
enum ReplyGrammar {
    static let gbnf = #"""
    root ::= "{" ws "\"direction\"" ws ":" ws direction ws "," ws "\"boxes\"" ws ":" ws boxes ws "," ws "\"edges\"" ws ":" ws edges ws "}"
    direction ::= "\"TD\"" | "\"LR\""
    boxes ::= "[" ws ( string ( ws "," ws string )* )? ws "]"
    edges ::= "[" ws ( edge ( ws "," ws edge )* )? ws "]"
    edge ::= "[" ws string ws "," ws string ws "," ws string ws "]"
    string ::= "\"" ( [^"\\\x7F\x00-\x1F] | "\\" ( ["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] ) )* "\""
    ws ::= | " " | "\n" [ \t]{0,20}
    """#
}
